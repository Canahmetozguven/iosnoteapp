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
}
