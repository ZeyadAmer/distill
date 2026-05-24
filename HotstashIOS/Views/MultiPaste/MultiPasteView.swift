import SwiftUI

struct MultiPasteView: View {

    @EnvironmentObject private var paste:   MultiPasteStore
    @EnvironmentObject private var history: ClipboardHistoryManager
    @State private var showAdd            = false
    @State private var newText            = ""
    @State private var copied             = false
    @State private var showHistoryPicker  = false
    @State private var selectedHistoryIDs = Set<UUID>()

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if !paste.queue.isEmpty {
                    copyBanner
                    Divider()
                }

                Group {
                    if paste.queue.isEmpty {
                        emptyState
                    } else {
                        queueList
                    }
                }
            }
            .navigationTitle("Paste Queue")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if !paste.queue.isEmpty {
                        Button("Clear") { paste.clearAll() }
                            .foregroundStyle(.red)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showAdd = true } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showAdd) {
                addSheet
            }
        }
    }

    // MARK: - Subviews

    private var copyBanner: some View {
        VStack(spacing: 10) {
            Text("\(paste.queue.count) item\(paste.queue.count == 1 ? "" : "s") in queue")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 12) {
                Button {
                    copyAll(separator: "\n")
                } label: {
                    Label("New Line", systemImage: "return")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)

                Button {
                    copyAll(separator: " ")
                } label: {
                    Label("Inline", systemImage: "arrow.right")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
            }

            if copied {
                Label("Copied!", systemImage: "checkmark.circle.fill")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.green)
                    .transition(.opacity)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
        .animation(.easeOut(duration: 0.2), value: copied)
    }

    private var queueList: some View {
        List {
            ForEach(Array(paste.queue.enumerated()), id: \.element.id) { index, item in
                PasteQueueRow(index: index, item: item) {
                    paste.remove(id: item.id)
                }
            }
            .onMove { from, to in paste.move(fromOffsets: from, toOffset: to) }
        }
        .listStyle(.plain)
        .environment(\.editMode, .constant(.active))
    }

    private var emptyState: some View {
        EmptyStateView(icon: "list.number", title: "Queue Empty", message: "Add items, then copy them all as new lines or inline.") {
            Button("Add Item") { showAdd = true }
                .buttonStyle(.borderedProminent)
        }
    }

    private var addSheet: some View {
        NavigationStack {
            Form {
                Section("Text to add") {
                    TextEditor(text: $newText)
                        .font(.system(.body, design: .monospaced))
                        .frame(minHeight: 120)
                }
                Section {
                    Button {
                        selectedHistoryIDs = []
                        showHistoryPicker = true
                    } label: {
                        Label("Select from History", systemImage: "clock")
                    }
                }
            }
            .navigationTitle("Add to Queue")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showAdd = false; newText = "" }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        let trimmed = newText.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmed.isEmpty { paste.enqueue(text: trimmed) }
                        showAdd = false
                        newText = ""
                    }
                    .disabled(newText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .sheet(isPresented: $showHistoryPicker) {
                historyPickerSheet
            }
        }
    }

    private var historyPickerSheet: some View {
        NavigationStack {
            List(history.items, selection: $selectedHistoryIDs) { item in
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.content)
                        .font(.system(.subheadline, design: .monospaced))
                        .lineLimit(2)
                    Text(item.contentType.displayName)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle("Select Items")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showHistoryPicker = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add \(selectedHistoryIDs.isEmpty ? "" : "(\(selectedHistoryIDs.count))")") {
                        let toAdd = history.items
                            .filter { selectedHistoryIDs.contains($0.id) }
                        paste.enqueueAll(texts: toAdd.map { $0.content })
                        showHistoryPicker = false
                        showAdd = false
                        newText = ""
                    }
                    .disabled(selectedHistoryIDs.isEmpty)
                }
            }
        }
    }

    // MARK: - Actions

    private func copyAll(separator: String) {
        let text = paste.copyAll(separator: separator)
        guard !text.isEmpty else { return }
        let item = ClipboardItem(content: text, contentType: ContentDetector.detect(text))
        history.add(item: item)
        withAnimation { copied = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation { copied = false }
        }
    }
}

private struct PasteQueueRow: View {
    let index: Int
    let item: MultiPasteItem
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(Color.accentColor.opacity(0.15))
                .overlay {
                    Text("\(index + 1)")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Color.accentColor)
                }
                .frame(width: 28, height: 28)

            Text(item.text)
                .font(.system(.subheadline, design: .monospaced))
                .lineLimit(2)
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive, action: onDelete) {
                Label("Remove", systemImage: "trash")
            }
        }
    }
}
