enum ClopAction: String, Codable, CaseIterable, Equatable {
    case optimise
    case aggressiveOptimise
    case crop
    case downscale
    case convert
    case cropPDF
    case uncropPDF
    case stripMetadata
}
