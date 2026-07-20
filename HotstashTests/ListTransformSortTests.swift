import Testing
@testable import Hotstash

@Suite("List sort transforms")
struct ListTransformSortTests {

    @Test("Sort A→Z orders lines ascending")
    func sortAscending() {
        let result = SortAZTransform().apply(to: "banana\napple\ncherry")
        #expect(result == "apple\nbanana\ncherry")
    }

    @Test("Sort A→Z preserves a trailing newline instead of floating a blank line to the top")
    func sortPreservesTrailingNewline() {
        let result = SortAZTransform().apply(to: "banana\napple\ncherry\n")
        #expect(result == "apple\nbanana\ncherry\n")
    }

    @Test("Sort Z→A orders lines descending and keeps the trailing newline")
    func sortDescending() {
        let result = SortZATransform().apply(to: "apple\ncherry\nbanana\n")
        #expect(result == "cherry\nbanana\napple\n")
    }
}
