import Foundation

struct ClopCLIDiscovery {
    static let overrideEnvironmentKey = "ALFRED_CLOP_CLI_PATH"
    static let defaultApplicationPath = "/Applications/Clop.app/Contents/SharedSupport/ClopCLI"
    static let setappApplicationPath = "/Applications/Setapp/Clop.app/Contents/SharedSupport/ClopCLI"

    private let fileManager: FileManager
    private let environment: [String: String]
    private let applicationPaths: [(path: String, source: String)]

    init(
        fileManager: FileManager = .default,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        applicationPaths: [(path: String, source: String)] = [
            (ClopCLIDiscovery.defaultApplicationPath, "defaultApplicationPath"),
            (ClopCLIDiscovery.setappApplicationPath, "setappApplicationPath")
        ]
    ) {
        self.fileManager = fileManager
        self.environment = environment
        self.applicationPaths = applicationPaths
    }

    func discover() -> ClopDiagnostics {
        var errors: [String] = []

        if let overridePath = environment[Self.overrideEnvironmentKey], !overridePath.isEmpty {
            if let error = validationError(for: overridePath) {
                errors.append("Override path \(overridePath): \(error)")
            } else {
                return found(path: overridePath, source: "environmentOverride", errors: errors)
            }
        }

        for candidate in applicationPaths {
            if validationError(for: candidate.path) == nil {
                return found(path: candidate.path, source: candidate.source, errors: errors)
            }
        }

        if let pathCandidate = executableOnPATH(named: "clop") {
            return found(path: pathCandidate, source: "path", errors: errors)
        }

        errors.append("Clop CLI was not found in the configured locations or on PATH.")
        return ClopDiagnostics(found: false, path: nil, source: nil, errors: errors)
    }

    private func found(path: String, source: String, errors: [String]) -> ClopDiagnostics {
        ClopDiagnostics(
            found: true,
            path: URL(fileURLWithPath: path).standardizedFileURL.path,
            source: source,
            errors: errors
        )
    }

    private func executableOnPATH(named executableName: String) -> String? {
        guard let pathValue = environment["PATH"] else {
            return nil
        }

        for directory in pathValue.split(separator: ":", omittingEmptySubsequences: false) {
            let baseDirectory = directory.isEmpty ? fileManager.currentDirectoryPath : String(directory)
            let candidate = URL(fileURLWithPath: baseDirectory)
                .appendingPathComponent(executableName)
                .path

            if validationError(for: candidate) == nil {
                return candidate
            }
        }

        return nil
    }

    private func validationError(for path: String) -> String? {
        var isDirectory = ObjCBool(false)

        guard fileManager.fileExists(atPath: path, isDirectory: &isDirectory) else {
            return "does not exist"
        }
        guard !isDirectory.boolValue else {
            return "is a directory"
        }
        guard fileManager.isExecutableFile(atPath: path) else {
            return "is not executable"
        }

        return nil
    }
}
