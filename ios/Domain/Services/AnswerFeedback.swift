import Foundation

enum AssistantAnswerFeedback: String, CaseIterable, Codable {
    case notRelevant
    case partlyWrong
    case missingSource

    var label: String {
        switch self {
        case .notRelevant: return "Not relevant"
        case .partlyWrong: return "Partly wrong"
        case .missingSource: return "Missing source"
        }
    }
}
