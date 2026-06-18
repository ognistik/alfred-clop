import Foundation

enum PublicRequestError: Error, Equatable {
    case empty
    case missingSeparator
    case missingInput
    case mixedInputSources
    case unknownDirective(String)
    case unknownAction(String)
    case unsupportedExecution(String)
    case missingParameter(String)
    case invalidParameter(String, String)
    case unexpectedParameter(String)
    case executeOnlyParameter(String)

    var title: String { "Invalid Clop request" }

    var detail: String {
        switch self {
        case .empty:
            return "Pass finder, clipboard, or one or more paths or URLs."
        case .missingSeparator:
            return "Add a blank line between directives and input."
        case .missingInput:
            return "Add finder, clipboard, or one or more paths or URLs after the blank line."
        case .mixedInputSources:
            return "Use finder, clipboard, or explicit paths and URLs, but do not combine them."
        case .unknownDirective(let directive):
            return "Unknown directive: \(directive)"
        case .unknownAction(let action):
            return "Unknown workflow action: \(action)"
        case .unsupportedExecution(let action):
            return "\(action) execution is not available yet. Open its menu instead."
        case .missingParameter(let parameter):
            return "Missing required parameter: \(parameter)"
        case let .invalidParameter(parameter, value):
            return "Invalid \(parameter): \(value)"
        case .unexpectedParameter(let parameter):
            return "The selected action does not use the \(parameter) parameter."
        case .executeOnlyParameter(let parameter):
            return "\(parameter) only works with execute."
        }
    }
}

enum PublicRequestParser {
    static func parse(_ value: String) throws -> ClopRequest {
        let normalized = value
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let trimmed = normalized.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw PublicRequestError.empty
        }

        if trimmed.first == "{" {
            do {
                return try JSONDecoder().decode(
                    ClopRequest.self,
                    from: Data(trimmed.utf8)
                )
            } catch {
                throw PublicRequestError.invalidParameter(
                    "JSON request",
                    "use the documented typed request format"
                )
            }
        }

        var lines = normalized.components(separatedBy: "\n")
        while lines.first?.trimmingCharacters(in: .whitespaces).isEmpty == true {
            lines.removeFirst()
        }
        while lines.last?.trimmingCharacters(in: .whitespaces).isEmpty == true {
            lines.removeLast()
        }
        guard let separator = lines.firstIndex(where: {
            $0.trimmingCharacters(in: .whitespaces).isEmpty
        }) else {
            if looksLikeDirective(lines[0]) {
                throw PublicRequestError.missingSeparator
            }
            return ClopRequest(
                input: try input(from: lines),
                route: .menu(action: nil)
            )
        }

        let directiveLines = Array(lines[..<separator])
        let inputLines = Array(lines[(separator + 1)...])
        guard !directiveLines.isEmpty else {
            return ClopRequest(
                input: try input(from: inputLines),
                route: .menu(action: nil)
            )
        }

        let directives = try parseDirectives(directiveLines)
        return ClopRequest(
            input: try input(from: inputLines),
            route: try route(from: directives)
        )
    }

    private static func looksLikeDirective(_ line: String) -> Bool {
        guard let colon = line.firstIndex(of: ":") else {
            return false
        }
        let key = normalizedName(String(line[..<colon]))
        return key == "menu" || key == "execute" || action(for: key) != nil
    }

    private static func parseDirectives(
        _ lines: [String]
    ) throws -> [(key: String, value: String)] {
        try lines.map { line in
            guard let colon = line.firstIndex(of: ":") else {
                throw PublicRequestError.unknownDirective(line)
            }
            let key = normalizedName(String(line[..<colon]))
            let value = String(line[line.index(after: colon)...])
                .trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty else {
                throw PublicRequestError.unknownDirective(line)
            }
            return (key, value)
        }
    }

    private static func input(from lines: [String]) throws -> ClopInputRequest {
        let values = lines.filter {
            !$0.trimmingCharacters(in: .whitespaces).isEmpty
        }
        guard !values.isEmpty else {
            throw PublicRequestError.missingInput
        }

        let sources = values.map(normalizedName)
        if sources == ["finder"] {
            return .finderSelection
        }
        if sources == ["clipboard"] {
            return .clipboard
        }
        if sources.contains("finder") || sources.contains("clipboard") {
            throw PublicRequestError.mixedInputSources
        }
        return .explicit(items: values, extractText: false)
    }

    private static func route(
        from directives: [(key: String, value: String)]
    ) throws -> ClopRouteRequest {
        guard let first = directives.first else {
            return .menu(action: nil)
        }

        if first.key == "menu" {
            guard !first.value.isEmpty else {
                try rejectExecuteOnlyParameters(Array(directives.dropFirst()))
                return .menu(action: nil)
            }
            if normalizedName(first.value) == "configuration" {
                try rejectExecuteOnlyParameters(Array(directives.dropFirst()))
                return .configuration
            }
            guard let action = action(for: first.value) else {
                throw PublicRequestError.unknownAction(first.value)
            }
            try rejectExecuteOnlyParameters(Array(directives.dropFirst()))
            return .menu(action: action)
        }

        if first.key == "execute" {
            let executeParameters = Array(directives.dropFirst())
            let values = try parameterDictionary(executeParameters)
            let overrides = try executionOverrides(from: values)
            let actionValues = values.filter {
                !executionOverrideKeys.contains($0.key)
            }
            if normalizedName(first.value) == "convert" {
                return .execute(
                    action: try inferredConversionExecution(values: actionValues),
                    overrides: overrides
                )
            }
            guard let action = action(for: first.value) else {
                throw PublicRequestError.unknownAction(first.value)
            }
            return .execute(
                action: try execution(
                    for: action,
                    values: actionValues
                ),
                overrides: overrides
            )
        }

        guard first.value.isEmpty, let action = action(for: first.key) else {
            throw PublicRequestError.unknownDirective(first.key)
        }
        try rejectExecuteOnlyParameters(Array(directives.dropFirst()))
        return .menu(action: action)
    }

    private static func execution(
        for action: ClopAction,
        values: [String: String]
    ) throws -> ActionRequest {
        switch action {
        case .optimise:
            return try optimizeExecution(values: values)
        case .crop:
            try rejectUnknown(
                values,
                allowed: [
                    "size",
                    "controls",
                    "adaptive",
                    "no adaptive",
                    "mute",
                    "remove audio"
                ]
            )
            guard let sizeValue = values["size"], !sizeValue.isEmpty else {
                throw PublicRequestError.missingParameter("size")
            }
            var controlParts = [sizeValue]
            if let controls = values["controls"], !controls.isEmpty {
                controlParts.append(controls)
            }
            if try boolean(
                values["adaptive"],
                name: "adaptive",
                defaultValue: false
            ) {
                controlParts.append("adaptive")
            }
            if try boolean(
                values["no adaptive"],
                name: "no adaptive",
                defaultValue: false
            ) {
                controlParts.append("no-adaptive")
            }
            let mute = try boolean(
                values["mute"],
                name: "mute",
                defaultValue: false
            )
            let removeAudio = try boolean(
                values["remove audio"],
                name: "remove audio",
                defaultValue: false
            )
            if mute || removeAudio {
                controlParts.append("mute")
            }
            let controlText = controlParts.joined(separator: " ")
            guard let controls = CropControlParser.parse(controlText) else {
                throw PublicRequestError.invalidParameter(
                    "crop controls",
                    controlText
                )
            }
            if controls.smartCrop && !cropSizeSupportsSmartCrop(controls.size) {
                throw PublicRequestError.invalidParameter(
                    "crop controls",
                    controls.size.value
                )
            }
            return .crop(
                size: controls.size.value,
                smartCrop: controls.smartCrop,
                longEdge: controls.size.longEdge,
                adaptiveOptimisation: controls.adaptiveOptimisation,
                removeAudio: controls.removeAudio
            )
        case .downscale:
            try rejectUnknown(
                values,
                allowed: [
                    "factor",
                    "controls",
                    "adaptive",
                    "no adaptive",
                    "mute",
                    "remove audio"
                ]
            )
            guard let factorValue = values["factor"],
                  !factorValue.isEmpty else {
                throw PublicRequestError.missingParameter("factor")
            }
            var controlParts = [factorValue]
            if let controls = values["controls"], !controls.isEmpty {
                controlParts.append(controls)
            }
            if try boolean(
                values["adaptive"],
                name: "adaptive",
                defaultValue: false
            ) {
                controlParts.append("adaptive")
            }
            if try boolean(
                values["no adaptive"],
                name: "no adaptive",
                defaultValue: false
            ) {
                controlParts.append("no-adaptive")
            }
            let mute = try boolean(
                values["mute"],
                name: "mute",
                defaultValue: false
            )
            let removeAudio = try boolean(
                values["remove audio"],
                name: "remove audio",
                defaultValue: false
            )
            if mute || removeAudio {
                controlParts.append("mute")
            }
            let controlText = controlParts.joined(separator: " ")
            guard let controls = DownscaleControlParser.parse(controlText) else {
                if controlParts.count == 1 {
                    throw PublicRequestError.invalidParameter(
                        "factor",
                        factorValue
                    )
                }
                throw PublicRequestError.invalidParameter(
                    "downscale controls",
                    controlText
                )
            }
            return .downscale(
                factor: controls.factor.factor,
                adaptiveOptimisation: controls.adaptiveOptimisation,
                removeAudio: controls.removeAudio
            )
        case .uncropPDF:
            try rejectUnknown(values, allowed: [])
            return .uncropPDF
        case .stripMetadata:
            try rejectUnknown(values, allowed: [])
            return .stripMetadata
        case .convertImage, .convertVideo, .convertAudio:
            return try conversionExecution(
                for: action,
                values: values
            )
        case .cropPDF:
            return try cropPDFExecution(values: values)
        case .pipeline:
            try rejectUnknown(values, allowed: [
                "pipeline",
                "name",
                "opt",
                "optimize",
                "hide"
            ])
            let pipelineValue = values["pipeline"] ?? values["name"]
            guard let pipeline = pipelineValue, !pipeline.isEmpty else {
                throw PublicRequestError.missingParameter("pipeline")
            }
            if values["pipeline"] != nil, values["name"] != nil {
                throw PublicRequestError.invalidParameter(
                    "pipeline",
                    "use pipeline or name, not both"
                )
            }
            if values["opt"] != nil, values["optimize"] != nil {
                throw PublicRequestError.invalidParameter(
                    "opt",
                    "use opt or optimize, not both"
                )
            }
            let hasOptimize = values["opt"] != nil || values["optimize"] != nil
            let optimizeFirst = try boolean(
                values["opt"] ?? values["optimize"],
                name: values["opt"] == nil ? "optimize" : "opt",
                defaultValue: false
            )
            let isInline = looksLikeInlinePipeline(pipeline)
            if hasOptimize, !isInline {
                throw PublicRequestError.invalidParameter(
                    values["opt"] == nil ? "optimize" : "opt",
                    "only works with inline pipeline steps"
                )
            }
            if isInline, let issue = PipelineSyntax.guidanceIssue(for: pipeline) {
                throw PublicRequestError.invalidParameter(
                    "pipeline",
                    issue.title
                )
            }
            return .pipeline(PipelineRunRequest(
                pipeline: PipelineSyntax.normalizedSteps(pipeline),
                isInline: isInline,
                optimizeFirst: optimizeFirst,
                hideResult: try boolean(
                    values["hide"],
                    name: "hide",
                    defaultValue: false
                )
            ))
        }
    }

    private static func cropPDFExecution(
        values: [String: String]
    ) throws -> ActionRequest {
        try rejectUnknown(
            values,
            allowed: [
                "ratio",
                "aspect ratio",
                "resolution",
                "device",
                "paper",
                "paper size",
                "page layout",
                "layout",
                "extend",
                "controls"
            ]
        )
        let targetValues = [
            values["ratio"],
            values["aspect ratio"],
            values["resolution"],
            values["device"],
            values["paper"],
            values["paper size"]
        ].compactMap { value in
            value?.isEmpty == false ? value : nil
        }
        guard targetValues.count == 1 else {
            throw targetValues.isEmpty
                ? PublicRequestError.missingParameter("ratio, device, or paper size")
                : PublicRequestError.invalidParameter(
                    "PDF crop target",
                    "choose only one target"
                )
        }

        let target: CropPDFTarget
        if let ratio = values["ratio"] ?? values["aspect ratio"] ?? values["resolution"] {
            guard let normalized = CropPDFControlParser.normalizedRatioTarget(ratio) else {
                throw PublicRequestError.invalidParameter("ratio", ratio)
            }
            target = .aspectRatio(normalized)
        } else if let device = values["device"] {
            target = .device(device)
        } else {
            target = .paperSize(values["paper"] ?? values["paper size"] ?? "")
        }

        let layoutValue = values["page layout"] ?? values["layout"]
        let layout: CropPDFPageLayout?
        if let layoutValue, !layoutValue.isEmpty {
            guard let parsed = CropPDFPageLayout(
                rawValue: normalizedName(layoutValue)
            ) else {
                throw PublicRequestError.invalidParameter(
                    "page layout",
                    layoutValue
                )
            }
            layout = parsed
        } else {
            layout = nil
        }

        var request = CropPDFRequest(
            target: target,
            pageLayout: layout,
            extend: try boolean(
                values["extend"],
                name: "extend",
                defaultValue: false
            )
        )
        if let controls = values["controls"], !controls.isEmpty {
            guard let parsed = CropPDFControlParser.parseControlsOnly(
                controls,
                base: request
            ) else {
                throw PublicRequestError.invalidParameter(
                    "PDF crop controls",
                    controls
                )
            }
            if request.pageLayout != nil || request.extend {
                throw PublicRequestError.invalidParameter(
                    "PDF crop controls",
                    "use controls or explicit layout/extend, not both"
                )
            }
            request = parsed
        }
        return .cropPDF(request)
    }

    private static func optimizeExecution(
        values: [String: String]
    ) throws -> ActionRequest {
        try rejectUnknown(
            values,
            allowed: [
                "aggressive",
                "media",
                "controls",
                "compression",
                "encoder",
                "remove audio",
                "playback speed",
                "dpi",
                "bitrate"
            ]
        )
        let controlValues = values.filter { key, _ in
            key != "aggressive"
        }
        guard !controlValues.isEmpty else {
            return .optimise(
                aggressive: try boolean(
                    values["aggressive"],
                    name: "aggressive",
                    defaultValue: false
                )
            )
        }
        guard values["aggressive"] == nil else {
            throw PublicRequestError.invalidParameter(
                "aggressive",
                "not available with media-specific Optimize controls"
            )
        }
        guard let mediaValue = values["media"],
              let media = optimizeMedia(for: mediaValue) else {
            throw PublicRequestError.missingParameter("media")
        }

        var controlParts = [String]()
        if let controls = values["controls"], !controls.isEmpty {
            controlParts.append(controls)
        }
        if let compression = values["compression"] {
            controlParts.append(compression)
        }
        if let encoder = values["encoder"] {
            controlParts.append(encoder)
        }
        if try boolean(
            values["remove audio"],
            name: "remove audio",
            defaultValue: false
        ) {
            controlParts.append("mute")
        }
        if let speed = values["playback speed"] {
            controlParts.append(speed.hasSuffix("x") ? speed : "\(speed)x")
        }
        if let dpi = values["dpi"] {
            controlParts.append("dpi \(dpi)")
        }
        if let bitrate = values["bitrate"] {
            controlParts.append("bitrate \(bitrate)")
        }
        guard let request = OptimizeControlParser.parse(
            controlParts.joined(separator: " "),
            media: media
        ), !OptimizeControlParser.controlDescriptions(for: request).isEmpty else {
            throw PublicRequestError.invalidParameter(
                "Optimize controls",
                controlParts.joined(separator: " ")
            )
        }
        return .optimiseMedia(request)
    }

    private static func inferredConversionExecution(
        values: [String: String]
    ) throws -> ActionRequest {
        try rejectUnknown(
            values,
            allowed: ["format", "compression", "bitrate"]
        )
        guard let formatValue = values["format"], !formatValue.isEmpty else {
            throw PublicRequestError.missingParameter("format")
        }
        guard values["compression"] == nil || values["bitrate"] == nil else {
            throw PublicRequestError.invalidParameter(
                "conversion controls",
                "use compression or bitrate, not both"
            )
        }

        let setting = try conversionSetting(from: values)
        guard let choice = ConversionCatalog.choice(
            forFormat: formatValue,
            setting: setting
        ) else {
            throw PublicRequestError.invalidParameter("format", formatValue)
        }
        guard ConversionCatalog.isSupported(choice) else {
            let value = values["compression"] ?? values["bitrate"] ?? formatValue
            throw PublicRequestError.invalidParameter(
                "conversion controls",
                value
            )
        }
        return .convert(choice)
    }

    private static func conversionExecution(
        for action: ClopAction,
        values: [String: String]
    ) throws -> ActionRequest {
        try rejectUnknown(
            values,
            allowed: ["format", "compression", "bitrate"]
        )
        let media: ConversionMediaKind
        switch action {
        case .convertImage:
            media = .image
        case .convertVideo:
            media = .video
        case .convertAudio:
            media = .audio
        default:
            throw PublicRequestError.unsupportedExecution(title(for: action))
        }
        guard let formatValue = values["format"], !formatValue.isEmpty else {
            throw PublicRequestError.missingParameter("format")
        }
        guard let format = ConversionCatalog.normalizedFormat(
            formatValue,
            media: media
        ) else {
            throw PublicRequestError.invalidParameter("format", formatValue)
        }
        guard values["compression"] == nil || values["bitrate"] == nil else {
            throw PublicRequestError.invalidParameter(
                "conversion controls",
                "use compression or bitrate, not both"
            )
        }

        let choice = ConversionChoice(
            media: media,
            format: format,
            setting: try conversionSetting(from: values)
        )
        guard ConversionCatalog.isSupported(choice) else {
            let value = values["compression"] ?? values["bitrate"] ?? format
            throw PublicRequestError.invalidParameter(
                "conversion controls",
                value
            )
        }
        return .convert(choice)
    }

    private static func conversionSetting(
        from values: [String: String]
    ) throws -> ConversionSetting? {
        if let compression = values["compression"] {
            if normalizedName(compression) == "auto" {
                return .automaticCompression
            } else if let value = Int(compression), (5...100).contains(value) {
                return .compression(value)
            } else {
                throw PublicRequestError.invalidParameter(
                    "compression",
                    compression
                )
            }
        } else if let bitrate = values["bitrate"] {
            guard let value = Int(bitrate), value > 0 else {
                throw PublicRequestError.invalidParameter("bitrate", bitrate)
            }
            return .bitrate(value)
        } else {
            return nil
        }
    }

    private static func cropSizeSupportsSmartCrop(_ size: CropSize) -> Bool {
        switch size.kind {
        case .exactDimensions, .aspectRatio:
            return true
        case .longEdge, .fixedWidth, .fixedHeight:
            return false
        }
    }

    private static func executionOverrides(
        from values: [String: String]
    ) throws -> ExecutionOverrides? {
        let output = try outputOverride(from: values)
        guard output != nil else {
            return nil
        }
        return ExecutionOverrides(output: output)
    }

    private static func outputOverride(
        from values: [String: String]
    ) throws -> OutputOverride? {
        let output = values["output"].map(normalizedName)
        let template = values["output template"]

        if let template {
            guard !template.isEmpty else {
                throw PublicRequestError.missingParameter("output template")
            }
            if let output, output != "template" {
                throw PublicRequestError.invalidParameter(
                    "output",
                    values["output"] ?? ""
                )
            }
            return .customTemplate(template)
        }

        guard let output else {
            return nil
        }
        switch output {
        case "default":
            return .default
        case "template":
            return .template
        case "false", "off", "no", "in-place", "in place":
            return .disabled
        default:
            throw PublicRequestError.invalidParameter(
                "output",
                values["output"] ?? ""
            )
        }
    }

    private static func rejectExecuteOnlyParameters(
        _ parameters: [(key: String, value: String)]
    ) throws {
        if let parameter = parameters.first {
            if executionOverrideKeys.contains(parameter.key) {
                throw PublicRequestError.executeOnlyParameter(parameter.key)
            }
            throw PublicRequestError.unexpectedParameter(parameter.key)
        }
    }

    private static func parameterDictionary(
        _ parameters: [(key: String, value: String)]
    ) throws -> [String: String] {
        var values = [String: String]()
        for parameter in parameters {
            guard values[parameter.key] == nil else {
                throw PublicRequestError.invalidParameter(
                    parameter.key,
                    "specified more than once"
                )
            }
            values[parameter.key] = parameter.value
        }
        return values
    }

    private static func rejectUnknown(
        _ parameters: [String: String],
        allowed: Set<String>
    ) throws {
        if let unknown = parameters.keys.sorted().first(where: {
            !allowed.contains($0)
        }) {
            throw PublicRequestError.unexpectedParameter(unknown)
        }
    }

    private static func boolean(
        _ value: String?,
        name: String,
        defaultValue: Bool
    ) throws -> Bool {
        guard let value else {
            return defaultValue
        }
        switch normalizedName(value) {
        case "true", "yes", "on":
            return true
        case "false", "no", "off":
            return false
        default:
            throw PublicRequestError.invalidParameter(name, value)
        }
    }

    private static func action(for value: String) -> ClopAction? {
        actionNames[normalizedName(value)]
    }

    private static func optimizeMedia(for value: String) -> OptimizeMediaKind? {
        switch normalizedName(value) {
        case "image", "images":
            return .image
        case "video", "videos":
            return .video
        case "pdf", "pdfs":
            return .pdf
        case "audio":
            return .audio
        default:
            return nil
        }
    }

    private static func title(for action: ClopAction) -> String {
        ActionCatalog.definitions.first(where: { $0.action == action })?.title
            ?? action.rawValue
    }

    private static func normalizedName(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    private static func looksLikeInlinePipeline(_ value: String) -> Bool {
        PipelineSyntax.looksLikeInlinePipeline(value)
    }

    private static let actionNames: [String: ClopAction] = [
        "optimize": .optimise,
        "crop": .crop,
        "crop / resize": .crop,
        "downscale": .downscale,
        "convert image": .convertImage,
        "convert video": .convertVideo,
        "convert audio": .convertAudio,
        "crop pdf": .cropPDF,
        "crop pdf (reversible)": .cropPDF,
        "uncrop pdf": .uncropPDF,
        "strip metadata": .stripMetadata,
        "pipeline": .pipeline,
        "pipelines": .pipeline
    ]

    private static let executionOverrideKeys: Set<String> = [
        "output",
        "output template"
    ]

}
