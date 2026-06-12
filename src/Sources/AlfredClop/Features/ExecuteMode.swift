import Foundation

enum ExecuteMode {
    private static let successTitles: Set<String> = [
        "Optimization complete",
        "Aggressive optimization complete",
        "Crop / resize complete",
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

        return successFeedback(for: request)
    }

    static func quietFeedback(
        requestJSON: String,
        builder: ClopCommandBuilder = ClopCommandBuilder(),
        runner: any ClopProcessRunning = FoundationClopProcessRunner()
    ) -> String? {
        let result = response(
            requestJSON: requestJSON,
            builder: builder,
            runner: runner
        )
        guard let item = result.items.first,
              !successTitles.contains(item.title) else {
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
        case .downscale, .convert, .cropPDF:
            return feedback(
                title: "Clop operation complete",
                subtitle: "Clop processed \(files).",
                valid: false
            )
        }
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
