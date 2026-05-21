import AppKit
import Foundation

// MARK: - ClipboardMonitor

/// Polls `NSPasteboard.general` on a 0.5-second timer and pushes new string
/// items into `ClipboardStore`.  The `isAppWriting` flag lets other parts of
/// the app suppress monitoring while they write to the pasteboard themselves.
@MainActor
final class ClipboardMonitor {

    // MARK: Singleton

    static let shared = ClipboardMonitor()

    // MARK: Public state

    /// Set this to `true` before writing to the pasteboard programmatically
    /// (e.g. when pasting a transformed item) so the monitor ignores that write.
    var isAppWriting: Bool = false

    // MARK: Private state

    private var timer: Timer?
    private var lastChangeCount: Int = NSPasteboard.general.changeCount

    // MARK: Init

    private init() {}

    // MARK: Lifecycle

    /// Starts the polling timer.  Safe to call multiple times — subsequent
    /// calls are no-ops if the timer is already running.
    func start() {
        guard timer == nil else { return }

        // Fire immediately to capture the current pasteboard state, then repeat.
        lastChangeCount = NSPasteboard.general.changeCount

        let t = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            // Timer callbacks arrive on the thread the timer was scheduled on.
            // We scheduled on the main run loop, so this is already on the main
            // actor — but we use Task to satisfy the @MainActor isolation.
            Task { @MainActor in
                self?.poll()
            }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    /// Stops the polling timer.
    func stop() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: - Polling

    private func poll() {
        let pasteboard = NSPasteboard.general
        let currentCount = pasteboard.changeCount

        guard currentCount != lastChangeCount else { return }
        lastChangeCount = currentCount

        // If the app itself triggered this write, skip it.
        guard !isAppWriting else { return }

        // Try image first.
        if let image = imageFromPasteboard(pasteboard) {
            let item = ClipboardItem(
                content: "[Image]",
                contentType: .image,
                imageData: thumbnailData(from: image)
            )
            ClipboardStore.shared.add(item: item)
            NotificationCenter.default.post(name: .clipboardDidUpdate, object: nil)
            return
        }

        // Fall back to plain-string content.
        guard let content = pasteboard.string(forType: .string),
              !content.isEmpty else { return }

        // If this content already exists anywhere in history, move it to top (no duplicate).
        let store = ClipboardStore.shared
        if let existing = store.items.first(where: { !$0.isPinned && $0.content == content }) {
            if store.items.first(where: { !$0.isPinned })?.id != existing.id {
                store.moveToTop(id: existing.id)
                NotificationCenter.default.post(name: .clipboardDidUpdate, object: nil)
            }
            return
        }

        let type = ContentDetector.detect(content)
        let item = ClipboardItem(content: content, contentType: type)
        store.add(item: item)
        NotificationCenter.default.post(name: .clipboardDidUpdate, object: nil)
    }

    // MARK: - Image helpers

    private func imageFromPasteboard(_ pasteboard: NSPasteboard) -> NSImage? {
        let imageTypes: [NSPasteboard.PasteboardType] = [.tiff, .png]
        for type in imageTypes {
            if let data = pasteboard.data(forType: type),
               let image = NSImage(data: data) {
                return image
            }
        }
        return nil
    }

    private func thumbnailData(from image: NSImage) -> Data? {
        let maxDim: CGFloat = 400
        let orig = image.size
        guard orig.width > 0, orig.height > 0 else { return nil }

        let scale = min(maxDim / orig.width, maxDim / orig.height, 1.0)
        let thumbSize = NSSize(width: orig.width * scale, height: orig.height * scale)

        let thumb = NSImage(size: thumbSize)
        thumb.lockFocus()
        image.draw(
            in: NSRect(origin: .zero, size: thumbSize),
            from: NSRect(origin: .zero, size: orig),
            operation: .copy,
            fraction: 1.0
        )
        thumb.unlockFocus()

        guard let tiff = thumb.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff) else { return nil }
        return bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.7])
    }
}
