import Foundation

enum CropPDFTarget: Codable, Equatable, Hashable {
    case aspectRatio(String)
    case device(String)
    case paperSize(String)

    private enum CodingKeys: String, CodingKey {
        case type
        case value
    }

    private enum TargetType: String, Codable {
        case aspectRatio
        case device
        case paperSize
    }

    var value: String {
        switch self {
        case .aspectRatio(let value), .device(let value), .paperSize(let value):
            return value
        }
    }

    var mode: String {
        switch self {
        case .aspectRatio:
            return "aspect-ratio"
        case .device:
            return "device"
        case .paperSize:
            return "paper-size"
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .aspectRatio(let value):
            try container.encode(TargetType.aspectRatio, forKey: .type)
            try container.encode(value, forKey: .value)
        case .device(let value):
            try container.encode(TargetType.device, forKey: .type)
            try container.encode(value, forKey: .value)
        case .paperSize(let value):
            try container.encode(TargetType.paperSize, forKey: .type)
            try container.encode(value, forKey: .value)
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let value = try container.decode(String.self, forKey: .value)
        switch try container.decode(TargetType.self, forKey: .type) {
        case .aspectRatio:
            self = .aspectRatio(value)
        case .device:
            self = .device(value)
        case .paperSize:
            self = .paperSize(value)
        }
    }
}

enum CropPDFPageLayout: String, Codable, Equatable, Hashable, CaseIterable {
    case auto
    case portrait
    case landscape

    var displayName: String {
        switch self {
        case .auto:
            return "Auto"
        case .portrait:
            return "Portrait"
        case .landscape:
            return "Landscape"
        }
    }
}

struct CropPDFRequest: Codable, Equatable, Hashable {
    var target: CropPDFTarget
    var pageLayout: CropPDFPageLayout?
    var extend: Bool

    init(
        target: CropPDFTarget,
        pageLayout: CropPDFPageLayout? = nil,
        extend: Bool = false
    ) {
        self.target = target
        self.pageLayout = pageLayout
        self.extend = extend
    }
}

struct CropPDFTargetValue: Equatable, Hashable {
    var value: String
    var category: String?
    var aliases: [String]

    var searchText: String {
        ([value, category] + aliases)
            .compactMap(\.self)
            .joined(separator: " ")
    }
}

enum CropPDFTargetKind: String, Equatable {
    case ratio
    case device
    case paper

    var prefix: String {
        switch self {
        case .ratio:
            return "ratio: "
        case .device:
            return "device: "
        case .paper:
            return "paper: "
        }
    }
}

struct CropPDFControls: Equatable {
    var request: CropPDFRequest
    var targetKind: CropPDFTargetKind
}

enum CropPDFControlParser {
    static let controlsPrefix = "controls:"

    static func parse(
        _ input: String,
        targetKind: CropPDFTargetKind,
        knownValues: [CropPDFTargetValue] = []
    ) -> CropPDFControls? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }
        let components = splitTargetAndControls(
            trimmed,
            knownValues: knownValues
        )
        guard let targetValue = components.target else {
            return nil
        }
        guard let controlResult = parseControls(components.controls) else {
            return nil
        }

        let target: CropPDFTarget
        switch targetKind {
        case .ratio:
            guard let ratio = normalizedRatioTarget(targetValue) else {
                return nil
            }
            target = .aspectRatio(ratio)
        case .device:
            target = .device(targetValue)
        case .paper:
            target = .paperSize(targetValue)
        }
        return CropPDFControls(
            request: CropPDFRequest(
                target: target,
                pageLayout: controlResult.layout,
                extend: controlResult.extend
            ),
            targetKind: targetKind
        )
    }

    static func parseControlsOnly(
        _ input: String,
        base request: CropPDFRequest
    ) -> CropPDFRequest? {
        let cleaned = input
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .removingLeadingControlsPrefix()
        guard let controls = parseControls(cleaned) else {
            return nil
        }
        return CropPDFRequest(
            target: request.target,
            pageLayout: controls.layout,
            extend: controls.extend
        )
    }

    static func normalizedRatioTarget(_ input: String) -> String? {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else {
            return nil
        }
        if let dimensions = components(of: value, separator: "x"),
           dimensions.count == 2,
           let width = Int(dimensions[0]),
           let height = Int(dimensions[1]),
           width > 0,
           height > 0 {
            return "\(width)x\(height)"
        }
        if let ratio = components(of: value, separator: ":"),
           ratio.count == 2,
           let width = Int(ratio[0]),
           let height = Int(ratio[1]),
           width > 0,
           height > 0 {
            let divisor = greatestCommonDivisor(width, height)
            return "\(width / divisor):\(height / divisor)"
        }
        return nil
    }

    static func displayValue(for request: CropPDFRequest) -> String {
        let prefix: String
        switch request.target {
        case .aspectRatio:
            prefix = "ratio:"
        case .device:
            prefix = "device:"
        case .paperSize:
            prefix = "paper:"
        }
        return ([prefix, request.target.value] + compactControlTokens(for: request))
            .joined(separator: " ")
    }

    static func compactControlTokens(for request: CropPDFRequest) -> [String] {
        [
            request.pageLayout.map(\.rawValue),
            request.extend ? "extend" : nil
        ].compactMap(\.self)
    }

    static func controlDescriptions(for request: CropPDFRequest) -> [String] {
        [
            request.pageLayout.map(\.displayName),
            request.extend ? "Extend" : nil
        ].compactMap(\.self)
    }

    static var largeTypeReference: String {
        """
        Crop PDF controls

        Choose one target:
        ratio: 16:9
        ratio: 1200x630
        device: iPad Air M4 11inch
        paper: A4

        Add optional controls after the target:
        a or auto
        p or portrait
        l or landscape
        e or extend

        Examples:
        ratio: 16:9 l
        device: iPad mini 6 & 7 e
        paper: A4 p e
        """
    }

    private static func splitTargetAndControls(
        _ input: String,
        knownValues: [CropPDFTargetValue]
    ) -> (target: String?, controls: String) {
        let normalizedInput = normalized(input)
        let match = knownValues
            .flatMap { [$0.value] + $0.aliases }
            .filter { candidate in
                let normalizedCandidate = normalized(candidate)
                return normalizedInput == normalizedCandidate
                    || normalizedInput.hasPrefix(normalizedCandidate + " ")
            }
            .sorted { $0.count > $1.count }
            .first
        if let match {
            let controlStart = input.index(input.startIndex, offsetBy: match.count)
            return (
                target: String(input[..<controlStart])
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                controls: String(input[controlStart...])
            )
        }

        let tokens = input.split(whereSeparator: \.isWhitespace).map(String.init)
        guard let first = tokens.first else {
            return (nil, "")
        }
        return (first, tokens.dropFirst().joined(separator: " "))
    }

    private static func parseControls(
        _ input: String
    ) -> (layout: CropPDFPageLayout?, extend: Bool)? {
        let tokens = input
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .removingLeadingControlsPrefix()
            .replacingOccurrences(of: ",", with: " ")
            .split(whereSeparator: \.isWhitespace)
            .map { String($0).lowercased() }
        var layout: CropPDFPageLayout?
        var extend = false
        for token in tokens {
            if let parsedLayout = pageLayout(for: token) {
                guard layout == nil else { return nil }
                layout = parsedLayout
            } else if token == "extend" || token == "e" {
                guard !extend else { return nil }
                extend = true
            } else {
                return nil
            }
        }
        return (layout, extend)
    }

    private static func pageLayout(for token: String) -> CropPDFPageLayout? {
        switch token {
        case "a", "auto":
            return .auto
        case "p", "portrait":
            return .portrait
        case "l", "landscape":
            return .landscape
        default:
            return nil
        }
    }

    private static func normalized(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    private static func components(
        of value: String,
        separator: Character
    ) -> [Substring]? {
        guard value.allSatisfy({ $0.isNumber || $0 == separator }) else {
            return nil
        }
        let components = value.split(
            separator: separator,
            omittingEmptySubsequences: false
        )
        return components.allSatisfy({ !$0.isEmpty }) ? components : nil
    }

    private static func greatestCommonDivisor(_ lhs: Int, _ rhs: Int) -> Int {
        var first = lhs
        var second = rhs
        while second != 0 {
            (first, second) = (second, first % second)
        }
        return first
    }
}

private extension String {
    func removingLeadingControlsPrefix() -> String {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.lowercased().hasPrefix("\(CropPDFControlParser.controlsPrefix) ") else {
            return trimmed
        }
        return String(trimmed.dropFirst(CropPDFControlParser.controlsPrefix.count))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
