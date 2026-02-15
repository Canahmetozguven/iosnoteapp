import Foundation

@Observable
final class ModelDownloadsViewModel {
    var states: [String: DownloadState] = [:] // modelId -> state

    func state(for modelId: String) -> DownloadState {
        states[modelId] ?? .notStarted
    }

    func setState(_ state: DownloadState, for modelId: String) {
        states[modelId] = state
    }

    func clearState(for modelId: String) {
        states.removeValue(forKey: modelId)
    }
}
