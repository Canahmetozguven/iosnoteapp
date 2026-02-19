import XCTest
@testable import SynapsNotes_iOS

final class RAGPipelineServiceTests: XCTestCase {
    func testRetrieveContextReturnsCitationsAndConfidence() {
        let service = RAGPipelineService()

        let relevantNote = Note(
            title: "Roadmap",
            content: "RAG ranking should prioritize grounded chunks for factual responses.",
            embedding: [0.99, 0.01]
        )
        let unrelatedNote = Note(
            title: "Shopping",
            content: "Milk and bread list.",
            embedding: [0.0, 1.0]
        )

        let document = KnowledgeDocument(
            title: "RAG Design",
            sourceType: "localFile",
            mimeType: "text/plain",
            localRelativePath: "docs/rag.txt"
        )
        let relevantChunk = KnowledgeChunk(
            chunkIndex: 0,
            pageNumber: 3,
            text: "Grounding improves reliability when the assistant cites evidence.",
            embedding: [0.97, 0.02],
            document: document
        )

        let result = service.retrieveContext(
            queryText: "How can we make rag grounded with citations?",
            queryEmbedding: [1.0, 0.0],
            notes: [relevantNote, unrelatedNote],
            chunks: [relevantChunk],
            profile: .fastRecommended
        )

        XCTAssertGreaterThan(result.selectedCount, 0)
        XCTAssertFalse(result.citations.isEmpty)
        XCTAssertEqual(result.citations.first?.id, "S1")
        XCTAssertEqual(result.citations.first(where: { $0.sourceType == .knowledgeChunk })?.pageNumber, 3)
        XCTAssertNotEqual(result.confidence, .none)
    }

    func testRetrieveContextReturnsEmptyForIrrelevantQueryWithoutSignals() {
        let service = RAGPipelineService()

        let note = Note(
            title: "General",
            content: "Completely unrelated content without overlap.",
            embedding: nil
        )

        let result = service.retrieveContext(
            queryText: "vector database tuning",
            queryEmbedding: nil,
            notes: [note],
            chunks: [],
            profile: .fastRecommended
        )

        XCTAssertEqual(result.selectedCount, 0)
        XCTAssertEqual(result.confidence, .none)
    }
}
