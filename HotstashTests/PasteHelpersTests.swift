import Foundation
import Testing
@testable import Hotstash

struct FieldMatcherTests {

    let stack: [(content: String, label: String)] = [
        ("Zeyad Amer", ""),
        ("zeyad@example.com", ""),
        ("+20 100 123 4567", ""),
        ("EG380019000500000000263180002", "IBAN"),
    ]

    @Test("Email field picks the email item")
    func emailField() {
        #expect(FieldMatcher.bestIndex(fieldText: "Email address you@company.com", candidates: stack) == 1)
    }

    @Test("Phone field picks the phone item")
    func phoneField() {
        #expect(FieldMatcher.bestIndex(fieldText: "Mobile number", candidates: stack) == 2)
    }

    @Test("A field named like an item's label picks that item")
    func labelMatch() {
        #expect(FieldMatcher.bestIndex(fieldText: "Your IBAN", candidates: stack) == 3)
    }

    @Test("Unknown or empty fields keep stack order")
    func noMatch() {
        #expect(FieldMatcher.bestIndex(fieldText: "Company", candidates: stack) == nil)
        #expect(FieldMatcher.bestIndex(fieldText: "", candidates: stack) == nil)
    }

    @Test("Short numbers aren't phones")
    func shortNumber() {
        #expect(FieldMatcher.kind(ofContent: "12345") == nil)
    }
}

struct SourceLinksTests {

    let page = URL(string: "https://example.com/post#intro")!

    @Test("Short text becomes one encoded directive, old fragment dropped")
    func shortText() {
        let url = SourceLinks.textFragmentURL(page: page, text: "self-hosted, fast & cheap")
        #expect(url.absoluteString == "https://example.com/post#:~:text=self%2Dhosted%2C%20fast%20%26%20cheap")
    }

    @Test("Long text uses first and last four words")
    func longText() {
        let url = SourceLinks.textFragmentURL(page: page, text: "one two three four five six seven eight nine ten")
        #expect(url.absoluteString == "https://example.com/post#:~:text=one%20two%20three%20four,seven%20eight%20nine%20ten")
    }
}

struct OneTimeClipsTests {

    @Test("Verification codes are one-time", arguments: ["123456", "12345678", "123 456", "123-456", "G-482913"])
    func codes(code: String) {
        #expect(OneTimeClips.isOneTime(code))
    }

    @Test("Ordinary values are kept", arguments: ["2026", "12345", "hello 123456", "+20 100 123 4567", "https://example.com/?id=1"])
    func notCodes(text: String) {
        #expect(!OneTimeClips.isOneTime(text))
    }

    @Test("Links carrying a long single-use token are one-time")
    func tokenLink() {
        #expect(OneTimeClips.isOneTime("https://app.example.com/login?token=abcdef0123456789xyz"))
        #expect(!OneTimeClips.isOneTime("https://app.example.com/login?token=short"))
    }
}
