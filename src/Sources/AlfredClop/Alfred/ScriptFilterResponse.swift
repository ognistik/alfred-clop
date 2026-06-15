import Foundation

struct ScriptFilterResponse: Codable, Equatable {
    var items: [ScriptFilterItem]
    var variables: [String: String]?
    var rerun: Double?
    var skipKnowledge: Bool?

    init(
        items: [ScriptFilterItem] = [],
        variables: [String: String]? = nil,
        rerun: Double? = nil,
        skipKnowledge: Bool? = nil
    ) {
        self.items = items
        self.variables = variables
        self.rerun = rerun
        self.skipKnowledge = skipKnowledge
    }

    enum CodingKeys: String, CodingKey {
        case items
        case variables
        case rerun
        case skipKnowledge = "skipknowledge"
    }
}

struct ScriptFilterItem: Codable, Equatable {
    var type: String?
    var uid: String?
    var title: String
    var subtitle: String
    var arg: String?
    var valid: Bool
    var autocomplete: String?
    var match: String?
    var icon: ScriptFilterIcon?
    var variables: [String: String]?
    var mods: ScriptFilterMods?
    var text: ScriptFilterText?
    var quickLookURL: String?
    var action: ScriptFilterAction?

    init(
        type: String? = nil,
        uid: String? = nil,
        title: String,
        subtitle: String = "",
        arg: String? = nil,
        valid: Bool = true,
        autocomplete: String? = nil,
        match: String? = nil,
        icon: ScriptFilterIcon? = nil,
        variables: [String: String]? = nil,
        mods: ScriptFilterMods? = nil,
        text: ScriptFilterText? = nil,
        quickLookURL: String? = nil,
        action: ScriptFilterAction? = nil
    ) {
        self.type = type
        self.uid = uid
        self.title = title
        self.subtitle = subtitle
        self.arg = arg
        self.valid = valid
        self.autocomplete = autocomplete
        self.match = match
        self.icon = icon
        self.variables = variables
        self.mods = mods
        self.text = text
        self.quickLookURL = quickLookURL
        self.action = action
    }

    enum CodingKeys: String, CodingKey {
        case type
        case uid
        case title
        case subtitle
        case arg
        case valid
        case autocomplete
        case match
        case icon
        case variables
        case mods
        case text
        case quickLookURL = "quicklookurl"
        case action
    }
}

enum ScriptFilterActionValue: Codable, Equatable {
    case single(String)
    case multiple([String])

    init?(_ values: [String]) {
        if values.isEmpty {
            return nil
        }
        if values.count == 1, let value = values.first {
            self = .single(value)
        } else {
            self = .multiple(values)
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(String.self) {
            self = .single(value)
        } else {
            self = .multiple(try container.decode([String].self))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .single(let value):
            try container.encode(value)
        case .multiple(let values):
            try container.encode(values)
        }
    }
}

struct ScriptFilterText: Codable, Equatable {
    var copy: String?
    var largetype: String?
}

struct ScriptFilterAction: Codable, Equatable {
    var text: ScriptFilterActionValue?
    var url: ScriptFilterActionValue?
    var file: ScriptFilterActionValue?
    var auto: ScriptFilterActionValue?

    init(
        text: [String] = [],
        url: [String] = [],
        file: [String] = [],
        auto: [String] = []
    ) {
        self.text = ScriptFilterActionValue(text)
        self.url = ScriptFilterActionValue(url)
        self.file = ScriptFilterActionValue(file)
        self.auto = ScriptFilterActionValue(auto)
    }

    init(
        text: String? = nil,
        url: String? = nil,
        file: String? = nil,
        auto: String? = nil
    ) {
        self.init(
            text: text.map { [$0] } ?? [],
            url: url.map { [$0] } ?? [],
            file: file.map { [$0] } ?? [],
            auto: auto.map { [$0] } ?? []
        )
    }
}

struct ScriptFilterIcon: Codable, Equatable {
    enum IconType: String, Codable {
        case fileIcon = "fileicon"
        case fileType = "filetype"
    }

    var path: String
    var type: IconType?

    init(path: String, type: IconType? = nil) {
        self.path = path
        self.type = type
    }
}

struct ScriptFilterMods: Codable, Equatable {
    var command: ScriptFilterModifier?
    var option: ScriptFilterModifier?
    var control: ScriptFilterModifier?
    var shift: ScriptFilterModifier?
    var function: ScriptFilterModifier?
    var commandOption: ScriptFilterModifier?
    var commandShift: ScriptFilterModifier?
    var optionShift: ScriptFilterModifier?
    var commandOptionShift: ScriptFilterModifier?

    enum CodingKeys: String, CodingKey {
        case command = "cmd"
        case option = "alt"
        case control = "ctrl"
        case shift
        case function = "fn"
        case commandOption = "cmd+alt"
        case commandShift = "cmd+shift"
        case optionShift = "alt+shift"
        case commandOptionShift = "cmd+alt+shift"
    }
}

struct ScriptFilterModifier: Codable, Equatable {
    var arg: String?
    var subtitle: String?
    var valid: Bool?
    var variables: [String: String]?

    init(
        arg: String? = nil,
        subtitle: String? = nil,
        valid: Bool? = nil,
        variables: [String: String]? = nil
    ) {
        self.arg = arg
        self.subtitle = subtitle
        self.valid = valid
        self.variables = variables
    }
}
