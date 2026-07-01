import Foundation
import Testing
@testable import Hotstash

struct LinkCleanerTests {

    @Test("Strips utm_* and known tracking params")
    func stripsTracking() {
        let out = LinkCleaner.clean("https://example.com/p?id=7&utm_source=news&fbclid=abc&igshid=xyz")
        #expect(out == "https://example.com/p?id=7")
    }

    @Test("Drops the query entirely when only tracking params remain")
    func dropsEmptyQuery() {
        let out = LinkCleaner.clean("https://example.com/p?utm_medium=email&utm_campaign=x")
        #expect(out == "https://example.com/p")
    }

    @Test("Unwraps Facebook l.php redirect to the real destination")
    func unwrapsFacebook() {
        let out = LinkCleaner.clean("https://l.facebook.com/l.php?u=https%3A%2F%2Fexample.com%2Fpost%3Futm_source%3Dfb&h=abc")
        #expect(out == "https://example.com/post")
    }

    @Test("Leaves clean URLs untouched")
    func leavesCleanURLs() {
        let out = LinkCleaner.clean("https://example.com/a/b?page=2")
        #expect(out == "https://example.com/a/b?page=2")
    }

    @Test("Non-URL input returned trimmed, unchanged")
    func nonURL() {
        #expect(LinkCleaner.clean("  just text  ") == "just text")
    }
}
