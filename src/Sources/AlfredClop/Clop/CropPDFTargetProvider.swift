import Foundation

enum CropPDFTargetProviderError: Error, Equatable {
    case missingCLI([String])
    case listFailed(String)
    case invalidOutput
}

protocol CropPDFTargetProviding {
    func devices() throws -> [CropPDFTargetValue]
    func paperSizes() throws -> [CropPDFTargetValue]
}

struct CropPDFTargetProvider: CropPDFTargetProviding {
    private enum ListKind: String, Codable {
        case devices
        case paperSizes

        var argument: String {
            switch self {
            case .devices:
                return "--list-devices"
            case .paperSizes:
                return "--list-paper-sizes"
            }
        }

        var cacheName: String {
            switch self {
            case .devices:
                return "crop-pdf-devices.json"
            case .paperSizes:
                return "crop-pdf-paper-sizes.json"
            }
        }
    }

    private struct CacheDocument: Codable {
        var cliPath: String
        var values: [CachedTargetValue]
    }

    private struct CachedTargetValue: Codable {
        var value: String
        var category: String?
        var aliases: [String]

        init(_ target: CropPDFTargetValue) {
            value = target.value
            category = target.category
            aliases = target.aliases
        }

        var target: CropPDFTargetValue {
            CropPDFTargetValue(
                value: value,
                category: category,
                aliases: aliases
            )
        }
    }

    var discovery: any ClopCLIDiscovering
    var runner: any ClopProcessRunning
    var environment: Environment
    var fileManager: FileManager

    init(
        discovery: any ClopCLIDiscovering = ClopCLIDiscovery(),
        runner: any ClopProcessRunning = FoundationClopProcessRunner(),
        environment: Environment = Environment(),
        fileManager: FileManager = .default
    ) {
        self.discovery = discovery
        self.runner = runner
        self.environment = environment
        self.fileManager = fileManager
    }

    func devices() throws -> [CropPDFTargetValue] {
        try values(kind: .devices)
    }

    func paperSizes() throws -> [CropPDFTargetValue] {
        try values(kind: .paperSizes)
    }

    private func values(kind: ListKind) throws -> [CropPDFTargetValue] {
        let diagnostics = discovery.discover()
        guard let path = diagnostics.path, diagnostics.found else {
            throw CropPDFTargetProviderError.missingCLI(diagnostics.errors)
        }
        if let cached = cachedValues(kind: kind, cliPath: path) {
            return cached
        }
        let command = ClopCommand(
            executableURL: URL(fileURLWithPath: path),
            arguments: ["crop-pdf", kind.argument],
            expectsJSON: false
        )
        let result = try runner.run(command)
        guard result.terminationStatus == 0 else {
            let message = String(data: result.standardError, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw CropPDFTargetProviderError.listFailed(
                message?.isEmpty == false ? message! : "Clop could not list PDF crop targets."
            )
        }
        guard let output = String(data: result.standardOutput, encoding: .utf8) else {
            throw CropPDFTargetProviderError.invalidOutput
        }
        let parsed = CropPDFTargetListParser.parse(output)
        guard !parsed.isEmpty else {
            throw CropPDFTargetProviderError.invalidOutput
        }
        cache(parsed, kind: kind, cliPath: path)
        return parsed
    }

    private func cachedValues(
        kind: ListKind,
        cliPath: String
    ) -> [CropPDFTargetValue]? {
        guard let url = cacheURL(kind: kind),
              let data = try? Data(contentsOf: url),
              let document = try? JSONDecoder().decode(
                  CacheDocument.self,
                  from: data
              ),
              document.cliPath == cliPath else {
            return nil
        }
        return document.values.map(\.target)
    }

    private func cache(
        _ values: [CropPDFTargetValue],
        kind: ListKind,
        cliPath: String
    ) {
        guard let url = cacheURL(kind: kind),
              let data = try? JSONEncoder().encode(CacheDocument(
                  cliPath: cliPath,
                  values: values.map(CachedTargetValue.init)
              )) else {
            return
        }
        try? fileManager.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? data.write(to: url, options: .atomic)
    }

    private func cacheURL(kind: ListKind) -> URL? {
        guard let path = environment["alfred_workflow_cache"]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !path.isEmpty else {
            return nil
        }
        return URL(fileURLWithPath: path, isDirectory: true)
            .appendingPathComponent("crop-pdf-targets", isDirectory: true)
            .appendingPathComponent(kind.cacheName)
    }
}

enum CropPDFTargetListParser {
    static func parse(_ output: String) -> [CropPDFTargetValue] {
        var values = [CropPDFTargetValue]()
        var category: String?
        var pendingValue: String?

        for rawLine in output.components(separatedBy: .newlines) {
            guard !rawLine.trimmingCharacters(in: .whitespaces).isEmpty else {
                continue
            }
            let leadingSpaces = rawLine.prefix { $0 == " " }.count
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if leadingSpaces == 0 || line.hasSuffix(":") {
                if let pendingValue {
                    values.append(CropPDFTargetValue(
                        value: pendingValue,
                        category: category,
                        aliases: []
                    ))
                }
                if line.hasSuffix(":") {
                    category = String(line.dropLast())
                }
                pendingValue = nil
                continue
            }
            if leadingSpaces == 2 {
                if let pendingValue {
                    values.append(CropPDFTargetValue(
                        value: pendingValue,
                        category: category,
                        aliases: []
                    ))
                }
                pendingValue = line
                continue
            }
            if leadingSpaces >= 6, let value = pendingValue {
                values.append(CropPDFTargetValue(
                    value: value,
                    category: category,
                    aliases: quotedValues(in: line)
                ))
                pendingValue = nil
            }
        }

        if let pendingValue {
            values.append(CropPDFTargetValue(
                value: pendingValue,
                category: category,
                aliases: []
            ))
        }

        return values
    }

    private static func quotedValues(in line: String) -> [String] {
        var values = [String]()
        var current = ""
        var insideQuote = false
        for character in line {
            if character == "\"" {
                if insideQuote {
                    values.append(current)
                    current = ""
                }
                insideQuote.toggle()
            } else if insideQuote {
                current.append(character)
            }
        }
        return values
    }
}
