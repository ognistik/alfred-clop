import Foundation
import Testing
@testable import AlfredClop

struct SettingsFoundationTests {
    @Test
    func outputTemplateRejectsEmptyAndUnknownTokens() {
        #expect(OutputTemplateValidator.validate(" ") == .empty)
        #expect(
            OutputTemplateValidator.validate("%P/%f-%Q")
                == .unsupportedToken("%Q")
        )
        #expect(OutputTemplateValidator.validate("%P/%f-clop") == nil)
    }

    @Test
    func outputPlanningProtectsDuplicatesAndSources() throws {
        let firstDirectory = try makeTemporaryDirectory()
        let secondDirectory = try makeTemporaryDirectory()
        let first = firstDirectory.appendingPathComponent("same.png")
        let second = secondDirectory.appendingPathComponent("same.png")
        try Data().write(to: first)
        try Data().write(to: second)

        #expect(throws: OutputTemplateError.duplicateOutput(
            "/tmp/same-clop.png"
        )) {
            try OutputTemplateValidator.plan(
                template: "/tmp/%f-clop",
                inputs: [first.path, second.path]
            )
        }

        let existing = firstDirectory.appendingPathComponent("same-clop.png")
        try Data().write(to: existing)
        #expect(throws: OutputTemplateError.sourceCollision(first.path)) {
            try OutputTemplateValidator.plan(
                template: "%P/%f.%e",
                inputs: [first.path]
            )
        }
    }

    @Test
    func outputPlanningAddsNextAvailableNumericSuffix() throws {
        let directory = try makeTemporaryDirectory()
        let source = directory.appendingPathComponent("photo.png")
        try Data().write(to: source)
        try Data().write(
            to: directory.appendingPathComponent("photo-clop.png")
        )
        try Data().write(
            to: directory.appendingPathComponent("photo-clop-2.png")
        )

        let plan = try OutputTemplateValidator.plan(
            template: "%P/%f-clop",
            inputs: [source.path]
        )

        #expect(plan.template == "%P/%f-clop-3")
        #expect(plan.outputPaths == [
            directory.appendingPathComponent("photo-clop-3.png").path
        ])
    }

    @Test
    func numericSuffixPrecedesExplicitExtensionToken() throws {
        let directory = try makeTemporaryDirectory()
        let source = directory.appendingPathComponent("photo.png")
        try Data().write(to: source)
        try Data().write(
            to: directory.appendingPathComponent("photo-small.png")
        )

        let plan = try OutputTemplateValidator.plan(
            template: "%P/%f-small.%e",
            inputs: [source.path]
        )

        #expect(plan.template == "%P/%f-small-2.%e")
    }

    @Test
    func environmentResolvesAllStaticExecutionSettings() throws {
        let directory = try makeTemporaryDirectory()
        let environment = Environment(values: [
            PresetStore.workflowDataEnvironmentKey: directory.path,
            "preserveOriginal": "true",
            "defaultOptimisation": "aggressive",
            "showClopUI": "false",
            "copyResult": "true",
            "recursiveFolders": "true",
            "completionNotifications": "true",
            "errorNotifications": "false",
            "cacheRetention": "15"
        ])
        let execution = try environment.resolvedExecutionOptions()

        #expect(environment.aggressiveByDefault)
        #expect(environment.completionNotifications)
        #expect(!environment.errorNotifications)
        #expect(environment.clipboardImageRetentionDays == 15)
        #expect(!execution.showClopUI)
        #expect(execution.copyResult)
        #expect(execution.recursiveFolders)
        #expect(execution.output == .sameFolder(template: "%P/%f-clop"))
    }

    @Test
    func optimizeAndCropExposeConfiguredDefaultInversions() throws {
        let directory = try makeTemporaryDirectory()
        let environment = Environment(values: [
            PresetStore.workflowDataEnvironmentKey: directory.path,
            "preserveOriginal": "true",
            "defaultOptimisation": "aggressive"
        ])
        let optimize = ActionMenu.response(
            for: InputSelection(
                inputs: ["/tmp/photo.png"],
                mediaKinds: [.image]
            ),
            query: "optimize",
            environment: environment
        )
        let optimizeItem = try #require(optimize.items.first)
        let normal = try operation(optimizeItem.arg)
        let command = try operation(optimizeItem.mods?.command?.arg)
        let shift = try operation(optimizeItem.mods?.shift?.arg)

        #expect(normal.action == .optimise(aggressive: true))
        #expect(command.action == .optimise(aggressive: false))
        #expect(normal.execution.output == .sameFolder(template: "%P/%f-clop"))
        #expect(shift.execution.output == .inPlace)

        let request = ParameterStepRequest(
            action: .crop,
            inputs: ["/tmp/photo.png"]
        )
        let crop = CropParameterMenu.response(
            stateJSON: try JSONOutput.string(
                for: MenuState.crop(request),
                prettyPrinted: false
            ),
            query: "16:9",
            environment: environment
        )
        let cropItem = try #require(crop.items.first)
        #expect(cropItem.mods?.option != nil)
        #expect(cropItem.mods?.commandOptionShift != nil)
        let smart = try operation(cropItem.mods?.option?.arg)
        #expect(smart.action == .crop(
            size: "16:9",
            smartCrop: true,
            longEdge: false
        ))
    }

    @Test
    func configurationResetKeepsPresetsAndCommandResetCountsThem() throws {
        let directory = try makeTemporaryDirectory()
        let environment = Environment(values: [
            PresetStore.workflowDataEnvironmentKey: directory.path
        ])
        let store = try PresetStore(environment: environment)
        _ = try store.save(.crop(CropActionPreset(
            size: try #require(CropSizeParser.parse("w128"))
        )))
        try store.updateOutputTemplate("%P/Processed/%f")
        let menu = ConfigurationMenu.response(
            stateJSON: try JSONOutput.string(
                for: MenuState.configuration(),
                prettyPrinted: false
            ),
            query: "",
            environment: environment
        )
        let reset = try #require(menu.items.first {
            $0.title == "Reset output template"
        })

        #expect(reset.mods?.command?.subtitle == "Reset all action presets (1)")

        let confirmation = ConfigurationMenu.response(
            stateJSON: try #require(
                reset.variables?[ActionMenu.menuStateVariable]
            ),
            query: "",
            environment: environment
        )
        _ = ConfigurationMenu.response(
            stateJSON: try #require(confirmation.items.first?.arg),
            query: "",
            environment: environment
        )

        let document = try store.load()
        #expect(document.outputTemplate == "%P/%f-clop")
        #expect(document.presets.count == 1)
    }

    @Test
    func cacheCleanupCountsOnlyWorkflowClipboardImages() throws {
        let directory = try makeTemporaryDirectory()
        let first = directory.appendingPathComponent("clipboard-one.png")
        let second = directory.appendingPathComponent("clipboard-two.tiff")
        let unrelated = directory.appendingPathComponent("other.png")
        try Data(repeating: 1, count: 10).write(to: first)
        try Data(repeating: 2, count: 20).write(to: second)
        try Data(repeating: 3, count: 40).write(to: unrelated)
        let cache = ClipboardImageCache(directories: [directory])

        #expect(cache.summary() == ClipboardImageCacheSummary(
            fileCount: 2,
            byteCount: 30
        ))
        #expect(cache.removeAll().fileCount == 2)
        #expect(FileManager.default.fileExists(atPath: unrelated.path))
    }

    private func operation(_ json: String?) throws -> OperationRequest {
        try JSONDecoder().decode(
            OperationRequest.self,
            from: Data(try #require(json).utf8)
        )
    }
}
