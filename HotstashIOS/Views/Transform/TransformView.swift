import SwiftUI

struct TransformView: View {

    @EnvironmentObject private var history: ClipboardHistoryManager
    @State private var inputText        = ""
    @State private var resultText       = ""
    @State private var selectedTransform: (any Transform)?
    @State private var copiedResult     = false
    @State private var searchText       = ""
    @FocusState private var inputFocused: Bool

    private var filteredTransforms: [any Transform] {
        guard !searchText.isEmpty else { return IOSTransforms.all }
        return IOSTransforms.all.filter {
            $0.name.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                inputSection
                Divider()
                transformList
            }
            .navigationTitle("Transform")
            .onAppear { loadFromClipboard() }
        }
    }

    // MARK: - Sections

    private var inputSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Input")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Paste from Clipboard") {
                    loadFromClipboard()
                }
                .font(.caption)
            }

            TextEditor(text: $inputText)
                .font(.system(.subheadline, design: .monospaced))
                .frame(height: 100)
                .padding(8)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .focused($inputFocused)
                .toolbar {
                    ToolbarItemGroup(placement: .keyboard) {
                        Spacer()
                        Button("Done") { inputFocused = false }
                    }
                }
                .onChange(of: inputText) { _ in
                    if let t = selectedTransform {
                        resultText = t.apply(to: inputText)
                    }
                }

            if !resultText.isEmpty {
                resultSection
            }
        }
        .padding()
    }

    private var resultSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Result")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    copyResult()
                } label: {
                    Label(
                        copiedResult ? "Copied!" : "Copy",
                        systemImage: copiedResult ? "checkmark" : "doc.on.doc"
                    )
                    .font(.caption.weight(.medium))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.mini)
                .tint(copiedResult ? .green : .accentColor)
                .animation(.easeOut(duration: 0.15), value: copiedResult)
            }

            Text(resultText)
                .font(.system(.subheadline, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .lineLimit(6)
        }
    }

    private var transformList: some View {
        List {
            ForEach(TransformCategory.allCases, id: \.self) { category in
                let transforms = filteredTransforms.filter { $0.category == category }
                if !transforms.isEmpty {
                    Section(category.rawValue) {
                        ForEach(transforms, id: \.id) { transform in
                            TransformRow(
                                transform: transform,
                                isSelected: selectedTransform?.id == transform.id
                            ) {
                                apply(transform)
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .searchable(text: $searchText, prompt: "Search transforms")
    }

    // MARK: - Actions

    private func loadFromClipboard() {
        let text = UIPasteboard.general.string ?? ""
        guard !text.isEmpty else { return }
        inputText = text
        resultText = ""
        selectedTransform = nil
    }

    private func apply(_ transform: any Transform) {
        guard !inputText.isEmpty else { return }
        selectedTransform = transform
        resultText = transform.apply(to: inputText)
    }

    private func copyResult() {
        guard !resultText.isEmpty else { return }
        UIPasteboard.general.string = resultText
        let item = ClipboardItem(
            content: resultText,
            contentType: ContentDetector.detect(resultText)
        )
        history.add(item: item)
        withAnimation { copiedResult = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation { copiedResult = false }
        }
    }
}
