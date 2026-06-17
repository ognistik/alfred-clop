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
    var name: String

    init(name: String) {
        self.name = name
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
    var skipOptimisation: Bool
    var hideResult: Bool
    var replace: Bool

    init(
        name: String,
        steps: String,
        fileType: PipelineFileType? = nil,
        skipOptimisation: Bool = false,
        hideResult: Bool = false,
        replace: Bool = false
    ) {
        self.name = name
        self.steps = steps
        self.fileType = fileType
        self.skipOptimisation = skipOptimisation
        self.hideResult = hideResult
        self.replace = replace
    }
}

enum PipelineMenuActionKind: String, Codable, Equatable {
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
