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

@Test func fingerprintChangesWhenSearchableTextChanges() {
    let one = bookmark(title: "Pasta")
    var renamed = one
    renamed.title = "Pasta, revised"
    #expect(SpotlightIndex.fingerprint([one]) != SpotlightIndex.fingerprint([renamed]))

    var noted = one
    noted.note = "Halve the salt."
    #expect(SpotlightIndex.fingerprint([one]) != SpotlightIndex.fingerprint([noted]))

    var refiled = one
    refiled.folder = "Shows"
    #expect(SpotlightIndex.fingerprint([one]) != SpotlightIndex.fingerprint([refiled]))
}

@Test func fingerprintIgnoresChangesSpotlightCannotSee() {
    let one = bookmark(title: "Pasta")
    var shown = one
    shown.lastShownAt = Date()
    var done = one
    done.doneAt = Date()
    var starred = one
    starred.favoritedAt = Date()
    // None of these change what a search would return, so none may force a
    // rebuild of the whole system index.
    #expect(SpotlightIndex.fingerprint([one]) == SpotlightIndex.fingerprint([shown]))
    #expect(SpotlightIndex.fingerprint([one]) == SpotlightIndex.fingerprint([done]))
    #expect(SpotlightIndex.fingerprint([one]) == SpotlightIndex.fingerprint([starred]))
}

@Test func fingerprintNoticesAdditionsRemovalsAndOrder() {
    let a = bookmark(title: "A")
    let b = bookmark(title: "B")
    #expect(SpotlightIndex.fingerprint([a]) != SpotlightIndex.fingerprint([a, b]))
    #expect(SpotlightIndex.fingerprint([a, b]) != SpotlightIndex.fingerprint([b]))
    #expect(SpotlightIndex.fingerprint([a, b]) == SpotlightIndex.fingerprint([a, b]))
}

@Test func fingerprintOfAnEmptyLibraryIsStable() {
    #expect(SpotlightIndex.fingerprint([]) == SpotlightIndex.fingerprint([]))
    #expect(SpotlightIndex.fingerprint([]) != SpotlightIndex.fingerprint([bookmark(title: "A")]))
}

@Test func fingerprintIsStableAcrossProcesses() {
    // Pinned to a literal on purpose. Swift's Hasher is seeded randomly per
    // process, so a fingerprint built on it would differ on every launch and
    // the whole comparison would be dead weight. If this value ever changes,
    // every installed copy rebuilds its index once, which is survivable, but
    // it must be a deliberate choice rather than an accident.
    let fixed = Bookmark(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
        url: "https://a.com/p", title: "Pasta", author: nil, note: nil,
        folder: "Recipes", source: .web, createdAt: Date(timeIntervalSince1970: 0),
        doneAt: nil, hasThumbnail: false, manuallyFiled: false)
    #expect(SpotlightIndex.fingerprint([fixed]) == "ac9376c0e89f395687938bb1aa8e02cffdc4a0aaa8c0a24e8eb27cdf0e7a3690")
}

@Test func fingerprintOfFiveThousandBookmarksIsUnder20ms() {
    // Runs on every debounced sync, including the ones where nothing changed.
    // It hashes the whole library, so it is worth a ceiling even though the
    // app computes it off the main actor.
    let bookmarks = (0..<5000).map { index in
        Bookmark(id: UUID(), url: "https://example.com/item/\(index)", title: "Item \(index)",
                 author: "Author \(index)", note: "A note about item \(index)",
                 folder: "Recipes", source: .web, createdAt: Date(timeIntervalSince1970: 0),
                 doneAt: nil, hasThumbnail: false, manuallyFiled: false)
    }
    let start = ContinuousClock.now
    let fingerprint = SpotlightIndex.fingerprint(bookmarks)
    let elapsed = ContinuousClock.now - start
    #expect(!fingerprint.isEmpty)
    if ProcessInfo.processInfo.environment["PERF"] != nil {
        #expect(elapsed < .milliseconds(20))
    }
}
