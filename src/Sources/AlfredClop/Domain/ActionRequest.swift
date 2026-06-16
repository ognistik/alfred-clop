enum ActionRequest: Codable, Equatable {
    case optimise(aggressive: Bool)
    case optimiseMedia(OptimizeRequest)
    case crop(
        size: String,
        smartCrop: Bool,
        longEdge: Bool,
        adaptiveOptimisation: CropAdaptiveOptimisation? = nil,
        removeAudio: Bool = false
    )
    case downscale(factor: Double)
    case convert(ConversionChoice)
    case cropPDF(mode: String, value: String, pageLayout: String?)
    case uncropPDF
    case stripMetadata

    private enum CodingKeys: String, CodingKey {
        case type
        case aggressive
        case optimize
        case size
        case smartCrop
        case longEdge
        case adaptiveOptimisation
        case removeAudio
        case factor
        case format
        case media
        case setting
        case mode
        case value
        case pageLayout
    }

    private enum ActionType: String, Codable {
        case optimise
        case optimiseMedia
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
        case let .optimiseMedia(request):
            try container.encode(ActionType.optimiseMedia, forKey: .type)
            try container.encode(request, forKey: .optimize)
        case let .crop(
            size,
            smartCrop,
            longEdge,
            adaptiveOptimisation,
            removeAudio
        ):
            try container.encode(ActionType.crop, forKey: .type)
            try container.encode(size, forKey: .size)
            try container.encode(smartCrop, forKey: .smartCrop)
            try container.encode(longEdge, forKey: .longEdge)
            try container.encodeIfPresent(
                adaptiveOptimisation,
                forKey: .adaptiveOptimisation
            )
            try container.encode(removeAudio, forKey: .removeAudio)
        case let .downscale(factor):
            try container.encode(ActionType.downscale, forKey: .type)
            try container.encode(factor, forKey: .factor)
        case let .convert(choice):
            try container.encode(ActionType.convert, forKey: .type)
            try container.encode(choice.media, forKey: .media)
            try container.encode(choice.format, forKey: .format)
            try container.encodeIfPresent(choice.setting, forKey: .setting)
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
        case .optimiseMedia:
            self = .optimiseMedia(
                try container.decode(OptimizeRequest.self, forKey: .optimize)
            )
        case .crop:
            self = .crop(
                size: try container.decode(String.self, forKey: .size),
                smartCrop: try container.decode(Bool.self, forKey: .smartCrop),
                longEdge: try container.decode(Bool.self, forKey: .longEdge),
                adaptiveOptimisation: try container.decodeIfPresent(
                    CropAdaptiveOptimisation.self,
                    forKey: .adaptiveOptimisation
                ),
                removeAudio: try container.decodeIfPresent(
                    Bool.self,
                    forKey: .removeAudio
                ) ?? false
            )
        case .downscale:
            self = .downscale(factor: try container.decode(Double.self, forKey: .factor))
        case .convert:
            self = .convert(ConversionChoice(
                media: try container.decode(
                    ConversionMediaKind.self,
                    forKey: .media
                ),
                format: try container.decode(String.self, forKey: .format),
                setting: try container.decodeIfPresent(
                    ConversionSetting.self,
                    forKey: .setting
                )
            ))
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
