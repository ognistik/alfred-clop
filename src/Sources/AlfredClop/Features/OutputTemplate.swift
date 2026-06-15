import Foundation

enum OutputTemplateError: Error, Equatable {
    case empty
    case unsupportedToken(String)
    case automaticExtension
    case explicitExtension(String)
    case unpredictableLocation
    case missingFilename
    case missingVariableFilename
    case unsupportedTilde
    case cannotPreflight(String)
    case duplicateOutput(String)
    case sourceCollision(String)
}

struct OutputTemplatePlan: Equatable {
    var template: String
    var outputPaths: [String]
}

enum OutputTemplateValidator {
    private static let supportedTokens = Set(
        [
            "y", "m", "n", "d", "w", "H", "M", "S", "p",
            "P", "f", "r", "i", "z", "s", "x", "q"
        ]
    )
    private static let variableFilenameTokens = [
        "%f", "%r", "%i", "%z", "%s", "%x", "%q"
    ]

    static func validate(_ template: String) -> OutputTemplateError? {
        let trimmed = template.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return .empty
        }
        if trimmed.hasPrefix("~"), !trimmed.hasPrefix("~/"), trimmed != "~" {
            return .unsupportedTilde
        }
        if trimmed == "%P" || trimmed == "~" {
            return .missingFilename
        }
        guard trimmed.hasPrefix("%P/")
                || trimmed.hasPrefix("/")
                || trimmed.hasPrefix("~/") else {
            return .unpredictableLocation
        }

        var index = trimmed.startIndex
        while index < trimmed.endIndex {
            guard trimmed[index] == "%" else {
                index = trimmed.index(after: index)
                continue
            }
            let tokenIndex = trimmed.index(after: index)
            guard tokenIndex < trimmed.endIndex else {
                return .unsupportedToken("%")
            }
            let token = String(trimmed[tokenIndex])
            if token == "e" {
                return .automaticExtension
            }
            guard supportedTokens.contains(token) else {
                return .unsupportedToken("%\(token)")
            }
            index = trimmed.index(after: tokenIndex)
        }

        let filename = trimmed.split(
            separator: "/",
            omittingEmptySubsequences: false
        ).last.map(String.init) ?? ""
        guard !filename.isEmpty else {
            return .missingFilename
        }
        guard variableFilenameTokens.contains(where: filename.contains) else {
            return .missingVariableFilename
        }
        if let explicitExtension = explicitExtension(in: filename) {
            return .explicitExtension(explicitExtension)
        }
        return nil
    }

    static func expandedTemplate(
        _ template: String,
        homeDirectory: String = NSHomeDirectory()
    ) -> String {
        let trimmed = template.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed == "~" || trimmed.hasPrefix("~/") else {
            return trimmed
        }
        return homeDirectory + trimmed.dropFirst()
    }

    static func plan(
        template: String,
        inputs: [String],
        outputExtension: String? = nil,
        fileManager: FileManager = .default,
        now: Date = Date()
    ) throws -> OutputTemplatePlan {
        if let error = validate(template) {
            throw error
        }

        let expanded = expandedTemplate(template)
        let basePlan = try plannedPaths(
            template: expanded,
            inputs: inputs,
            outputExtension: outputExtension,
            fileManager: fileManager,
            now: now
        )
        if basePlan.allSatisfy({
            !fileManager.fileExists(atPath: $0)
        }) {
            return OutputTemplatePlan(
                template: expanded,
                outputPaths: basePlan
            )
        }

        var suffix = 2
        while true {
            let candidate = templateByAddingSuffix(
                suffix,
                to: expanded
            )
            let outputPaths = try plannedPaths(
                template: candidate,
                inputs: inputs,
                outputExtension: outputExtension,
                fileManager: fileManager,
                now: now
            )
            if outputPaths.allSatisfy({
                !fileManager.fileExists(atPath: $0)
            }) {
                return OutputTemplatePlan(
                    template: candidate,
                    outputPaths: outputPaths
                )
            }
            suffix += 1
        }
    }

    static func preview(
        template: String,
        source: URL = URL(fileURLWithPath: "/Users/me/Pictures/Photo.png"),
        now: Date = Date(),
        homeDirectory: String = NSHomeDirectory()
    ) -> String? {
        guard validate(template) == nil else {
            return nil
        }
        return plannedURL(
            template: expandedTemplate(
                template,
                homeDirectory: homeDirectory
            ),
            source: source,
            index: 1,
            now: now
        ).path
    }

    private static func explicitExtension(in filename: String) -> String? {
        guard let dot = filename.lastIndex(of: "."),
              dot != filename.startIndex else {
            return nil
        }
        let suffix = filename[filename.index(after: dot)...]
        guard (1...5).contains(suffix.count),
              !suffix.contains("%"),
              suffix.allSatisfy({ $0.isLetter || $0.isNumber }) else {
            return nil
        }
        return ".\(suffix)"
    }

    private static func plannedURL(
        template: String,
        source: URL,
        index: Int,
        now: Date,
        outputExtension: String? = nil
    ) -> URL {
        let calendar = Calendar.current
        let replacements: [String: String] = [
            "%y": String(calendar.component(.year, from: now)),
            "%m": String(format: "%02d", calendar.component(.month, from: now)),
            "%n": monthName(now),
            "%d": String(format: "%02d", calendar.component(.day, from: now)),
            "%w": weekdayName(now),
            "%H": String(format: "%02d", calendar.component(.hour, from: now)),
            "%M": String(format: "%02d", calendar.component(.minute, from: now)),
            "%S": String(format: "%02d", calendar.component(.second, from: now)),
            "%p": calendar.component(.hour, from: now) < 12 ? "AM" : "PM",
            "%P": source.deletingLastPathComponent().path,
            "%f": source.deletingPathExtension().lastPathComponent,
            "%e": source.pathExtension,
            "%r": "preview\(index)",
            "%i": String(index)
        ]
        var path = template
        for (token, value) in replacements {
            path = path.replacingOccurrences(of: token, with: value)
        }

        var output = URL(fileURLWithPath: path)
        let resolvedExtension = outputExtension ?? source.pathExtension
        if output.pathExtension.isEmpty, !resolvedExtension.isEmpty {
            output.appendPathExtension(resolvedExtension)
        }
        return output
    }

    private static func plannedPaths(
        template: String,
        inputs: [String],
        outputExtension: String?,
        fileManager: FileManager,
        now: Date
    ) throws -> [String] {
        var planned = Set<String>()
        return try inputs.enumerated().map { offset, input in
            guard !input.hasPrefix("http://"), !input.hasPrefix("https://") else {
                throw OutputTemplateError.cannotPreflight(input)
            }
            var isDirectory: ObjCBool = false
            let exists = fileManager.fileExists(
                atPath: input,
                isDirectory: &isDirectory
            )
            guard !exists || !isDirectory.boolValue else {
                throw OutputTemplateError.cannotPreflight(input)
            }

            let source = URL(fileURLWithPath: input).standardizedFileURL
            let output = plannedURL(
                template: template,
                source: source,
                index: offset + 1,
                now: now,
                outputExtension: outputExtension
            ).standardizedFileURL
            if output == source {
                throw OutputTemplateError.sourceCollision(output.path)
            }
            guard planned.insert(output.path).inserted else {
                throw OutputTemplateError.duplicateOutput(output.path)
            }
            return output.path
        }
    }

    private static func templateByAddingSuffix(
        _ suffix: Int,
        to template: String
    ) -> String {
        let slash = template.lastIndex(of: "/")
        let filenameStart = slash.map { template.index(after: $0) }
            ?? template.startIndex
        let filename = template[filenameStart...]
        guard let dot = filename.lastIndex(of: "."),
              dot != filename.startIndex else {
            return "\(template)-\(suffix)"
        }
        return "\(template[..<dot])-\(suffix)\(template[dot...])"
    }

    private static func monthName(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MMMM"
        return formatter.string(from: date)
    }

    private static func weekdayName(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEEE"
        return formatter.string(from: date)
    }
}

extension OutputTemplateError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .empty:
            return "The output template cannot be empty."
        case .unsupportedToken(let token):
            return "The output template contains unsupported token \(token)."
        case .automaticExtension:
            return "Clop adds the correct extension automatically. Remove %e."
        case .explicitExtension(let value):
            return "Clop adds the correct extension automatically. Remove \(value)."
        case .unpredictableLocation:
            return "Start with %P/, ~/, or an absolute path so the output location is predictable."
        case .missingFilename:
            return "The template ends with a folder. Add a filename such as %f-clop."
        case .missingVariableFilename:
            return "Include a filename token such as %f, %i, or %r."
        case .unsupportedTilde:
            return "Use ~/ for your home folder. Other users' home shortcuts are not supported."
        case .cannotPreflight(let input):
            return "Preservation cannot safely preflight \(input)."
        case .duplicateOutput(let path):
            return "Multiple inputs would write to \(path)."
        case .sourceCollision(let path):
            return "The output would overwrite its source at \(path)."
        }
    }
}
