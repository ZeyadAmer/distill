import AppKit
import Foundation
import LinkPresentation
import OSLog
import Vision

// MARK: - ItemEnricher

/// Background enrichment for freshly-captured items:
/// - OCR: text inside copied images becomes searchable (`ocrText`)
/// - Link titles: URL items get their page title (`linkTitle`)
///
/// Both run after capture and update the stored item when they finish, so
/// capture latency is never affected. Failures are silent by design — an
/// item without enrichment is still fully functional.
@MainActor
final class ItemEnricher {

    static let shared = ItemEnricher()

    private let logger = Logger(subsystem: "com.zeyadamer.hotstash", category: "ItemEnricher")
    /// Providers retained for the duration of their fetch (LPMetadataProvider is one-shot).
    private var activeProviders: [UUID: LPMetadataProvider] = [:]

    private init() {}

    func enrich(_ item: ClipboardItem) {
        switch item.contentType {
        case .image:
            recognizeText(in: item)
        case .url:
            fetchLinkTitle(for: item)
        default:
            break
        }
    }

    // MARK: - OCR

    private func recognizeText(in item: ClipboardItem) {
        guard let data = item.imageData else { return }
        let id = item.id
        Task.detached(priority: .utility) {
            guard let cgImage = NSImage(data: data)?
                .cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }

            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            let handler = VNImageRequestHandler(cgImage: cgImage)
            try? handler.perform([request])

            let text = (request.results ?? [])
                .compactMap { $0.topCandidates(1).first?.string }
                .joined(separator: "\n")
            guard !text.isEmpty else { return }

            await MainActor.run {
                ClipboardStore.shared.setOCRText(id: id, text: text)
            }
        }
    }

    // MARK: - Link titles

    private func fetchLinkTitle(for item: ClipboardItem) {
        guard let url = URL(string: item.content.trimmingCharacters(in: .whitespacesAndNewlines)),
              url.scheme == "http" || url.scheme == "https" else { return }

        let provider = LPMetadataProvider()
        provider.timeout = 10
        let id = item.id
        activeProviders[id] = provider

        provider.startFetchingMetadata(for: url) { [weak self] metadata, error in
            Task { @MainActor in
                self?.activeProviders[id] = nil
                if let error {
                    self?.logger.debug("link metadata failed: \(error.localizedDescription, privacy: .public)")
                    return
                }
                guard let title = metadata?.title, !title.isEmpty else { return }
                ClipboardStore.shared.setLinkTitle(id: id, title: title)
            }
        }
    }
}
