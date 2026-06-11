enum ActionRequest: Codable, Equatable {
    case optimise(aggressive: Bool)
    case crop(size: String, smartCrop: Bool, longEdge: Bool)
    case downscale(factor: Double)
    case convert(format: String, quality: Int)
    case cropPDF(mode: String, value: String, pageLayout: String?)
    case uncropPDF
    case stripMetadata

    private enum CodingKeys: String, CodingKey {
        case type
        case aggressive
        case size
        case smartCrop
        case longEdge
        case factor
        case format
        case quality
        case mode
        case value
        case pageLayout
    }

    private enum ActionType: String, Codable {
        case optimise
        case crop
        case downscale
        case convert
        case cropPDF
        case uncropPDF
        case stripMetadata
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case let .optimise(aggressive):
            try container.encode(ActionType.optimise, forKey: .type)
            try container.encode(aggressive, forKey: .aggressive)
        case let .crop(size, smartCrop, longEdge):
            try container.encode(ActionType.crop, forKey: .type)
            try container.encode(size, forKey: .size)
            try container.encode(smartCrop, forKey: .smartCrop)
            try container.encode(longEdge, forKey: .longEdge)
        case let .downscale(factor):
            try container.encode(ActionType.downscale, forKey: .type)
            try container.encode(factor, forKey: .factor)
        case let .convert(format, quality):
            try container.encode(ActionType.convert, forKey: .type)
            try container.encode(format, forKey: .format)
            try container.encode(quality, forKey: .quality)
        case let .cropPDF(mode, value, pageLayout):
            try container.encode(ActionType.cropPDF, forKey: .type)
            try container.encode(mode, forKey: .mode)
            try container.encode(value, forKey: .value)
            try container.encodeIfPresent(pageLayout, forKey: .pageLayout)
        case .uncropPDF:
            try container.encode(ActionType.uncropPDF, forKey: .type)
        case .stripMetadata:
            try container.encode(ActionType.stripMetadata, forKey: .type)
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(ActionType.self, forKey: .type)

        switch type {
        case .optimise:
            self = .optimise(aggressive: try container.decode(Bool.self, forKey: .aggressive))
        case .crop:
            self = .crop(
                size: try container.decode(String.self, forKey: .size),
                smartCrop: try container.decode(Bool.self, forKey: .smartCrop),
                longEdge: try container.decode(Bool.self, forKey: .longEdge)
            )
        case .downscale:
            self = .downscale(factor: try container.decode(Double.self, forKey: .factor))
        case .convert:
            self = .convert(
                format: try container.decode(String.self, forKey: .format),
                quality: try container.decode(Int.self, forKey: .quality)
            )
        case .cropPDF:
            self = .cropPDF(
                mode: try container.decode(String.self, forKey: .mode),
                value: try container.decode(String.self, forKey: .value),
                pageLayout: try container.decodeIfPresent(String.self, forKey: .pageLayout)
            )
        case .uncropPDF:
            self = .uncropPDF
        case .stripMetadata:
            self = .stripMetadata
        }
    }
}
