import Foundation
import Testing
@testable import DogearKit

@Test func displayStringUsesApplesModifierOrder() {
    let combo = HotKeyCombo(
        keyCode: 2,
        modifiers: HotKeyCombo.command | HotKeyCombo.shift | HotKeyCombo.option | HotKeyCombo.control)
    #expect(combo.displayString == "\u{2303}\u{2325}\u{21E7}\u{2318}D")
}

@Test func displayStringNamesTheKeysWithNoLetter() {
    #expect(HotKeyCombo(keyCode: 49, modifiers: HotKeyCombo.command).displayString == "\u{2318}Space")
    #expect(HotKeyCombo(keyCode: 122, modifiers: HotKeyCombo.option).displayString == "\u{2325}F1")
}

@Test func displayStringFallsBackToTheNumberForAnUnknownKey() {
    #expect(HotKeyCombo(keyCode: 9999, modifiers: HotKeyCombo.command).displayString == "\u{2318}Key 9999")
}

@Test func aComboWithNoModifierIsRefused() {
    #expect(!HotKeyCombo(keyCode: 2, modifiers: 0).isValid)
    #expect(HotKeyCombo(keyCode: 2, modifiers: HotKeyCombo.control).isValid)
}

@Test func storedValueRoundTrips() throws {
    let combo = HotKeyCombo(keyCode: 2, modifiers: HotKeyCombo.command | HotKeyCombo.shift)
    let restored = try #require(HotKeyCombo(defaultsValue: combo.defaultsValue))
    #expect(restored == combo)
}

@Test func anUnreadableStoredValueYieldsNoShortcut() {
    #expect(HotKeyCombo(defaultsValue: "") == nil)
    #expect(HotKeyCombo(defaultsValue: "nonsense") == nil)
    #expect(HotKeyCombo(defaultsValue: "2:") == nil)
    #expect(HotKeyCombo(defaultsValue: "2:256:512") == nil)
}
