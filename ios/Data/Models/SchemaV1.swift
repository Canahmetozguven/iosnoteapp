import SwiftData
import Foundation

// Define the Schema Version 1
enum SchemaV1: VersionedSchema {
    static var versionIdentifier = Schema.Version(1, 0, 0)
    static var models: [any PersistentModel.Type] {
        [Note.self, ChatMessage.self]
    }
    
    @Model
    final class Note {
        var id: UUID
        var title: String
        var content: String
        var createdAt: Date
        var updatedAt: Date
        var tags: [String]
        
        // Embedding for RAG (Cosine Similarity)
        // Store as [Float]
        var embedding: [Float]?
        
        init(
            id: UUID = UUID(),
            title: String,
            content: String,
            createdAt: Date = Date(),
            updatedAt: Date = Date(),
            tags: [String] = [],
            embedding: [Float]? = nil
        ) {
            self.id = id
            self.title = title
            self.content = content
            self.createdAt = createdAt
            self.updatedAt = updatedAt
            self.tags = tags
            self.embedding = embedding
        }
    }
    
    @Model
    final class ChatMessage {
        var id: UUID
        var role: String // "user", "assistant", "system"
        var content: String
        var thoughtProcess: String? // For models that output <think>...</think>
        var sourceNoteIds: [UUID]
        var createdAt: Date
        
        init(
            id: UUID = UUID(),
            role: String,
            content: String,
            thoughtProcess: String? = nil,
            sourceNoteIds: [UUID] = [],
            createdAt: Date = Date()
        ) {
            self.id = id
            self.role = role
            self.content = content
            self.thoughtProcess = thoughtProcess
            self.sourceNoteIds = sourceNoteIds
            self.createdAt = createdAt
        }
    }
}

// Type aliases for easier usage
typealias Note = SchemaV1.Note
typealias ChatMessage = SchemaV1.ChatMessage

extension Note: Hashable {
    static func == (lhs: Note, rhs: Note) -> Bool {
        lhs.id == rhs.id
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
