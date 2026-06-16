import Foundation

struct ScriptFilterAffordance {
    var quickLookURL: String?
    var action: ScriptFilterAction?
    var largeType: String?

    static func processingInputs(
        _ inputs: [String],
        itemKinds: [InputItemKind]? = nil
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
            largeType: inputLargeType(inputs)
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

    private static func inputLargeType(_ inputs: [String]) -> String? {
        guard !inputs.isEmpty else {
            return nil
        }

        let maximumVisibleInputs = 50
        if inputs.count == 1 {
            return inputs[0]
        }

        var lines = ["\(inputs.count) inputs", ""]
        lines.append(contentsOf: inputs.prefix(maximumVisibleInputs))
        if inputs.count > maximumVisibleInputs {
            lines.append("…and \(inputs.count - maximumVisibleInputs) more")
        }
        return lines.joined(separator: "\n")
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
