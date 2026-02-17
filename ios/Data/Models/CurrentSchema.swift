import Foundation

typealias Note = SchemaV3.Note
typealias ChatMessage = SchemaV3.ChatMessage
typealias ChatSession = SchemaV3.ChatSession
typealias KnowledgeDocument = SchemaV3.KnowledgeDocument
typealias KnowledgeChunk = SchemaV3.KnowledgeChunk

extension Note: Hashable {
    static func == (lhs: Note, rhs: Note) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

extension KnowledgeDocument: Hashable {
    static func == (lhs: KnowledgeDocument, rhs: KnowledgeDocument) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

extension KnowledgeChunk: Hashable {
    static func == (lhs: KnowledgeChunk, rhs: KnowledgeChunk) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
