import Foundation

struct CropSize: Equatable {
    var value: String
    var longEdge: Bool
}

enum CropSizeParser {
    static func parse(_ input: String) -> CropSize? {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else {
            return nil
        }

        if value.allSatisfy(\.isNumber),
           let edge = Int(value),
           edge > 0 {
            return CropSize(value: value, longEdge: true)
        }

        if let dimensions = components(of: value, separator: "x"),
           dimensions.count == 2,
           let width = Int(dimensions[0]),
           let height = Int(dimensions[1]),
           width >= 0,
           height >= 0,
           width + height > 0 {
            return CropSize(value: value, longEdge: false)
        }

        if let ratio = components(of: value, separator: ":"),
           ratio.count == 2,
           let width = Int(ratio[0]),
           let height = Int(ratio[1]),
           width > 0,
           height > 0 {
            return CropSize(value: value, longEdge: false)
        }

        return nil
    }

    private static func components(
        of value: String,
        separator: Character
    ) -> [Substring]? {
        guard value.allSatisfy({ $0.isNumber || $0 == separator }) else {
            return nil
        }
        let components = value.split(
            separator: separator,
            omittingEmptySubsequences: false
        )
        return components.allSatisfy({ !$0.isEmpty }) ? components : nil
    }
}

private struct CropPreset {
    var title: String
    var value: String
    var aliases: [String]

    var searchText: String {
        ([title, value] + aliases).joined(separator: " ")
    }
}

enum CropParameterMenu {
    private static let presets: [CropPreset] = [
        CropPreset(
            title: "1200 x 630",
            value: "1200x630",
            aliases: ["social", "open graph", "dimensions"]
        ),
        CropPreset(
            title: "1920 x 1080",
            value: "1920x1080",
            aliases: ["full hd", "dimensions"]
        ),
        CropPreset(
            title: "1080 x 1080",
            value: "1080x1080",
            aliases: ["square", "dimensions"]
        ),
        CropPreset(title: "16:9", value: "16:9", aliases: ["widescreen", "ratio"]),
        CropPreset(title: "4:3", value: "4:3", aliases: ["standard", "ratio"]),
        CropPreset(title: "3:2", value: "3:2", aliases: ["photo", "ratio"]),
        CropPreset(title: "1:1", value: "1:1", aliases: ["square", "ratio"]),
        CropPreset(title: "9:16", value: "9:16", aliases: ["vertical", "story", "ratio"]),
        CropPreset(title: "Long edge 1920", value: "1920", aliases: ["resize", "edge"]),
        CropPreset(title: "Long edge 1600", value: "1600", aliases: ["resize", "edge"]),
        CropPreset(title: "Long edge 1280", value: "1280", aliases: ["resize", "edge"]),
        CropPreset(title: "Long edge 1080", value: "1080", aliases: ["resize", "edge"]),
        CropPreset(title: "Width 128, auto height", value: "128x0", aliases: ["width", "auto"]),
        CropPreset(title: "Auto width, height 720", value: "0x720", aliases: ["height", "auto"])
    ]

    static func response(stateJSON: String, query: String) -> ScriptFilterResponse {
        guard let state = try? JSONDecoder().decode(
            MenuState.self,
            from: Data(stateJSON.utf8)
        ),
        state.mode == .crop,
        let request = state.parameterRequest,
        request.step == "parameters",
        request.action == .crop,
        !request.inputs.isEmpty else {
            return error(
                title: "Unable to open Crop / Resize",
                subtitle: "The parameter menu state is invalid or incomplete."
            )
        }

        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        var items = filteredPresets(query: trimmedQuery).compactMap {
            item(for: $0.value, title: $0.title, request: request)
        }

        if !trimmedQuery.isEmpty {
            if let parsed = CropSizeParser.parse(trimmedQuery) {
                let custom = item(
                    for: parsed.value,
                    title: "Use \(parsed.value)",
                    request: request
                )
                if !items.contains(where: { $0.arg == custom?.arg }),
                   let custom {
                    items.insert(custom, at: 0)
                }
            } else if items.isEmpty {
                items.insert(
                    ScriptFilterItem(
                        title: "Invalid crop or resize value",
                        subtitle: "Use 1200x630, 16:9, 1920, 128x0, or 0x720.",
                        arg: "",
                        valid: false
                    ),
                    at: 0
                )
            }
        }

        guard !items.isEmpty else {
            return error(
                title: "No matching crop presets",
                subtitle: "Type dimensions, a ratio, or a positive long-edge size."
            )
        }

        return ScriptFilterResponse(
            items: items,
            variables: preservedVariables(for: request, stateJSON: stateJSON)
        )
    }

    private static func filteredPresets(query: String) -> [CropPreset] {
        guard !query.isEmpty else {
            return presets
        }
        let normalized = query.lowercased()
        let matches = presets.filter { preset in
            preset.searchText.lowercased().contains(normalized)
        }
        return matches.filter { $0.value.lowercased() == normalized }
            + matches.filter { $0.value.lowercased() != normalized }
    }

    private static func item(
        for value: String,
        title: String,
        request: ParameterStepRequest
    ) -> ScriptFilterItem? {
        guard let size = CropSizeParser.parse(value),
              let argument = try? JSONOutput.string(
                for: OperationRequest(
                    inputs: request.inputs,
                    action: .crop(
                        size: size.value,
                        smartCrop: false,
                        longEdge: size.longEdge
                    ),
                    execution: defaultExecutionOptions
                ),
                prettyPrinted: false
              ) else {
            return nil
        }

        return ScriptFilterItem(
            uid: "crop.\(size.value)",
            title: title,
            subtitle: "\(request.inputContext.subtitlePrefix): Crop / resize to \(size.value)",
            arg: argument,
            valid: true,
            autocomplete: size.value,
            match: "\(title) \(size.value)",
            variables: [
                ActionMenu.requestKindVariable:
                    WorkflowRequestKind.operation.rawValue
            ]
        )
    }

    private static func preservedVariables(
        for request: ParameterStepRequest,
        stateJSON: String
    ) -> [String: String] {
        [
            ActionMenu.inputJSONVariable: (try? JSONOutput.string(
                for: MenuInput(paths: request.inputs),
                prettyPrinted: false
            )) ?? "",
            ActionMenu.inputContextVariable: request.inputContext.rawValue,
            ActionMenu.menuStateVariable: stateJSON
        ]
    }

    private static var defaultExecutionOptions: ExecutionOptions {
        ExecutionOptions(
            showClopUI: true,
            copyResult: false,
            output: .inPlace,
            backup: .trustClop,
            adaptiveOptimisation: nil,
            pdfDPI: nil
        )
    }

    private static func error(
        title: String,
        subtitle: String
    ) -> ScriptFilterResponse {
        ScriptFilterResponse(items: [
            ScriptFilterItem(
                title: title,
                subtitle: subtitle,
                arg: "",
                valid: false
            )
        ])
    }
}
