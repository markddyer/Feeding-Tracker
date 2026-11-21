import FeedingCore
import SwiftUI

/// The watch's colours (`DESIGN.md`, "Apple Watch"). A black background by day as well as at
/// night (the user's choice, 16 Nov 2026: Apple's advice for watches, so the screen's edge
/// disappears into the watch and nothing is bright when a wrist is lifted). By day the coral and
/// the feed colours are the phone's day colours; at night they are the phone's night colours, and
/// the letters are thinner.
struct WatchPalette {
    let background: Color
    let surface: Color
    let text: Color
    let textMuted: Color
    let primary: Color
    let onPrimary: Color
    let track: Color
    let window: Color
    let breast: Color
    let onBreast: Color
    let bottle: Color
    /// Sleep, wee and poo (`06-more-than-feeds.md`, 17 Nov 2026): the phone's day colours by day
    /// (poo a little lighter, to read on black), and the phone's night colours at night.
    let sleep: Color
    let wee: Color
    let poo: Color
    /// The window bar's parts, as on the phone (the users' choice B, 21 Nov 2026): misty blue for
    /// the wait, coral (`window`, then `primary`) for the feeding window, terracotta for the backup
    /// alarm's stretch. `...Tint` is a part still to come, darker than on the phone so it shows on
    /// black; the plain colour is a part the time has passed.
    let wait: Color
    let waitTint: Color
    let backup: Color
    let backupTint: Color
    let backupStripe: Color
    /// The bell on a full backup part.
    let onBackup: Color

    static let day = WatchPalette(
        background: Color(hex: 0x000000), surface: Color(hex: 0x2A1F18), text: Color(hex: 0xFFF4E2),
        textMuted: Color(hex: 0xBFA995), primary: Color(hex: 0xFF8E6E), onPrimary: Color(hex: 0x3A1A0E),
        track: Color(hex: 0x3A2C22), window: Color(hex: 0x7A4A35), breast: Color(hex: 0xF07C8F),
        onBreast: Color(hex: 0x3A1A0E), bottle: Color(hex: 0x5FA8E8), sleep: Color(hex: 0x8B8FE0),
        wee: Color(hex: 0xF0C23B), poo: Color(hex: 0xC08A5A),
        wait: Color(hex: 0x9DB4CC), waitTint: Color(hex: 0x27313B), backup: Color(hex: 0xCF6248),
        backupTint: Color(hex: 0x36211B), backupStripe: Color(hex: 0x6E3A2E), onBackup: Color(hex: 0x3A1A0E))

    static let night = WatchPalette(
        background: Color(hex: 0x000000), surface: Color(hex: 0x1C1612), text: Color(hex: 0xE8D6C2),
        textMuted: Color(hex: 0x978472), primary: Color(hex: 0xB9714F), onPrimary: Color(hex: 0x120A06),
        track: Color(hex: 0x231B15), window: Color(hex: 0x4A3022), breast: Color(hex: 0xA85A68),
        onBreast: Color(hex: 0xE8D6C2), bottle: Color(hex: 0x4A7299), sleep: Color(hex: 0x6A6DB0),
        wee: Color(hex: 0x9C832F), poo: Color(hex: 0x9A6E48),
        wait: Color(hex: 0x5B6675), waitTint: Color(hex: 0x1B2128), backup: Color(hex: 0x93483A),
        backupTint: Color(hex: 0x2E1F1A), backupStripe: Color(hex: 0x5A2E26), onBackup: Color(hex: 0xE8D6C2))

    static func of(_ look: Look) -> WatchPalette { look == .night ? .night : .day }

    /// A parent's colour by its saved name, for the dot beside the other parent's feed.
    static func parent(_ name: String, look: Look) -> Color {
        let night = look == .night
        switch name {
        case "sunflower", "amber": return Color(hex: night ? 0x9C7A30 : 0xF2B33D)
        case "lavender": return Color(hex: night ? 0x68568A : 0xA78BDF)
        case "plum": return Color(hex: night ? 0x6F375F : 0x9E4F88)
        case "caramel": return Color(hex: night ? 0x79583A : 0xC99260)
        case "stone": return Color(hex: night ? 0x615D58 : 0x9A948C)
        default: return Color(hex: night ? 0x2A695E : 0x3FA796)
        }
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}
