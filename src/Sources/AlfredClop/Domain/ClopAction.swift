enum ClopAction: String, Codable, CaseIterable, Equatable {
    case optimise
    case crop
    case downscale
    case convertImage
    case convertVideo
    case convertAudio
    case cropPDF
    case uncropPDF
    case stripMetadata
}
