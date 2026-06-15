import Foundation

enum ExecuteMode {
    private static let successTitles: Set<String> = [
        "Optimization complete",
        "Aggressive optimization complete",
        "Crop / resize complete",
        "Downscale complete",
        "PDF uncrop complete",
        "Metadata removed",
        "Clop operation complete"
    ]

    static func response(
        requestJSON: String,
        builder: ClopCommandBuilder = ClopCommandBuilder(),
        runner: any ClopProcessRunning = FoundationClopProcessRunner()
    ) -> ScriptFilterResponse {
        let data = Data(requestJSON.utf8)

        if let parameterRequest = try? JSONDecoder().decode(
            ParameterStepRequest.self,
            from: data
        ), parameterRequest.step == "parameters" {
            return feedback(
                title: "This action needs more information",
                subtitle: "Parameter menus are not available yet.",
                valid: false
            )
        }

        let request: OperationRequest
        do {
            request = try JSONDecoder().decode(OperationRequest.self, from: data)
        } catch {
            return feedback(
                title: "Invalid Clop request",
                subtitle: "The selected action could not be decoded.",
                valid: false
            )
        }

        let command: ClopCommand
        do {
            command = try builder.command(for: request)
        } catch ClopCommandBuilderError.missingCLI(let errors) {
            return feedback(
                title: "Clop CLI not found",
                subtitle: errors.last ?? "Install Clop or configure its CLI path.",
                valid: false
            )
        } catch ClopCommandBuilderError.missingInputs {
            return feedback(
                title: "No files to process",
                subtitle: "Choose one or more files and try again.",
                valid: false
            )
        } catch ClopCommandBuilderError.invalidCropSize {
            return feedback(
                title: "Invalid crop or resize value",
                subtitle: "Use dimensions, a ratio, or a positive long-edge size.",
                valid: false
            )
        } catch ClopCommandBuilderError.invalidDownscaleFactor {
            return feedback(
                title: "Invalid downscale factor",
                subtitle: "Use a value greater than 0 and less than 100%.",
                valid: false
            )
        } catch ClopCommandBuilderError.unsupportedAction {
            return feedback(
                title: "This action cannot run yet",
                subtitle: "Its parameter step has not been implemented.",
                valid: false
            )
        } catch ClopCommandBuilderError.unsupportedBackupBehavior {
            return feedback(
                title: "Backup option not supported yet",
                subtitle: "Use Clop's existing backup behavior for now.",
                valid: false
            )
        } catch ClopCommandBuilderError.invalidOutputTemplate(let error) {
            return feedback(
                title: "Unsafe output template",
                subtitle: error.localizedDescription,
                valid: false
            )
        } catch {
            return feedback(
                title: "Unable to prepare Clop",
                subtitle: error.localizedDescription,
                valid: false
            )
        }

        let result: ClopProcessResult
        do {
            result = try runner.run(command)
        } catch {
            return feedback(
                title: "Unable to launch Clop",
                subtitle: error.localizedDescription,
                valid: false
            )
        }

        guard result.terminationStatus == 0 else {
            return feedback(
                title: "Clop operation failed",
                subtitle: failureMessage(from: result),
                valid: false
            )
        }

        if command.expectsJSON,
           (try? JSONSerialization.jsonObject(with: result.standardOutput)) == nil {
            return feedback(
                title: "Unable to read Clop result",
                subtitle: "Clop finished, but did not return valid JSON.",
                valid: false
            )
        }

        if command.expectsJSON,
           var appResult = try? JSONDecoder().decode(
               ClopAppResult.self,
               from: result.standardOutput
           ) {
            appResult.failed.removeAll {
                isKnownRemoteURLFalseFailure($0, request: request)
            }
            if !appResult.failed.isEmpty {
                return incompleteFeedback(for: request, result: appResult)
            }
        }

        return successFeedback(for: request)
    }

    static func quietFeedback(
        requestJSON: String,
        environment: Environment = Environment(),
        fileManager: FileManager = .default,
        builder: ClopCommandBuilder = ClopCommandBuilder(),
        runner: any ClopProcessRunning = FoundationClopProcessRunner()
    ) -> String? {
        let result = response(
            requestJSON: requestJSON,
            builder: builder,
            runner: runner
        )
        guard let item = result.items.first else {
            return nil
        }
        let isSuccess = successTitles.contains(item.title)
        let request = try? JSONDecoder().decode(
            OperationRequest.self,
            from: Data(requestJSON.utf8)
        )
        let showsClopUI = request?.execution.showClopUI ?? false
        if isSuccess && showsClopUI {
            return nil
        }
        guard isSuccess ? environment.completionNotifications
            : environment.errorNotifications else {
            return nil
        }

        if item.subtitle.isEmpty {
            return item.title
        }
        return "\(item.title): \(item.subtitle)"
    }

    private static func successFeedback(
        for request: OperationRequest
    ) -> ScriptFilterResponse {
        let count = request.inputs.count
        let files = count == 1 ? "1 file" : "\(count) files"

        switch request.action {
        case let .optimise(aggressive):
            return feedback(
                title: aggressive
                    ? "Aggressive optimization complete"
                    : "Optimization complete",
                subtitle: "Clop processed \(files).",
                valid: false
            )
        case .uncropPDF:
            return feedback(
                title: "PDF uncrop complete",
                subtitle: "Clop processed \(files).",
                valid: false
            )
        case .stripMetadata:
            return feedback(
                title: "Metadata removed",
                subtitle: "Clop processed \(files).",
                valid: false
            )
        case .crop:
            return feedback(
                title: "Crop / resize complete",
                subtitle: "Clop processed \(files).",
                valid: false
            )
        case .downscale:
            return feedback(
                title: "Downscale complete",
                subtitle: "Clop processed \(files).",
                valid: false
            )
        case .convert, .cropPDF:
            return feedback(
                title: "Clop operation complete",
                subtitle: "Clop processed \(files).",
                valid: false
            )
        }
    }

    private static func incompleteFeedback(
        for request: OperationRequest,
        result: ClopAppResult
    ) -> ScriptFilterResponse {
        let completedCount = result.done.count
        let failedCount = result.failed.count
        let totalCount = completedCount + failedCount
        let label = operationLabel(for: request.action)
        let title = completedCount == 0
            ? "\(label) not performed"
            : "\(label) partly complete"

        let countMessage: String
        if completedCount == 0 {
            countMessage = failedCount == 1
                ? "The file was not processed."
                : "\(failedCount) files were not processed."
        } else {
            countMessage = "Processed \(completedCount) of \(totalCount) files."
        }

        let detail = failureDetail(from: result.failed)
        let subtitle = detail.isEmpty
            ? countMessage
            : "\(countMessage) \(detail)"

        return feedback(title: title, subtitle: subtitle, valid: false)
    }

    private static func operationLabel(for action: ActionRequest) -> String {
        switch action {
        case .optimise:
            return "Optimization"
        case .crop:
            return "Crop / resize"
        case .downscale:
            return "Downscale"
        case .convert:
            return "Conversion"
        case .cropPDF:
            return "PDF crop"
        case .uncropPDF:
            return "PDF uncrop"
        case .stripMetadata:
            return "Metadata removal"
        }
    }

    private static func failureDetail(
        from failures: [ClopAppResult.Failure]
    ) -> String {
        guard let failure = failures.first else {
            return ""
        }

        if failures.count > 1,
           failures.allSatisfy({ isAlreadyAtRequestedSize($0.error) }) {
            return "They are already at the requested size or smaller."
        }

        guard failures.count == 1 else {
            return ""
        }

        let filename = failure.forURL
            .flatMap(URL.init(string:))?
            .lastPathComponent

        guard let error = failure.error?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !error.isEmpty else {
            return filename.map { "Skipped \($0)." } ?? ""
        }

        if isAlreadyAtRequestedSize(error) {
            let name = filename ?? "The image"
            return "\(name) is already at the requested size or smaller."
        }

        return error.hasSuffix(".") ? error : "\(error)."
    }

    private static func isAlreadyAtRequestedSize(_ error: String?) -> Bool {
        error?.hasPrefix("Image is already at the correct size or smaller:") == true
    }

    private static func isKnownRemoteURLFalseFailure(
        _ failure: ClopAppResult.Failure,
        request: OperationRequest
    ) -> Bool {
        guard let value = failure.forURL,
              request.inputs.contains(value),
              value.hasPrefix("http://") || value.hasPrefix("https://"),
              let error = failure.error?.lowercased() else {
            return false
        }
        return error.contains("url type https")
            && error.contains("isn")
            && error.contains("supported")
    }

    private static func failureMessage(from result: ClopProcessResult) -> String {
        let error = String(decoding: result.standardError, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !error.isEmpty {
            return error
        }

        let output = String(decoding: result.standardOutput, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !output.isEmpty {
            return output
        }

        return "Clop exited with status \(result.terminationStatus)."
    }

    private static func feedback(
        title: String,
        subtitle: String,
        valid: Bool
    ) -> ScriptFilterResponse {
        ScriptFilterResponse(items: [
            ScriptFilterItem(
                title: title,
                subtitle: subtitle,
                arg: "",
                valid: valid
            )
        ])
    }
}

private struct ClopAppResult: Decodable {
    struct Completed: Decodable {}

    struct Failure: Decodable {
        var error: String?
        var forURL: String?
    }

    var done: [Completed]
    var failed: [Failure]

    private enum CodingKeys: String, CodingKey {
        case done
        case failed
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        done = try container.decodeIfPresent([Completed].self, forKey: .done) ?? []
        failed = try container.decodeIfPresent([Failure].self, forKey: .failed) ?? []
    }
}
