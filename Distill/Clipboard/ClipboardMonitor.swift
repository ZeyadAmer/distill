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

        // Only handle plain-string content.
        guard let content = pasteboard.string(forType: .string),
              !content.isEmpty else { return }

        // Deduplicate: ignore if this is identical to the most recent item.
        if let latest = ClipboardStore.shared.items.first,
           latest.content == content {
            return
        }

        let type = ContentDetector.detect(content)
        let item = ClipboardItem(
            content: content,
            contentType: type,
            timestamp: Date()
        )

        ClipboardStore.shared.add(item: item)

        NotificationCenter.default.post(name: .clipboardDidUpdate, object: item)
    }
}
