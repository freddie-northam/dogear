import SwiftUI

/// Reminders-style folder accents, defined once for the sidebar, the cards,
/// and the popover pick row. System colors only, so both appearances adapt.
func folderColor(for name: String) -> Color {
    switch name {
    case "Recipes": .orange
    case "Restaurants": .pink
    case "Shows": .purple
    case "Music": .red
    case "Articles": .blue
    case "Unsorted": .gray
    default: .teal
    }
}

/// The SF Symbol for a folder, shared by the sidebar and the popover badge.
func folderSymbol(for name: String) -> String {
    switch name {
    case "Recipes": "fork.knife"
    case "Restaurants": "mappin.and.ellipse"
    case "Shows": "tv"
    case "Music": "music.note"
    case "Articles": "doc.text"
    case "Unsorted": "tray"
    default: "folder"
    }
}
