import SwiftUI

enum AppTheme {
    static let primary = Color(hex: "#0F766E")
    static let primaryDark = Color(hex: "#0B5D57")
    static let secondary = Color(hex: "#1D4ED8")
    static let backgroundLight = Color(hex: "#EFF7F6")
    static let surfaceLight = Color(hex: "#F8FAFC")
    static let onSurfaceLight = Color(hex: "#0F172A")
    static let secondaryText = Color(hex: "#64748B")
    static let greenSuccess = Color(hex: "#22C55E")
    static let redError = Color(hex: "#DC2626")
    static let bubbleAi = Color(hex: "#DDF6F2")
    static let card = Color(hex: "#121720")
    static let cardBorder = Color(hex: "#2A3342")
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
