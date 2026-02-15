import Foundation

@Observable
final class CustomModelStore {
    private enum Key {
        static let customItemsV1 = "custom_model_catalog_items_v1"
    }

    private let defaults: UserDefaults
    var items: [ModelCatalogItem] = []

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
    }

    func add(_ item: ModelCatalogItem) {
        if let idx = items.firstIndex(where: { $0.id == item.id }) {
            items[idx] = item
        } else {
            items.append(item)
        }
        save()
    }

    func remove(id: String) {
        items.removeAll { $0.id == id }
        save()
    }

    private func load() {
        guard let data = defaults.data(forKey: Key.customItemsV1) else {
            items = []
            return
        }
        do {
            items = try JSONDecoder().decode([ModelCatalogItem].self, from: data)
        } catch {
            items = []
        }
    }

    private func save() {
        do {
            let data = try JSONEncoder().encode(items)
            defaults.set(data, forKey: Key.customItemsV1)
        } catch {
            // Best-effort persistence.
        }
    }
}

