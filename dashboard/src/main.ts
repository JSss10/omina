// main.ts
// Einstiegspunkt: Konfiguration prüfen, Sitzung ermitteln, Ansicht wählen.

import "./styles/app.css";

import { missingConfig, supabase } from "./lib/supabase.ts";
import { el, must, render } from "./lib/dom.ts";
import { authHeader, brandBar } from "./components/chrome.ts";
import { initTheme } from "./components/theme.ts";
import { loginView } from "./components/login.ts";
import { mountDashboard, signOut } from "./app.ts";

// Vor dem ersten Rendern, damit die Seite nicht kurz im falschen Modus steht.
initTheme();

const root = must<HTMLElement>("#app");

function showConfigError(message: string): void {
  render(
    root,
    el("div", { class: "login" }, [
      brandBar(),
      el(
        "div",
        { class: "login__card" },
        authHeader("Konfiguration fehlt", message),
      ),
    ]),
  );
}

async function route(): Promise<void> {
  const configError = missingConfig();
  if (configError !== null) {
    showConfigError(configError);
    return;
  }

  const { data } = await supabase.auth.getSession();
  const session = data.session;

  if (session === null) {
    render(root, loginView(() => void route()));
    return;
  }

  // Zustands-Screen wie in der App: getönte Fläche, Titel im Markenviolett.
  render(root, [
    brandBar(),
    el(
      "main",
      { class: "app-main" },
      el(
        "div",
        { class: "state" },
        el("p", { class: "state__title" }, "Dashboard wird geladen …"),
      ),
    ),
  ]);

  await mountDashboard(
    root,
    session.user.email ?? "angemeldet",
    () => {
      void signOut().then(() => void route());
    },
  );
}

void route();