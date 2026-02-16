import Foundation

typealias Note = SchemaV2.Note
typealias ChatMessage = SchemaV2.ChatMessage
typealias ChatSession = SchemaV2.ChatSession

extension Note: Hashable {
    static func == (lhs: Note, rhs: Note) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
