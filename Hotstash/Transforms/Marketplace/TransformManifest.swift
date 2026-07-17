import Foundation

// MARK: - Transform Kind

/// Whether a marketplace transform operates on text (via JS) or images (via a step pipeline).
enum TransformKind: String, Codable {
    case text
    case image
}

// MARK: - Param Value

/// A single parameter value for an image step. Encodes/decodes as a raw JSON scalar:
/// a JSON string ↔ `.string`, a JSON number ↔ `.double`/`.int`, a JSON bool ↔ `.bool`.
enum ParamValue: Codable, Equatable {
    case string(String)
    case double(Double)
    case int(Int)
    case bool(Bool)

    // MARK: Accessors

    var stringValue: String? {
        if case let .string(value) = self { return value }
        return nil
    }

    var doubleValue: Double? {
        switch self {
        case let .double(value): return value
        case let .int(value): return Double(value)
        default: return nil
        }
    }

    var intValue: Int? {
        if case let .int(value) = self { return value }
        return nil
    }

    var boolValue: Bool? {
        if case let .bool(value) = self { return value }
        return nil
    }

    // MARK: Codable

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        // Bool must be checked before numeric types: JSON booleans can otherwise
        // be coerced into 0/1 by some decoders.
        if let value = try? container.decode(Bool.self) {
            self = .bool(value)
            return
        }
        if let value = try? container.decode(Int.self) {
            self = .int(value)
            return
        }
        if let value = try? container.decode(Double.self) {
            self = .double(value)
            return
        }
        if let value = try? container.decode(String.self) {
            self = .string(value)
            return
        }

        throw DecodingError.dataCorruptedError(
            in: container,
            debugDescription: "ParamValue must be a string, number, or bool scalar"
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .string(value): try container.encode(value)
        case let .double(value): try container.encode(value)
        case let .int(value): try container.encode(value)
        case let .bool(value): try container.encode(value)
        }
    }
}

// MARK: - Image Step

/// A single step in an image transform pipeline (e.g. resize, rotate, grayscale).
struct ImageStep: Codable, Equatable {
    let type: String
    let params: [String: ParamValue]

    init(type: String, params: [String: ParamValue] = [:]) {
        self.type = type
        self.params = params
    }

    private enum CodingKeys: String, CodingKey {
        case type
        case params
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decode(String.self, forKey: .type)
        params = try container.decodeIfPresent([String: ParamValue].self, forKey: .params) ?? [:]
    }
}

// MARK: - Transform Body

/// The executable payload of a transform. Encoded as an object that contains either
/// `"js"` (text transforms) or `"steps"` (image transforms).
enum TransformBody: Codable, Equatable {
    case text(js: String)
    case image(steps: [ImageStep])

    private enum CodingKeys: String, CodingKey {
        case js
        case steps
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let js = try container.decodeIfPresent(String.self, forKey: .js) {
            self = .text(js: js)
            return
        }
        if let steps = try container.decodeIfPresent([ImageStep].self, forKey: .steps) {
            self = .image(steps: steps)
            return
        }
        throw DecodingError.dataCorruptedError(
            forKey: CodingKeys.js,
            in: container,
            debugDescription: "TransformBody must contain either \"js\" or \"steps\""
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .text(js):
            try container.encode(js, forKey: .js)
        case let .image(steps):
            try container.encode(steps, forKey: .steps)
        }
    }
}

// MARK: - Transform Manifest

/// The marketplace manifest describing a single transform: metadata plus its executable body.
struct TransformManifest: Codable, Equatable, Identifiable {
    let schemaVersion: Int
    let id: UUID
    let slug: String
    let version: Int
    let kind: TransformKind
    let name: String
    let description: String
    /// Optional worked example shown on the transform's detail page. Populated by
    /// the author or carried over from the AI generator's example.
    let exampleInput: String?
    let exampleOutput: String?
    let icon: String
    let category: String
    let authorId: String?
    let authorName: String?
    let createdAt: Date
    let updatedAt: Date
    let body: TransformBody

    init(
        schemaVersion: Int = 1,
        id: UUID = UUID(),
        slug: String,
        version: Int = 1,
        kind: TransformKind,
        name: String,
        description: String,
        exampleInput: String? = nil,
        exampleOutput: String? = nil,
        icon: String,
        category: String,
        authorId: String? = nil,
        authorName: String? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        body: TransformBody
    ) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.slug = slug
        self.version = version
        self.kind = kind
        self.name = name
        self.description = description
        self.exampleInput = exampleInput
        self.exampleOutput = exampleOutput
        self.icon = icon
        self.category = category
        self.authorId = authorId
        self.authorName = authorName
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.body = body
    }
}
