import AppKit
import SwiftUI

/// Keep the final reply's text layout across SwiftUI measurements and tab changes.
/// The outer chat scroll view owns scrolling and supplies the column width.
struct CareerHistoryText: NSViewRepresentable, Equatable {
    let text: String
    let width: CGFloat
    final class Coordinator {
        var source: String?
        var columnWidth: CGFloat = 0
        var height: CGFloat = 1
    }
    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSTextView {
        let storage = NSTextStorage()
        let layout = NSLayoutManager()
        let container = NSTextContainer(containerSize: NSSize(width: width, height: .greatestFiniteMagnitude))
        storage.addLayoutManager(layout)
        layout.addTextContainer(container)
        container.lineFragmentPadding = 0
        let view = NSTextView(frame: .zero, textContainer: container)
        view.isEditable = false
        view.isSelectable = true
        view.drawsBackground = false
        view.isVerticallyResizable = false
        view.textContainerInset = .zero
        container.widthTracksTextView = false
        container.heightTracksTextView = false
        return view
    }

    func updateNSView(_ view: NSTextView, context: Context) {
        guard let storage = view.textStorage, let layout = view.layoutManager, let container = view.textContainer else { return }
        let cache = context.coordinator
        guard cache.source != text || cache.columnWidth != width else { return }
        if cache.source != text {
            storage.setAttributedString(Self.formatted(text))
            cache.source = text
        }
        cache.columnWidth = width
        container.containerSize = NSSize(width: width, height: .greatestFiniteMagnitude)
        layout.ensureLayout(for: container)
        cache.height = max(1, ceil(layout.usedRect(for: container).height))
        view.invalidateIntrinsicContentSize()
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSTextView, context: Context) -> CGSize? {
        CGSize(width: width, height: context.coordinator.height)
    }

    private static func formatted(_ text: String) -> NSAttributedString {
        let parsed = (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(text)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 5
        let result = NSMutableAttributedString()
        for run in parsed.runs {
            let intent = run.inlinePresentationIntent ?? []
            let base = intent.contains(.code) ? NSFont.monospacedSystemFont(ofSize: 13, weight: .regular) : NSFont.systemFont(ofSize: 13)
            var traits: NSFontTraitMask = []
            if intent.contains(.stronglyEmphasized) { traits.insert(.boldFontMask) }
            if intent.contains(.emphasized) { traits.insert(.italicFontMask) }
            var attributes: [NSAttributedString.Key: Any] = [.font: NSFontManager.shared.convert(base, toHaveTrait: traits), .foregroundColor: NSColor.labelColor, .paragraphStyle: paragraph]
            if let link = run.link { attributes[.link] = link }
            if intent.contains(.strikethrough) { attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
            result.append(NSAttributedString(string: String(parsed[run.range].characters), attributes: attributes))
        }
        return result
    }
}
