import Foundation

enum PipelineSyntax {
    struct Step: Equatable {
        var name: String
        var category: Category
        var summary: String
        var example: String?
    }

    enum Category: String, CaseIterable {
        case processing = "Processing"
        case mediaSpecific = "Media-specific"
        case filters = "Filters"
        case fileOperations = "File operations"
        case actions = "Actions"
    }

    struct SplitExpression: Equatable {
        var steps: String
        var options: String
    }

    struct GuidanceIssue: Equatable {
        var title: String
        var subtitle: String
        var detail: String
    }

    static let steps: [Step] = [
        Step(
            name: "optimise",
            category: .processing,
            summary: "compress file size",
            example: "optimise"
        ),
        Step(
            name: "downscale",
            category: .processing,
            summary: "scale down by factor",
            example: "downscale(factor: 0.5)"
        ),
        Step(
            name: "lowerBitrate",
            category: .processing,
            summary: "lower audio bitrate",
            example: "lowerBitrate(kbps: 128)"
        ),
        Step(
            name: "convert",
            category: .processing,
            summary: "change format",
            example: "convert(to: webp)"
        ),
        Step(
            name: "crop",
            category: .processing,
            summary: "resize to pixels or long edge",
            example: "crop(width: 1600)"
        ),
        Step(
            name: "extractPagesAsImages",
            category: .processing,
            summary: "render PDF pages",
            example: "extractPagesAsImages(format: jpeg, quality: high)"
        ),
        Step(
            name: "targetSize",
            category: .processing,
            summary: "fit under a size limit",
            example: "targetSize(size: 10MB)"
        ),
        Step(
            name: "stripExif",
            category: .processing,
            summary: "remove metadata",
            example: "stripExif"
        ),
        Step(
            name: "watermark",
            category: .processing,
            summary: "overlay a watermark image",
            example: #"watermark(image: "%P/logo.png", position: bottomRight)"#
        ),
        Step(
            name: "removeAudio",
            category: .mediaSpecific,
            summary: "strip video audio",
            example: "removeAudio"
        ),
        Step(
            name: "changeSpeed",
            category: .mediaSpecific,
            summary: "change playback speed",
            example: "changeSpeed(factor: 2.0)"
        ),
        Step(
            name: "capFps",
            category: .mediaSpecific,
            summary: "cap video frame rate",
            example: "capFps(fps: 30)"
        ),
        Step(
            name: "normalize",
            category: .mediaSpecific,
            summary: "normalize audio loudness",
            example: "normalize(lufs: -16)"
        ),
        Step(
            name: "if",
            category: .filters,
            summary: "continue when conditions match",
            example: #"if(types: jpeg png)"#
        ),
        Step(
            name: "ifNot",
            category: .filters,
            summary: "continue when conditions do not match",
            example: #"ifNot(nameContains: "draft")"#
        ),
        Step(
            name: "copy",
            category: .fileOperations,
            summary: "copy to path or template",
            example: #"copy(to: "~/Pictures/%f")"#
        ),
        Step(
            name: "move",
            category: .fileOperations,
            summary: "move to path or template",
            example: #"move(to: "~/Pictures/%y/%m/")"#
        ),
        Step(
            name: "rename",
            category: .fileOperations,
            summary: "rename with a template",
            example: #"rename(to: "%f-web")"#
        ),
        Step(
            name: "delete",
            category: .fileOperations,
            summary: "delete source or path",
            example: #"delete(path: "sourceFile")"#
        ),
        Step(
            name: "runScript",
            category: .actions,
            summary: "run a script or one-line shell code",
            example: #"runScript(code: "sips -Z 800 $1")"#
        ),
        Step(
            name: "runShortcut",
            category: .actions,
            summary: "run a macOS Shortcut",
            example: #"runShortcut(name: "Compress for web")"#
        ),
        Step(
            name: "copyToClipboard",
            category: .actions,
            summary: "copy path, image data, or markdown",
            example: "copyToClipboard(format: markdown)"
        ),
        Step(
            name: "copyLinkForSending",
            category: .actions,
            summary: "copy a secure sharing link",
            example: "copyLinkForSending(expiration: 1h)"
        ),
        Step(
            name: "shelveWith",
            category: .actions,
            summary: "shelve with Yoink, Dockside, or Dropover",
            example: "shelveWith(app: yoink)"
        ),
        Step(
            name: "uploadWith",
            category: .actions,
            summary: "upload with a supported app",
            example: "uploadWith(app: dropshare)"
        ),
        Step(
            name: "openWith",
            category: .actions,
            summary: "open with an app",
            example: "openWith(app: Preview)"
        )
    ]

    static let optionNames: Set<String> = ["opt", "hide"]

    private static let stepLookup = Dictionary(
        uniqueKeysWithValues: steps.map { ($0.name.lowercased(), $0) }
    )

    static var knownStepNames: Set<String> {
        Set(stepLookup.keys)
    }

    static func isKnownStep(_ name: String) -> Bool {
        let normalized = normalizedStepName(name)
        return stepLookup[normalized] != nil
    }

    static func looksLikeInlinePipeline(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return false
        }
        let expression = splitOptions(from: trimmed)?.steps ?? trimmed
        if containsTopLevelArrow(expression) {
            return true
        }
        if expression.contains("("), expression.contains(")") {
            return true
        }
        return isKnownStep(expression)
    }

    static func looksLikePipelineAttempt(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return false
        }
        return looksLikeInlinePipeline(trimmed)
            || trimmed.contains("(")
            || trimmed.contains(")")
            || trimmed.contains("->")
            || trimmed.contains(";")
    }

    static func splitOptions(from value: String) -> SplitExpression? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }
        guard let semicolon = firstTopLevelSemicolon(in: trimmed) else {
            return SplitExpression(steps: trimmed, options: "")
        }
        let steps = String(trimmed[..<semicolon])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let options = String(trimmed[trimmed.index(after: semicolon)...])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !steps.isEmpty else {
            return nil
        }
        return SplitExpression(steps: steps, options: options)
    }

    static func guidanceIssue(for value: String) -> GuidanceIssue? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }
        guard let split = splitOptions(from: trimmed) else {
            return GuidanceIssue(
                title: "Finish the pipeline steps",
                subtitle: "Use step(...) -> step ; opt hide",
                detail: syntaxReference()
            )
        }

        if !split.options.isEmpty {
            let invalidOptions = split.options
                .split(whereSeparator: \.isWhitespace)
                .map(String.init)
                .filter { !optionNames.contains($0.lowercased()) }
            if let invalid = invalidOptions.first {
                return GuidanceIssue(
                    title: "Unknown pipeline option \(invalid)",
                    subtitle: "Use opt, hide, or remove the option suffix",
                    detail: """
                    Pipeline options

                    opt: optimize before the written steps
                    hide: hide Clop's floating result UI

                    Example:
                    convert(to: webp) ; opt hide
                    """
                )
            }
        }

        if hasUnbalancedQuotes(split.steps) {
            return GuidanceIssue(
                title: "Close the quoted value",
                subtitle: #"Add the missing " before running the pipeline"#,
                detail: syntaxReference()
            )
        }
        if let balance = parenthesesBalanceIssue(in: split.steps) {
            return balance
        }

        let parts = stepExpressions(in: split.steps)
        if parts.contains(where: { $0.isEmpty }) {
            return GuidanceIssue(
                title: "Finish the pipeline step",
                subtitle: "Use step(...) -> step",
                detail: syntaxReference()
            )
        }

        let unknown = parts
            .compactMap(stepName(from:))
            .first { !isKnownStep($0) }
        if let unknown {
            let suggestion = nearestStepName(to: unknown)
            return GuidanceIssue(
                title: "Unknown pipeline step \(unknown)",
                subtitle: suggestion.map { "Did you mean \($0)?" }
                    ?? "Check the step name or press Command-L for syntax",
                detail: syntaxReference()
            )
        }

        return nil
    }

    static func syntaxReference(
        savedCreation: Bool = false,
        includeExamples: Bool = true
    ) -> String {
        var lines = [
            savedCreation ? "Pipeline add syntax" : "Pipeline syntax",
            "",
            savedCreation ? "Name => steps ; options" : "step(key: value) -> step ; options",
            "",
            "Options",
            "opt: optimize before the written steps",
            "hide: hide Clop's floating result UI"
        ]
        if savedCreation {
            lines.insert("img / vid / aud / pdf / all: file type", at: lines.endIndex)
            lines += ["", "Without opt, Clop saves the written steps only."]
        } else {
            lines += ["", "Without opt, Alfred Clop runs only the written steps."]
        }

        lines += [
            "",
            "Execution notes",
            "Workflow settings wrap the run; pipeline steps and saved settings can still do their own UI/output work.",
            "hide affects Clop result UI for this pipeline.",
            "copyToClipboard is a step, separate from workflow Copy Result.",
            "",
            "Known steps"
        ]
        for category in Category.allCases {
            let categorySteps = steps.filter { $0.category == category }
            guard !categorySteps.isEmpty else { continue }
            lines += [
                "",
                category.rawValue,
                categorySteps.map(\.name).joined(separator: ", ")
            ]
        }

        if includeExamples {
            lines += [
                "",
                "Examples",
                "crop(width: 1600) -> convert(to: webp)",
                "targetSize(size: 10MB)",
                "changeSpeed(factor: 2.0) -> removeAudio",
                "extractPagesAsImages(format: jpeg, quality: high)",
                "convert(to: webp) ; opt hide"
            ]
            if savedCreation {
                lines += [
                    "",
                    "Saved examples",
                    "to WebP => convert(to: webp) ; img",
                    "2x silent => changeSpeed(factor: 2.0) -> removeAudio ; vid hide",
                    "small WebP => convert(to: webp) ; img opt"
                ]
            }
        }

        return lines.joined(separator: "\n")
    }

    private static func stepName(from expression: String) -> String? {
        let trimmed = expression.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }
        let name = trimmed.split(
            whereSeparator: { $0 == "(" || $0.isWhitespace }
        ).first.map(String.init) ?? trimmed
        return name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func normalizedStepName(_ name: String) -> String {
        let normalized = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized == "optimize" ? "optimise" : normalized
    }

    static func normalizedSteps(_ value: String) -> String {
        splitTopLevelArrows(value).map { expression in
            normalizeStepSpelling(expression)
        }.joined(separator: " -> ")
    }

    private static func stepExpressions(in value: String) -> [String] {
        splitTopLevelArrows(value).map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    private static func normalizeStepSpelling(_ expression: String) -> String {
        let trimmed = expression.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let name = stepName(from: trimmed),
              name.caseInsensitiveCompare("optimize") == .orderedSame,
              let range = trimmed.range(of: name) else {
            return trimmed
        }
        return trimmed.replacingCharacters(in: range, with: "optimise")
    }

    private static func containsTopLevelArrow(_ value: String) -> Bool {
        splitTopLevelArrows(value).count > 1
    }

    private static func splitTopLevelArrows(_ value: String) -> [String] {
        var parts = [String]()
        var current = ""
        var depth = 0
        var quote: Character?
        var escaped = false
        var index = value.startIndex
        while index < value.endIndex {
            let char = value[index]
            if escaped {
                current.append(char)
                escaped = false
                index = value.index(after: index)
                continue
            }
            if char == "\\" {
                current.append(char)
                escaped = quote != nil
                index = value.index(after: index)
                continue
            }
            if let activeQuote = quote {
                current.append(char)
                if char == activeQuote {
                    quote = nil
                }
                index = value.index(after: index)
                continue
            }
            if char == "\"" || char == "'" {
                quote = char
                current.append(char)
                index = value.index(after: index)
                continue
            }
            if char == "(" {
                depth += 1
                current.append(char)
                index = value.index(after: index)
                continue
            }
            if char == ")" {
                depth = max(0, depth - 1)
                current.append(char)
                index = value.index(after: index)
                continue
            }
            if depth == 0,
               char == "-",
               value.index(after: index) < value.endIndex,
               value[value.index(after: index)] == ">" {
                parts.append(current)
                current = ""
                index = value.index(index, offsetBy: 2)
                continue
            }
            current.append(char)
            index = value.index(after: index)
        }
        parts.append(current)
        return parts
    }

    private static func firstTopLevelSemicolon(in value: String) -> String.Index? {
        var depth = 0
        var quote: Character?
        var escaped = false
        var index = value.startIndex
        while index < value.endIndex {
            let char = value[index]
            if escaped {
                escaped = false
                index = value.index(after: index)
                continue
            }
            if char == "\\" {
                escaped = quote != nil
                index = value.index(after: index)
                continue
            }
            if let activeQuote = quote {
                if char == activeQuote {
                    quote = nil
                }
                index = value.index(after: index)
                continue
            }
            if char == "\"" || char == "'" {
                quote = char
                index = value.index(after: index)
                continue
            }
            if char == "(" {
                depth += 1
            } else if char == ")" {
                depth = max(0, depth - 1)
            } else if char == ";", depth == 0 {
                return index
            }
            index = value.index(after: index)
        }
        return nil
    }

    private static func hasUnbalancedQuotes(_ value: String) -> Bool {
        var quote: Character?
        var escaped = false
        for char in value {
            if escaped {
                escaped = false
                continue
            }
            if char == "\\" {
                escaped = quote != nil
                continue
            }
            if let activeQuote = quote {
                if char == activeQuote {
                    quote = nil
                }
            } else if char == "\"" || char == "'" {
                quote = char
            }
        }
        return quote != nil
    }

    private static func parenthesesBalanceIssue(in value: String) -> GuidanceIssue? {
        var depth = 0
        var quote: Character?
        var escaped = false
        for char in value {
            if escaped {
                escaped = false
                continue
            }
            if char == "\\" {
                escaped = quote != nil
                continue
            }
            if let activeQuote = quote {
                if char == activeQuote {
                    quote = nil
                }
                continue
            }
            if char == "\"" || char == "'" {
                quote = char
            } else if char == "(" {
                depth += 1
            } else if char == ")" {
                depth -= 1
                if depth < 0 {
                    return GuidanceIssue(
                        title: "Remove the extra closing parenthesis",
                        subtitle: "Use step(key: value) -> step",
                        detail: syntaxReference()
                    )
                }
            }
        }
        guard depth != 0 else {
            return nil
        }
        return GuidanceIssue(
            title: "Close the pipeline step",
            subtitle: "Add the missing ) before running the pipeline",
            detail: syntaxReference()
        )
    }

    private static func nearestStepName(to value: String) -> String? {
        let normalized = value.lowercased()
        let candidates = steps
            .map { ($0.name, levenshtein(normalized, $0.name.lowercased())) }
            .sorted { lhs, rhs in
                if lhs.1 == rhs.1 {
                    return lhs.0 < rhs.0
                }
                return lhs.1 < rhs.1
            }
        guard let best = candidates.first, best.1 <= 3 else {
            return nil
        }
        return best.0
    }

    private static func levenshtein(_ lhs: String, _ rhs: String) -> Int {
        let lhsChars = Array(lhs)
        let rhsChars = Array(rhs)
        guard !lhsChars.isEmpty else { return rhsChars.count }
        guard !rhsChars.isEmpty else { return lhsChars.count }

        var previous = Array(0...rhsChars.count)
        var current = Array(repeating: 0, count: rhsChars.count + 1)
        for lhsIndex in 1...lhsChars.count {
            current[0] = lhsIndex
            for rhsIndex in 1...rhsChars.count {
                let cost = lhsChars[lhsIndex - 1] == rhsChars[rhsIndex - 1] ? 0 : 1
                current[rhsIndex] = min(
                    previous[rhsIndex] + 1,
                    current[rhsIndex - 1] + 1,
                    previous[rhsIndex - 1] + cost
                )
            }
            previous = current
        }
        return previous[rhsChars.count]
    }
}
