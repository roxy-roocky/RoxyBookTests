#!/usr/bin/env bash
# Démarre MySQL dans le conteneur.
#  - Si le volume /var/lib/mysql contient déjà des données MySQL : elles sont réutilisées telles quelles.
#  - Sinon : une nouvelle instance est initialisée.
#  - Dans tous les cas, la base et l'utilisateur de l'application sont ensuite vérifiés/créés.
# Le script est idempotent : on peut le relancer à tout moment, même si MySQL tourne déjà
# ou si une exécution précédente a été interrompue en cours de route.
set -euo pipefail

DATA_DIR="/var/lib/mysql"
RUN_DIR="/var/run/mysqld"
LOG_DIR="/var/log/mysql"
ERROR_LOG="$LOG_DIR/error.log"

DB_NAME="${MYSQL_DATABASE:-appdb}"
DB_USER="${MYSQL_USER:-app}"
DB_PASSWORD="${MYSQL_PASSWORD:-app_password}"
ROOT_PASSWORD="${MYSQL_ROOT_PASSWORD:-root_password}"

log() { echo "[mysql] $*"; }
fail() {
  echo "[mysql] ERREUR : $*" >&2
  if sudo test -f "$ERROR_LOG"; then
    echo "[mysql] Dernières lignes de $ERROR_LOG :" >&2
    sudo tail -n 20 "$ERROR_LOG" >&2
  fi
  exit 1
}

# Mode de connexion au serveur : socket par défaut, basculé en TCP si la socket est inutilisable.
CONN_ARGS=(--protocol=socket)

# Le serveur répond-il ?
#  1. par la socket : on lit le message de mysqladmin plutôt que son code retour
#     ("mysqld is alive" ou "Access denied" prouvent tous deux que le serveur répond ;
#     ce script tourne avec un utilisateur système sans compte MySQL) ;
#  2. sinon, en secours : le port TCP 3306 est ouvert (indépendant de mysqladmin et de la socket).
is_up() {
  local out
  out=$(mysqladmin "${CONN_ARGS[@]}" ping 2>&1 || true)
  if [[ "$out" == *"mysqld is alive"* || "$out" == *"Access denied"* ]]; then
    return 0
  fi
  if (exec 3<>/dev/tcp/127.0.0.1/3306) 2>/dev/null; then
    CONN_ARGS=(--protocol=tcp -h127.0.0.1 -P3306)
    return 0
  fi
  return 1
}

# Requêtes en root : avec le mot de passe configuré, ou sans mot de passe
# (cas d'une initialisation précédente interrompue avant la définition du mot de passe).
root_sql()  { MYSQL_PWD="$ROOT_PASSWORD" mysql "${CONN_ARGS[@]}" -uroot "$@"; }
nopw_sql()  { env -u MYSQL_PWD mysql "${CONN_ARGS[@]}" -uroot "$@"; }

# sudo ne doit jamais demander de mot de passe (y compris pour `sudo -u mysql`)
sudo -n -u mysql true 2>/dev/null \
  || fail "sudo demande un mot de passe pour exécuter des commandes en tant que 'mysql' (voir /etc/sudoers.d dans le Dockerfile)."

NEW_INSTANCE=false

if is_up; then
  log "MySQL est déjà démarré."
else
  # --- Préparation des dossiers et des droits -------------------------------
  sudo mkdir -p "$RUN_DIR" "$LOG_DIR"
  sudo chown mysql:mysql "$RUN_DIR" "$LOG_DIR"
  # Un volume neuf, ou créé par un autre conteneur, peut avoir un autre propriétaire
  if [ -n "$(sudo find "$DATA_DIR" ! -user mysql -print -quit)" ]; then
    log "Correction des droits sur le volume de données..."
    sudo chown -R mysql:mysql "$DATA_DIR"
  fi

  # --- Données existantes dans le volume ? ----------------------------------
  # mysql.ibd est le tablespace système créé par MySQL 8 lors de l'initialisation.
  if sudo test -f "$DATA_DIR/mysql.ibd"; then
    log "Données MySQL existantes détectées dans le volume : réutilisation."
  else
    log "Volume vide : initialisation d'une nouvelle instance MySQL..."
    sudo -u mysql mysqld --initialize-insecure --user=mysql --log-error="$ERROR_LOG" \
      || fail "l'initialisation a échoué (le dossier $DATA_DIR contient-il des fichiers étrangers ?)."
    NEW_INSTANCE=true
  fi

  # --- Démarrage du serveur -------------------------------------------------
  log "Démarrage de mysqld..."
  sudo -u mysql mysqld --user=mysql --daemonize --log-error="$ERROR_LOG" >/dev/null 2>&1 \
    || fail "mysqld n'a pas pu démarrer."

  for _ in $(seq 1 60); do
    is_up && break
    sleep 1
  done
  if ! is_up; then
    echo "[mysql] Diagnostic :" >&2
    echo "[mysql]   mysqladmin : $(command -v mysqladmin || echo 'INTROUVABLE')" >&2
    echo "[mysql]   mysqld lancé : $(pgrep -x mysqld >/dev/null && echo oui || echo non)" >&2
    echo "[mysql]   sortie de 'mysqladmin ping' :" >&2
    mysqladmin "${CONN_ARGS[@]}" ping 2>&1 | sed 's/^/[mysql]     /' >&2 || true
    echo "[mysql]   contenu de $RUN_DIR :" >&2
    ls -la "$RUN_DIR" 2>&1 | sed 's/^/[mysql]     /' >&2 || true
    fail "MySQL ne répond pas après 60 s."
  fi
fi

# --- Provisionnement (idempotent) --------------------------------------------
READY=false
ERR_WITH_PW=""
ERR_NO_PW=""
if ERR_WITH_PW=$(root_sql -e "SELECT 1" 2>&1); then
  READY=true
elif ERR_NO_PW=$(nopw_sql -e "SELECT 1" 2>&1); then
  # --initialize-insecure crée root sans mot de passe : on le définit maintenant
  log "root n'a pas encore de mot de passe : définition de MYSQL_ROOT_PASSWORD."
  nopw_sql -e "ALTER USER 'root'@'localhost' IDENTIFIED BY '${ROOT_PASSWORD}';"
  READY=true
fi

if [ "$READY" = true ]; then
  root_sql <<SQL
CREATE DATABASE IF NOT EXISTS \`${DB_NAME}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS '${DB_USER}'@'%' IDENTIFIED BY '${DB_PASSWORD}';
GRANT ALL PRIVILEGES ON \`${DB_NAME}\`.* TO '${DB_USER}'@'%';
FLUSH PRIVILEGES;
SQL
  if [ "$NEW_INSTANCE" = true ]; then
    log "Nouvelle instance prête : base '${DB_NAME}', utilisateur '${DB_USER}'."
  else
    log "Instance prête : base '${DB_NAME}', utilisateur '${DB_USER}'."
  fi
else
  log "Attention : connexion root impossible (mode de connexion : ${CONN_ARGS[*]})."
  log "  avec MYSQL_ROOT_PASSWORD : $ERR_WITH_PW"
  log "  sans mot de passe        : $ERR_NO_PW"
  log "La base et l'utilisateur n'ont pas été vérifiés."
fi
