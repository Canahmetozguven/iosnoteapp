import Foundation

typealias Note = SchemaV4.Note
typealias ChatMessage = SchemaV4.ChatMessage
typealias ChatSession = SchemaV4.ChatSession
typealias KnowledgeDocument = SchemaV4.KnowledgeDocument
typealias KnowledgeChunk = SchemaV4.KnowledgeChunk

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
