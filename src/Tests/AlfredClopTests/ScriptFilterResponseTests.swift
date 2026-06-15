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
                ),
                text: ScriptFilterText(
                    copy: "Copy reference",
                    largetype: "Large reference"
                )
            )
        ])

        let data = try JSONOutput.data(for: response)
        let text = String(decoding: data, as: UTF8.self)

        #expect(text.contains(#""uid" : "optimize""#))
        #expect(text.contains(#""autocomplete" : "Optimize""#))
        #expect(text.contains(#""match" : "compress shrink optimize""#))
        #expect(text.contains(#""cmd""#))
        #expect(text.contains(#""largetype" : "Large reference""#))
    }

    @Test
    func responseSupportsFileActionsAndQuickLook() throws {
        let response = ScriptFilterResponse(items: [
            ScriptFilterItem(
                type: "file",
                title: "Workflow Settings",
                arg: "/tmp/settings.json",
                quickLookURL: "/tmp/settings.json",
                action: ScriptFilterAction(file: "/tmp/settings.json")
            )
        ])

        let data = try JSONOutput.data(for: response)
        let json = try #require(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        let items = try #require(json["items"] as? [[String: Any]])
        let item = try #require(items.first)
        let action = try #require(item["action"] as? [String: String])

        #expect(item["type"] as? String == "file")
        #expect(item["quicklookurl"] as? String == "/tmp/settings.json")
        #expect(action["file"] == "/tmp/settings.json")
    }

    @Test
    func responseSupportsMultipleFileAndURLActions() throws {
        let response = ScriptFilterResponse(items: [
            ScriptFilterItem(
                title: "Crop / Resize",
                arg: "request-json",
                action: ScriptFilterAction(
                    url: ["https://example.com/photo.png"],
                    file: ["/tmp/one.png", "/tmp/Folder"]
                )
            )
        ])

        let data = try JSONOutput.data(for: response)
        let json = try #require(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        let items = try #require(json["items"] as? [[String: Any]])
        let item = try #require(items.first)
        let action = try #require(item["action"] as? [String: Any])

        #expect(action["file"] as? [String] == ["/tmp/one.png", "/tmp/Folder"])
        #expect(action["url"] as? String == "https://example.com/photo.png")
    }

    @Test
    func responseEncodesAlfredSkipKnowledgeKey() throws {
        let data = try JSONOutput.data(for: ScriptFilterResponse(
            items: [],
            skipKnowledge: true
        ))
        let json = try #require(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )

        #expect(json["skipknowledge"] as? Bool == true)
    }
}
