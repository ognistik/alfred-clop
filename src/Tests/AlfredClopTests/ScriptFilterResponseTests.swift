import Foundation
import Testing
@testable import AlfredClop

struct ScriptFilterResponseTests {
    @Test
    func responseEncodesRequiredAlfredFields() throws {
        let response = ScriptFilterResponse(items: [
            ScriptFilterItem(
                title: "Optimize",
                subtitle: "Compress selected files",
                arg: "request-json",
                valid: true
            )
        ])

        let data = try JSONOutput.data(for: response)
        let json = try #require(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        let items = try #require(json["items"] as? [[String: Any]])
        let item = try #require(items.first)

        #expect(item["title"] as? String == "Optimize")
        #expect(item["subtitle"] as? String == "Compress selected files")
        #expect(item["arg"] as? String == "request-json")
        #expect(item["valid"] as? Bool == true)
    }

    @Test
    func responseSupportsFuzzyMenuFieldsAndModifiers() throws {
        let response = ScriptFilterResponse(items: [
            ScriptFilterItem(
                uid: "optimize",
                title: "Optimize",
                autocomplete: "Optimize",
                match: "compress shrink optimize",
                mods: ScriptFilterMods(
                    command: ScriptFilterModifier(
                        arg: "aggressive",
                        subtitle: "Aggressive optimize",
                        valid: true
                    )
                )
            )
        ])

        let data = try JSONOutput.data(for: response)
        let text = String(decoding: data, as: UTF8.self)

        #expect(text.contains(#""uid" : "optimize""#))
        #expect(text.contains(#""autocomplete" : "Optimize""#))
        #expect(text.contains(#""match" : "compress shrink optimize""#))
        #expect(text.contains(#""cmd""#))
    }
}
