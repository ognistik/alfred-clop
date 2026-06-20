import Foundation

struct ScriptFilterAffordance {
    var quickLookURL: String?
    var action: ScriptFilterAction?
    var largeType: String?

    static func processingInputs(
        _ inputs: [String],
        itemKinds: [InputItemKind]? = nil,
        pixelDimensions: [PixelDimensions?]? = nil
    ) -> ScriptFilterAffordance {
        var files = [String]()
        var urls = [String]()

        for (index, input) in inputs.enumerated() {
            switch kind(for: input, index: index, itemKinds: itemKinds) {
            case .remoteURL:
                urls.append(input)
            case .localFile, .folder:
                files.append(input)
            }
        }

        let action = files.isEmpty && urls.isEmpty
            ? nil
            : ScriptFilterAction(url: urls, file: files)

        return ScriptFilterAffordance(
            quickLookURL: inputs.first,
            action: action,
            largeType: inputLargeType(
                inputs,
                pixelDimensions: pixelDimensions
            )
        )
    }

    static func settingsFile(
        _ path: String,
        largeType: String? = nil
    ) -> ScriptFilterAffordance {
        ScriptFilterAffordance(
            quickLookURL: path,
            action: ScriptFilterAction(file: path),
            largeType: largeType
        )
    }

    func apply(to item: ScriptFilterItem) -> ScriptFilterItem {
        var item = item
        if item.quickLookURL == nil {
            item.quickLookURL = quickLookURL
        }
        if item.action == nil {
            item.action = action
        }
        if let largeType, item.text?.largetype == nil {
            var text = item.text ?? ScriptFilterText()
            text.largetype = largeType
            item.text = text
        }
        return item
    }

    static func inputLargeType(
        _ inputs: [String],
        pixelDimensions: [PixelDimensions?]? = nil
    ) -> String? {
        guard !inputs.isEmpty else {
            return nil
        }

        let maximumVisibleInputs = 5
        if inputs.count == 1 {
            return inputLargeTypeLine(
                displayPath(inputs[0]),
                dimensions: dimensions(at: 0, in: pixelDimensions)
            )
        }

        let sharedParent = sharedParentDirectory(for: inputs)
        var lines = ["\(inputs.count) inputs"]
        if let sharedParent {
            lines.append("Folder: \(displayPath(sharedParent))")
        }
        lines.append("")
        lines.append(contentsOf: inputs.prefix(maximumVisibleInputs)
            .enumerated()
            .map { index, input in
                inputLargeTypeLine(
                    sharedParent == nil
                        ? displayPath(input)
                        : URL(fileURLWithPath: input).lastPathComponent,
                    dimensions: dimensions(at: index, in: pixelDimensions)
                )
            })
        if inputs.count > maximumVisibleInputs {
            lines.append("... and \(inputs.count - maximumVisibleInputs) more")
        }
        return lines.joined(separator: "\n")
    }

    static func referenceLargeType(
        _ reference: String,
        inputs: [String],
        pixelDimensions: [PixelDimensions?]? = nil
    ) -> String {
        guard let inputReference = inputLargeType(
            inputs,
            pixelDimensions: pixelDimensions
        ) else {
            return reference
        }
        return "\(reference)\n\nInputs\n\(inputReference)"
    }

    private static func inputLargeTypeLine(
        _ input: String,
        dimensions: PixelDimensions?
    ) -> String {
        guard let dimensions else {
            return input
        }
        return "\(input) (\(dimensions.displayValue))"
    }

    private static func sharedParentDirectory(
        for inputs: [String]
    ) -> String? {
        guard inputs.count > 1,
              inputs.allSatisfy({ $0.hasPrefix("/") }) else {
            return nil
        }
        let parents = inputs.map {
            URL(fileURLWithPath: $0).deletingLastPathComponent().path
        }
        guard let first = parents.first,
              parents.dropFirst().allSatisfy({ $0 == first }) else {
            return nil
        }
        return first
    }

    private static func displayPath(_ input: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if input == home {
            return "~"
        }
        if input.hasPrefix("\(home)/") {
            return "~\(input.dropFirst(home.count))"
        }
        return input
    }

    private static func dimensions(
        at index: Int,
        in values: [PixelDimensions?]?
    ) -> PixelDimensions? {
        guard let values, index < values.count else {
            return nil
        }
        return values[index]
    }

    private static func kind(
        for input: String,
        index: Int,
        itemKinds: [InputItemKind]?
    ) -> InputItemKind {
        if let itemKinds, index < itemKinds.count {
            return itemKinds[index]
        }
        if let scheme = URL(string: input)?.scheme?.lowercased(),
           scheme == "http" || scheme == "https" {
            return .remoteURL
        }
        return .localFile
    }
}
