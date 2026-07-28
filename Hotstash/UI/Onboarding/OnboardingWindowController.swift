import AppKit
import SwiftUI

// MARK: - OnboardingWindowController

/// Presents the first-run guided tour: hero intro, a live hotkey step, then a
/// spotlight that walks across a faithful replica of the clipboard panel and
/// the Settings → Marketplace tab, one feature per step.
///
/// Gated behind `RemoteFlags.onboardingEnabled` (the caller checks); replayable
/// from Settings → About → "Show Tutorial". Completing, skipping, or closing
/// the window all mark the tour done so it never re-fires on launch.
final class OnboardingWindowController: NSWindowController, NSWindowDelegate {

    /// UserDefaults key marking the v8 tour as seen (Done/Skip/close).
    static let completedKey = "hasCompletedTourV8"

    private static var retained: OnboardingWindowController?
    private var escMonitor: Any?

    /// Whether a tour window is currently on screen. AppDelegate consults this
    /// so the global hotkey advances the tour instead of toggling the panel.
    static var isTourVisible: Bool { retained?.window?.isVisible ?? false }

    /// Shows the tour (creating it if needed) and brings it to front.
    static func present() {
        let wc = retained ?? OnboardingWindowController()
        retained = wc
        wc.showWindow(nil)
        wc.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Marks the tour complete (and legacy onboarding + current What's New
    /// version, so neither window re-fires right after the tour).
    static func markCompleted() {
        let defaults = UserDefaults.standard
        defaults.set(true, forKey: completedKey)
        defaults.set(true, forKey: "hasCompletedOnboarding")
        if let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
            defaults.set(v, forKey: "lastSeenVersion")
        }
    }

    // MARK: Init

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 680, height: 600),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Welcome to Hotstash"
        window.isReleasedWhenClosed = false
        window.isMovableByWindowBackground = true
        window.contentView = NSHostingView(rootView: TourView())

        super.init(window: window)
        window.delegate = self
        window.center()

        // Escape skips the tour, matching the clipboard panel's behaviour.
        escMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53, self?.window?.isKeyWindow == true else { return event }
            self?.close()
            return nil
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func windowWillClose(_ notification: Notification) {
        Self.markCompleted()
        if let escMonitor { NSEvent.removeMonitor(escMonitor) }
        escMonitor = nil
        Self.retained = nil
    }
}

// MARK: - Tour model

private enum TourStage: Equatable {
    case hero(HeroKind)
    case panel(target: String)
    case settings(target: String)
}

private enum HeroKind: Equatable { case welcome, hotkey, ready }

private struct TourStep {
    let stage: TourStage
    var badge = ""
    var title = ""
    var body = ""
}

private let tourSteps: [TourStep] = {
    let copyBody = RemoteFlags.directPasteEnabled
        ? "Press Return to copy the selected item — or have it pasted straight into the app you came from when Direct Paste is on."
        : "Press Return to put the selected item on your clipboard, then ⌘V pastes it right where you were."
    return [
        TourStep(stage: .hero(.welcome)),
        TourStep(stage: .hero(.hotkey)),
        TourStep(stage: .panel(target: "search"), badge: "Find",
                 title: "Search everything",
                 body: "Type to filter your entire history instantly — text, links, images (OCR), even names you give items."),
        TourStep(stage: .panel(target: "item"), badge: "Browse",
                 title: "Your clipboard history",
                 body: "Every copy is saved automatically. Newest on top — use ↑ ↓ to move, or ⌘1–9 to grab by position."),
        TourStep(stage: .panel(target: "tabs"), badge: "Organize",
                 title: "Recents, Pinned & Folders",
                 body: "Pin items so they never scroll away, and press ＋ to create folders that keep snippets sorted your way."),
        TourStep(stage: .panel(target: "copy"), badge: "Paste",
                 title: "Copy with Return",
                 body: copyBody),
        TourStep(stage: .panel(target: "transform"), badge: "Refine",
                 title: "Transform anything",
                 body: "Change case, format JSON, clean links, strip formatting, resize images — 30+ one-click transforms."),
        TourStep(stage: .panel(target: "multistack"), badge: "Power",
                 title: "Multi-Paste & Paste Stack",
                 body: "Paste several items at once (⌘⇧L), or ⌘-click rows to build a stack — then every ⌘V pastes the next one."),
        TourStep(stage: .settings(target: "markettab"), badge: "Extend",
                 title: "Transforms Marketplace",
                 body: "Install community and AI-generated transforms from Settings → Marketplace — or publish your own."),
        TourStep(stage: .hero(.ready)),
    ]
}()

// MARK: - TourView

private struct TourView: View {

    @State private var index = 0
    @State private var hotkeyCaught = false

    private var step: TourStep { tourSteps[index] }
    private var isLast: Bool { index == tourSteps.count - 1 }

    private var reduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    var body: some View {
        VStack(spacing: 0) {
            stage
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()
            footer
        }
        .frame(width: 680, height: 562)
        .onReceive(NotificationCenter.default.publisher(for: .hotstashHotkeyPressed)) { _ in
            guard step.stage == .hero(.hotkey), !hotkeyCaught else { return }
            hotkeyCaught = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { advance() }
        }
    }

    // MARK: Stage

    @ViewBuilder
    private var stage: some View {
        ZStack {
            switch step.stage {
            case .hero(let kind):
                HeroStepView(kind: kind, hotkeyCaught: hotkeyCaught, reduceMotion: reduceMotion)
                    .transition(.opacity)
            case .panel(let target):
                SpotlightStage(target: target, step: step, reduceMotion: reduceMotion) {
                    PanelReplicaView()
                }
                .transition(.opacity)
            case .settings(let target):
                SpotlightStage(target: target, step: step, reduceMotion: reduceMotion) {
                    SettingsReplicaView()
                }
                .transition(.opacity)
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: index)
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 12) {
            Button("Skip") { finish() }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .opacity(isLast ? 0 : 1)

            Spacer()

            HStack(spacing: 6) {
                ForEach(tourSteps.indices, id: \.self) { i in
                    Capsule()
                        .fill(i == index ? Color.accentColor : Color.secondary.opacity(0.3))
                        .frame(width: i == index ? 18 : 6, height: 6)
                }
            }
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: index)

            Spacer()

            Button("Back") { if index > 0 { index -= 1 } }
                .opacity(index == 0 ? 0 : 1)

            Button(isLast ? "Done" : (index == 0 ? "Get Started" : "Next")) {
                isLast ? finish() : advance()
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    private func advance() {
        guard index < tourSteps.count - 1 else { return }
        index += 1
    }

    private func finish() {
        OnboardingWindowController.markCompleted()
        NSApp.keyWindow?.close()
    }
}

// MARK: - Hero steps

private struct HeroStepView: View {
    let kind: HeroKind
    let hotkeyCaught: Bool
    let reduceMotion: Bool

    @State private var appeared = false

    var body: some View {
        VStack(spacing: 18) {
            Spacer()
            glyph
                .scaleEffect(appeared || reduceMotion ? 1 : 0.7)
                .opacity(appeared || reduceMotion ? 1 : 0)

            VStack(spacing: 10) {
                Text(title).font(.system(size: 30, weight: .bold))
                Text(subtitle)
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .offset(y: appeared || reduceMotion ? 0 : 12)
            .opacity(appeared || reduceMotion ? 1 : 0)

            if kind == .hotkey { keycaps }
            Spacer()
        }
        .padding(.horizontal, 60)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.spring(response: 0.55, dampingFraction: 0.8)) { appeared = true }
        }
    }

    private var glyph: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 22)
                .fill(LinearGradient(colors: glyphColors, startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 92, height: 92)
                .shadow(color: glyphColors[0].opacity(0.45), radius: 16, y: 6)
            Image(systemName: glyphSymbol)
                .font(.system(size: 42, weight: .medium))
                .foregroundStyle(.white)
        }
    }

    private var keycaps: some View {
        HStack(spacing: 8) {
            ForEach(["⌘", "⇧", "V"], id: \.self) { key in
                Text(key)
                    .font(.system(size: 20, weight: .bold))
                    .frame(width: 44, height: 40)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(hotkeyCaught ? Color.green.opacity(0.25) : Color.primary.opacity(0.06))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(hotkeyCaught ? Color.green : Color.primary.opacity(0.12), lineWidth: 1)
                    )
            }
            if hotkeyCaught {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(.green)
                    .transition(.scale)
            }
        }
        .animation(reduceMotion ? nil : .spring(response: 0.35), value: hotkeyCaught)
        .padding(.top, 4)
    }

    private var title: String {
        switch kind {
        case .welcome: "Welcome to Hotstash"
        case .hotkey:  hotkeyCaught ? "Nice — that's it!" : "Open from anywhere"
        case .ready:   "You're all set"
        }
    }

    private var subtitle: String {
        switch kind {
        case .welcome: "Everything you copy is saved. Search it, organize it, clean it up, and paste it perfectly — from anywhere."
        case .hotkey:  "Try pressing the shortcut right now — it works in any app."
        case .ready:   "Press ⌘⇧V to start. Replay this tour anytime from Settings → About → “Show Tutorial.”"
        }
    }

    private var glyphSymbol: String {
        switch kind {
        case .welcome: "doc.on.clipboard.fill"
        case .hotkey:  "keyboard.fill"
        case .ready:   "checkmark"
        }
    }

    private var glyphColors: [Color] {
        switch kind {
        case .welcome: [Color.accentColor, .purple]
        case .hotkey:  [.green, Color.accentColor]
        case .ready:   [.green, .mint]
        }
    }
}

// MARK: - Spotlight machinery

private struct TourTargetKey: PreferenceKey {
    static var defaultValue: [String: Anchor<CGRect>] = [:]
    static func reduce(value: inout [String: Anchor<CGRect>], nextValue: () -> [String: Anchor<CGRect>]) {
        value.merge(nextValue()) { $1 }
    }
}

private extension View {
    func tourTarget(_ id: String) -> some View {
        anchorPreference(key: TourTargetKey.self, value: .bounds) { [id: $0] }
    }
}

/// Renders a mock, dims everything except the current target, rings it, and
/// places a coach bubble beside it. The cutout animates between targets.
private struct SpotlightStage<Mock: View>: View {
    let target: String
    let step: TourStep
    let reduceMotion: Bool
    @ViewBuilder let mock: () -> Mock

    @State private var pulsing = false

    var body: some View {
        mock()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlayPreferenceValue(TourTargetKey.self) { anchors in
                GeometryReader { proxy in
                    if let anchor = anchors[target] {
                        let rect = proxy[anchor].insetBy(dx: -6, dy: -6)
                        spotlight(rect: rect, in: proxy.size)
                    }
                }
            }
    }

    @ViewBuilder
    private func spotlight(rect: CGRect, in size: CGSize) -> some View {
        let anim: Animation? = reduceMotion ? nil : .spring(response: 0.5, dampingFraction: 0.85)

        // Dim with a punched-out hole over the target.
        Rectangle()
            .fill(Color.black.opacity(0.45))
            .mask {
                Rectangle()
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .frame(width: rect.width, height: rect.height)
                            .position(x: rect.midX, y: rect.midY)
                            .blendMode(.destinationOut)
                    )
                    .compositingGroup()
            }
            .animation(anim, value: rect)
            .allowsHitTesting(false)

        // Accent ring (+ pulse unless reduced motion).
        RoundedRectangle(cornerRadius: 10)
            .stroke(Color.accentColor, lineWidth: 2)
            .frame(width: rect.width, height: rect.height)
            .position(x: rect.midX, y: rect.midY)
            .animation(anim, value: rect)
            .allowsHitTesting(false)

        if !reduceMotion {
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.accentColor.opacity(0.7), lineWidth: 2)
                .frame(width: rect.width, height: rect.height)
                .scaleEffect(pulsing ? 1.18 : 1)
                .opacity(pulsing ? 0 : 0.7)
                .position(x: rect.midX, y: rect.midY)
                .animation(.easeOut(duration: 1.5).repeatForever(autoreverses: false), value: pulsing)
                .allowsHitTesting(false)
                .onAppear { pulsing = true }
        }

        coach(rect: rect, in: size)
            .animation(anim, value: rect)
    }

    private func coach(rect: CGRect, in size: CGSize) -> some View {
        let width: CGFloat = 240
        let estHeight: CGFloat = 104
        let below = rect.maxY + 14 + estHeight < size.height
        let x = min(max(rect.midX, width / 2 + 10), size.width - width / 2 - 10)
        let y = below ? rect.maxY + 14 + estHeight / 2 : rect.minY - 14 - estHeight / 2

        return VStack(alignment: .leading, spacing: 4) {
            Text(step.badge.uppercased())
                .font(.system(size: 10, weight: .bold))
                .kerning(1)
                .foregroundStyle(Color.accentColor)
            Text(step.title)
                .font(.system(size: 14, weight: .bold))
            Text(step.body)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(width: width, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(.regularMaterial))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.primary.opacity(0.1), lineWidth: 1))
        .shadow(color: .black.opacity(0.25), radius: 18, y: 8)
        .position(x: x, y: y)
    }
}

// MARK: - Panel replica

/// Faithful, non-interactive copy of the clipboard panel used as the tour's
/// backdrop. Keep in sync with `ClipboardPanelVC` when the real layout changes.
private struct PanelReplicaView: View {

    var body: some View {
        VStack(spacing: 0) {
            searchRow
            Divider()
            tabsRow
            Divider()
            list
            Divider()
            toolbar
        }
        .frame(width: 344)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.primary.opacity(0.1), lineWidth: 1))
        .shadow(color: .black.opacity(0.3), radius: 24, y: 10)
    }

    private var searchRow: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").font(.system(size: 11))
                Text("Search clipboard history…").font(.system(size: 12))
                Spacer()
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8).padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.05)))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.primary.opacity(0.12), lineWidth: 1))
            .tourTarget("search")

            Image(systemName: "xmark")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10).padding(.vertical, 9)
    }

    private var tabsRow: some View {
        HStack(spacing: 2) {
            tab("Recents", selected: true)
            tab("Pinned")
            HStack(spacing: 4) {
                Image(systemName: "folder").font(.system(size: 10))
                Text("Work").font(.system(size: 11.5, weight: .medium))
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10).padding(.vertical, 4)
            tab("＋")
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 7).fill(Color.primary.opacity(0.06)))
        .tourTarget("tabs")
        .frame(maxWidth: .infinity)
        .padding(.vertical, 7)
    }

    private func tab(_ label: String, selected: Bool = false) -> some View {
        Text(label)
            .font(.system(size: 11.5, weight: .medium))
            .foregroundStyle(selected ? .primary : .secondary)
            .padding(.horizontal, 12).padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(selected ? Color.primary.opacity(0.12) : .clear)
            )
    }

    private var list: some View {
        VStack(spacing: 1) {
            row(icon: "link", tint: .blue,
                title: "https://hotstash.app/download", sub: "Link · copied 2m ago",
                selected: true)
                .tourTarget("item")
            row(icon: "photo", tint: .orange,
                title: "Screenshot 2026-07-28.png", sub: "Image · 4m ago")
            row(icon: "text.alignleft", tint: .secondary,
                title: "Meeting notes — Q3 roadmap draft…", sub: "Text · 11m ago",
                pinned: true)
        }
        .padding(5)
    }

    private func row(icon: String, tint: Color, title: String, sub: String,
                     selected: Bool = false, pinned: Bool = false) -> some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.06))
                    .frame(width: 30, height: 30)
                Image(systemName: icon).font(.system(size: 13)).foregroundStyle(tint)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 12.5, weight: .medium)).lineLimit(1)
                Text(sub).font(.system(size: 10.5)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            if pinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.accentColor)
            }
        }
        .padding(.horizontal, 9).padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(selected ? Color.accentColor.opacity(0.16) : .clear)
        )
    }

    private var toolbar: some View {
        HStack(spacing: 6) {
            Text("Copy")
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 12).padding(.vertical, 5)
                .background(Capsule().fill(Color.accentColor))
                .tourTarget("copy")

            Text("Transform ▾")
                .font(.system(size: 11.5, weight: .medium))
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(Capsule().fill(Color.primary.opacity(0.07)))
                .tourTarget("transform")

            HStack(spacing: 8) {
                Image(systemName: "rectangle.stack")
                Image(systemName: "square.stack.3d.up")
            }
            .font(.system(size: 13))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 4).padding(.vertical, 5)
            .tourTarget("multistack")

            Spacer()

            HStack(spacing: 9) {
                Image(systemName: "pin")
                Image(systemName: "delete.left")
                Image(systemName: "trash.circle")
                Image(systemName: "gearshape")
            }
            .font(.system(size: 13))
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(Color.primary.opacity(0.025))
    }
}

// MARK: - Settings replica (Marketplace step)

/// Compact copy of the real Settings window (top tab bar, Marketplace selected)
/// so the marketplace step points at where the feature actually lives.
private struct SettingsReplicaView: View {

    var body: some View {
        VStack(spacing: 0) {
            tabBar
            Divider()
            content
        }
        .frame(width: 440)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.primary.opacity(0.1), lineWidth: 1))
        .shadow(color: .black.opacity(0.3), radius: 24, y: 10)
    }

    private var tabBar: some View {
        HStack(spacing: 4) {
            tab("General", icon: "gear")
            tab("Transforms", icon: "wand.and.stars")
            tab("Marketplace", icon: "bag", selected: true)
                .tourTarget("markettab")
            tab("About", icon: "info.circle")
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    private func tab(_ label: String, icon: String, selected: Bool = false) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon).font(.system(size: 10))
            Text(label).font(.system(size: 11.5, weight: .medium))
        }
        .foregroundStyle(selected ? .primary : .secondary)
        .padding(.horizontal, 11).padding(.vertical, 5)
        .background(Capsule().fill(selected ? Color.primary.opacity(0.1) : .clear))
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 2) {
                segment("Browse", selected: true)
                segment("My Transforms")
                segment("Review")
            }
            .padding(2)
            .background(RoundedRectangle(cornerRadius: 7).fill(Color.primary.opacity(0.06)))
            .frame(maxWidth: .infinity)

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").font(.system(size: 10))
                Text("Search transforms…").font(.system(size: 11.5))
                Spacer()
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8).padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.05)))

            card(name: "Clean URL", tags: "Cleanup · text", installs: "12k")
            card(name: "Convert List to SQL IN Format", tags: "Case · text", installs: "6")
            card(name: "JSON Prettify", tags: "Code · text", installs: "8k")
        }
        .padding(14)
    }

    private func segment(_ label: String, selected: Bool = false) -> some View {
        Text(label)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(selected ? Color.white : .secondary)
            .padding(.horizontal, 12).padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 5).fill(selected ? Color.accentColor : .clear))
    }

    private func card(name: String, tags: String, installs: String) -> some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(LinearGradient(colors: [Color.accentColor, .purple],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 30, height: 30)
                Image(systemName: "wand.and.stars")
                    .font(.system(size: 13)).foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(.system(size: 12, weight: .semibold))
                Text(tags).font(.system(size: 10)).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                HStack(spacing: 2) {
                    Image(systemName: "star.fill").font(.system(size: 8)).foregroundStyle(.yellow)
                    Text("5.0").font(.system(size: 10, weight: .semibold))
                }
                Text("↓ \(installs)").font(.system(size: 9)).foregroundStyle(.secondary)
            }
        }
        .padding(9)
        .background(RoundedRectangle(cornerRadius: 9).fill(Color.primary.opacity(0.04)))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(Color.primary.opacity(0.07), lineWidth: 1))
    }
}
