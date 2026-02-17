import Foundation

enum ModelKind: String, Codable, CaseIterable {
    case chat
    case embedding
    case ocr
    case vl
}
