import Foundation

struct ExportPayloadV1: Codable {
    var version: Int
    var exportedAt: Date
    var notes: [ExportNoteV1]
    var chatSessions: [ExportChatSessionV1]?
    var chatMessages: [ExportChatMessageV1]
}

struct ExportNoteV1: Codable {
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
}

struct ExportChatSessionV1: Codable {
    var id: UUID
    var title: String
    var createdAt: Date
    var updatedAt: Date
}

struct ExportChatMessageV1: Codable {
    var id: UUID
    var role: String
    var content: String
    var thoughtProcess: String?
    var sourceNoteIds: [UUID]
    var createdAt: Date
    var sessionId: UUID?
}

struct ExportManifestV1: Codable {
    var version: Int
    var createdAt: Date
    var noteCount: Int
    var chatSessionCount: Int?
    var chatMessageCount: Int
    var appVersion: String?
}
