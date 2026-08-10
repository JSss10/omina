// login.ts
// Anmeldung am Dashboard.
//
// Es gibt bewusst keine Registrierung: berechtigt ist, wer in
// `dashboard_researchers` steht (supabase/migrations/dashboard_access.sql). Konten legt
// die Betreuung im Supabase-Dashboard an.

import { supabase } from "../lib/supabase.ts";
import { el, render } from "../lib/dom.ts";

export function loginView(onSignedIn: () => void): HTMLElement {
  const errorBox = el("div", {
    class: "form-error",
    role: "alert",
    hidden: true,
  });

  const email = el("input", {
    class: "input",
    type: "email",
    id: "login-email",
    name: "email",
    autocomplete: "username",
    required: true,
    // Ohne dieses Attribut meldet Safari beim Absenden nur «ungültig», ohne
    // zu sagen, welches Feld gemeint ist.
    "aria-describedby": "login-hint",
  });

  const password = el("input", {
    class: "input",
    type: "password",
    id: "login-password",
    name: "password",
    autocomplete: "current-password",
    required: true,
  });

  const submit = el(
    "button",
    { class: "btn btn--primary btn--full", type: "submit" },
    "Anmelden",
  );

  const form = el("form", { class: "login__card card", novalidate: true }, [
    el("h1", { class: "login__title" }, "Feldtest-Auswertung"),
    el(
      "p",
      { class: "login__intro", id: "login-hint" },
      "AR-Mikronavigation – Altstadt Zürich. Der Zugang ist auf die Konten beschränkt, die für die Auswertung freigeschaltet sind.",
    ),
    errorBox,
    el("div", { class: "field" }, [
      el("label", { class: "field__label", for: "login-email" }, "E-Mail"),
      email,
    ]),
    el("div", { class: "field" }, [
      el("label", { class: "field__label", for: "login-password" }, "Passwort"),
      password,
    ]),
    submit,
  ]);

  function showError(message: string): void {
    render(errorBox, message);
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

  return el("div", { class: "login" }, form);
}