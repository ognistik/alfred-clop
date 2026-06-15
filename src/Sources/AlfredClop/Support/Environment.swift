import Foundation

struct Environment {
    var values: [String: String]

    init(values: [String: String] = ProcessInfo.processInfo.environment) {
        self.values = values
    }

    subscript(key: String) -> String? {
        values[key]
    }

    func checkbox(_ key: String) -> Bool {
        switch values[key]?.lowercased() {
        case "1", "true", "yes", "on":
            return true
        default:
            return false
        }
    }

    func checkbox(_ key: String, default defaultValue: Bool) -> Bool {
        guard values[key] != nil else {
            return defaultValue
        }
        return checkbox(key)
    }

    var preserveOriginal: Bool {
        checkbox("preserveOriginal")
    }

    var aggressiveByDefault: Bool {
        values["defaultOptimisation"]?.lowercased() == "aggressive"
    }

    var completionNotifications: Bool {
        checkbox("completionNotifications", default: true)
    }

    var errorNotifications: Bool {
        if values["errorNotifications"] != nil {
            return checkbox("errorNotifications")
        }
        return !checkbox("dnd")
    }

    var clipboardImageRetentionDays: Int {
        guard let value = values["cacheRetention"].flatMap(Int.init) else {
            return 7
        }
        return min(15, max(1, value))
    }

    var readClipboardForKeyword: Bool {
        checkbox("readClipboardForKeyword", default: true)
    }

    func executionOptions(
        outputTemplate: String = SettingsDocument.builtInOutputTemplate,
        preserveOriginal override: Bool? = nil
    ) -> ExecutionOptions {
        let preserve = override ?? preserveOriginal
        return ExecutionOptions(
            showClopUI: checkbox("showClopUI", default: true),
            copyResult: checkbox("copyResult"),
            output: preserve ? .sameFolder(template: outputTemplate) : .inPlace,
            backup: .trustClop,
            adaptiveOptimisation: nil,
            pdfDPI: nil,
            recursiveFolders: checkbox("recursiveFolders")
        )
    }

    func resolvedExecutionOptions(
        fileManager: FileManager = .default,
        preserveOriginal override: Bool? = nil
    ) throws -> ExecutionOptions {
        let document: SettingsDocument
        do {
            document = try PresetStore(
                environment: self,
                fileManager: fileManager
            ).load()
        } catch PresetStoreError.missingWorkflowDataDirectory {
            document = SettingsDocument()
        }
        return executionOptions(
            outputTemplate: document.outputTemplate,
            preserveOriginal: override
        )
    }

    var executionOptions: ExecutionOptions {
        (try? resolvedExecutionOptions()) ?? executionOptions()
    }
}
