import SwiftUI

struct SnippetsView: View {

    @EnvironmentObject private var snippets: SnippetStore
    @EnvironmentObject private var history:  ClipboardHistoryManager
    @State private var showAdd       = false
    @State private var editTarget: Snippet?
    @State private var copiedID: UUID?

    var body: some View {
        NavigationStack {
            Group {
                if snippets.snippets.isEmpty {
                    emptyState
                } else {
                    list
                }
            }
            .navigationTitle("Snippets")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showAdd = true } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showAdd) {
                SnippetEditSheet(existingSnippet: nil)
                    .environmentObject(snippets)
            }
            .sheet(item: $editTarget) { snippet in
                SnippetEditSheet(existingSnippet: snippet)
                    .environmentObject(snippets)
            }
        }
    }

    // MARK: - Subviews

    private var list: some View {
        List {
            ForEach(snippets.snippets) { snippet in
                SnippetRow(snippet: snippet, isCopied: copiedID == snippet.id) {
                    copy(snippet)
                }
                .swipeActions(edge: .leading) {
                    Button { editTarget = snippet } label: {
                        Label("Edit", systemImage: "pencil")
                    }
                    .tint(.blue)
                }
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        snippets.delete(id: snippet.id)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        }
        .listStyle(.plain)
    }

    private var emptyState: some View {
        EmptyStateView(icon: "bookmark", title: "No Snippets", message: "Save frequently-used text here.") {
            Button("Add Snippet") { showAdd = true }
                .buttonStyle(.borderedProminent)
        }
    }

    private func copy(_ snippet: Snippet) {
        UIPasteboard.general.string = snippet.content
        let item = ClipboardItem(
            content: snippet.content,
            contentType: ContentDetector.detect(snippet.content)
        )
        history.add(item: item)
        withAnimation { copiedID = snippet.id }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            withAnimation { copiedID = nil }
        }
    }
}

// MARK: - SnippetRow

struct SnippetRow: View {
    let snippet: Snippet
    let isCopied: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(snippet.title)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                    Text(snippet.content)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer()
                Image(systemName: isCopied ? "checkmark.circle.fill" : "doc.on.doc")
                    .foregroundStyle(isCopied ? .green : .secondary)
                    .animation(.easeOut(duration: 0.15), value: isCopied)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.vertical, 4)
    }
}

// MARK: - SnippetEditSheet

struct SnippetEditSheet: View {

    @EnvironmentObject private var snippets: SnippetStore
    @Environment(\.dismiss) private var dismiss

    let existingSnippet: Snippet?

    @State private var title   = ""
    @State private var content = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Title") {
                    TextField("Optional title", text: $title)
                }
                Section("Content") {
                    TextEditor(text: $content)
                        .font(.system(.body, design: .monospaced))
                        .frame(minHeight: 120)
                }
            }
            .navigationTitle(existingSnippet == nil ? "New Snippet" : "Edit Snippet")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear {
                if let s = existingSnippet {
                    title   = s.title
                    content = s.content
                }
            }
        }
    }

    private func save() {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if let s = existingSnippet {
            snippets.update(id: s.id, title: title, content: trimmed)
        } else {
            snippets.add(title: title, content: trimmed)
        }
        dismiss()
    }
}
