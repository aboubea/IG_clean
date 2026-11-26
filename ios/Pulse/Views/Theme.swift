import SwiftUI

/// Identité « Pulse » : fond sombre, un seul accent citron vert.
enum Theme {
    static let background = Color(red: 0.051, green: 0.051, blue: 0.063)
    static let card = Color(red: 0.094, green: 0.094, blue: 0.114)
    static let track = Color(red: 0.149, green: 0.149, blue: 0.180)
    static let lime = Color(red: 0.776, green: 0.957, blue: 0.196)
    static let coral = Color(red: 1.0, green: 0.478, blue: 0.42)
    static let muted = Color(red: 0.553, green: 0.553, blue: 0.6)
}

struct Card<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

/// Petit titre en capitales au-dessus d'un bloc.
struct Kicker: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text.uppercased())
            .font(.caption)
            .fontWeight(.semibold)
            .tracking(1)
            .foregroundStyle(Theme.muted)
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(Theme.background)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 17)
            .background(Theme.lime, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

struct GhostButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(Color.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Theme.track, lineWidth: 1.5))
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}

/// Courbe d'évolution sans axes ; `closed` ferme la forme vers le bas pour le dégradé.
struct Sparkline: Shape {
    let values: [Double]
    var closed = false

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard values.count > 1, let low = values.min(), let high = values.max() else { return path }
        let span = high - low < 1 ? 1 : high - low
        let step = rect.width / CGFloat(values.count - 1)
        for (index, value) in values.enumerated() {
            let ratio = CGFloat((value - low) / span)
            let point = CGPoint(x: rect.minX + CGFloat(index) * step, y: rect.maxY - ratio * rect.height)
            if index == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }
        if closed {
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.closeSubpath()
        }
        return path
    }
}
