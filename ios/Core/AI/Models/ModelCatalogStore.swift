import Foundation

@Observable
final class ModelCatalogStore {
    private(set) var builtin: [ModelCatalogItem] = []
    private let customStore: CustomModelStore

    init(customStore: CustomModelStore = CustomModelStore()) {
        self.customStore = customStore
        loadBuiltin()
    }

    var items: [ModelCatalogItem] {
        // Custom items override built-in by id.
        var byId: [String: ModelCatalogItem] = [:]
        for item in builtin { byId[item.id] = item }
        for item in customStore.items { byId[item.id] = item }
        return byId.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func items(kind: ModelKind) -> [ModelCatalogItem] {
        items.filter { $0.kind == kind }
    }

    func addCustom(_ item: ModelCatalogItem) {
        customStore.add(item)
    }

    func removeCustom(id: String) {
        customStore.remove(id: id)
    }

    func isCustom(id: String) -> Bool {
        customStore.items.contains(where: { $0.id == id })
    }

    private func loadBuiltin() {
        guard let url = Bundle.main.url(forResource: "ModelCatalog", withExtension: "json") else {
            builtin = []
            return
        }
        do {
            let data = try Data(contentsOf: url)
            let decoded = try JSONDecoder().decode(ModelCatalog.self, from: data)
            builtin = decoded.items
        } catch {
            builtin = []
        }
    }
}

