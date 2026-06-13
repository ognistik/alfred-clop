import Foundation

struct CropActionPreset: Codable, Equatable, Hashable {
    var size: String
    var longEdge: Bool

    init(size: CropSize) {
        self.size = size.value
        self.longEdge = size.longEdge
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let size = try container.decode(String.self, forKey: .size)
        let longEdge = try container.decode(Bool.self, forKey: .longEdge)

        guard let parsed = CropSizeParser.parse(size),
              parsed.value == size,
              parsed.longEdge == longEdge else {
            throw DecodingError.dataCorruptedError(
                forKey: .size,
                in: container,
                debugDescription: "Crop preset is not normalized or supported."
            )
        }

        self.size = size
        self.longEdge = longEdge
    }

    var cropSize: CropSize {
        CropSizeParser.parse(size)!
    }

    var displayValue: String {
        switch cropSize.kind {
        case let .fixedWidth(width):
            return "w\(width)"
        case let .fixedHeight(height):
            return "h\(height)"
        case .exactDimensions, .aspectRatio, .longEdge:
            return size
        }
    }

    var stableUID: String {
        "crop.preset.\(longEdge ? "long-edge" : "size").\(size)"
    }
}

enum ActionPreset: Codable, Equatable, Hashable {
    case crop(CropActionPreset)

    private enum CodingKeys: String, CodingKey {
        case type
        case size
        case longEdge
    }

    private enum PresetType: String, Codable {
        case crop
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case let .crop(preset):
            try container.encode(PresetType.crop, forKey: .type)
            try container.encode(preset.size, forKey: .size)
            try container.encode(preset.longEdge, forKey: .longEdge)
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(PresetType.self, forKey: .type) {
        case .crop:
            self = .crop(try CropActionPreset(from: decoder))
        }
    }
}

struct PresetDocument: Codable, Equatable {
    static let currentVersion = 1

    var version: Int
    var presets: [ActionPreset]

    init(version: Int = currentVersion, presets: [ActionPreset] = []) {
        self.version = version
        self.presets = presets
    }
}

struct SettingsDocument: Codable, Equatable {
    static let currentVersion = 1
    static let builtInOutputTemplate = "%P/%f-clop"

    var version: Int
    var presets: [ActionPreset]
    var outputTemplate: String

    init(
        version: Int = currentVersion,
        presets: [ActionPreset] = [],
        outputTemplate: String = builtInOutputTemplate
    ) {
        self.version = version
        self.presets = presets
        self.outputTemplate = outputTemplate
    }
}
