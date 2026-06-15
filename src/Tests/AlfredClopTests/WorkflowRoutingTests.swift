import Foundation
import Testing
@testable import AlfredClop

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
    func clipboardMenuHotkeyBypassesKeywordClipboardPreference() throws {
        let plist = try workflowPlist()
        let objects = try #require(plist["objects"] as? [[String: Any]])
        let connections = try #require(
            plist["connections"] as? [String: [[String: Any]]]
        )
        let hotkeyRoutes = try #require(
            connections["11111111-1111-4111-8111-111111111111"]
        )
        let explicitClipboard = try #require(objects.first {
            $0["uid"] as? String == "BBBBBBBB-BBBB-4BBB-8BBB-BBBBBBBBBBBB"
        })
        let explicitConfig = try #require(
            explicitClipboard["config"] as? [String: Any]
        )
        let variables = try #require(
            explicitConfig["variables"] as? [String: String]
        )
        let explicitRoutes = try #require(
            connections["BBBBBBBB-BBBB-4BBB-8BBB-BBBBBBBBBBBB"]
        )
        let scriptFilter = try #require(objects.first {
            $0["uid"] as? String == "086222E0-0634-41BB-8795-059C6B8AF42C"
        })
        let scriptFilterConfig = try #require(
            scriptFilter["config"] as? [String: Any]
        )
        let script = try #require(scriptFilterConfig["script"] as? String)

        #expect(hotkeyRoutes.contains {
            $0["destinationuid"] as? String
                == "BBBBBBBB-BBBB-4BBB-8BBB-BBBBBBBBBBBB"
        })
        #expect(variables["alfred_clop_explicit_clipboard"] == "true")
        #expect(explicitRoutes.contains {
            $0["destinationuid"] as? String
                == "086222E0-0634-41BB-8795-059C6B8AF42C"
        })
        #expect(script.contains("--input-source clipboard"))
        #expect(script.contains("--input-source keywordClipboard"))
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

        #expect(notificationScripts.count == 11)
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
            "readClipboardForKeyword",
            "cacheRetention",
            "theKw"
        ]))
        let clipboardKeyword = try #require(settings.first {
            $0["variable"] as? String == "readClipboardForKeyword"
        })
        let clipboardKeywordConfig = try #require(
            clipboardKeyword["config"] as? [String: Any]
        )
        #expect(clipboardKeywordConfig["default"] as? Bool == true)

        let objects = try #require(plist["objects"] as? [[String: Any]])
        let scriptFilter = try #require(objects.first {
            $0["type"] as? String == "alfred.workflow.input.scriptfilter"
        })
        let scriptFilterConfig = try #require(
            scriptFilter["config"] as? [String: Any]
        )
        let script = try #require(scriptFilterConfig["script"] as? String)
        #expect(script.contains("--input-source keywordClipboard"))

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

    @Test
    func commandReturnCanApplyConfigurationAndReturnToNamespace() throws {
        let plist = try workflowPlist()
        let objects = try #require(plist["objects"] as? [[String: Any]])
        let connections = try #require(
            plist["connections"] as? [String: [[String: Any]]]
        )
        let scriptFilterRoutes = try #require(
            connections["086222E0-0634-41BB-8795-059C6B8AF42C"]
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
        let returnVariables = try #require(objects.first {
            $0["uid"] as? String == "C0C0C0C0-C0C0-40C0-80C0-C0C0C0C0C0C0"
        })
        let variableConfig = try #require(
            returnVariables["config"] as? [String: Any]
        )
        #expect(returnVariables["version"] as? Int == 1)
        let variables = try #require(
            variableConfig["variables"] as? [String: String]
        )
        let returnTrigger = try #require(objects.first {
            $0["uid"] as? String == "A0A0A0A0-A0A0-40A0-80A0-A0A0A0A0A0A0"
        })
        let triggerConfig = try #require(
            returnTrigger["config"] as? [String: Any]
        )

        #expect(scriptFilterRoutes.contains {
            $0["modifiers"] as? Int == 1_048_576
                && $0["vitoclose"] as? Bool == true
        })
        #expect(conditions.contains {
            $0["matchstring"] as? String == "configurationMutationReturn"
        })
        #expect(variableConfig["argument"] as? String == ":")
        #expect(variables[ActionMenu.menuStateVariable] == "")
        #expect(variables[ActionMenu.publicRequestVariable] == nil)
        #expect(triggerConfig["externaltriggerid"] as? String == "mainMenu")
        #expect(triggerConfig["passinputasargument"] as? Bool == true)

        let terminalRoutes = try #require(
            connections["B30C287D-7137-4B63-8FA2-95B849C440FA"]
        )
        #expect(terminalRoutes.contains {
            $0["destinationuid"] as? String
                == "D0D0D0D0-D0D0-40D0-80D0-D0D0D0D0D0D0"
        })
    }

    @Test
    func workflowKeepsSixUserConfigurableHotkeys() throws {
        let plist = try workflowPlist()
        let objects = try #require(plist["objects"] as? [[String: Any]])

        #expect(objects.filter {
            $0["type"] as? String == "alfred.workflow.trigger.hotkey"
        }.count == 6)
    }

    @Test
    func optimizeUniversalActionUsesModifiersInsteadOfDuplicateAggressiveAction() throws {
        let plist = try workflowPlist()
        let objects = try #require(plist["objects"] as? [[String: Any]])
        let connections = try #require(
            plist["connections"] as? [String: [[String: Any]]]
        )
        let universalActions = objects.filter {
            $0["type"] as? String == "alfred.workflow.trigger.universalaction"
        }
        let names = universalActions.compactMap {
            ($0["config"] as? [String: Any])?["name"] as? String
        }
        let routes = try #require(
            connections["03E954FC-A80B-44A5-8A25-1E3A1A676063"]
        )
        let scriptsByUID: [String: String] = Dictionary(
            uniqueKeysWithValues: objects.compactMap { object in
                guard object["type"] as? String == "alfred.workflow.action.script",
                      let uid = object["uid"] as? String,
                      let script = (object["config"] as? [String: Any])?["script"]
                        as? String else {
                    return nil
                }
                return (uid, script)
            }
        )

        #expect(names.contains("Clop Optimize"))
        #expect(!names.contains("Clop Optimize (Aggressive)"))
        #expect(Set(routes.compactMap { $0["modifiers"] as? Int }) == [
            0,
            131_072,
            1_048_576,
            1_179_648
        ])

        func script(for modifiers: Int) throws -> String {
            let route = try #require(routes.first {
                $0["modifiers"] as? Int == modifiers
            })
            let uid = try #require(route["destinationuid"] as? String)
            return try #require(scriptsByUID[uid])
        }

        #expect(try !script(for: 0).contains("--standard"))
        #expect(try script(for: 1_048_576).contains("--invert-aggressive"))
        #expect(try script(for: 131_072).contains("--invert-preserve"))
        #expect(try script(for: 1_179_648).contains("--invert-aggressive"))
        #expect(try script(for: 1_179_648).contains("--invert-preserve"))
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
