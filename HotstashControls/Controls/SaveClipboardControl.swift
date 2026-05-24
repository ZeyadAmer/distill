import SwiftUI
import WidgetKit

@available(iOS 18.0, *)
struct SaveClipboardControl: ControlWidget {
    static let kind = "com.zeyadamer.hotstash.control.save"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind) {
            ControlWidgetButton(action: SaveClipboardIntent()) {
                Label("Save Clipboard", systemImage: "plus.square.on.square")
            }
        }
        .displayName("Save to Hotstash")
        .description("Saves the current clipboard content into Hotstash history.")
    }
}
