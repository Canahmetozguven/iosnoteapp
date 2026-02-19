import Foundation

typealias Note = SchemaV5.Note
typealias ChatMessage = SchemaV5.ChatMessage
typealias ChatSession = SchemaV5.ChatSession
typealias KnowledgeDocument = SchemaV5.KnowledgeDocument
typealias KnowledgeChunk = SchemaV5.KnowledgeChunk

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
