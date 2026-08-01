import AndromedaDomain
import Testing

@testable import AndromedaProjections

@Suite("AndromedaProjections.HashBagOfWordsEmbeddingProvider")
struct HashEmbeddingTests {
    @Test("produces a 384-dimensional vector")
    func dimensionIs384() {
        let provider = HashBagOfWordsEmbeddingProvider()
        let vector = provider.embedding(for: "hello world")

        #expect(provider.dimension == 384)
        #expect(vector.count == 384)
    }

    @Test("embedding is deterministic for identical input")
    func deterministicForSameInput() {
        let provider = HashBagOfWordsEmbeddingProvider()
        let text = "Deterministic bag-of-words embedding for Andromeda."

        let first = provider.embedding(for: text)
        let second = provider.embedding(for: text)

        #expect(first == second)
    }

    @Test("different inputs produce different vectors")
    func differentInputsDiffer() {
        let provider = HashBagOfWordsEmbeddingProvider()
        let vectorA = provider.embedding(for: "apple")
        let vectorB = provider.embedding(for: "banana")

        #expect(vectorA != vectorB)
    }

    @Test("empty input returns a zero vector")
    func emptyInputIsZeroVector() {
        let provider = HashBagOfWordsEmbeddingProvider()
        let vector = provider.embedding(for: "")

        #expect(vector.count == 384)
        #expect(vector.allSatisfy { $0 == 0 })
    }
}
