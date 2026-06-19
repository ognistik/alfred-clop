import Foundation

enum JSONOutput {
    static func data<T: Encodable>(
        for value: T,
        prettyPrinted: Bool = true,
        sortedKeys: Bool = true
    ) throws -> Data {
        let encoder = JSONEncoder()
        var formatting: JSONEncoder.OutputFormatting = []

        if prettyPrinted {
            formatting.insert(.prettyPrinted)
        }
        if sortedKeys {
            formatting.insert(.sortedKeys)
        }

        encoder.outputFormatting = formatting
        return try encoder.encode(value)
    }

    static func string<T: Encodable>(
        for value: T,
        prettyPrinted: Bool = true,
        sortedKeys: Bool = true
    ) throws -> String {
        let encoded = try data(
            for: value,
            prettyPrinted: prettyPrinted,
            sortedKeys: sortedKeys
        )
        return String(decoding: encoded, as: UTF8.self)
    }

    static func print<T: Encodable>(_ value: T) {
        do {
            let output = try string(for: value)
            FileHandle.standardOutput.write(Data("\(output)\n".utf8))
        } catch {
            let fallback = #"{"items":[{"title":"Unable to encode Clop for Alfred output","subtitle":"JSON encoding failed","arg":"","valid":false}]}"#
            FileHandle.standardOutput.write(Data("\(fallback)\n".utf8))
        }
    }
}
