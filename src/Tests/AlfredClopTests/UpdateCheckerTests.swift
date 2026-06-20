import Foundation
import Testing
@testable import AlfredClop

struct UpdateCheckerTests {
    @Test
    func semanticVersionsCompareNumericComponents() throws {
        #expect(try #require(WorkflowVersion("0.1.9")) < #require(WorkflowVersion("0.1.10")))
        #expect(try #require(WorkflowVersion("v1.2")) == #require(WorkflowVersion("1.2.0")))
        #expect(WorkflowVersion("release") == nil)
    }

    @Test
    func firstAutomaticCheckCachesReleaseAndNotifiesOnce() throws {
        let fixture = try UpdateFixture(
            currentVersion: "0.1.0",
            releases: [.success(UpdateRelease(
                version: "0.1.1",
                url: "https://github.com/ognistik/alfred-clop/releases/tag/v0.1.1"
            ))]
        )

        let release = fixture.coordinator.automaticRelease()
        let state = fixture.store.load()

        #expect(release?.version == "0.1.1")
        #expect(fixture.fetcher.callCount == 1)
        #expect(fixture.notifier.messages == ["Clop for Alfred 0.1.1 is available"])
        #expect(state.lastAttemptAt == fixture.date)
        #expect(state.latestRelease == release)
        #expect(state.lastNotifiedVersion == "0.1.1")
    }

    @Test
    func cachedReleaseAvoidsNetworkWithinSevenDays() throws {
        let fixture = try UpdateFixture(
            currentVersion: "0.1.0",
            releases: [.success(UpdateRelease(
                version: "0.1.1",
                url: "https://github.com/ognistik/alfred-clop/releases/tag/v0.1.1"
            ))]
        )
        _ = fixture.coordinator.automaticRelease()
        let second = fixture.coordinator.automaticRelease()

        #expect(second?.version == "0.1.1")
        #expect(fixture.fetcher.callCount == 1)
        #expect(fixture.notifier.messages.count == 1)
    }

    @Test
    func laterCheckDoesNotRepeatNotificationForSameVersion() throws {
        let release = UpdateRelease(
            version: "0.1.1",
            url: "https://github.com/ognistik/alfred-clop/releases/tag/v0.1.1"
        )
        let fixture = try UpdateFixture(
            currentVersion: "0.1.0",
            releases: [.success(release), .success(release)]
        )
        _ = fixture.coordinator.automaticRelease()
        fixture.date = fixture.date.addingTimeInterval(UpdateCoordinator.checkInterval)
        _ = fixture.coordinator.automaticRelease()

        #expect(fixture.fetcher.callCount == 2)
        #expect(fixture.notifier.messages == ["Clop for Alfred 0.1.1 is available"])
    }

    @Test
    func failedCheckIsThrottledAndPreservesCachedRelease() throws {
        let cached = UpdateRelease(
            version: "0.1.1",
            url: "https://github.com/ognistik/alfred-clop/releases/tag/v0.1.1"
        )
        let fixture = try UpdateFixture(
            currentVersion: "0.1.0",
            releases: [.failure(UpdateCheckError.requestFailed)]
        )
        try fixture.store.persist(UpdateState(latestRelease: cached))

        let first = fixture.coordinator.automaticRelease()
        let second = fixture.coordinator.automaticRelease()

        #expect(first == cached)
        #expect(second == cached)
        #expect(fixture.fetcher.callCount == 1)
        #expect(fixture.store.load().lastAttemptAt == fixture.date)
    }

    @Test
    func installedReleaseDoesNotProduceHintOrNotification() throws {
        let fixture = try UpdateFixture(
            currentVersion: "0.1.1",
            releases: [.success(UpdateRelease(
                version: "0.1.1",
                url: "https://github.com/ognistik/alfred-clop/releases/tag/v0.1.1"
            ))]
        )

        #expect(fixture.coordinator.automaticRelease() == nil)
        #expect(fixture.notifier.messages.isEmpty)
    }

    @Test
    func updateItemOpensReleaseThroughWorkflowRoute() throws {
        let fixture = try UpdateFixture(currentVersion: "0.1.0", releases: [])
        let release = UpdateRelease(
            version: "0.2.0",
            url: "https://github.com/ognistik/alfred-clop/releases/tag/v0.2.0"
        )

        let item = fixture.coordinator.updateItem(for: release)

        #expect(item.title == "Clop for Alfred 0.2.0 is available")
        #expect(item.arg == release.url)
        #expect(item.quickLookURL == release.url)
        #expect(item.action?.url == .single(release.url))
        #expect(item.icon == WorkflowIcon.updateAvailable)
        #expect(
            item.variables?[ActionMenu.requestKindVariable]
                == WorkflowRequestKind.openUpdateRelease.rawValue
        )
    }

    @Test
    func manualCheckReportsAvailableAndCurrentVersions() throws {
        let available = try UpdateFixture(
            currentVersion: "0.1.0",
            releases: [.success(UpdateRelease(
                version: "0.1.1",
                url: "https://github.com/ognistik/alfred-clop/releases/tag/v0.1.1"
            ))]
        )
        let current = try UpdateFixture(
            currentVersion: "0.1.1",
            releases: [.success(UpdateRelease(
                version: "0.1.1",
                url: "https://github.com/ognistik/alfred-clop/releases/tag/v0.1.1"
            ))]
        )

        #expect(available.coordinator.checkNow() == "Clop for Alfred 0.1.1 is available")
        #expect(current.coordinator.checkNow() == "Clop for Alfred is up to date (0.1.1)")
    }

    @Test
    func disabledAutomaticChecksLeaveMenuUntouched() {
        let response = ScriptFilterResponse(items: [
            ScriptFilterItem(title: "Optimize")
        ])

        let decorated = UpdateMenuIntegration.decorate(
            response,
            query: "",
            environment: Environment(values: ["notifyOnUpdates": "false"])
        )

        #expect(decorated == response)
    }

    @Test
    func configurationOffersManualCheckWithAutomaticStatus() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let response = ConfigurationMenu.namespaceResponse(
            query: ":updates",
            environment: Environment(values: [
                PresetStore.workflowDataEnvironmentKey: directory.path,
                "notifyOnUpdates": "false"
            ])
        )
        let item = try #require(response.items.first)

        #expect(response.items.count == 1)
        #expect(item.title == "Check for Updates")
        #expect(item.subtitle.contains("Automatic checks are disabled"))
        #expect(
            item.variables?[ActionMenu.requestKindVariable]
                == WorkflowRequestKind.updateCheck.rawValue
        )
    }
}

private final class StubLatestReleaseFetcher: LatestReleaseFetching {
    var results: [Result<UpdateRelease, Error>]
    private(set) var callCount = 0

    init(results: [Result<UpdateRelease, Error>]) {
        self.results = results
    }

    func fetchLatestRelease() throws -> UpdateRelease {
        callCount += 1
        guard !results.isEmpty else {
            throw UpdateCheckError.requestFailed
        }
        return try results.removeFirst().get()
    }
}

private final class StubUpdateNotifier: UpdateNotificationSending {
    private(set) var messages: [String] = []

    func send(_ message: String) {
        messages.append(message)
    }
}

private final class UpdateFixture {
    let directory: URL
    let store: UpdateStateStore
    let fetcher: StubLatestReleaseFetcher
    let notifier = StubUpdateNotifier()
    var date = Date(timeIntervalSince1970: 1_750_000_000)
    lazy var coordinator = UpdateCoordinator(
        currentVersion: currentVersion,
        store: store,
        fetcher: fetcher,
        notifier: notifier,
        now: { [unowned self] in self.date }
    )
    private let currentVersion: String

    init(
        currentVersion: String,
        releases: [Result<UpdateRelease, Error>]
    ) throws {
        self.currentVersion = currentVersion
        directory = try makeTemporaryDirectory()
        store = UpdateStateStore(
            fileURL: directory.appendingPathComponent(UpdateStateStore.fileName)
        )
        fetcher = StubLatestReleaseFetcher(results: releases)
    }

    deinit {
        try? FileManager.default.removeItem(at: directory)
    }
}
