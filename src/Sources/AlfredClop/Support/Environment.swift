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

    var executionOptions: ExecutionOptions {
        ExecutionOptions(
            showClopUI: true,
            copyResult: checkbox("copyResult"),
            output: .inPlace,
            backup: .trustClop,
            adaptiveOptimisation: nil,
            pdfDPI: nil,
            recursiveFolders: checkbox("recursiveFolders")
        )
    }
}
