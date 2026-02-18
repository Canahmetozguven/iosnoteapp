import SwiftData
import Foundation

enum SchemaV4: VersionedSchema {
    static var versionIdentifier = Schema.Version(4, 0, 0)

    static var models: [any PersistentModel.Type] {
        [
            Note.self,
            ChatSession.self,
            ChatMessage.self,
            KnowledgeDocument.self,
            KnowledgeChunk.self
        ]
    }

    @Model
    final class Note {
        var id: UUID
        var title: String
        var content: String
        var createdAt: Date
        var updatedAt: Date
        var tags: [String]

        var embedding: [Float]?
        var embeddingModelId: String?
        var embeddingUpdatedAt: Date?
        var embeddingContentHash: String?
        var titleNormalized: String?
        var contentTokenCount: Int?

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
            embeddingContentHash: String? = nil,
            titleNormalized: String? = nil,
            contentTokenCount: Int? = nil
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
            self.titleNormalized = titleNormalized
            self.contentTokenCount = contentTokenCount
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
        var role: String
        var content: String
        var thoughtProcess: String?
        var sourceNoteIds: [UUID]
        var sourceKnowledgeChunkIds: [UUID]
        var createdAt: Date
        var session: ChatSession?

        init(
            id: UUID = UUID(),
            role: String,
            content: String,
            thoughtProcess: String? = nil,
            sourceNoteIds: [UUID] = [],
            sourceKnowledgeChunkIds: [UUID] = [],
            createdAt: Date = Date(),
            session: ChatSession? = nil
        ) {
            self.id = id
            self.role = role
            self.content = content
            self.thoughtProcess = thoughtProcess
            self.sourceNoteIds = sourceNoteIds
            self.sourceKnowledgeChunkIds = sourceKnowledgeChunkIds
            self.createdAt = createdAt
            self.session = session
        }
    }

    @Model
    final class KnowledgeDocument {
        var id: UUID
        var title: String
        var sourceType: String
        var mimeType: String
        var localRelativePath: String
        var driveFileId: String?
        var extractionStatus: String
        var extractionError: String?
        var extractionEngine: String?
        var contentHash: String?
        var createdAt: Date
        var updatedAt: Date
        @Relationship(deleteRule: .cascade, inverse: \KnowledgeChunk.document)
        var chunks: [KnowledgeChunk]

        init(
            id: UUID = UUID(),
            title: String,
            sourceType: String,
            mimeType: String,
            localRelativePath: String,
            driveFileId: String? = nil,
            extractionStatus: String = "pending",
            extractionError: String? = nil,
            extractionEngine: String? = nil,
            contentHash: String? = nil,
            createdAt: Date = Date(),
            updatedAt: Date = Date()
        ) {
            self.id = id
            self.title = title
            self.sourceType = sourceType
            self.mimeType = mimeType
            self.localRelativePath = localRelativePath
            self.driveFileId = driveFileId
            self.extractionStatus = extractionStatus
            self.extractionError = extractionError
            self.extractionEngine = extractionEngine
            self.contentHash = contentHash
            self.createdAt = createdAt
            self.updatedAt = updatedAt
            self.chunks = []
        }
    }

    @Model
    final class KnowledgeChunk {
        var id: UUID
        var chunkIndex: Int
        var text: String
        var embedding: [Float]?
        var embeddingModelId: String?
        var embeddingUpdatedAt: Date?
        var embeddingContentHash: String?
        var tokenCount: Int?
        var charCount: Int?
        var sectionHint: String?
        var documentTitleNormalized: String?
        var createdAt: Date
        var updatedAt: Date
        var document: KnowledgeDocument?

        init(
            id: UUID = UUID(),
            chunkIndex: Int,
            text: String,
            embedding: [Float]? = nil,
            embeddingModelId: String? = nil,
            embeddingUpdatedAt: Date? = nil,
            embeddingContentHash: String? = nil,
            tokenCount: Int? = nil,
            charCount: Int? = nil,
            sectionHint: String? = nil,
            documentTitleNormalized: String? = nil,
            createdAt: Date = Date(),
            updatedAt: Date = Date(),
            document: KnowledgeDocument? = nil
        ) {
            self.id = id
            self.chunkIndex = chunkIndex
            self.text = text
            self.embedding = embedding
            self.embeddingModelId = embeddingModelId
            self.embeddingUpdatedAt = embeddingUpdatedAt
            self.embeddingContentHash = embeddingContentHash
            self.tokenCount = tokenCount
            self.charCount = charCount
            self.sectionHint = sectionHint
            self.documentTitleNormalized = documentTitleNormalized
            self.createdAt = createdAt
            self.updatedAt = updatedAt
            self.document = document
        }
    }
}
