import Foundation

struct FuzzySearch<Target> {
    struct Match: Comparable, Equatable {
        let isMatch: Bool
        let score: Int
        let targetIndex: Int

        static func < (lhs: Match, rhs: Match) -> Bool {
            if lhs.score == rhs.score {
                return lhs.targetIndex > rhs.targetIndex
            }
            return lhs.score < rhs.score
        }
    }

    private let query: ContiguousArray<UnicodeScalar>
    private let targetText: (Target) -> String
    private let separators = Set("_-./ ".unicodeScalars)

    init(query: String, targetText: @escaping (Target) -> String) {
        let normalized = query.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: nil
        )
        self.query = ContiguousArray(normalized.unicodeScalars)
        self.targetText = targetText
    }

    func sorted(_ candidates: [Target], matchesOnly: Bool = true) -> [Match] {
        guard !query.isEmpty else {
            return candidates.indices.map { Match(isMatch: true, score: 0, targetIndex: $0) }
        }

        let matches = candidates.enumerated()
            .map { match($0.element, at: $0.offset) }
            .sorted(by: >)

        return matchesOnly ? matches.filter(\.isMatch) : matches
    }

    private func match(_ target: Target, at index: Int) -> Match {
        let normalizedTarget = targetText(target).folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: nil
        )
        let targetScalars = ContiguousArray(normalizedTarget.unicodeScalars)
        var queryIndex = 0
        var score = 0
        var previousMatched = false
        var previousWasSeparator = true

        for (targetIndex, scalar) in targetScalars.enumerated() {
            guard queryIndex < query.count else {
                score -= 1
                continue
            }

            if scalar == query[queryIndex] {
                if queryIndex == 0 {
                    score += max(-targetIndex * 3, -9)
                }
                if previousMatched {
                    score += 5
                }
                if previousWasSeparator {
                    score += 10
                }
                queryIndex += 1
                previousMatched = true
            } else {
                score -= 1
                previousMatched = false
            }

            previousWasSeparator = separators.contains(scalar)
        }

        return Match(
            isMatch: queryIndex == query.count,
            score: score,
            targetIndex: index
        )
    }
}
