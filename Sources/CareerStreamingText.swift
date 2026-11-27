import AppKit
import SwiftUI

/// Keep the same text storage and line layout as new pieces of a reply arrive.
struct CareerStreamingText: NSViewRepresentable {
    let preview: CareerReplyPreview
    let chunkCount: Int
    let width: CGFloat

    final class Coordinator {
        var renderedChunks = 0
        var width: CGFloat = 0
        var height: CGFloat = 1
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSTextView {
        let storage = NSTextStorage()
        let layout = NSLayoutManager()
        storage.addLayoutManager(layout)
        let container = NSTextContainer(containerSize: NSSize(width: width, height: .greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        layout.addTextContainer(container)
        let view = NSTextView(frame: .zero, textContainer: container)
        view.isEditable = false
        view.isSelectable = true
        view.drawsBackground = false
        view.textContainerInset = .zero
        view.isVerticallyResizable = false
        container.widthTracksTextView = false
        container.heightTracksTextView = false
        view.setAccessibilityLabel("正在生成的回答")
        return view
    }

    func updateNSView(_ view: NSTextView, context: Context) {
        guard let container = view.textContainer, let layout = view.layoutManager,
              let storage = view.textStorage else { return }
        guard chunkCount == preview.chunks.count else { return }
        let cache = context.coordinator
        guard cache.width != width || cache.renderedChunks != chunkCount else { return }
        if cache.width != width {
            container.containerSize = NSSize(width: width, height: .greatestFiniteMagnitude)
            cache.width = width
        }
        if chunkCount < cache.renderedChunks {
            storage.deleteCharacters(in: NSRange(location: 0, length: storage.length))
            cache.renderedChunks = 0
        }
        if chunkCount > cache.renderedChunks {
            let delta = preview.chunks[cache.renderedChunks..<chunkCount].joined()
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineSpacing = 5
            storage.append(NSAttributedString(string: delta, attributes: [
                .font: NSFont.systemFont(ofSize: 13), .foregroundColor: NSColor.labelColor,
                .paragraphStyle: paragraph
            ]))
            cache.renderedChunks = chunkCount
        }
        layout.ensureLayout(for: container)
        let height = max(1, ceil(layout.usedRect(for: container).height))
        if cache.height != height {
            cache.height = height
            view.invalidateIntrinsicContentSize()
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSTextView, context: Context) -> CGSize? {
        CGSize(width: width, height: context.coordinator.height)
    }
}
