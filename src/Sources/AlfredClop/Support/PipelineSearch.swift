import Foundation

struct PipelineSearchResult: Equatable {
    var score: Int
    var matchedStep: String?
}

enum PipelineSearch {
    static func match(
        _ pipeline: SavedPipeline,
        query: String,
        visibleText: String
    ) -> PipelineSearchResult? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return PipelineSearchResult(score: 0, matchedStep: nil)
        }

        let visibleSearch = FuzzySearch<String>(
            query: trimmed,
            targetText: { $0 }
        )
        if let match = visibleSearch.sorted([visibleText]).first {
            return PipelineSearchResult(score: match.score, matchedStep: nil)
        }

        guard let matchedStep = matchedStep(in: pipeline.rawText, query: trimmed) else {
            return nil
        }
        let hiddenSearch = FuzzySearch<String>(
            query: trimmed,
            targetText: { $0 }
        )
        let score = hiddenSearch.sorted([pipeline.rawText]).first?.score ?? 0
        return PipelineSearchResult(score: score, matchedStep: matchedStep)
    }

    static func visibleText(
        for pipeline: SavedPipeline,
        typeDescription: String
    ) -> String {
        [
            pipeline.name,
            pipeline.fileType?.rawValue,
            typeDescription
        ].compactMap(\.self).joined(separator: " ")
    }

    private static func matchedStep(
        in rawText: String,
        query: String
    ) -> String? {
        guard let range = rawText.range(
            of: query,
            options: [.caseInsensitive, .diacriticInsensitive]
        ) else {
            return nil
        }

        let tokenRange = rawText.tokenRange(containing: range)
        let token = rawText[tokenRange]
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return token.isEmpty ? String(rawText[range]) : String(token)
    }
}

private extension String {
    func tokenRange(containing range: Range<String.Index>) -> Range<String.Index> {
        var lower = range.lowerBound
        var upper = range.upperBound

        while lower > startIndex {
            let previous = index(before: lower)
            guard self[previous].isPipelineSearchTokenCharacter else {
                break
            }
            lower = previous
        }

        while upper < endIndex,
              self[upper].isPipelineSearchTokenCharacter {
            upper = index(after: upper)
        }

        return lower..<upper
    }
}

private extension Character {
    var isPipelineSearchTokenCharacter: Bool {
        unicodeScalars.allSatisfy { scalar in
            CharacterSet.alphanumerics.contains(scalar)
                || scalar == "_"
                || scalar == "-"
        }
    }
}
