import Foundation

struct ClopDiagnostics: Codable, Equatable {
    var found: Bool
    var path: String?
    var source: String?
    var errors: [String]
}

enum ClopDiagnosticReport {
    static let expectedCommandFamilies = [
        "optimise",
        "crop",
        "downscale",
        "convert",
        "crop-pdf",
        "uncrop-pdf",
        "strip-exif",
        "pipeline"
    ]

    static func text(
        environment: Environment = Environment(),
        discovery: any ClopCLIDiscovering = ClopCLIDiscovery(),
        fileManager: FileManager = .default,
        store: PresetStore? = nil,
        pipelineProvider: (any ClopPipelineProviding)? = nil
    ) -> String {
        let diagnostics = discovery.discover()
        let activeStore = store ?? (try? PresetStore(
            environment: environment,
            fileManager: fileManager
        ))
        let document = try? activeStore?.load()
        let execution = environment.executionOptions(
            outputTemplate: document?.outputTemplate
                ?? SettingsDocument.builtInOutputTemplate
        )
        let cliPath = diagnostics.path ?? "Not found"
        let executable = diagnostics.path.map {
            fileManager.isExecutableFile(atPath: $0)
        }
        let bundle = diagnostics.path.flatMap {
            appBundleInfo(containing: $0, fileManager: fileManager)
        }
        let workflowName = value(
            environment["alfred_workflow_name"],
            fallback: "Clop"
        )
        let workflowBundleID = value(
            environment["alfred_workflow_bundleid"],
            fallback: "com.aft.clop"
        )
        let workflowVersion = value(
            environment["alfred_workflow_version"],
            fallback: "Unavailable"
        )
        let executableText = executable.map(yesNo) ?? "Unknown"
        let bundleID = value(bundle?.identifier, fallback: "Unavailable")
        let outputTemplate = document?.outputTemplate
            ?? SettingsDocument.builtInOutputTemplate
        let settingsFile = activeStore?.fileURL.path ?? "Unavailable"
        let settingsSchema = document.map { String($0.version) } ?? "Unavailable"
        let commandAvailability = diagnostics.found && executable == true
            ? "CLI found and executable; individual commands are not probed."
            : "CLI unavailable, so commands cannot be verified."

        var lines = [
            "Alfred Clop Diagnostic Report",
            "Generated: \(iso8601Now())",
            "",
            "Workflow",
            "- Name: \(workflowName)",
            "- Bundle ID: \(workflowBundleID)",
            "- Version: \(workflowVersion)",
            "",
            "Clop CLI",
            "- Found: \(yesNo(diagnostics.found))",
            "- Path: \(cliPath)",
            "- Discovery source: \(displaySource(diagnostics.source))",
            "- Executable: \(executableText)"
        ]

        lines += [
            "- App bundle ID: \(bundleID)",
            "- App version: \(bundleVersion(bundle))",
            "",
            "Workflow Configuration",
            "- Preserve originals: \(yesNo(environment.preserveOriginal))",
            "- Output template: \(outputTemplate)",
            "- Default optimization: \(environment.aggressiveByDefault ? "Aggressive" : "Standard")",
            "- Floating Result: \(yesNo(execution.showClopUI))",
            "- Copy Result: \(yesNo(execution.copyResult))",
            "- Recurse into folders: \(yesNo(execution.recursiveFolders))",
            "- Read Clipboard keyword input: \(yesNo(environment.readClipboardForKeyword))",
            "- Clipboard History fallback: \(yesNo(environment.recoverClipboardHistory))",
            "- Completion notifications: \(yesNo(environment.completionNotifications))",
            "- Error notifications: \(yesNo(environment.errorNotifications))",
            "- Notify on Updates: \(yesNo(environment.notifyOnUpdates))",
            "- Clipboard image retention: \(environment.clipboardImageRetentionDays) days",
            "",
            "Workflow Data",
            "- Settings file: \(settingsFile)",
            "- Settings schema: \(settingsSchema)"
        ]

        lines.append(contentsOf: presetSummary(document?.presets ?? []))
        lines.append("- Saved pipelines: \(pipelineSummary(provider: pipelineProvider))")

        lines += [
            "",
            "Expected Command Families",
            "- \(expectedCommandFamilies.joined(separator: ", "))",
            "- Availability: \(commandAvailability)",
            "",
            "Discovery Errors"
        ]
        if diagnostics.errors.isEmpty {
            lines.append("- None")
        } else {
            lines.append(contentsOf: diagnostics.errors.map { "- \($0)" })
        }

        return lines.joined(separator: "\n")
    }

    private static func presetSummary(_ presets: [ActionPreset]) -> [String] {
        let groups = presetCounts(presets)
        guard groups.contains(where: { $0.count > 0 }) else {
            return ["- Presets: 0"]
        }
        return groups.map { "- \($0.title) presets: \($0.count)" }
    }

    private static func presetCounts(
        _ presets: [ActionPreset]
    ) -> [(title: String, count: Int)] {
        var optimize = 0
        var crop = 0
        var cropPDF = 0
        var downscale = 0
        var convertImage = 0
        var convertVideo = 0
        var convertAudio = 0

        for preset in presets {
            switch preset {
            case .optimize:
                optimize += 1
            case .crop:
                crop += 1
            case .cropPDF:
                cropPDF += 1
            case .downscale:
                downscale += 1
            case .conversion(let value):
                switch value.choice.media {
                case .image:
                    convertImage += 1
                case .video:
                    convertVideo += 1
                case .audio:
                    convertAudio += 1
                }
            }
        }

        return [
            ("Optimize", optimize),
            ("Crop / Resize", crop),
            ("Crop PDF", cropPDF),
            ("Downscale", downscale),
            ("Convert Image", convertImage),
            ("Convert Video", convertVideo),
            ("Convert Audio", convertAudio)
        ]
    }

    private static func pipelineSummary(
        provider: (any ClopPipelineProviding)?
    ) -> String {
        guard let provider else {
            return "Not checked"
        }
        do {
            return String(try provider.listPipelines().count)
        } catch {
            return "Unavailable (\(error.localizedDescription))"
        }
    }

    private static func appBundleInfo(
        containing executablePath: String,
        fileManager: FileManager
    ) -> AppBundleInfo? {
        var url = URL(fileURLWithPath: executablePath)
        while url.path != "/" {
            if url.pathExtension == "app" {
                let infoURL = url
                    .appendingPathComponent("Contents", isDirectory: true)
                    .appendingPathComponent("Info.plist")
                guard let data = fileManager.contents(atPath: infoURL.path),
                      let plist = try? PropertyListSerialization
                        .propertyList(
                            from: data,
                            options: [],
                            format: nil
                        ) as? [String: Any] else {
                    return AppBundleInfo()
                }
                return AppBundleInfo(
                    identifier: plist["CFBundleIdentifier"] as? String,
                    shortVersion: plist["CFBundleShortVersionString"] as? String,
                    buildVersion: plist["CFBundleVersion"] as? String
                )
            }
            url.deleteLastPathComponent()
        }
        return nil
    }

    private static func bundleVersion(_ info: AppBundleInfo?) -> String {
        guard let info else {
            return "Unavailable"
        }
        switch (
            value(info.shortVersion, fallback: ""),
            value(info.buildVersion, fallback: "")
        ) {
        case let (short, build) where !short.isEmpty && !build.isEmpty:
            return "\(short) (\(build))"
        case let (short, _) where !short.isEmpty:
            return short
        case let (_, build) where !build.isEmpty:
            return build
        default:
            return "Unavailable"
        }
    }

    private static func displaySource(_ source: String?) -> String {
        switch source {
        case "environmentOverride":
            return "Override (\(ClopCLIDiscovery.overrideEnvironmentKey))"
        case "defaultApplicationPath":
            return "/Applications"
        case "setappApplicationPath":
            return "Setapp"
        case "path":
            return "PATH"
        case .some(let source):
            return source
        case nil:
            return "Unavailable"
        }
    }

    private static func yesNo(_ value: Bool) -> String {
        value ? "Yes" : "No"
    }

    private static func value(_ value: String?, fallback: String) -> String {
        guard let value, !value.trimmingCharacters(in: .whitespaces).isEmpty else {
            return fallback
        }
        return value
    }

    private static func iso8601Now() -> String {
        ISO8601DateFormatter().string(from: Date())
    }
}

private struct AppBundleInfo {
    var identifier: String?
    var shortVersion: String?
    var buildVersion: String?
}
