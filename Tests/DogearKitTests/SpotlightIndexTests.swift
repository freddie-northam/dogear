import CoreSpotlight
import Foundation
import Testing
@testable import DogearKit

private func bookmark(title: String, note: String? = nil, folder: String = "Recipes",
                      author: String? = nil, place: Place? = nil) -> Bookmark {
    Bookmark(id: UUID(), url: "https://a.com/p", title: title, author: author, note: note,
             folder: folder, source: .web, createdAt: Date(), doneAt: nil,
             hasThumbnail: false, manuallyFiled: false, place: place)
}

@Test func itemCarriesTheBookmarkIDSoTheAppCanFindItAgain() {
    let saved = bookmark(title: "Pasta")
    let item = SpotlightIndex.item(for: saved)
    #expect(item.uniqueIdentifier == saved.id.uuidString)
    #expect(item.domainIdentifier == SpotlightIndex.domain)
    // Spotlight drops an item after a month unless told to keep it.
    #expect((item.expirationDate ?? .distantPast) > Date(timeIntervalSinceNow: 3600 * 24 * 365))
}

@Test func descriptionPrefersTheUsersOwnNote() {
    let attributes = SpotlightIndex.attributes(for: bookmark(title: "Pasta", note: "Halve the salt."))
    #expect(attributes.title == "Pasta")
    #expect(attributes.contentDescription == "Halve the salt.")
}

@Test func descriptionFallsBackToThePlaceAddressThenTheLink() {
    let place = Place(name: "Kagari", address: "Tokyo, Japan", latitude: 35.6, longitude: 139.7)
    #expect(SpotlightIndex.attributes(for: bookmark(title: "Kagari", place: place))
        .contentDescription == "Tokyo, Japan")
    #expect(SpotlightIndex.attributes(for: bookmark(title: "Pasta"))
        .contentDescription == "https://a.com/p")
}

@Test func keywordsCoverTheFolderAndTheAuthorWhenThereIsOne() {
    #expect(SpotlightIndex.attributes(for: bookmark(title: "Pasta", author: "Rachel"))
        .keywords == ["Recipes", "Rachel"])
    #expect(SpotlightIndex.attributes(for: bookmark(title: "Pasta")).keywords == ["Recipes"])
}
