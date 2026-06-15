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

struct DownscaleActionPreset: Codable, Equatable, Hashable {
    var factor: Double

    init(factor: Double) {
        self.factor = factor
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let factor = try container.decode(Double.self, forKey: .factor)

        guard DownscaleFactorParser.isSupported(factor) else {
            throw DecodingError.dataCorruptedError(
                forKey: .factor,
                in: container,
                debugDescription: "Downscale preset factor is not supported."
            )
        }

        self.factor = factor
    }

    var displayValue: String {
        DownscaleFactorParser.displayValue(for: factor)
    }

    var stableFactor: String {
        DownscaleFactorParser.factorValue(for: factor)
    }

    var stableUID: String {
        "downscale.preset.factor.\(stableFactor)"
    }
}

struct ConversionActionPreset: Codable, Equatable, Hashable {
    var choice: ConversionChoice

    init(choice: ConversionChoice) {
        self.choice = choice
    }

    init(from decoder: Decoder) throws {
        let choice = try ConversionChoice(from: decoder)
        guard choice.setting != nil, ConversionCatalog.isSupported(choice) else {
            throw DecodingError.dataCorrupted(
                .init(
                    codingPath: decoder.codingPath,
                    debugDescription:
                        "Conversion preset is incomplete or unsupported."
                )
            )
        }
        self.choice = choice
    }

    var displayValue: String {
        choice.displayValue
    }

    var stableUID: String {
        let setting: String
        switch choice.setting {
        case .compression(let value):
            setting = "compression.\(value)"
        case .automaticCompression:
            setting = "compression.auto"
        case .bitrate(let value):
            setting = "bitrate.\(value)"
        case nil:
            setting = "default"
        }
        return "convert.preset.\(choice.media.rawValue).\(choice.format).\(setting)"
    }
}

enum ActionPreset: Codable, Equatable, Hashable {
    case crop(CropActionPreset)
    case downscale(DownscaleActionPreset)
    case conversion(ConversionActionPreset)

    private enum CodingKeys: String, CodingKey {
        case type
        case size
        case longEdge
        case factor
        case media
        case format
        case setting
    }

    private enum PresetType: String, Codable {
        case crop
        case downscale
        case conversion
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case let .crop(preset):
            try container.encode(PresetType.crop, forKey: .type)
            try container.encode(preset.size, forKey: .size)
            try container.encode(preset.longEdge, forKey: .longEdge)
        case let .downscale(preset):
            try container.encode(PresetType.downscale, forKey: .type)
            try container.encode(preset.factor, forKey: .factor)
        case let .conversion(preset):
            try container.encode(PresetType.conversion, forKey: .type)
            try container.encode(preset.choice.media, forKey: .media)
            try container.encode(preset.choice.format, forKey: .format)
            try container.encode(preset.choice.setting, forKey: .setting)
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(PresetType.self, forKey: .type) {
        case .crop:
            self = .crop(try CropActionPreset(from: decoder))
        case .downscale:
            self = .downscale(try DownscaleActionPreset(from: decoder))
        case .conversion:
            self = .conversion(try ConversionActionPreset(from: decoder))
        }
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
