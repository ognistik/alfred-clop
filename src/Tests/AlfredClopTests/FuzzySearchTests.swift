import Testing
@testable import AlfredClop

struct FuzzySearchTests {
    @Test
    func ranksPrefixAndWordBoundaryMatchesFirst() {
        let candidates = [
            "Strip Metadata",
            "Aggressive Optimize",
            "Optimize",
            "Crop PDF"
        ]
        let search = FuzzySearch<String>(query: "opt", targetText: { $0 })
        let matches = search.sorted(candidates)

        #expect(matches.map(\.targetIndex) == [2, 1])
    }

    @Test
    func matchesAreCaseAndDiacriticInsensitive() {
        let candidates = ["Optimisé", "Crop"]
        let search = FuzzySearch<String>(query: "optimise", targetText: { $0 })

        #expect(search.sorted(candidates).map(\.targetIndex) == [0])
    }

    @Test
    func emptyQueryPreservesOriginalOrder() {
        let candidates = ["Convert", "Crop", "Optimize"]
        let search = FuzzySearch<String>(query: "", targetText: { $0 })

        #expect(search.sorted(candidates).map(\.targetIndex) == [0, 1, 2])
    }
}
