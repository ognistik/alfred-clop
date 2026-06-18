enum PipelineFileType: String, Codable, CaseIterable, Equatable {
    case image
    case video
    case audio
    case pdf

    var title: String {
        switch self {
        case .image:
            return "Image"
        case .video:
            return "Video"
        case .audio:
            return "Audio"
        case .pdf:
            return "PDF"
        }
    }

    var mediaKind: MediaKind {
        switch self {
        case .image:
            return .image
        case .video:
            return .video
        case .audio:
            return .audio
        case .pdf:
            return .pdf
        }
    }
}

struct PipelineRunRequest: Codable, Equatable {
    var pipeline: String
    var isInline: Bool
    var optimizeFirst: Bool
    var hideResult: Bool

    init(
        pipeline: String,
        isInline: Bool = false,
        optimizeFirst: Bool = false,
        hideResult: Bool = false
    ) {
        self.pipeline = pipeline
        self.isInline = isInline
        self.optimizeFirst = optimizeFirst
        self.hideResult = hideResult
    }

    init(name: String) {
        self.init(pipeline: name)
    }

    private enum CodingKeys: String, CodingKey {
        case pipeline
        case name
        case isInline
        case optimizeFirst
        case hideResult
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(pipeline, forKey: .pipeline)
        if isInline {
            try container.encode(true, forKey: .isInline)
        }
        if optimizeFirst {
            try container.encode(true, forKey: .optimizeFirst)
        }
        if hideResult {
            try container.encode(true, forKey: .hideResult)
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        pipeline = try container.decodeIfPresent(
            String.self,
            forKey: .pipeline
        ) ?? container.decode(String.self, forKey: .name)
        isInline = try container.decodeIfPresent(
            Bool.self,
            forKey: .isInline
        ) ?? false
        optimizeFirst = try container.decodeIfPresent(
            Bool.self,
            forKey: .optimizeFirst
        ) ?? false
        hideResult = try container.decodeIfPresent(
            Bool.self,
            forKey: .hideResult
        ) ?? false
    }
}

struct SavedPipeline: Codable, Equatable {
    var id: String?
    var name: String
    var fileType: PipelineFileType?
    var rawText: String
    var skipOptimisation: Bool
    var hideResult: Bool

    init(
        id: String? = nil,
        name: String,
        fileType: PipelineFileType? = nil,
        rawText: String,
        skipOptimisation: Bool = false,
        hideResult: Bool = false
    ) {
        self.id = id
        self.name = name
        self.fileType = fileType
        self.rawText = rawText
        self.skipOptimisation = skipOptimisation
        self.hideResult = hideResult
    }
}

struct PipelineAddRequest: Codable, Equatable {
    var name: String
    var steps: String
    var fileType: PipelineFileType?
    var optimizeFirst: Bool
    var hideResult: Bool
    var replace: Bool

    init(
        name: String,
        steps: String,
        fileType: PipelineFileType? = nil,
        optimizeFirst: Bool = false,
        hideResult: Bool = false,
        replace: Bool = false
    ) {
        self.name = name
        self.steps = steps
        self.fileType = fileType
        self.optimizeFirst = optimizeFirst
        self.hideResult = hideResult
        self.replace = replace
    }
}

enum PipelineMenuActionKind: String, Codable, Equatable {
    case nameInline
    case add
    case confirmDelete
    case delete
}

struct PipelineMenuAction: Codable, Equatable {
    var kind: PipelineMenuActionKind
    var add: PipelineAddRequest?
    var pipeline: SavedPipeline?

    init(kind: PipelineMenuActionKind, add: PipelineAddRequest? = nil, pipeline: SavedPipeline? = nil) {
        self.kind = kind
        self.add = add
        self.pipeline = pipeline
    }
}
