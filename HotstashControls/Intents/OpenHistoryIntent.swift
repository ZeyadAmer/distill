import AppIntents

struct OpenHistoryIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Hotstash History"
    static let description = IntentDescription("Opens Hotstash clipboard history.")
    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        .result()
    }
}
