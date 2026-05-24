import SwiftUI
import WidgetKit

@available(iOS 18.0, *)
struct OpenHistoryControl: ControlWidget {
    static let kind = "com.zeyadamer.hotstash.control.history"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind) {
            ControlWidgetButton(action: OpenHistoryIntent()) {
                Label("Paste from Hotstash", systemImage: "clock.arrow.circlepath")
            }
        }
        .displayName("Paste from Hotstash")
        .description("Opens Hotstash clipboard history so you can choose what to paste.")
    }
}
