import Foundation
import Testing

struct WorkflowRoutingTests {
    @Test
    func publicTriggerDispatchesBeforeOpeningTheScriptFilter() throws {
        let plist = try workflowPlist()
        let objects = try #require(plist["objects"] as? [[String: Any]])
        let dispatcher = try #require(objects.first {
            $0["uid"] as? String == "1D00E9FC-D864-41B6-B316-BDAEF753DCE4"
        })
        let config = try #require(dispatcher["config"] as? [String: Any])
        let script = try #require(config["script"] as? String)
        let connections = try #require(
            plist["connections"] as? [String: Any]
        )

        #expect(dispatcher["type"] as? String == "alfred.workflow.action.script")
        #expect(script.contains("alfred-clop route"))
        #expect(script.contains("alfred-clop route --public-request \"$request\""))
        #expect(script.contains("alfred-clop request --public-request \"$request\" --quiet"))
        #expect(script.contains("alfred-clop handoff --public-request \"$request\""))
        #expect(!script.contains("run trigger \"mainMenu\""))
        #expect(connections["1D00E9FC-D864-41B6-B316-BDAEF753DCE4"] != nil)
    }

    @Test
    func internalMenuReadsFreshRequestFromVariableAndKeepsQuerySeparate() throws {
        let plist = try workflowPlist()
        let objects = try #require(plist["objects"] as? [[String: Any]])
        let scriptFilter = try #require(objects.first {
            $0["uid"] as? String == "086222E0-0634-41BB-8795-059C6B8AF42C"
        })
        let config = try #require(scriptFilter["config"] as? [String: Any])
        let script = try #require(config["script"] as? String)

        #expect(script.hasPrefix("if [[ -n \"${alfred_clop_request:-}\" ]]"))
        #expect(script.contains("--public-request \"$alfred_clop_request\""))
        #expect(script.contains("--query \"${1:-}\""))
        #expect(script.contains("elif [[ -n \"${alfred_clop_menu_state:-}\" ]]"))
    }

    @Test
    func quietNotificationScriptsUseResolvedCLIFeedback() throws {
        let plist = try workflowPlist()
        let objects = try #require(plist["objects"] as? [[String: Any]])
        let notificationScripts = objects.compactMap { object -> String? in
            guard object["type"] as? String == "alfred.workflow.action.script",
                  let config = object["config"] as? [String: Any],
                  let script = config["script"] as? String,
                  script.contains("display notification") else {
                return nil
            }
            return script
        }

        #expect(notificationScripts.count == 6)
        #expect(notificationScripts.allSatisfy {
            $0.contains("if [[ -n \"$feedback\" ]]")
                && !$0.contains("${dnd")
        })
        #expect(notificationScripts.contains {
            $0.contains("alfred-clop configure")
                && $0.contains("configurationMutation")
        })
    }

    @Test
    func workflowExposesSharedExecutionSettings() throws {
        let plist = try workflowPlist()
        let settings = try #require(
            plist["userconfigurationconfig"] as? [[String: Any]]
        )
        let variables = Set(settings.compactMap { $0["variable"] as? String })

        #expect(variables == Set([
            "settingsPath",
            "preserveOriginal",
            "defaultOptimisation",
            "showClopUI",
            "completionNotifications",
            "errorNotifications",
            "copyResult",
            "recursiveFolders",
            "cacheRetention"
        ]))
        let completion = try #require(settings.first {
            $0["variable"] as? String == "completionNotifications"
        })
        let completionConfig = try #require(
            completion["config"] as? [String: Any]
        )
        #expect(completionConfig["default"] as? Bool == true)
    }

    @Test
    func workflowSettingsRouteOpensAlfredConfiguration() throws {
        let plist = try workflowPlist()
        let objects = try #require(plist["objects"] as? [[String: Any]])
        let settingsAction = try #require(objects.first {
            $0["uid"] as? String == "C10F19A2-39AB-4FC0-9387-33A1FB76AFA4"
        })
        let settingsConfig = try #require(
            settingsAction["config"] as? [String: Any]
        )
        let conditional = try #require(objects.first {
            $0["uid"] as? String == "C81E575B-0A6B-45AE-B968-6A2313FB84A7"
        })
        let conditionalConfig = try #require(
            conditional["config"] as? [String: Any]
        )
        let conditions = try #require(
            conditionalConfig["conditions"] as? [[String: Any]]
        )
        let connections = try #require(
            plist["connections"] as? [String: [[String: Any]]]
        )
        let routes = try #require(
            connections["C81E575B-0A6B-45AE-B968-6A2313FB84A7"]
        )

        #expect(
            settingsConfig["script"] as? String
                == "tell application id \"com.runningwithcrayons.Alfred\" to reveal workflow (system attribute \"alfred_workflow_bundleid\") with configuration"
        )
        #expect(conditions.contains {
            $0["matchstring"] as? String == "workflowSettings"
        })
        #expect(routes.contains {
            $0["destinationuid"] as? String
                == "C10F19A2-39AB-4FC0-9387-33A1FB76AFA4"
                && $0["sourceoutputuid"] as? String
                == "498E7A69-76E2-48E1-89F4-1C6FC647BA23"
        })
    }

    private func workflowPlist() throws -> [String: Any] {
        let testFile = URL(fileURLWithPath: #filePath)
        let repository = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let data = try Data(
            contentsOf: repository.appendingPathComponent("workflow/info.plist")
        )
        return try #require(
            PropertyListSerialization.propertyList(
                from: data,
                format: nil
            ) as? [String: Any]
        )
    }
}
