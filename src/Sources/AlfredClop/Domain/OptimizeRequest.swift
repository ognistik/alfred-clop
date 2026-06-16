import Foundation

enum OptimizeMediaKind: String, Codable, CaseIterable, Equatable, Hashable {
    case image
    case video
    case pdf
    case audio

    var mediaKind: MediaKind {
        switch self {
        case .image:
            return .image
        case .video:
            return .video
        case .pdf:
            return .pdf
        case .audio:
            return .audio
        }
    }

    var displayName: String {
        switch self {
        case .image:
            return "Image"
        case .video:
            return "Video"
        case .pdf:
            return "PDF"
        case .audio:
            return "Audio"
        }
    }

    var pluralDisplayName: String {
        switch self {
        case .image:
            return "Images"
        case .video:
            return "Videos"
        case .pdf:
            return "PDFs"
        case .audio:
            return "Audio"
        }
    }
}

enum ImageOptimizeCompression: Codable, Equatable, Hashable {
    case value(Int)
    case adaptive

    private enum CodingKeys: String, CodingKey {
        case type
        case value
    }

    private enum CompressionType: String, Codable {
        case value
        case adaptive
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .value(let value):
            try container.encode(CompressionType.value, forKey: .type)
            try container.encode(value, forKey: .value)
        case .adaptive:
            try container.encode(CompressionType.adaptive, forKey: .type)
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(CompressionType.self, forKey: .type) {
        case .value:
            self = .value(try container.decode(Int.self, forKey: .value))
        case .adaptive:
            self = .adaptive
        }
    }
}

enum VideoOptimizeCompression: Codable, Equatable, Hashable {
    case value(Int)
    case automatic

    private enum CodingKeys: String, CodingKey {
        case type
        case value
    }

    private enum CompressionType: String, Codable {
        case value
        case automatic
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .value(let value):
            try container.encode(CompressionType.value, forKey: .type)
            try container.encode(value, forKey: .value)
        case .automatic:
            try container.encode(CompressionType.automatic, forKey: .type)
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(CompressionType.self, forKey: .type) {
        case .value:
            self = .value(try container.decode(Int.self, forKey: .value))
        case .automatic:
            self = .automatic
        }
    }
}

enum VideoOptimizeEncoder: String, Codable, Equatable, Hashable {
    case hardware
    case software
    case lossless
    case adaptive
}

enum PDFOptimizeDPI: Codable, Equatable, Hashable {
    case value(Int)
    case adaptive

    private enum CodingKeys: String, CodingKey {
        case type
        case value
    }

    private enum DPIType: String, Codable {
        case value
        case adaptive
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .value(let value):
            try container.encode(DPIType.value, forKey: .type)
            try container.encode(value, forKey: .value)
        case .adaptive:
            try container.encode(DPIType.adaptive, forKey: .type)
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(DPIType.self, forKey: .type) {
        case .value:
            self = .value(try container.decode(Int.self, forKey: .value))
        case .adaptive:
            self = .adaptive
        }
    }
}

struct ImageOptimizeControls: Codable, Equatable, Hashable {
    var compression: ImageOptimizeCompression?
}

struct VideoOptimizeControls: Codable, Equatable, Hashable {
    var compression: VideoOptimizeCompression?
    var encoder: VideoOptimizeEncoder?
    var removeAudio: Bool
    var playbackSpeed: Double?

    init(
        compression: VideoOptimizeCompression? = nil,
        encoder: VideoOptimizeEncoder? = nil,
        removeAudio: Bool = false,
        playbackSpeed: Double? = nil
    ) {
        self.compression = compression
        self.encoder = encoder
        self.removeAudio = removeAudio
        self.playbackSpeed = playbackSpeed
    }
}

struct PDFOptimizeControls: Codable, Equatable, Hashable {
    var dpi: PDFOptimizeDPI?
}

struct AudioOptimizeControls: Codable, Equatable, Hashable {
    var compression: Int?
    var bitrate: Int?
}

enum OptimizeControls: Codable, Equatable, Hashable {
    case image(ImageOptimizeControls)
    case video(VideoOptimizeControls)
    case pdf(PDFOptimizeControls)
    case audio(AudioOptimizeControls)

    private enum CodingKeys: String, CodingKey {
        case media
        case image
        case video
        case pdf
        case audio
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .image(let controls):
            try container.encode(OptimizeMediaKind.image, forKey: .media)
            try container.encode(controls, forKey: .image)
        case .video(let controls):
            try container.encode(OptimizeMediaKind.video, forKey: .media)
            try container.encode(controls, forKey: .video)
        case .pdf(let controls):
            try container.encode(OptimizeMediaKind.pdf, forKey: .media)
            try container.encode(controls, forKey: .pdf)
        case .audio(let controls):
            try container.encode(OptimizeMediaKind.audio, forKey: .media)
            try container.encode(controls, forKey: .audio)
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(OptimizeMediaKind.self, forKey: .media) {
        case .image:
            self = .image(try container.decode(
                ImageOptimizeControls.self,
                forKey: .image
            ))
        case .video:
            self = .video(try container.decode(
                VideoOptimizeControls.self,
                forKey: .video
            ))
        case .pdf:
            self = .pdf(try container.decode(
                PDFOptimizeControls.self,
                forKey: .pdf
            ))
        case .audio:
            self = .audio(try container.decode(
                AudioOptimizeControls.self,
                forKey: .audio
            ))
        }
    }
}

struct OptimizeRequest: Codable, Equatable, Hashable {
    var media: OptimizeMediaKind
    var controls: OptimizeControls

    init(media: OptimizeMediaKind, controls: OptimizeControls) {
        self.media = media
        self.controls = controls
    }
}

enum OptimizeControlParser {
    static let supportedPDFDPI: Set<Int> = [300, 250, 200, 150, 100, 72, 48]

    static func parse(
        _ value: String,
        media: OptimizeMediaKind
    ) -> OptimizeRequest? {
        let tokens = normalizedTokens(value)
        switch media {
        case .image:
            return parseImage(tokens).map {
                OptimizeRequest(media: .image, controls: .image($0))
            }
        case .video:
            return parseVideo(tokens).map {
                OptimizeRequest(media: .video, controls: .video($0))
            }
        case .pdf:
            return parsePDF(tokens).map {
                OptimizeRequest(media: .pdf, controls: .pdf($0))
            }
        case .audio:
            return parseAudio(tokens).map {
                OptimizeRequest(media: .audio, controls: .audio($0))
            }
        }
    }

    static func isSupported(_ request: OptimizeRequest) -> Bool {
        switch request.controls {
        case .image(let controls):
            guard request.media == .image else { return false }
            switch controls.compression {
            case .value(let value):
                return supportedCompression(value)
            case .adaptive:
                return true
            case nil:
                return true
            }
        case .video(let controls):
            guard request.media == .video else { return false }
            if let speed = controls.playbackSpeed, speed <= 0 {
                return false
            }
            switch controls.compression {
            case .value(let value):
                return supportedCompression(value)
            case .automatic, nil:
                return true
            }
        case .pdf(let controls):
            guard request.media == .pdf else { return false }
            switch controls.dpi {
            case .value(let value):
                return supportedPDFDPI.contains(value)
            case .adaptive, nil:
                return true
            }
        case .audio(let controls):
            guard request.media == .audio else { return false }
            if controls.compression != nil && controls.bitrate != nil {
                return false
            }
            if let compression = controls.compression,
               !supportedCompression(compression) {
                return false
            }
            if let bitrate = controls.bitrate, bitrate <= 0 {
                return false
            }
            return true
        }
    }

    static func displayValue(for request: OptimizeRequest) -> String {
        let details = controlDescriptions(for: request)
        guard !details.isEmpty else {
            return "\(request.media.displayName) Defaults"
        }
        return "\(request.media.displayName) · \(details.joined(separator: " · "))"
    }

    static func grammarHint(for media: OptimizeMediaKind) -> String {
        switch media {
        case .image:
            return "Type 5-100 or ad"
        case .video:
            return "Type 5-100/au, hw/sw/ll/ad, m, or 2x"
        case .pdf:
            return "Type DPI or ad"
        case .audio:
            return "Type 5-100 or b128"
        }
    }

    static func largeTypeReference(for media: OptimizeMediaKind) -> String {
        switch media {
        case .image:
            return """
            Image Optimize controls

            Type a number from 5 to 100 for compression.
            Type ad for adaptive compression.

            Separate controls with spaces or commas.

            Examples:
            70
            ad
            """
        case .video:
            return """
            Video Optimize controls

            Type a number from 5 to 100 for compression.
            Type au for automatic compression.
            Type hw, sw, ll, or ad for encoder.
            Type m to remove audio.
            Type 2x or 1.5x for playback speed.

            Separate controls with spaces or commas.
            Full words also work: auto, hardware, software, lossless, adaptive, mute.

            Examples:
            70 m
            70, hw
            au sw m
            ad, m, 1.5x
            """
        case .pdf:
            return """
            PDF Optimize controls

            Type ad for adaptive DPI.
            Type one supported DPI: 300, 250, 200, 150, 100, 72, or 48.
            You can also type dpi 150.

            Separate controls with spaces or commas.
            """
        case .audio:
            return """
            Audio Optimize controls

            Type a number from 5 to 100 for compression.
            Type b128 or bitrate 128 for target bitrate.

            Separate controls with spaces or commas.
            """
        }
    }

    static func isPossiblePrefix(
        _ value: String,
        media: OptimizeMediaKind
    ) -> Bool {
        let tokens = normalizedTokens(value)
        guard let last = tokens.last else {
            return true
        }
        if let parsed = parse(value, media: media),
           !controlDescriptions(for: parsed).isEmpty {
            return false
        }
        let previous = Array(tokens.dropLast())
        if !previous.isEmpty {
            guard let parsed = parse(previous.joined(separator: " "), media: media),
                  !controlDescriptions(for: parsed).isEmpty else {
                return false
            }
        }
        return isPossiblePrefixToken(last, media: media)
    }

    static func controlDescriptions(for request: OptimizeRequest) -> [String] {
        switch request.controls {
        case .image(let controls):
            return [imageCompressionDescription(controls.compression)]
                .compactMap(\.self)
        case .video(let controls):
            return [
                videoCompressionDescription(controls.compression),
                controls.encoder.map { "Encoder \($0.rawValue)" },
                controls.removeAudio ? "Mute" : nil,
                controls.playbackSpeed.map { "\(displayNumber($0))x speed" }
            ].compactMap(\.self)
        case .pdf(let controls):
            return [pdfDPIDescription(controls.dpi)].compactMap(\.self)
        case .audio(let controls):
            return [
                controls.compression.map { "Compression \($0)" },
                controls.bitrate.map { "\($0) kbps" }
            ].compactMap(\.self)
        }
    }

    static func stableKey(for request: OptimizeRequest) -> String {
        switch request.controls {
        case .image(let controls):
            switch controls.compression {
            case .value(let value):
                return "compression.\(value)"
            case .adaptive:
                return "compression.adaptive"
            case nil:
                return "defaults"
            }
        case .video(let controls):
            var parts = [String]()
            switch controls.compression {
            case .value(let value):
                parts.append("compression.\(value)")
            case .automatic:
                parts.append("compression.auto")
            case nil:
                break
            }
            if let encoder = controls.encoder {
                parts.append("encoder.\(encoder.rawValue)")
            }
            if controls.removeAudio {
                parts.append("mute")
            }
            if let speed = controls.playbackSpeed {
                parts.append("speed.\(displayNumber(speed))")
            }
            return parts.isEmpty ? "defaults" : parts.joined(separator: ".")
        case .pdf(let controls):
            switch controls.dpi {
            case .value(let value):
                return "dpi.\(value)"
            case .adaptive:
                return "dpi.adaptive"
            case nil:
                return "defaults"
            }
        case .audio(let controls):
            if let compression = controls.compression {
                return "compression.\(compression)"
            }
            if let bitrate = controls.bitrate {
                return "bitrate.\(bitrate)"
            }
            return "defaults"
        }
    }

    static func displayNumber(_ value: Double) -> String {
        if value.rounded() == value {
            return String(Int(value))
        }
        return String(format: "%g", value)
    }

    private static func parseImage(
        _ tokens: [String]
    ) -> ImageOptimizeControls? {
        guard !tokens.isEmpty else {
            return ImageOptimizeControls()
        }
        var compression: ImageOptimizeCompression?
        for token in tokens {
            guard compression == nil else { return nil }
            if token == "ad" || token == "adaptive" {
                compression = .adaptive
            } else if let value = Int(token), supportedCompression(value) {
                compression = .value(value)
            } else {
                return nil
            }
        }
        return ImageOptimizeControls(compression: compression)
    }

    private static func parseVideo(
        _ tokens: [String]
    ) -> VideoOptimizeControls? {
        guard !tokens.isEmpty else {
            return VideoOptimizeControls()
        }
        var controls = VideoOptimizeControls()
        for token in tokens {
            if token == "au" || token == "auto" {
                guard controls.compression == nil else { return nil }
                controls.compression = .automatic
            } else if let value = Int(token), supportedCompression(value) {
                guard controls.compression == nil else { return nil }
                controls.compression = .value(value)
            } else if token == "ad" || token == "adaptive" {
                guard controls.encoder == nil else { return nil }
                controls.encoder = .adaptive
            } else if let encoder = videoEncoder(for: token) {
                guard controls.encoder == nil else { return nil }
                controls.encoder = encoder
            } else if token == "m" || token == "mu" || token == "mute" {
                guard !controls.removeAudio else { return nil }
                controls.removeAudio = true
            } else if token.hasSuffix("x"),
                      let value = Double(token.dropLast()),
                      value > 0 {
                guard controls.playbackSpeed == nil else { return nil }
                controls.playbackSpeed = value
            } else {
                return nil
            }
        }
        return controls
    }

    private static func parsePDF(_ tokens: [String]) -> PDFOptimizeControls? {
        guard !tokens.isEmpty else {
            return PDFOptimizeControls()
        }
        var dpi: PDFOptimizeDPI?
        var index = tokens.startIndex
        while index < tokens.endIndex {
            guard dpi == nil else { return nil }
            let token = tokens[index]
            if token == "ad" || token == "adaptive" {
                dpi = .adaptive
                index = tokens.index(after: index)
            } else if token == "dpi" {
                let nextIndex = tokens.index(after: index)
                guard nextIndex < tokens.endIndex,
                      let value = Int(tokens[nextIndex]),
                      supportedPDFDPI.contains(value) else {
                    return nil
                }
                dpi = .value(value)
                index = tokens.index(after: nextIndex)
            } else if let value = Int(token), supportedPDFDPI.contains(value) {
                dpi = .value(value)
                index = tokens.index(after: index)
            } else {
                return nil
            }
        }
        return PDFOptimizeControls(dpi: dpi)
    }

    private static func parseAudio(
        _ tokens: [String]
    ) -> AudioOptimizeControls? {
        guard !tokens.isEmpty else {
            return AudioOptimizeControls()
        }
        var compression: Int?
        var bitrate: Int?
        var index = tokens.startIndex
        while index < tokens.endIndex {
            let token = tokens[index]
            if let value = Int(token), supportedCompression(value) {
                guard compression == nil, bitrate == nil else { return nil }
                compression = value
                index = tokens.index(after: index)
            } else if token.hasPrefix("b"),
                      let value = Int(token.dropFirst()),
                      value > 0 {
                guard compression == nil, bitrate == nil else { return nil }
                bitrate = value
                index = tokens.index(after: index)
            } else if token == "bitrate" {
                let nextIndex = tokens.index(after: index)
                guard compression == nil,
                      bitrate == nil,
                      nextIndex < tokens.endIndex,
                      let value = Int(tokens[nextIndex]),
                      value > 0 else {
                    return nil
                }
                bitrate = value
                index = tokens.index(after: nextIndex)
            } else {
                return nil
            }
        }
        return AudioOptimizeControls(
            compression: compression,
            bitrate: bitrate
        )
    }

    private static func normalizedTokens(_ value: String) -> [String] {
        value
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split { $0.isWhitespace || $0 == "," }
            .map(String.init)
    }

    private static func videoEncoder(for token: String) -> VideoOptimizeEncoder? {
        switch token {
        case "hw", "hardware":
            return .hardware
        case "sw", "software":
            return .software
        case "ll", "lossless":
            return .lossless
        default:
            return VideoOptimizeEncoder(rawValue: token)
        }
    }

    private static func isPossiblePrefixToken(
        _ token: String,
        media: OptimizeMediaKind
    ) -> Bool {
        switch media {
        case .image:
            return isIntegerPrefix(token, for: 5...100)
                || isProperPrefix(token, of: ["ad", "adaptive"])
        case .video:
            return isIntegerPrefix(token, for: 5...100)
                || isSpeedPrefix(token)
                || isProperPrefix(token, of: [
                    "au", "auto",
                    "hw", "hardware",
                    "sw", "software",
                    "ll", "lossless",
                    "ad", "adaptive",
                    "m", "mu", "mute"
                ])
        case .pdf:
            return isProperPrefix(token, of: [
                "300", "250", "200", "150", "100", "72", "48",
                "ad", "adaptive", "dpi"
            ])
        case .audio:
            return isIntegerPrefix(token, for: 5...100)
                || isBitratePrefix(token)
                || isProperPrefix(token, of: ["bitrate"])
        }
    }

    private static func isProperPrefix(
        _ token: String,
        of candidates: [String]
    ) -> Bool {
        candidates.contains {
            $0.hasPrefix(token) && $0 != token
        }
    }

    private static func isIntegerPrefix(
        _ token: String,
        for range: ClosedRange<Int>
    ) -> Bool {
        guard !token.isEmpty,
              token.allSatisfy(\.isNumber),
              Int(token) != nil else {
            return false
        }
        return range.lazy.contains { String($0).hasPrefix(token) }
    }

    private static func isSpeedPrefix(_ token: String) -> Bool {
        if token.hasSuffix("x") {
            return false
        }
        guard !token.isEmpty,
              token.allSatisfy({ $0.isNumber || $0 == "." }),
              token.contains(".") || Int(token) != nil else {
            return false
        }
        return true
    }

    private static func isBitratePrefix(_ token: String) -> Bool {
        guard token.hasPrefix("b") else {
            return false
        }
        return token == "b"
    }

    private static func supportedCompression(_ value: Int) -> Bool {
        (5...100).contains(value)
    }

    private static func imageCompressionDescription(
        _ compression: ImageOptimizeCompression?
    ) -> String? {
        switch compression {
        case .value(let value):
            return "Compression \(value)"
        case .adaptive:
            return "Adaptive"
        case nil:
            return nil
        }
    }

    private static func videoCompressionDescription(
        _ compression: VideoOptimizeCompression?
    ) -> String? {
        switch compression {
        case .value(let value):
            return "Compression \(value)"
        case .automatic:
            return "Auto compression"
        case nil:
            return nil
        }
    }

    private static func pdfDPIDescription(_ dpi: PDFOptimizeDPI?) -> String? {
        switch dpi {
        case .value(let value):
            return "\(value) DPI"
        case .adaptive:
            return "Adaptive DPI"
        case nil:
            return nil
        }
    }
}
