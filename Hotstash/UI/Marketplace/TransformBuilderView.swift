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
    @State private var category = TransformCategory.cleanup.rawValue
    @State private var icon = "wand.and.stars"
    @State private var kind: TransformKind = .text

    // Bodies
    @State private var jsSource = "function transform(input) {\n  return input;\n}"
    @State private var steps: [EditableStep] = []

    // Live test
    @State private var sampleInput = ""
    @State private var testOutput = ""
    @State private var testFailed = false

    // Feedback
    @State private var saveMessage: String?

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

    // MARK: Metadata

    private var metadataSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            labeledField("Name") {
                TextField("Transform name", text: $name).textFieldStyle(.roundedBorder)
            }
            labeledField("Description") {
                TextField("Short description", text: $description).textFieldStyle(.roundedBorder)
            }
            HStack {
                labeledField("Category") {
                    Picker("", selection: $category) {
                        ForEach(TransformCategory.allCases, id: \.self) { c in
                            Text(c.rawValue).tag(c.rawValue)
                        }
                    }
                    .labelsHidden()
                }
                labeledField("Icon (SF Symbol)") {
                    TextField("wand.and.stars", text: $icon).textFieldStyle(.roundedBorder)
                }
            }
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
        category = manifest.category
        icon = manifest.icon
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
            slug: Self.slug(from: trimmedName),
            version: (editing?.version ?? 0) + 1,
            kind: kind,
            name: trimmedName,
            description: description,
            icon: icon.isEmpty ? "wand.and.stars" : icon,
            category: category,
            authorName: editing?.authorName,
            body: body
        )
    }

    private func save() {
        let manifest = buildManifest()
        MarketplaceLibrary.shared.upsert(manifest: manifest, origin: "local")
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
