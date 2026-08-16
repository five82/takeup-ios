import SwiftUI

// SF Pro worked the way the Android app works Google Sans Flex: the system
// switches optical sizes automatically; the scale and the uppercase tracked
// label voice are what carry the identity.

extension Font {
    static let displayLarge = Font.system(size: 40, weight: .semibold)
    static let displayMedium = Font.system(size: 30, weight: .semibold)
    static let displaySmall = Font.system(size: 24, weight: .semibold)
    static let headlineMedium = Font.system(size: 21, weight: .semibold)
    static let titleLarge = Font.system(size: 20, weight: .semibold)
    static let titleMedium = Font.system(size: 16, weight: .semibold)
    static let titleSmall = Font.system(size: 14, weight: .medium)
    static let bodyLarge = Font.system(size: 16)
    static let bodyMedium = Font.system(size: 14)
    static let bodySmall = Font.system(size: 12)
    static let labelLarge = Font.system(size: 14, weight: .semibold)
    static let labelMedium = Font.system(size: 12, weight: .semibold)
    static let labelSmall = Font.system(size: 11, weight: .medium)
}

/// The signature row-label voice: uppercase, semibold, +0.14em tracking.
struct RowLabel: View {
    let text: String
    var color: Color = .muted
    var font: Font = .labelMedium
    var tracking: CGFloat = 12 * 0.14

    var body: some View {
        Text(text.uppercased())
            .font(font)
            .tracking(tracking)
            .foregroundStyle(color)
    }
}

/// Home row headers: bigger than a plain row label but the same voice —
/// titleMedium borrowing labelMedium's tracking, uppercased.
struct HomeRowLabel: View {
    let text: String
    var color: Color = .muted

    var body: some View {
        RowLabel(text: text, color: color, font: .titleMedium, tracking: 16 * 0.14)
    }
}
