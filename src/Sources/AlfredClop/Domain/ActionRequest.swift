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
    case downscale(
        factor: Double,
        adaptiveOptimisation: CropAdaptiveOptimisation? = nil,
        removeAudio: Bool = false
    )
    case convert(ConversionChoice)
    case cropPDF(CropPDFRequest)
    case uncropPDF
    case stripMetadata
    case pipeline(PipelineRunRequest)

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
        case cropPDF
        case pipeline
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
        case pipeline
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
        case let .downscale(factor, adaptiveOptimisation, removeAudio):
            try container.encode(ActionType.downscale, forKey: .type)
            try container.encode(factor, forKey: .factor)
            try container.encodeIfPresent(
                adaptiveOptimisation,
                forKey: .adaptiveOptimisation
            )
            try container.encode(removeAudio, forKey: .removeAudio)
        case let .convert(choice):
            try container.encode(ActionType.convert, forKey: .type)
            try container.encode(choice.media, forKey: .media)
            try container.encode(choice.format, forKey: .format)
            try container.encodeIfPresent(choice.setting, forKey: .setting)
        case let .cropPDF(request):
            try container.encode(ActionType.cropPDF, forKey: .type)
            try container.encode(request, forKey: .cropPDF)
        case .uncropPDF:
            try container.encode(ActionType.uncropPDF, forKey: .type)
        case .stripMetadata:
            try container.encode(ActionType.stripMetadata, forKey: .type)
        case let .pipeline(request):
            try container.encode(ActionType.pipeline, forKey: .type)
            try container.encode(request, forKey: .pipeline)
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
            self = .downscale(
                factor: try container.decode(Double.self, forKey: .factor),
                adaptiveOptimisation: try container.decodeIfPresent(
                    CropAdaptiveOptimisation.self,
                    forKey: .adaptiveOptimisation
                ),
                removeAudio: try container.decodeIfPresent(
                    Bool.self,
                    forKey: .removeAudio
                ) ?? false
            )
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
            if let request = try container.decodeIfPresent(
                CropPDFRequest.self,
                forKey: .cropPDF
            ) {
                self = .cropPDF(request)
            } else {
                self = .cropPDF(CropPDFRequest(
                    target: legacyCropPDFTarget(
                        mode: try container.decode(String.self, forKey: .mode),
                        value: try container.decode(String.self, forKey: .value)
                    ),
                    pageLayout: try container
                        .decodeIfPresent(String.self, forKey: .pageLayout)
                        .flatMap(CropPDFPageLayout.init(rawValue:)),
                    extend: false
                ))
            }
        case .uncropPDF:
            self = .uncropPDF
        case .stripMetadata:
            self = .stripMetadata
        case .pipeline:
            self = .pipeline(
                try container.decode(PipelineRunRequest.self, forKey: .pipeline)
            )
        }
    }
}

private func legacyCropPDFTarget(mode: String, value: String) -> CropPDFTarget {
    switch mode {
    case "device", "for-device":
        return .device(value)
    case "paper", "paper-size":
        return .paperSize(value)
    default:
        return .aspectRatio(value)
    }
}
