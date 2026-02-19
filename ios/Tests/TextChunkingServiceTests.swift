import XCTest
@testable import SynapsNotes_iOS

final class TextChunkingServiceTests: XCTestCase {
    func testChunkProducesSemanticWindowsWithoutEmptyValues() {
        let service = TextChunkingService()
        let text = """
        Heading: Quarterly Plan

        The first paragraph explains the main objectives for the quarter. It includes delivery goals and quality goals.

        The second paragraph focuses on risk areas. We need better retrieval ranking. We also need stronger grounding.

        The third paragraph describes release sequencing and test strategy. It has enough words to force more than one chunk.
        """

        let chunks = service.chunk(text: text, chunkSize: 140, overlap: 30)

        XCTAssertGreaterThan(chunks.count, 1)
        XCTAssertFalse(chunks.contains(where: { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }))
        XCTAssertTrue(chunks.allSatisfy { $0.count <= 140 })
    }

    func testChunkPagesKeepsPageBoundaries() {
        let service = TextChunkingService()
        let pages = [
            "Page one has a short paragraph with product overview.",
            "Page two contains different details and should remain separately chunked."
        ]

        let chunks = service.chunkPages(pages, chunkSize: 200, overlap: 40)

        XCTAssertEqual(chunks.count, 2)
        XCTAssertTrue(chunks[0].contains("Page one"))
        XCTAssertTrue(chunks[1].contains("Page two"))
    }

    func testChunkAvoidsAbbreviationOnlyFragments() {
        let service = TextChunkingService()
        let text = "Dr. Smith reviewed the U.S.A. report carefully. It was approved by the team."
        let chunks = service.chunk(text: text, chunkSize: 28, overlap: 0)

        XCTAssertFalse(chunks.contains { $0 == "Dr." })
        XCTAssertFalse(chunks.contains { $0 == "U.S.A." })
    }

    func testOverlapStartsAtWordBoundary() {
        let service = TextChunkingService()
        let words = ["alpha", "beta", "gamma", "delta", "epsilon", "zeta", "theta", "kappa"]
        let text = Array(repeating: words.joined(separator: " "), count: 14).joined(separator: " ")
        let chunks = service.chunk(text: text, chunkSize: 70, overlap: 24)

        XCTAssertGreaterThan(chunks.count, 2)
        for chunk in chunks.dropFirst() {
            let first = chunk
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .split(separator: " ")
                .first
                .map(String.init)
            XCTAssertTrue(first.map { words.contains($0) } ?? false)
        }
    }

    func testChunkPagesWithMetadataIncludesPageNumbers() {
        let service = TextChunkingService()
        let pages = ["Page one text", "Page two text"]
        let chunks = service.chunkPagesWithMetadata(pages, chunkSize: 120, overlap: 20)

        XCTAssertEqual(chunks.count, 2)
        XCTAssertEqual(chunks[0].pageNumber, 1)
        XCTAssertEqual(chunks[1].pageNumber, 2)
    }
}
