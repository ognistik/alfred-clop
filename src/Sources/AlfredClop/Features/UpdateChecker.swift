import Foundation

struct WorkflowVersion: Comparable, Equatable {
    var components: [Int]

    init?(_ rawValue: String) {
        let normalized = rawValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .drop(while: { $0 == "v" || $0 == "V" })
        let core = normalized.split(separator: "-", maxSplits: 1)[0]
        let parts = core.split(separator: ".", omittingEmptySubsequences: false)
        guard !parts.isEmpty,
              parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }) else {
            return nil
        }
        components = parts.compactMap { Int($0) }
    }

    static func < (lhs: WorkflowVersion, rhs: WorkflowVersion) -> Bool {
        let count = max(lhs.components.count, rhs.components.count)
        for index in 0..<count {
            let left = index < lhs.components.count ? lhs.components[index] : 0
            let right = index < rhs.components.count ? rhs.components[index] : 0
            if left != right {
                return left < right
            }
        }
        return false
    }

    static func == (lhs: WorkflowVersion, rhs: WorkflowVersion) -> Bool {
        !(lhs < rhs) && !(rhs < lhs)
    }
}

struct UpdateRelease: Codable, Equatable {
    var version: String
    var url: String
}

struct UpdateState: Codable, Equatable {
    var lastAttemptAt: Date?
    var latestRelease: UpdateRelease?
    var lastNotifiedVersion: String?

    init(
        lastAttemptAt: Date? = nil,
        latestRelease: UpdateRelease? = nil,
        lastNotifiedVersion: String? = nil
    ) {
        self.lastAttemptAt = lastAttemptAt
        self.latestRelease = latestRelease
        self.lastNotifiedVersion = lastNotifiedVersion
    }
}

enum UpdateCheckError: Error, Equatable {
    case missingWorkflowDataDirectory
    case httpStatus(Int)
    case invalidResponse
    case invalidRelease
    case requestFailed
}

extension UpdateCheckError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .missingWorkflowDataDirectory:
            return "Alfred did not provide a workflow data directory."
        case .httpStatus(404):
            return "The GitHub release is not publicly available."
        case .httpStatus(let status):
            return "GitHub returned HTTP status \(status)."
        case .invalidResponse:
            return "GitHub returned an unexpected response."
        case .invalidRelease:
            return "The latest GitHub release has an invalid version or URL."
        case .requestFailed:
            return "The latest release could not be retrieved from GitHub."
        }
    }
}

protocol LatestReleaseFetching {
    func fetchLatestRelease() throws -> UpdateRelease
}

final class GitHubLatestReleaseFetcher: LatestReleaseFetching {
    private struct Response: Decodable {
        var tagName: String
        var htmlURL: String

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case htmlURL = "html_url"
        }
    }

    private let session: URLSession
    private let endpoint: URL
    private let timeout: TimeInterval

    init(
        session: URLSession = .shared,
        endpoint: URL = URL(
            string: "https://api.github.com/repos/ognistik/alfred-clop/releases/latest"
        )!,
        timeout: TimeInterval = 3
    ) {
        self.session = session
        self.endpoint = endpoint
        self.timeout = timeout
    }

    func fetchLatestRelease() throws -> UpdateRelease {
        var request = URLRequest(url: endpoint)
        request.timeoutInterval = timeout
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Alfred-Clop-Update-Checker", forHTTPHeaderField: "User-Agent")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")

        let semaphore = DispatchSemaphore(value: 0)
        let result = UpdateRequestResult()
        let task = session.dataTask(with: request) { data, response, error in
            result.data = data
            result.response = response
            result.error = error
            semaphore.signal()
        }
        task.resume()
        guard semaphore.wait(timeout: .now() + timeout + 0.5) == .success else {
            task.cancel()
            throw UpdateCheckError.requestFailed
        }
        guard result.error == nil else {
            throw UpdateCheckError.requestFailed
        }
        guard let response = result.response as? HTTPURLResponse else {
            throw UpdateCheckError.invalidResponse
        }
        guard (200..<300).contains(response.statusCode) else {
            throw UpdateCheckError.httpStatus(response.statusCode)
        }
        guard let data = result.data else {
            throw UpdateCheckError.invalidResponse
        }
        guard let decoded = try? JSONDecoder().decode(Response.self, from: data),
              let version = WorkflowVersion(decoded.tagName),
              version.components.count >= 2,
              let releaseURL = URL(string: decoded.htmlURL),
              releaseURL.scheme == "https",
              releaseURL.host == "github.com",
              releaseURL.path.hasPrefix("/ognistik/alfred-clop/releases/tag/") else {
            throw UpdateCheckError.invalidRelease
        }
        return UpdateRelease(
            version: decoded.tagName.trimmingCharacters(in: CharacterSet(charactersIn: "vV")),
            url: decoded.htmlURL
        )
    }
}

private final class UpdateRequestResult: @unchecked Sendable {
    var data: Data?
    var response: URLResponse?
    var error: Error?
}

struct UpdateStateStore {
    static let fileName = "update-state.json"

    var fileURL: URL
    var fileManager: FileManager
    var writer: any AtomicDataWriting

    init(
        environment: Environment = Environment(),
        fileManager: FileManager = .default,
        writer: any AtomicDataWriting = FoundationAtomicDataWriter()
    ) throws {
        guard let path = environment[PresetStore.workflowDataEnvironmentKey]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !path.isEmpty else {
            throw UpdateCheckError.missingWorkflowDataDirectory
        }
        fileURL = URL(fileURLWithPath: path, isDirectory: true)
            .appendingPathComponent(Self.fileName)
        self.fileManager = fileManager
        self.writer = writer
    }

    init(
        fileURL: URL,
        fileManager: FileManager = .default,
        writer: any AtomicDataWriting = FoundationAtomicDataWriter()
    ) {
        self.fileURL = fileURL
        self.fileManager = fileManager
        self.writer = writer
    }

    func load() -> UpdateState {
        guard let data = try? Data(contentsOf: fileURL),
              let state = try? JSONDecoder().decode(UpdateState.self, from: data) else {
            return UpdateState()
        }
        return state
    }

    func persist(_ state: UpdateState) throws {
        try fileManager.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try writer.writeAtomically(encoder.encode(state), to: fileURL)
    }
}

protocol UpdateNotificationSending {
    func send(_ message: String)
}

struct AlfredUpdateNotificationSender: UpdateNotificationSending {
    func send(_ message: String) {
        var components = URLComponents(
            string: "alfred://runtrigger/com.aft.clop/updateNotification/"
        )
        components?.queryItems = [URLQueryItem(name: "argument", value: message)]
        guard let url = components?.url else {
            return
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-g", url.absoluteString]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
    }
}

struct UpdateCoordinator {
    static let checkInterval: TimeInterval = 7 * 24 * 60 * 60

    var currentVersion: String
    var store: UpdateStateStore
    var fetcher: any LatestReleaseFetching
    var notifier: any UpdateNotificationSending
    var now: () -> Date

    init(
        currentVersion: String,
        store: UpdateStateStore,
        fetcher: any LatestReleaseFetching = GitHubLatestReleaseFetcher(),
        notifier: any UpdateNotificationSending = AlfredUpdateNotificationSender(),
        now: @escaping () -> Date = Date.init
    ) {
        self.currentVersion = currentVersion
        self.store = store
        self.fetcher = fetcher
        self.notifier = notifier
        self.now = now
    }

    func automaticRelease() -> UpdateRelease? {
        var state = store.load()
        let currentTime = now()
        if shouldCheck(state: state, at: currentTime) {
            state.lastAttemptAt = currentTime
            do {
                let release = try fetcher.fetchLatestRelease()
                state.latestRelease = release
                if isNewer(release), state.lastNotifiedVersion != release.version {
                    state.lastNotifiedVersion = release.version
                    try store.persist(state)
                    notifier.send("Clop for Alfred \(release.version) is available")
                } else {
                    try store.persist(state)
                }
            } catch {
                try? store.persist(state)
            }
        }
        return state.latestRelease.flatMap { isNewer($0) ? $0 : nil }
    }

    func checkNow() -> String {
        var state = store.load()
        state.lastAttemptAt = now()
        do {
            let release = try fetcher.fetchLatestRelease()
            state.latestRelease = release
            try store.persist(state)
            if isNewer(release) {
                return "Clop for Alfred \(release.version) is available"
            }
            return "Clop for Alfred is up to date (\(currentVersion))"
        } catch {
            try? store.persist(state)
            return "Unable to check for updates: \(error.localizedDescription)"
        }
    }

    func updateItem(for release: UpdateRelease) -> ScriptFilterItem {
        ScriptFilterItem(
            uid: "update.\(release.version)",
            title: "Clop for Alfred \(release.version) is available",
            subtitle: "Press Return to open the GitHub release",
            arg: release.url,
            valid: true,
            autocomplete: "update",
            match: "update upgrade new version release github",
            variables: [
                ActionMenu.requestKindVariable:
                    WorkflowRequestKind.openUpdateRelease.rawValue
            ],
            quickLookURL: release.url,
            action: ScriptFilterAction(url: release.url)
        )
    }

    private func shouldCheck(state: UpdateState, at date: Date) -> Bool {
        guard let lastAttempt = state.lastAttemptAt else {
            return true
        }
        return date.timeIntervalSince(lastAttempt) >= Self.checkInterval
    }

    private func isNewer(_ release: UpdateRelease) -> Bool {
        guard let installed = WorkflowVersion(currentVersion),
              let latest = WorkflowVersion(release.version) else {
            return false
        }
        return installed < latest
    }
}

enum UpdateMenuIntegration {
    static func decorate(
        _ response: ScriptFilterResponse,
        query: String,
        environment: Environment = Environment()
    ) -> ScriptFilterResponse {
        guard environment.notifyOnUpdates,
              query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let currentVersion = environment["alfred_workflow_version"],
              let store = try? UpdateStateStore(environment: environment) else {
            return response
        }
        let coordinator = UpdateCoordinator(
            currentVersion: currentVersion,
            store: store
        )
        guard let release = coordinator.automaticRelease() else {
            return response
        }
        var decorated = response
        decorated.items.insert(coordinator.updateItem(for: release), at: 0)
        return decorated
    }

    static func checkNow(environment: Environment = Environment()) -> String {
        guard let currentVersion = environment["alfred_workflow_version"],
              let store = try? UpdateStateStore(environment: environment) else {
            return "Unable to check for updates: Alfred workflow data is unavailable."
        }
        return UpdateCoordinator(
            currentVersion: currentVersion,
            store: store
        ).checkNow()
    }
}
