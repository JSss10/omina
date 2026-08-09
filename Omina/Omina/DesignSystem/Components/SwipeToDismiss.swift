// SwipeToDismiss.swift
// Omina
//
// Wegswipen zum Ausblenden für In-App-Banner (z. B. Barriere-Warnungen).
// Die Barriere-Benachrichtigungen sollen bewusst NICHT automatisch
// verschwinden, sondern erst, wenn man sie zur Seite wischt (Feldtest-
// Rückmeldung Tag 1). Ein horizontales Ziehen über die Schwelle löst
// `onDismiss` aus; darunter federt das Banner zurück.

import SwiftUI

struct SwipeToDismiss: ViewModifier {
    let onDismiss: () -> Void

    @State private var offsetX: CGFloat = 0

    /// Ziehweite (Punkte), ab der losgelassen das Banner ausblendet.
    private let dismissThreshold: CGFloat = 60

    func body(content: Content) -> some View {
        content
            .offset(x: offsetX)
            .opacity(Double(1 - min(1, abs(offsetX) / 160) * 0.7))
            .gesture(
                DragGesture(minimumDistance: 10)
                    .onChanged { value in
                        // Nur horizontales Wegswipen berücksichtigen.
                        offsetX = value.translation.width
                    }
                    .onEnded { value in
                        if abs(value.translation.width) > dismissThreshold {
                            let direction: CGFloat = value.translation.width > 0 ? 1 : -1
                            withAnimation(.easeOut(duration: 0.2)) {
                                offsetX = direction * 600
                            }
                            onDismiss()
                        } else {
                            withAnimation(.spring(duration: 0.3)) {
                                offsetX = 0
                            }
                        }
                    }
            )
    }
}

extension View {
    /// Macht das Banner per horizontalem Wegswipen ausblendbar. `onDismiss`
    /// wird ausgelöst, sobald weit genug gewischt wurde.
    func swipeToDismiss(perform onDismiss: @escaping () -> Void) -> some View {
        modifier(SwipeToDismiss(onDismiss: onDismiss))
    }
}