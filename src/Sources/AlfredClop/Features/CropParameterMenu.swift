import Foundation

enum CropSizeKind: Equatable {
    case exactDimensions(width: Int, height: Int)
    case aspectRatio(width: Int, height: Int)
    case longEdge(Int)
    case fixedWidth(Int)
    case fixedHeight(Int)
}

struct CropSize: Equatable {
    var value: String
    var longEdge: Bool
    var kind: CropSizeKind
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
            return CropSize(
                value: value,
                longEdge: true,
                kind: .longEdge(edge)
            )
        }

        if value.first == "w",
           let width = positiveInteger(String(value.dropFirst())) {
            return CropSize(
                value: "\(width)x0",
                longEdge: false,
                kind: .fixedWidth(width)
            )
        }

        if value.first == "h",
           let height = positiveInteger(String(value.dropFirst())) {
            return CropSize(
                value: "0x\(height)",
                longEdge: false,
                kind: .fixedHeight(height)
            )
        }

        if let dimensions = components(of: value, separator: "x"),
           dimensions.count == 2,
           let width = Int(dimensions[0]),
           let height = Int(dimensions[1]),
           width >= 0,
           height >= 0,
           width + height > 0 {
            let kind: CropSizeKind
            if height == 0 {
                kind = .fixedWidth(width)
            } else if width == 0 {
                kind = .fixedHeight(height)
            } else {
                kind = .exactDimensions(width: width, height: height)
            }
            return CropSize(value: value, longEdge: false, kind: kind)
        }

        if let ratio = components(of: value, separator: ":"),
           ratio.count == 2,
           let width = Int(ratio[0]),
           let height = Int(ratio[1]),
           width > 0,
           height > 0 {
            return CropSize(
                value: value,
                longEdge: false,
                kind: .aspectRatio(width: width, height: height)
            )
        }

        return nil
    }

    private static func positiveInteger(_ value: String) -> Int? {
        guard !value.isEmpty,
              value.allSatisfy(\.isNumber),
              let number = Int(value),
              number > 0 else {
            return nil
        }
        return number
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

enum CropParameterMenu {
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
        let item: ScriptFilterItem
        if trimmedQuery.isEmpty {
            item = ScriptFilterItem(
                title: "Type crop or resize parameters",
                subtitle: "Examples: 1200x630, 16:9, 1920, w128, h720",
                arg: "",
                valid: false
            )
        } else if let size = CropSizeParser.parse(trimmedQuery),
                  let interpretedItem = interpretedItem(
                    for: size,
                    request: request
                  ) {
            item = interpretedItem
        } else {
            item = ScriptFilterItem(
                title: "Invalid crop or resize value",
                subtitle: "Use 1200x630, 16:9, 1920, w128, h720, 128x0, or 0x720.",
                arg: "",
                valid: false
            )
        }

        return ScriptFilterResponse(
            items: [item],
            variables: preservedVariables(for: request, stateJSON: stateJSON)
        )
    }

    private static func interpretedItem(
        for size: CropSize,
        request: ParameterStepRequest
    ) -> ScriptFilterItem? {
        guard let argument = try? JSONOutput.string(
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

        let title: String
        let interpretation: String
        switch size.kind {
        case let .exactDimensions(width, height):
            title = "Use \(width)x\(height)"
            interpretation = "Crop / resize to exact dimensions \(width)x\(height)"
        case let .aspectRatio(width, height):
            title = "Use \(width):\(height)"
            interpretation = "Crop to aspect ratio \(width):\(height)"
        case let .longEdge(edge):
            title = "Use long edge \(edge)"
            interpretation = "Resize the long edge to \(edge)"
        case let .fixedWidth(width):
            title = "Width \(width), auto height"
            interpretation = "Resize to fixed width \(width) with calculated height"
        case let .fixedHeight(height):
            title = "Height \(height), auto width"
            interpretation = "Resize to fixed height \(height) with calculated width"
        }

        return ScriptFilterItem(
            uid: "crop.\(size.value)",
            title: title,
            subtitle: "\(request.inputContext.subtitlePrefix): \(interpretation)",
            arg: argument,
            valid: true,
            autocomplete: size.value,
            match: size.value,
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
