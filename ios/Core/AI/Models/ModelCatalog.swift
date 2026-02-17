import Foundation

struct ModelCatalogItem: Codable, Identifiable, Hashable {
    var id: String
    var kind: ModelKind
    var name: String
    var subtitle: String?
    var filename: String
    var auxiliaryFilename: String?
    var auxiliaryURL: String?
    var auxiliarySha256: String?
    var modality: String?
    var url: String
    var sizeBytes: Int64?
    var sha256: String?

    var downloadURL: URL? { URL(string: url) }
}

struct ModelCatalog: Codable {
    var version: Int
    var items: [ModelCatalogItem]
}
