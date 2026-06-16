import Foundation

enum ConversionMediaKind: String, Codable, CaseIterable, Equatable, Hashable {
    case image
    case video
    case audio

    var action: ClopAction {
        switch self {
        case .image:
            return .convertImage
        case .video:
            return .convertVideo
        case .audio:
            return .convertAudio
        }
    }
}

enum ConversionSetting: Codable, Equatable, Hashable {
    case compression(Int)
    case automaticCompression
    case bitrate(Int)

    private enum CodingKeys: String, CodingKey {
        case type
        case value
    }

    private enum SettingType: String, Codable {
        case compression
        case automaticCompression
        case bitrate
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .compression(let value):
            try container.encode(SettingType.compression, forKey: .type)
            try container.encode(value, forKey: .value)
        case .automaticCompression:
            try container.encode(
                SettingType.automaticCompression,
                forKey: .type
            )
        case .bitrate(let value):
            try container.encode(SettingType.bitrate, forKey: .type)
            try container.encode(value, forKey: .value)
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(SettingType.self, forKey: .type) {
        case .compression:
            self = .compression(try container.decode(Int.self, forKey: .value))
        case .automaticCompression:
            self = .automaticCompression
        case .bitrate:
            self = .bitrate(try container.decode(Int.self, forKey: .value))
        }
    }
}

struct ConversionChoice: Codable, Equatable, Hashable {
    var media: ConversionMediaKind
    var format: String
    var setting: ConversionSetting?

    init(
        media: ConversionMediaKind,
        format: String,
        setting: ConversionSetting? = nil
    ) {
        self.media = media
        self.format = format.lowercased()
        self.setting = setting
    }

    var displayFormat: String {
        switch format {
        case "webp":
            return "WebP"
        case "avif":
            return "AVIF"
        case "heic":
            return "HEIC"
        case "jxl":
            return "JXL"
        case "jpeg":
            return "JPEG"
        case "png":
            return "PNG"
        case "mp4":
            return "MP4 / H.264"
        case "gif":
            return "GIF"
        case "webm":
            return "WebM / VP9"
        case "hevc":
            return "HEVC / H.265"
        case "x265":
            return "x265 / H.265"
        case "av1":
            return "AV1 / MKV"
        case "mp3":
            return "MP3"
        case "aac":
            return "AAC"
        case "m4a":
            return "M4A"
        case "opus":
            return "Opus"
        case "ogg":
            return "Ogg"
        case "flac":
            return "FLAC"
        case "wav":
            return "WAV"
        case "aiff":
            return "AIFF"
        default:
            return format.uppercased()
        }
    }

    var displayValue: String {
        guard let setting else {
            return displayFormat
        }
        switch setting {
        case .compression(let value):
            return "\(displayFormat) · Compression \(value)"
        case .automaticCompression:
            return "\(displayFormat) · Automatic compression"
        case .bitrate(let value):
            return "\(displayFormat) · \(value) kbps"
        }
    }

    var outputExtension: String {
        switch format {
        case "hevc", "x265":
            return "mp4"
        case "av1":
            return "mkv"
        default:
            return format
        }
    }
}

enum ConversionCatalog {
    static func formats(for media: ConversionMediaKind) -> [String] {
        switch media {
        case .image:
            return ["webp", "avif", "heic", "jxl", "jpeg", "png"]
        case .video:
            return ["mp4", "gif", "webm", "hevc", "x265", "av1"]
        case .audio:
            return ["mp3", "aac", "m4a", "opus", "ogg", "flac", "wav", "aiff"]
        }
    }

    static func normalizedFormat(
        _ value: String,
        media: ConversionMediaKind
    ) -> String? {
        let normalized = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let canonical = normalized == "jpg" ? "jpeg" : normalized
        return formats(for: media).contains(canonical) ? canonical : nil
    }

    static func choice(
        forFormat value: String,
        setting: ConversionSetting? = nil
    ) -> ConversionChoice? {
        for media in ConversionMediaKind.allCases {
            if let format = normalizedFormat(value, media: media) {
                return ConversionChoice(
                    media: media,
                    format: format,
                    setting: setting
                )
            }
        }
        return nil
    }

    static func supportsControls(_ choice: ConversionChoice) -> Bool {
        switch choice.media {
        case .image, .audio:
            return true
        case .video:
            return choice.format == "mp4"
        }
    }

    static func isSupported(_ choice: ConversionChoice) -> Bool {
        guard normalizedFormat(choice.format, media: choice.media)
                == choice.format else {
            return false
        }
        guard let setting = choice.setting else {
            return true
        }
        switch (choice.media, choice.format, setting) {
        case (_, _, .compression(let value)):
            return (5...100).contains(value)
                && supportsControls(choice)
        case (.video, "mp4", .automaticCompression):
            return true
        case (.audio, _, .bitrate(let value)):
            return value > 0
        default:
            return false
        }
    }
}
