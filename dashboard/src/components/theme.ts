// theme.ts
// Umschalter Hell/Dunkel/System.
//
// Ohne gespeicherte Wahl entscheidet `prefers-color-scheme` (Systemeinstellung).
// Eine getroffene Wahl setzt `data-theme` am <html>-Element und überstimmt die
// Media Query – dieselben drei Zustände wie in den iOS-Einstellungen.

import { el } from "../lib/dom.ts";

type Theme = "light" | "dark" | "system";

const STORAGE_KEY = "omina.dashboard.theme";

function stored(): Theme {
  const value = localStorage.getItem(STORAGE_KEY);
  return value === "light" || value === "dark" ? value : "system";
}

function apply(theme: Theme): void {
  if (theme === "system") {
    document.documentElement.removeAttribute("data-theme");
    localStorage.removeItem(STORAGE_KEY);
  } else {
    document.documentElement.setAttribute("data-theme", theme);
    localStorage.setItem(STORAGE_KEY, theme);
  }
}

/** Muss vor dem ersten Rendern laufen, damit die Seite nicht kurz umspringt. */
export function initTheme(): void {
  apply(stored());
}

const LABELS: Record<Theme, string> = {
  system: "System",
  light: "Hell",
  dark: "Dunkel",
};

export function themeToggle(): HTMLElement {
  const select = el("select", {
    class: "select",
    id: "theme-select",
    "aria-label": "Farbschema",
  });

  for (const value of ["system", "light", "dark"] as const) {
    const option = el("option", { value }, LABELS[value]);
    if (value === stored()) option.selected = true;
    select.appendChild(option);
  }

  select.addEventListener("change", () => {
    apply(select.value as Theme);
  });

  // Form und Mindestbreite in der Kopfzeile setzt app.css
  // (`.app-header__actions .select`) – hier bleibt nur das Verhalten.
  return select;
}