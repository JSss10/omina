// login.ts
// Anmeldung am Dashboard.
//
// Aufbau wie SignInView.swift in der App: Akzentleiste, Titel im
// Markenviolett mit erklärender Zeile, die beiden Felder ohne eigene
// Label-Zeile – die Beschriftung steht im Feld – und die Primäraktion
// darunter. Das Konto ist dasselbe wie in der App (dieselbe Supabase-
// Instanz, dieselbe Anmeldung mit E-Mail und Passwort); welche Daten es
// sieht, entscheidet Row Level Security.
//
// Es gibt bewusst keine Registrierung: berechtigt ist, wer in
// `dashboard_researchers` steht (supabase/migrations/dashboard_access.sql). Konten legt
// die Betreuung im Supabase-Dashboard an.

import { supabase } from "../lib/supabase.ts";
import { el, render } from "../lib/dom.ts";
import { authHeader, brandBar } from "./chrome.ts";
import { icon } from "./icons.ts";

/**
 * Feld nach Entwurf: getönte Fläche ohne Rand, die Beschriftung als
 * Platzhalter im Feld. Damit Screenreader das Feld trotzdem benennen,
 * steht das Label als `visually-hidden` im DOM – wie das
 * accessibilityLabel in AppTextField.swift.
 */
function textField(
  id: string,
  label: string,
  attrs: Record<string, string | boolean>,
  /** Schaltfläche im Feld, z. B. das Auge am Passwortfeld. */
  trailing?: HTMLElement,
): { field: HTMLElement; input: HTMLInputElement } {
  const input = el("input", {
    class: "input",
    id,
    name: id.replace("login-", ""),
    placeholder: label,
    required: true,
    ...attrs,
  });

  const field = el("div", { class: "field" }, [
    el("label", { class: "visually-hidden", for: id }, label),
    el("div", { class: "field__control" }, [input, trailing]),
  ]);

  return { field, input };
}

export function loginView(onSignedIn: () => void): HTMLElement {
  const errorBox = el("div", {
    class: "form-error",
    role: "alert",
    hidden: true,
  });

  const { field: emailField, input: email } = textField(
    "login-email",
    "E-Mail",
    {
      type: "email",
      autocomplete: "username",
      // Ohne dieses Attribut meldet Safari beim Absenden nur «ungültig», ohne
      // zu sagen, welches Feld gemeint ist.
      "aria-describedby": "login-hint",
    },
  );

  // Auge-Schaltfläche im Feld: kleiner violetter Kreis, antippbar in voller
  // Zielgrösse (AppTextField.swift).
  const reveal = el(
    "button",
    {
      class: "field__reveal",
      type: "button",
      "aria-label": "Passwort anzeigen",
      "aria-pressed": "false",
    },
    icon("eye"),
  );

  const { field: passwordField, input: password } = textField(
    "login-password",
    "Passwort",
    { type: "password", autocomplete: "current-password" },
    reveal,
  );

  reveal.addEventListener("click", () => {
    const revealed = password.type === "password";
    password.type = revealed ? "text" : "password";
    reveal.setAttribute("aria-pressed", String(revealed));
    reveal.setAttribute(
      "aria-label",
      revealed ? "Passwort verbergen" : "Passwort anzeigen",
    );
    render(reveal, icon(revealed ? "eye-off" : "eye"));
    password.focus();
  });

  const submit = el(
    "button",
    { class: "btn btn--primary btn--full", type: "submit" },
    "Anmelden",
  );

  const form = el("form", { class: "login__card", novalidate: true }, [
    authHeader(
      "Feldtest-Auswertung",
      "Melde dich mit dem Konto an, das für die Auswertung freigeschaltet ist.",
      "login-hint",
    ),
    errorBox,
    emailField,
    passwordField,
    submit,
  ]);

  function showError(message: string): void {
    render(errorBox, [icon("warning"), el("span", {}, message)]);
    errorBox.hidden = false;
  }

  form.addEventListener("submit", (event) => {
    event.preventDefault();
    errorBox.hidden = true;

    if (email.value.trim() === "" || password.value === "") {
      showError("Bitte E-Mail und Passwort eingeben.");
      return;
    }

    submit.disabled = true;
    render(submit, "Wird angemeldet …");

    void (async () => {
      const { error } = await supabase.auth.signInWithPassword({
        email: email.value.trim(),
        password: password.value,
      });

      submit.disabled = false;
      render(submit, "Anmelden");

      if (error) {
        // Supabase meldet falsche Zugangsdaten bewusst unspezifisch, damit
        // sich darüber keine gültigen Adressen abfragen lassen.
        showError(
          error.message === "Invalid login credentials"
            ? "E-Mail oder Passwort stimmt nicht."
            : `Anmeldung fehlgeschlagen: ${error.message}`,
        );
        password.focus();
        return;
      }

      onSignedIn();
    })();
  });

  return el("div", { class: "login" }, [brandBar(), form]);
}