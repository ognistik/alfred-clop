import Foundation

struct ScriptFilterResponse: Codable, Equatable {
    var items: [ScriptFilterItem]
    var variables: [String: String]?
    var rerun: Double?

    init(
        items: [ScriptFilterItem] = [],
        variables: [String: String]? = nil,
        rerun: Double? = nil
    ) {
        self.items = items
        self.variables = variables
        self.rerun = rerun
    }
}

struct ScriptFilterItem: Codable, Equatable {
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

    init(
        uid: String? = nil,
        title: String,
        subtitle: String = "",
        arg: String? = nil,
        valid: Bool = true,
        autocomplete: String? = nil,
        match: String? = nil,
        icon: ScriptFilterIcon? = nil,
        variables: [String: String]? = nil,
        mods: ScriptFilterMods? = nil
    ) {
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

    enum CodingKeys: String, CodingKey {
        case command = "cmd"
        case option = "alt"
        case control = "ctrl"
        case shift
        case function = "fn"
        case commandOption = "cmd+alt"
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
