export function setTheme(theme, cookieName)
{
    console.log("Switch theme to ", theme);
    let html = document.querySelector("html");
    html.setAttribute("data-bs-theme", theme);
    document.cookie = `${cookieName}=${theme}; path=/; max-age=31536000; SameSite=Lax`;
}