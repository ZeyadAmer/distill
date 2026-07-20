import SwiftUI
import UniformTypeIdentifiers

// MARK: - TransformBuilderView

/// Authoring UI for creating or editing a transform. Builds a `TransformManifest`
/// from form input, runs a live text test, saves to the local library, and can
/// export a `.hotstashtransform` file.
struct TransformBuilderView: View {

    /// Existing manifest to edit, or nil to author a new one.
    let editing: TransformManifest?
    var onSaved: (() -> Void)?

    @Environment(\.dismiss) private var dismiss

    // Metadata
    @State private var name = ""
    @State private var description = ""
    @State private var exampleInput = ""
    @State private var exampleOutput = ""
    @State private var category = TransformCategory.cleanup.rawValue
    @State private var icon = "wand.and.stars"
    @State private var iconMode: IconMode = .symbol
    @State private var kind: TransformKind = .text

    /// How the author is currently entering the icon. The stored `icon` string
    /// stays polymorphic (symbol name / emoji / data URI); this only drives the UI.
    enum IconMode: String, CaseIterable {
        case symbol = "Symbol", emoji = "Emoji", image = "Image"
    }

    // Bodies
    @State private var jsSource = "function transform(input) {\n  return input;\n}"
    @State private var steps: [EditableStep] = []

    // Live test
    @State private var sampleInput = ""
    @State private var testOutput = ""
    @State private var testFailed = false

    // Feedback
    @State private var saveMessage: String?

    // AI generation
    @ObservedObject private var purchase = PurchaseManager.shared
    @State private var aiDescription = ""
    @State private var aiExampleInput = ""
    @State private var aiExpectedOutput = ""
    @State private var aiBusy = false
    @State private var aiStatus: AIStatus?

    /// Result badge shown after an AI generation attempt.
    enum AIStatus: Equatable {
        case verified, unverified, error(String)
    }

    init(editing: TransformManifest? = nil, onSaved: (() -> Void)? = nil) {
        self.editing = editing
        self.onSaved = onSaved
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    aiSection
                    metadataSection
                    bodySection
                    testSection
                }
                .padding(16)
            }
            Divider()
            footer
        }
        .frame(width: 520, height: 620)
        .onAppear(perform: loadEditing)
    }

    // MARK: Header

    private var header: some View {
        HStack {
            Text(editing == nil ? "New Transform" : "Edit Transform")
                .font(.title3).bold()
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(16)
    }

    // MARK: AI generation

    /// Describe-and-example panel that generates the JS via the backend, then
    /// self-verifies against the example. Hidden entirely when there's no backend
    /// configured or for image transforms (JS-only feature).
    @ViewBuilder
    private var aiSection: some View {
        if kind == .text, AIGenerationServiceProvider.isConfigured {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("Generate with AI", systemImage: "sparkles").font(.headline)
                    Spacer()
                    if !purchase.isPurchased {
                        Text("PRO").font(.caption2).bold()
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color.accentColor.opacity(0.15))
                            .clipShape(Capsule())
                    }
                }
                Text("Describe what it should do and give one example. AI writes the function, then checks it against your example.")
                    .font(.caption).foregroundStyle(.secondary)

                TextField("Description — e.g. convert to kebab-case", text: $aiDescription)
                    .textFieldStyle(.roundedBorder)
                HStack(spacing: 8) {
                    labeledField("Example input") {
                        TextField("Hello World", text: $aiExampleInput, axis: .vertical).textFieldStyle(.roundedBorder)
                    }
                    labeledField("Expected output") {
                        TextField("hello-world", text: $aiExpectedOutput, axis: .vertical).textFieldStyle(.roundedBorder)
                    }
                }

                HStack(spacing: 10) {
                    Button(action: generateWithAI) {
                        if aiBusy {
                            ProgressView().controlSize(.small)
                        } else {
                            Label("Generate", systemImage: "sparkles")
                        }
                    }
                    .disabled(!canGenerate)
                    if let aiStatus { aiStatusBadge(aiStatus) }
                    Spacer()
                }
                if !purchase.isPurchased {
                    Text("Upgrade to Pro to use AI generation.")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            .padding(10)
            .background(Color.accentColor.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    @ViewBuilder
    private func aiStatusBadge(_ status: AIStatus) -> some View {
        switch status {
        case .verified:
            Label("Verified", systemImage: "checkmark.seal.fill")
                .font(.caption).foregroundStyle(.green)
        case .unverified:
            Label("Couldn't verify — review it", systemImage: "exclamationmark.triangle.fill")
                .font(.caption).foregroundStyle(.orange)
        case .error(let message):
            Text(message).font(.caption).foregroundStyle(.red)
                .lineLimit(2)
        }
    }

    private var canGenerate: Bool {
        purchase.isPurchased && !aiBusy
            && !aiDescription.trimmingCharacters(in: .whitespaces).isEmpty
            && !aiExampleInput.isEmpty
            && !aiExpectedOutput.isEmpty
    }

    private func generateWithAI() {
        guard let service = AIGenerationServiceProvider.shared else {
            aiStatus = .error("AI generation isn't available in this build.")
            return
        }
        aiBusy = true
        aiStatus = nil
        let generator = AITransformGenerator(service: service)
        let desc = aiDescription
        let input = aiExampleInput
        let expected = aiExpectedOutput
        Task {
            defer { aiBusy = false }
            let entitlement = await PurchaseManager.shared.proEntitlementJWS()
                ?? PurchaseManager.debugEntitlementFallback
            do {
                let outcome = try await generator.generate(
                    description: desc, exampleInput: input, expectedOutput: expected,
                    deviceID: DeviceTracker.installID, entitlement: entitlement
                )
                applyGenerated(outcome, generatedExampleInput: input)
            } catch {
                aiStatus = .error((error as? LocalizedError)?.errorDescription ?? "Generation failed.")
            }
        }
    }

    /// Fills the editor from a generated transform. Metadata only fills fields the
    /// user hasn't already typed into; the JS always replaces the editor content.
    private func applyGenerated(_ outcome: AITransformGenerator.Outcome, generatedExampleInput: String) {
        let generated: AIGeneratedTransform
        let verified: Bool
        switch outcome {
        case .verified(let g):   generated = g; verified = true
        case .unverified(let g): generated = g; verified = false
        }

        jsSource = generated.js
        if name.trimmingCharacters(in: .whitespaces).isEmpty, let suggested = generated.name {
            name = suggested
        }
        if description.trimmingCharacters(in: .whitespaces).isEmpty, let suggested = generated.description {
            description = suggested
        }
        if let suggested = generated.category, TransformCategory(rawValue: suggested) != nil {
            category = suggested
        }
        if let suggested = generated.icon, !suggested.isEmpty {
            icon = suggested
            iconMode = Self.iconMode(for: suggested)
        }

        // Carry the AI example over as the transform's worked example, unless the
        // author already filled them in.
        if exampleInput.trimmingCharacters(in: .whitespaces).isEmpty {
            exampleInput = aiExampleInput
        }
        if exampleOutput.trimmingCharacters(in: .whitespaces).isEmpty {
            exampleOutput = aiExpectedOutput
        }

        // Prefill the live-test with the example and run it so the result is visible.
        sampleInput = generatedExampleInput
        runTextTest()
        aiStatus = verified ? .verified : .unverified
    }

    // MARK: Metadata

    private var metadataSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            labeledField("Name") {
                TextField("Transform name", text: $name).textFieldStyle(.roundedBorder)
            }
            labeledField("Description") {
                TextField("Short description", text: $description).textFieldStyle(.roundedBorder)
            }
            HStack(spacing: 8) {
                labeledField("Example input (optional)") {
                    TextField("Hello World", text: $exampleInput, axis: .vertical).textFieldStyle(.roundedBorder)
                }
                labeledField("Example output (optional)") {
                    TextField("hello-world", text: $exampleOutput, axis: .vertical).textFieldStyle(.roundedBorder)
                }
            }
            labeledField("Category") {
                Picker("", selection: $category) {
                    ForEach(TransformCategory.allCases, id: \.self) { c in
                        Text(c.rawValue).tag(c.rawValue)
                    }
                }
                .labelsHidden()
            }
            iconField
            labeledField("Kind") {
                Picker("", selection: $kind) {
                    Text("Text").tag(TransformKind.text)
                    Text("Image").tag(TransformKind.image)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 200)
            }
        }
    }

    // MARK: Icon

    private var iconField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Icon").font(.caption).foregroundStyle(.secondary)
            Picker("", selection: $iconMode) {
                ForEach(IconMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .labelsHidden().pickerStyle(.segmented).frame(width: 260)
            .onChange(of: iconMode) { _, mode in normalizeIcon(for: mode) }

            HStack(spacing: 10) {
                TransformIconView(icon: icon.isEmpty ? "wand.and.stars" : icon)
                    .foregroundStyle(.tint)
                    .frame(width: 30, height: 30)
                    .background(Color.secondary.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 6))

                switch iconMode {
                case .symbol:
                    TextField("wand.and.stars", text: $icon).textFieldStyle(.roundedBorder)
                case .emoji:
                    TextField("🔥", text: $icon).textFieldStyle(.roundedBorder)
                    Button("Emoji…") { NSApp.orderFrontCharacterPalette(nil) }
                case .image:
                    Text(icon.hasPrefix("data:") ? "Custom image · 64×64 PNG" : "No image chosen")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Choose…") { chooseImage() }
                }
            }
        }
    }

    // MARK: Body

    @ViewBuilder
    private var bodySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Body").font(.headline)
            if kind == .text {
                Text("Define a global transform(input) function.")
                    .font(.caption).foregroundStyle(.secondary)
                TextEditor(text: $jsSource)
                    .font(.system(.body, design: .monospaced))
                    .frame(height: 160)
                    .border(Color.secondary.opacity(0.3))
            } else {
                imageStepBuilder
            }
        }
    }

    private var imageStepBuilder: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach($steps) { $step in
                StepRow(step: $step) { remove(step) }
            }
            Menu {
                ForEach(EditableStep.StepType.allCases, id: \.self) { type in
                    Button(type.rawValue) { steps.append(EditableStep(type: type)) }
                }
            } label: {
                Label("Add Step", systemImage: "plus.circle")
            }
        }
    }

    // MARK: Test

    @ViewBuilder
    private var testSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Live Test").font(.headline)
            if kind == .text {
                HStack {
                    TextField("Sample input", text: $sampleInput).textFieldStyle(.roundedBorder)
                    Button("Run") { runTextTest() }
                }
                if !testOutput.isEmpty || testFailed {
                    Text(testFailed ? "Transform errored — check your JS." : testOutput)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(testFailed ? .red : .primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                        .background(Color(nsColor: .textBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
            } else {
                Text("Test image transforms with a copied image from the panel.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Footer

    private var footer: some View {
        HStack {
            if let saveMessage {
                Text(saveMessage).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Export…") { export() }
            Button("Save") { save() }
                .buttonStyle(.borderedProminent)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(16)
    }

    // MARK: Helpers

    private func labeledField<Content: View>(_ label: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            content()
        }
    }

    private func remove(_ step: EditableStep) {
        steps.removeAll { $0.id == step.id }
    }

    /// Trims a field, returning nil when it holds only whitespace.
    private func blankToNil(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    // MARK: Icon helpers

    /// The mode implied by a stored icon string.
    static func iconMode(for icon: String) -> IconMode {
        if icon.hasPrefix("data:") { return .image }
        if TransformIconView.isEmoji(icon) { return .emoji }
        return .symbol
    }

    /// Clears a value that doesn't belong to the newly-selected mode so the
    /// field starts fresh (e.g. switching Image → Symbol drops the data URI).
    private func normalizeIcon(for mode: IconMode) {
        switch mode {
        case .symbol: if icon.hasPrefix("data:") || TransformIconView.isEmoji(icon) { icon = "wand.and.stars" }
        case .emoji:  if !TransformIconView.isEmoji(icon) { icon = "" }
        case .image:  if !icon.hasPrefix("data:") { icon = "" }
        }
    }

    private func chooseImage() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.png, .jpeg, .heic, .image]
        guard panel.runModal() == .OK, let url = panel.url,
              let image = NSImage(contentsOf: url) else { return }
        guard let data = Self.pngIcon(image, side: 64) else {
            saveMessage = "Couldn't process that image."
            return
        }
        icon = "data:image/png;base64," + data.base64EncodedString()
    }

    /// Redraws any image into a `side`×`side` RGBA PNG — bounds the base64 blob
    /// stored inline in the transform (a 64px PNG is a few KB).
    static func pngIcon(_ image: NSImage, side: Int) -> Data? {
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ) else { return nil }
        rep.size = NSSize(width: side, height: side)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image.draw(in: NSRect(x: 0, y: 0, width: side, height: side),
                   from: .zero, operation: .copy, fraction: 1.0)
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:])
    }

    private func runTextTest() {
        let result = TextTransformEngine.run(js: jsSource, input: sampleInput)
        testFailed = result.didError
        testOutput = result.output
    }

    // MARK: Load / Save / Export

    private func loadEditing() {
        guard let manifest = editing else { return }
        name = manifest.name
        description = manifest.description
        exampleInput = manifest.exampleInput ?? ""
        exampleOutput = manifest.exampleOutput ?? ""
        category = manifest.category
        icon = manifest.icon
        iconMode = Self.iconMode(for: manifest.icon)
        kind = manifest.kind
        switch manifest.body {
        case let .text(js):
            jsSource = js
        case let .image(imageSteps):
            steps = imageSteps.map(EditableStep.init(from:))
        }
    }

    private func buildManifest() -> TransformManifest {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let body: TransformBody = kind == .text
            ? .text(js: jsSource)
            : .image(steps: steps.map { $0.toImageStep() })
        return TransformManifest(
            id: editing?.id ?? UUID(),
            // Preserve the slug when editing — it's the stable identity used by the
            // registry, local library, and server. Only new transforms derive it.
            slug: editing?.slug ?? Self.slug(from: trimmedName),
            version: (editing?.version ?? 0) + 1,
            kind: kind,
            name: trimmedName,
            description: description,
            exampleInput: blankToNil(exampleInput),
            exampleOutput: blankToNil(exampleOutput),
            icon: icon.isEmpty ? "wand.and.stars" : icon,
            category: category,
            authorName: editing?.authorName,
            body: body
        )
    }

    private func save() {
        let manifest = buildManifest()
        do {
            try MarketplaceLibrary.shared.upsert(manifest: manifest, origin: "local")
        } catch {
            saveMessage = "Couldn't save: \(error.localizedDescription)"
            return
        }
        saveMessage = "Saved."
        onSaved?()
        dismiss()
    }

    private func export() {
        let manifest = buildManifest()
        guard let data = try? MarketplaceLibrary.shared.exportData(manifest) else {
            saveMessage = "Couldn't encode manifest."
            return
        }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(manifest.slug).\(MarketplaceLibrary.fileExtension)"
        if let type = UTType(filenameExtension: MarketplaceLibrary.fileExtension) {
            panel.allowedContentTypes = [type]
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try data.write(to: url)
            saveMessage = "Exported."
        } catch {
            saveMessage = "Export failed."
        }
    }

    /// Generates a non-empty slug: lowercased, non-alphanumeric → "-", trimmed.
    static func slug(from name: String) -> String {
        let lowered = name.lowercased()
        var slug = ""
        var lastWasDash = false
        for character in lowered {
            if character.isLetter || character.isNumber {
                slug.append(character)
                lastWasDash = false
            } else if !lastWasDash {
                slug.append("-")
                lastWasDash = true
            }
        }
        let trimmed = slug.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return trimmed.isEmpty ? "transform-\(UUID().uuidString.prefix(8).lowercased())" : trimmed
    }
}

// MARK: - StepRow

/// One editable image step: a type label, remove button, and param fields.
private struct StepRow: View {
    @Binding var step: EditableStep
    let onRemove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(step.type.rawValue).font(.body).bold()
                Spacer()
                Button(role: .destructive) { onRemove() } label: {
                    Image(systemName: "minus.circle")
                }
                .buttonStyle(.plain)
            }
            ForEach(step.type.paramKeys, id: \.self) { key in
                HStack {
                    Text(key).font(.caption).foregroundStyle(.secondary).frame(width: 80, alignment: .leading)
                    TextField(key, text: Binding(
                        get: { step.params[key] ?? "" },
                        set: { step.params[key] = $0 }
                    ))
                    .textFieldStyle(.roundedBorder)
                }
            }
        }
        .padding(8)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

// MARK: - EditableStep

/// Mutable editor model for an image step; bridges to/from `ImageStep`.
struct EditableStep: Identifiable, Equatable {
    let id = UUID()
    var type: StepType
    var params: [String: String]

    enum StepType: String, CaseIterable {
        case resize, grayscale, rotate, flipHorizontal, convertPNG, convertWebP

        /// Param field keys exposed for this step type.
        var paramKeys: [String] {
            switch self {
            case .resize: return ["scale", "maxDim"]
            case .rotate: return ["degrees"]
            default: return []
            }
        }
    }

    init(type: StepType, params: [String: String] = [:]) {
        self.type = type
        self.params = params
    }

    init(from step: ImageStep) {
        self.type = StepType(rawValue: step.type) ?? .grayscale
        var stringParams: [String: String] = [:]
        for (key, value) in step.params {
            if let double = value.doubleValue {
                stringParams[key] = double == double.rounded() ? String(Int(double)) : String(double)
            } else if let string = value.stringValue {
                stringParams[key] = string
            }
        }
        self.params = stringParams
    }

    /// Converts edited string params into typed `ParamValue`s for the manifest.
    func toImageStep() -> ImageStep {
        var typed: [String: ParamValue] = [:]
        for key in type.paramKeys {
            guard let raw = params[key]?.trimmingCharacters(in: .whitespaces), !raw.isEmpty else { continue }
            if key == "maxDim" || key == "degrees", let intValue = Int(raw) {
                typed[key] = .int(intValue)
            } else if let doubleValue = Double(raw) {
                typed[key] = .double(doubleValue)
            }
        }
        return ImageStep(type: type.rawValue, params: typed)
    }
}
