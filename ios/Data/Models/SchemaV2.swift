import SwiftData
import Foundation

enum SchemaV2: VersionedSchema {
    static var versionIdentifier = Schema.Version(2, 0, 0)

    static var models: [any PersistentModel.Type] {
        [Note.self, ChatSession.self, ChatMessage.self]
    }

    @Model
    final class Note {
        var id: UUID
        var title: String
        var content: String
        var createdAt: Date
        var updatedAt: Date
        var tags: [String]

        // Embedding fields for RAG.
        var embedding: [Float]?
        var embeddingModelId: String?
        var embeddingUpdatedAt: Date?
        var embeddingContentHash: String?

        init(
            id: UUID = UUID(),
            title: String,
            content: String,
            createdAt: Date = Date(),
            updatedAt: Date = Date(),
            tags: [String] = [],
            embedding: [Float]? = nil,
            embeddingModelId: String? = nil,
            embeddingUpdatedAt: Date? = nil,
            embeddingContentHash: String? = nil
        ) {
            self.id = id
            self.title = title
            self.content = content
            self.createdAt = createdAt
            self.updatedAt = updatedAt
            self.tags = tags
            self.embedding = embedding
            self.embeddingModelId = embeddingModelId
            self.embeddingUpdatedAt = embeddingUpdatedAt
            self.embeddingContentHash = embeddingContentHash
        }
    }

    @Model
    final class ChatSession {
        var id: UUID
        var title: String
        var createdAt: Date
        var updatedAt: Date
        @Relationship(deleteRule: .cascade, inverse: \ChatMessage.session)
        var messages: [ChatMessage]

        init(
            id: UUID = UUID(),
            title: String,
            createdAt: Date = Date(),
            updatedAt: Date = Date()
        ) {
            self.id = id
            self.title = title
            self.createdAt = createdAt
            self.updatedAt = updatedAt
            self.messages = []
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
        var session: ChatSession?

        init(
            id: UUID = UUID(),
            role: String,
            content: String,
            thoughtProcess: String? = nil,
            sourceNoteIds: [UUID] = [],
            createdAt: Date = Date(),
            session: ChatSession? = nil
        ) {
            self.id = id
            self.role = role
            self.content = content
            self.thoughtProcess = thoughtProcess
            self.sourceNoteIds = sourceNoteIds
            self.createdAt = createdAt
            self.session = session
        }
    }
}
