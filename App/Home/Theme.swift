import SwiftUI

/// The night look (plan v1, "Night UI"): true black, dim warm accents, nothing bright, and no
/// red or green verdicts anywhere.
enum Theme {
    static let background = Color.black
    /// Warm off-white for the main text.
    static let text = Color(red: 0.96, green: 0.90, blue: 0.82)
    static let secondaryText = Color(red: 0.68, green: 0.62, blue: 0.55)
    /// Dim amber for the ring and the main buttons.
    static let accent = Color(red: 0.86, green: 0.56, blue: 0.26)
    /// Button and card backgrounds: a warm near-black.
    static let surface = Color(red: 0.11, green: 0.09, blue: 0.08)
    static let raisedSurface = Color(red: 0.17, green: 0.14, blue: 0.12)
    /// For problems, such as sync being broken. A muted orange, never a verdict.
    static let warning = Color(red: 0.93, green: 0.48, blue: 0.20)
}
