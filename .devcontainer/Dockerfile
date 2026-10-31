FROM mcr.microsoft.com/devcontainers/dotnet:dev-10.0-noble

# Serveur + client MySQL (8.0, version d'Ubuntu 24.04).
# Le datadir installé par le paquet est vidé : /var/lib/mysql sera un volume nommé
# et c'est le script mysql-start.sh qui décide d'initialiser ou de réutiliser les données.
RUN apt-get update \
    && export DEBIAN_FRONTEND=noninteractive \
    && apt-get install -y --no-install-recommends mysql-server mysql-client \
    && (service mysql stop || true) \
    && rm -rf /var/lib/mysql/* \
    && mkdir -p /var/run/mysqld /var/log/mysql \
    && chown mysql:mysql /var/run/mysqld /var/log/mysql /var/lib/mysql \
    && apt-get clean -y \
    && rm -rf /var/lib/apt/lists/*

# sudo sans mot de passe pour vscode, y compris `sudo -u mysql ...` : la règle par défaut
# des images devcontainer est limitée à (root), ce qui ne couvre pas l'utilisateur mysql.
RUN echo 'vscode ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/vscode-nopasswd \
    && chmod 0440 /etc/sudoers.d/vscode-nopasswd \
    && visudo -cf /etc/sudoers.d/vscode-nopasswd

# Configuration MySQL pour le développement (écoute uniquement en local)
RUN printf '[mysqld]\nbind-address = 127.0.0.1\nmysqlx = OFF\ncharacter-set-server = utf8mb4\ncollation-server = utf8mb4_unicode_ci\n' \
    > /etc/mysql/conf.d/dev.cnf

# dotnet-ef (branche 10.x, alignée sur le SDK .NET 10), installé globalement dans /usr/local/bin
RUN dotnet tool install dotnet-ef --version "10.*" --tool-path /usr/local/bin

# Script de démarrage MySQL embarqué dans l'image : il ne dépend ni du dossier de travail
# ni du bit exécutable, et ses fins de ligne sont normalisées (LF).
COPY scripts/mysql-start.sh /usr/local/bin/mysql-start.sh
RUN sed -i 's/\r$//' /usr/local/bin/mysql-start.sh \
    && chmod +x /usr/local/bin/mysql-start.sh

ENV DOTNET_NOLOGO=true \
    DOTNET_CLI_TELEMETRY_OPTOUT=true
