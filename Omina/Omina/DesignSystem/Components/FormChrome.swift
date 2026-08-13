// FormChrome.swift
// Omina
//
// Grundflächen der Formular-Screens (Profil, Profil bearbeiten,
// Benachrichtigungen, Sprache, Datenschutz, Über die App).
//
// Ein `Form` steht sonst auf den Systemfarben: im Hellmodus grau mit weissen
// Zeilen, im Dunkelmodus schwarz mit grauen Zeilen. Neben dem violetten
// Dunkelton der App (#1E1830) wirkt das wie ein fremder Screen. Die beiden
// Modifier legen Fläche und Zeilen auf die Farbtokens – ein Formular gehört
// damit in beiden Modi sichtbar zur App.

import SwiftUI

extension View {

    /// Grundfläche eines Formular-Screens. Gehört an das `Form` (oder an die
    /// Ansicht darum): schaltet die Systemfläche der Liste ab und legt die
    /// App-Fläche darunter – hell #FFFFFF, dunkel #1E1830.
    func appFormBackground() -> some View {
        self
            .scrollContentBackground(.hidden)
            .background(AppColor.backgroundPrimary.ignoresSafeArea())
    }

    /// Zeilenfläche eines Formulars: violett getönt (hell #EDE9FE,
    /// dunkel #241D3A), damit sich die Zeilen in beiden Modi von der Fläche
    /// darunter abheben.
    ///
    /// Gehört an die einzelnen `Section`s – oder an eine `Group` um mehrere
    /// Sections, die den Modifier an jede von ihnen weiterreicht.
    func appFormRowBackground() -> some View {
        listRowBackground(AppColor.surfaceTinted)
    }
}