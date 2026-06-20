struct PixelDimensions: Codable, Equatable {
    var width: Int
    var height: Int

    var displayValue: String {
        "\(width) × \(height) px"
    }
}
