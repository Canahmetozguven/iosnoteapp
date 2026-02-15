import SwiftUI

enum AppTheme {
    static let primary = Color(hex: "#6650A5")
    static let primaryDark = Color(hex: "#513F84")
    static let secondary = Color(hex: "#625B71")
    static let backgroundLight = Color(hex: "#F7F6F7")
    static let surfaceLight = Color(hex: "#FFFFFF")
    static let onSurfaceLight = Color(hex: "#1C1B1F")
    static let secondaryText = Color(hex: "#A8A5B1")
    static let greenSuccess = Color(hex: "#22C55E")
    static let redError = Color(hex: "#DC2626")
    static let bubbleAi = Color(hex: "#EADCF5")
}

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r = Double((int >> 16) & 0xFF) / 255.0
        let g = Double((int >> 8) & 0xFF) / 255.0
        let b = Double(int & 0xFF) / 255.0
        self.init(red: r, green: g, blue: b)
    }
}

