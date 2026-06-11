import Foundation

struct Environment {
    var values: [String: String]

    init(values: [String: String] = ProcessInfo.processInfo.environment) {
        self.values = values
    }

    subscript(key: String) -> String? {
        values[key]
    }
}
