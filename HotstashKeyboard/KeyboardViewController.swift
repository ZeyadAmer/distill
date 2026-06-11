import UIKit
import SwiftUI

// MARK: - KeyboardViewController

/// Custom keyboard showing the user's recent Hotstash clips. Tapping a clip
/// inserts its text into the host app via `textDocumentProxy`.
///
/// Data source: the JSON mirror written by the main app into the app-group
/// UserDefaults (`KeyboardClipsMirror`). The keyboard never opens the
/// SwiftData/CloudKit store. Reading the app group requires Full Access; when
/// it's off we show a friendly hint instead of crashing.
final class KeyboardViewController: UIInputViewController {

    private static let keyboardHeight: CGFloat = 260

    private let dataSource = KeyboardDataSource()
    private var heightConstraint: NSLayoutConstraint?

    // MARK: Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()

        let rootView = KeyboardView(
            dataSource: dataSource,
            showsGlobeKey: needsInputModeSwitchKey,
            configureGlobeButton: { [weak self] button in
                guard let self else { return }
                button.addTarget(
                    self,
                    action: #selector(self.handleInputModeList(from:with:)),
                    for: .allTouchEvents
                )
            },
            onInsert: { [weak self] text in
                self?.textDocumentProxy.insertText(text)
            },
            onDelete: { [weak self] in
                self?.textDocumentProxy.deleteBackward()
            }
        )

        let host = UIHostingController(rootView: rootView)
        addChild(host)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        host.view.backgroundColor = .clear
        view.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        host.didMove(toParent: self)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        dataSource.reload(hasFullAccess: hasFullAccess)

        if heightConstraint == nil {
            let constraint = view.heightAnchor.constraint(equalToConstant: Self.keyboardHeight)
            constraint.priority = UILayoutPriority(999)
            constraint.isActive = true
            heightConstraint = constraint
        }
    }
}
