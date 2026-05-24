import Foundation

struct Snippet: Identifiable, Codable, Equatable {
    let id: UUID
    var title: String
    var content: String
    let createdAt: Date

    init(id: UUID = UUID(), title: String, content: String, createdAt: Date = Date()) {
        self.id = id
        self.title = title
        self.content = content
        self.createdAt = createdAt
    }
}

@MainActor
final class SnippetStore: ObservableObject {

    static let shared = SnippetStore()

    @Published private(set) var snippets: [Snippet] = []

    private init() { load() }

    func add(title: String, content: String) {
        let snippet = Snippet(title: title.isEmpty ? String(content.prefix(40)) : title, content: content)
        snippets.insert(snippet, at: 0)
        persist()
    }

    func delete(id: UUID) {
        snippets.removeAll { $0.id == id }
        persist()
    }

    func update(id: UUID, title: String, content: String) {
        guard let i = snippets.firstIndex(where: { $0.id == id }) else { return }
        snippets[i].title   = title
        snippets[i].content = content
        persist()
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(snippets) else { return }
        SharedDefaults.store.set(data, forKey: SharedDefaults.Keys.snippets)
    }

    private func load() {
        guard
            let data    = SharedDefaults.store.data(forKey: SharedDefaults.Keys.snippets),
            let decoded = try? JSONDecoder().decode([Snippet].self, from: data)
        else { return }
        snippets = decoded
    }
}
