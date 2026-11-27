import SwiftUI

/// Compact, neutral controls for the browser chrome; website content keeps its own styling.
struct BrowserToolbarButtonStyle: ButtonStyle {
    var iconOnly = false
    func makeBody(configuration: Configuration) -> some View {
        Face(configuration: configuration, iconOnly: iconOnly)
    }
    private struct Face: View {
        let configuration: ButtonStyle.Configuration
        let iconOnly: Bool
        @Environment(\.isEnabled) private var enabled
        @State private var hovered = false
        var body: some View {
            configuration.label
                .font(.system(size: 13, weight: .medium))
                .padding(.horizontal, iconOnly ? 0 : 11)
                .frame(minWidth: 34, minHeight: 34)
                .foregroundStyle(Color.primary.opacity(enabled ? 0.85 : 0.26))
                .background(Color.black.opacity(configuration.isPressed ? 0.09 : hovered && enabled ? 0.055 : 0), in: RoundedRectangle(cornerRadius: 8))
                .contentShape(RoundedRectangle(cornerRadius: 8))
                .onHover { hovered = $0 }
        }
    }
}
extension ButtonStyle where Self == BrowserToolbarButtonStyle {
    static var browserToolbar: Self { .init() }
    static var browserIcon: Self { .init(iconOnly: true) }
}
