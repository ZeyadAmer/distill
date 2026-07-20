import UIKit
import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import Social

// Entry point for the Share Extension.
// Receives text from any app, shows a SwiftUI transform picker,
// copies the result to the clipboard and saves to shared history.
final class ShareViewController: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()
        extractText { [weak self] text in
            DispatchQueue.main.async {
                guard let self else { return }
                if let text {
                    self.showPicker(for: text)
                } else {
                    self.extensionContext?.completeRequest(returningItems: nil)
                }
            }
        }
    }

    // MARK: - Text extraction

    private func extractText(completion: @escaping (String?) -> Void) {
        guard let items = extensionContext?.inputItems as? [NSExtensionItem] else {
            completion(nil)
            return
        }

        for item in items {
            for provider in (item.attachments ?? []) {
                if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                    provider.loadItem(forTypeIdentifier: UTType.plainText.identifier) { data, _ in
                        if let text = data as? String {
                            completion(text)
                            return
                        }
                        if let data = data as? Data, let text = String(data: data, encoding: .utf8) {
                            completion(text)
                            return
                        }
                        completion(nil)
                    }
                    return
                }

                if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                    provider.loadItem(forTypeIdentifier: UTType.url.identifier) { data, _ in
                        if let url = data as? URL {
                            completion(url.absoluteString)
                        } else {
                            completion(nil)
                        }
                    }
                    return
                }
            }
        }

        completion(nil)
    }

    // MARK: - UI

    private func showPicker(for text: String) {
        let hostingVC = UIHostingController(
            rootView: ShareTransformView(
                inputText: text,
                onDone: { [weak self] in self?.extensionContext?.completeRequest(returningItems: nil) }
            )
        )
        addChild(hostingVC)
        view.addSubview(hostingVC.view)
        hostingVC.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            hostingVC.view.topAnchor.constraint(equalTo: view.topAnchor),
            hostingVC.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hostingVC.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hostingVC.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        hostingVC.didMove(toParent: self)
    }
}

// MARK: - ShareTransformView

private struct ShareTransformView: View {

    let inputText: String
    let onDone: () -> Void

    @State private var resultText       = ""
    @State private var selectedID: String?
    @State private var copied           = false
    @State private var searchText       = ""
    @State private var finished         = false

    /// completeRequest must be called at most once per NSExtensionContext.
    /// Guard every path (Cancel, Copy & Close, the delayed close) through here.
    private func finish() {
        guard !finished else { return }
        finished = true
        onDone()
    }

    private var filteredTransforms: [any Transform] {
        guard !searchText.isEmpty else { return IOSTransformSettings.enabledOrdered() }
        return IOSTransformSettings.enabledOrdered().filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Input preview
                VStack(alignment: .leading, spacing: 6) {
                    Text("Input")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(inputText)
                        .font(.system(.subheadline, design: .monospaced))
                        .lineLimit(4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .padding()

                if !resultText.isEmpty {
                    resultSection
                        .padding(.horizontal)
                        .padding(.bottom, 8)
                    Divider()
                }

                // Transform list
                List {
                    ForEach(TransformCategory.allCases, id: \.self) { category in
                        let transforms = filteredTransforms.filter { $0.category == category }
                        if !transforms.isEmpty {
                            Section(category.rawValue) {
                                ForEach(transforms, id: \.id) { transform in
                                    Button {
                                        apply(transform)
                                    } label: {
                                        TransformRowLabel(
                                            icon: transform.icon,
                                            name: transform.name,
                                            isSelected: selectedID == transform.id
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .searchable(text: $searchText, prompt: "Search transforms")
            }
            .navigationTitle("Hotstash")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { finish() }
                        .disabled(finished)
                }
            }
        }
    }

    private var resultSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Result")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    copyAndSave()
                } label: {
                    Label(copied ? "Copied!" : "Copy & Close",
                          systemImage: copied ? "checkmark" : "doc.on.doc")
                        .font(.caption.weight(.medium))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(copied ? .green : .accentColor)
                .animation(.easeOut(duration: 0.15), value: copied)
            }
            Text(resultText)
                .font(.system(.subheadline, design: .monospaced))
                .lineLimit(4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }

    private func apply(_ transform: any Transform) {
        selectedID = transform.id
        resultText = transform.apply(to: inputText)
    }

    private func copyAndSave() {
        guard !copied else { return }
        UIPasteboard.general.string = resultText
        saveToSharedHistory(resultText)
        withAnimation { copied = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { finish() }
    }

    /// Inserts the item into the shared SwiftData store (the main app exports
    /// it to CloudKit the next time it runs) and updates the keyboard mirror.
    private func saveToSharedHistory(_ text: String) {
        let item = ClipboardItem(content: text, contentType: ContentDetector.detect(text))
        let context = ModelContext(ModelContainer.hotstashIOSExtension)
        context.insert(item)
        do {
            try context.save()
        } catch {
            print("[HotstashShare] SwiftData save failed: \(error.localizedDescription)")
        }
        KeyboardClipsMirror.prepend(
            KeyboardClip(id: item.id, content: text, contentTypeRaw: item.contentTypeRaw, isPinned: false)
        )
    }
}

private struct TransformRowLabel: View {
    let icon: String
    let name: String
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                .frame(width: 20)
            Text(name)
                .foregroundStyle(.primary)
            Spacer()
            if isSelected {
                Image(systemName: "checkmark")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
            }
        }
        .contentShape(Rectangle())
    }
}
