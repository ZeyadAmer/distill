import AppKit
import SwiftUI

// MARK: - OnboardingWindowController

/// Presents the first-launch onboarding flow in a fixed-size, non-resizable window.
final class OnboardingWindowController: NSWindowController {

    // MARK: Init

    init() {
        let contentRect = NSRect(x: 0, y: 0, width: 540, height: 360)
        let styleMask: NSWindow.StyleMask = [.titled, .closable]

        let window = NSWindow(
            contentRect: contentRect,
            styleMask: styleMask,
            backing: .buffered,
            defer: false
        )
        window.title = "Welcome to Hotstash"
        window.isReleasedWhenClosed = false
        window.isMovableByWindowBackground = true

        let hostingView = NSHostingView(rootView: OnboardingView())
        window.contentView = hostingView

        super.init(window: window)

        window.center()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }
}

// MARK: - OnboardingView

struct OnboardingView: View {

    @State private var step: Int = 1

    var body: some View {
        ZStack {
            if step == 1 {
                StepWelcomeView(onNext: advance)
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing),
                        removal: .move(edge: .leading)
                    ))
            } else {
                StepReadyView(onDone: finish)
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing),
                        removal: .move(edge: .leading)
                    ))
            }
        }
        .frame(width: 540, height: 360)
        .animation(.easeInOut(duration: 0.3), value: step)
    }

    // MARK: - Navigation

    private func advance() {
        step += 1
    }

    private func finish() {
        UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
        NSApp.keyWindow?.close()
    }
}

// MARK: - Step 1: Welcome

private struct StepWelcomeView: View {

    let onNext: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "doc.on.clipboard.fill")
                .font(.system(size: 64))
                .foregroundStyle(Color.accentColor)

            VStack(spacing: 8) {
                Text("Welcome to Hotstash")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                Text("Copy anything. Paste it perfectly.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button(action: onNext) {
                Text("Get Started")
                    .frame(width: 200)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)

            stepIndicator(current: 1, total: 2)
                .padding(.bottom, 20)
        }
        .padding(.horizontal, 48)
    }
}

// MARK: - Step 2: Ready

private struct StepReadyView: View {

    let onDone: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.green)

            VStack(spacing: 8) {
                Text("You're Ready!")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                Text("Press ⌘⇧V anywhere to open Hotstash. Select an item, press Return to copy it, then ⌘V to paste.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            Button(action: onDone) {
                Text("Done")
                    .frame(width: 200)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)

            stepIndicator(current: 2, total: 2)
                .padding(.bottom, 20)
        }
        .padding(.horizontal, 48)
    }
}

// MARK: - Step indicator helper

private func stepIndicator(current: Int, total: Int) -> some View {
    HStack(spacing: 8) {
        ForEach(1...total, id: \.self) { index in
            Circle()
                .fill(index == current ? Color.accentColor : Color.secondary.opacity(0.3))
                .frame(width: 8, height: 8)
        }
    }
}
