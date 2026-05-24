import SwiftUI

struct HistoryView: View {

    @EnvironmentObject private var history: ClipboardHistoryManager
    @State private var searchText    = ""
    @State private var copied: UUID? = nil
    @State private var showClearConfirm = false

    private var displayItems: [ClipboardItem] {
        searchText.isEmpty ? history.items : history.search(query: searchText)
    }

    var body: some View {
        NavigationStack {
            Group {
                if history.items.isEmpty {
                    emptyState
                } else {
                    list
                }
            }
            .navigationTitle("History")
            .searchable(text: $searchText, prompt: "Search clipboard")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Clear", role: .destructive) {
                        showClearConfirm = true
                    }
                    .disabled(history.items.filter { !$0.isPinned }.isEmpty)
                }
            }
            .confirmationDialog("Clear unpinned history?", isPresented: $showClearConfirm, titleVisibility: .visible) {
                Button("Clear History", role: .destructive) {
                    history.clearUnpinned()
                }
            }
        }
    }

    // MARK: - Subviews

    private var list: some View {
        List {
            ForEach(displayItems) { item in
                HistoryRow(item: item, isCopied: copied == item.id) {
                    copy(item)
                }
                .swipeActions(edge: .leading) {
                    Button {
                        item.isPinned ? history.unpin(id: item.id) : history.pin(id: item.id)
                    } label: {
                        Label(item.isPinned ? "Unpin" : "Pin",
                              systemImage: item.isPinned ? "pin.slash" : "pin")
                    }
                    .tint(.orange)
                }
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        history.remove(id: item.id)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        }
        .listStyle(.plain)
    }

    private var emptyState: some View {
        EmptyStateView(icon: "clipboard", title: "No History", message: "Copy something and come back.")
    }

    // MARK: - Actions

    private func copy(_ item: ClipboardItem) {
        history.copyToClipboard(item)
        withAnimation(.easeOut(duration: 0.15)) { copied = item.id }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            withAnimation { copied = nil }
        }
    }
}
