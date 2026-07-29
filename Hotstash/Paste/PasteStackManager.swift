import AppKit
import Carbon.HIToolbox
import OSLog

// MARK: - PasteStackManager

/// Sequential paste queue ("paste stack").
///
/// The user selects several history items and starts a stack. The first item
/// is placed on the pasteboard immediately; every subsequent ⌘V anywhere in
/// the system advances the stack, so N plain ⌘V presses paste N items in
/// order. A listen-only CGEvent tap detects the ⌘V keystrokes — this uses the
/// same Accessibility permission the app already holds for direct paste.
@MainActor
final class PasteStackManager {

    static let shared = PasteStackManager()

    private let logger = Logger(subsystem: "com.zeyadamer.hotstash", category: "PasteStack")

    // MARK: State

    private(set) var queue: [ClipboardItem] = []
    private(set) var nextIndex: Int = 0
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    var isActive: Bool { !queue.isEmpty && nextIndex < queue.count }
    var remainingCount: Int { max(0, queue.count - nextIndex) }

    private init() {}

    // MARK: - Public API

    /// Starts a stack with the given items (pasted top-to-bottom in array order).
    /// Returns false when the event tap cannot be created (no Accessibility).
    @discardableResult
    func start(items: [ClipboardItem]) -> Bool {
        guard !items.isEmpty else { return false }
        stop()

        guard installEventTap() else {
            logger.warning("paste stack tap creation failed — accessibility not granted")
            return false
        }

        queue = items
        nextIndex = 0
        stage(itemAt: 0)
        NotificationCenter.default.post(name: .pasteStackChanged, object: nil)
        return true
    }

    /// Cancels the stack and removes the event tap.
    func stop() {
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            runLoopSource = nil
        }
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            eventTap = nil
        }
        queue = []
        nextIndex = 0
        awaitingKeyUp = false
        NotificationCenter.default.post(name: .pasteStackChanged, object: nil)
    }

    // MARK: - Advancing

    /// Set when a ⌘V key-down is seen; the matching key-up advances the stack.
    /// The paste happens on key-down, so by key-up the frontmost app has read
    /// the pasteboard and the next item can be staged immediately — no timer,
    /// no race with a fast follow-up ⌘V.
    private var awaitingKeyUp = false

    /// Called from the event tap on ⌘V key-down. Records that a paste started.
    fileprivate func userPasteBegan() {
        // Ignore the app's own synthesized ⌘V (direct paste / quick transforms).
        if Date.now.timeIntervalSince(AutoPasteService.lastSyntheticPaste) < 0.3 { return }
        guard isActive else { return }
        awaitingKeyUp = true
    }

    /// Called from the event tap on the V key-up that ends the paste keystroke.
    fileprivate func userPasteEnded() {
        guard awaitingKeyUp else { return }
        awaitingKeyUp = false
        guard isActive else { return }

        nextIndex += 1
        if nextIndex < queue.count {
            stage(itemAt: nextIndex)
            NotificationCenter.default.post(name: .pasteStackChanged, object: nil)
        } else {
            NSSound(named: "Pop")?.play()
            stop()
        }
    }

    /// macOS disables taps it considers unresponsive; turn ours back on.
    fileprivate func reenableTap() {
        guard let tap = eventTap else { return }
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    private func stage(itemAt index: Int) {
        guard index < queue.count else { return }
        PasteEngine.hotstashedCopy(item: queue[index])
    }

    // MARK: - Event tap

    private func installEventTap() -> Bool {
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
                 | CGEventMask(1 << CGEventType.keyUp.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgAnnotatedSessionEventTap,
            place: .tailAppendEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: { _, type, event, _ in
                switch type {
                case .tapDisabledByTimeout, .tapDisabledByUserInput:
                    Task { @MainActor in PasteStackManager.shared.reenableTap() }
                case .keyDown:
                    if event.getIntegerValueField(.keyboardEventKeycode) == Int64(kVK_ANSI_V),
                       event.getIntegerValueField(.keyboardEventAutorepeat) == 0,
                       event.flags.contains(.maskCommand),
                       !event.flags.contains(.maskAlternate),
                       !event.flags.contains(.maskShift),
                       !event.flags.contains(.maskControl) {
                        Task { @MainActor in
                            PasteStackManager.shared.userPasteBegan()
                        }
                    }
                case .keyUp:
                    if event.getIntegerValueField(.keyboardEventKeycode) == Int64(kVK_ANSI_V) {
                        Task { @MainActor in
                            PasteStackManager.shared.userPasteEnded()
                        }
                    }
                default:
                    break
                }
                return Unmanaged.passUnretained(event)
            },
            userInfo: nil
        ) else { return false }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        eventTap = tap
        runLoopSource = source
        return true
    }
}

// MARK: - Notification

extension Notification.Name {
    /// Posted whenever the paste stack starts, advances, or finishes.
    static let pasteStackChanged = Notification.Name("pasteStackChanged")
}
