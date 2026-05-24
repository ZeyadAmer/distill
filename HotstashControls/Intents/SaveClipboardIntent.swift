import AppIntents

struct SaveClipboardIntent: AppIntent {
    static let title: LocalizedStringResource = "Save Clipboard to Hotstash"
    static let description = IntentDescription("Opens Hotstash and saves current clipboard content to history.")
    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        .result()
    }
}
