enum InputItemKind: String, Codable, Equatable {
    case localFile
    case folder
    case remoteURL
}

enum AmbiguousInputKind: String, Codable, Equatable {
    case folder
    case remoteURL
}

struct InputSelection: Codable, Equatable {
    var inputs: [String]
    var mediaKinds: [MediaKind]
    var itemKinds: [InputItemKind]
    var ambiguousKinds: [AmbiguousInputKind]
    var processableItemCount: Int?

    init(
        inputs: [String],
        mediaKinds: [MediaKind],
        itemKinds: [InputItemKind] = [],
        ambiguousKinds: [AmbiguousInputKind] = [],
        processableItemCount: Int? = nil
    ) {
        self.inputs = inputs
        self.mediaKinds = mediaKinds
        self.itemKinds = itemKinds.isEmpty
            ? Array(repeating: .localFile, count: inputs.count)
            : itemKinds
        self.ambiguousKinds = ambiguousKinds
        self.processableItemCount = processableItemCount
    }
}
