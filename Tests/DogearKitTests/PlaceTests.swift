import Foundation
import Testing
@testable import DogearKit

@Test func parsesCityAndNameSeparatedByATilde() {
    let queries = PlaceParser.parse("London, UK ~ Bao Borough")
    #expect(queries.count == 1)
    #expect(queries[0].name == "Bao Borough")
    #expect(queries[0].near == "London, UK")
    #expect(queries[0].searchText == "Bao Borough, London, UK")
}

@Test func parsesALineWithNoTildeAsANameOnItsOwn() {
    let queries = PlaceParser.parse("Bao Borough")
    #expect(queries == [PlaceQuery(name: "Bao Borough", near: nil)])
    #expect(queries[0].searchText == "Bao Borough")
}

@Test func parseDropsBlankLinesAndListMarkers() {
    let queries = PlaceParser.parse("""
        - Lisbon, Portugal ~ Time Out Market

        * Tokyo ~ Kagari
        \u{2022} Paris ~ Septime
        """)
    #expect(queries.map(\.name) == ["Time Out Market", "Kagari", "Septime"])
    #expect(queries.map(\.near) == ["Lisbon, Portugal", "Tokyo", "Paris"])
}

@Test func parseSplitsOnTheFirstTildeOnly() {
    let queries = PlaceParser.parse("Berlin ~ Bar ~ Grill")
    #expect(queries == [PlaceQuery(name: "Bar ~ Grill", near: "Berlin")])
}

@Test func parseDropsALineWithNoNameAfterTheTilde() {
    #expect(PlaceParser.parse("London ~   ").isEmpty)
}

@Test func mapsURLCarriesTheCoordinatesAndStaysHTTPS() throws {
    let place = Place(name: "Bao Borough", address: "13 Stoney St, London",
                      latitude: 51.5054, longitude: -0.0912)
    let url = try #require(place.mapsURL)
    #expect(URLCleaner.isCapturable(url))
    #expect(url.host == "maps.apple.com")
    let query = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
    #expect(query.contains(URLQueryItem(name: "ll", value: "51.5054,-0.0912")))
    #expect(query.contains(URLQueryItem(name: "q", value: "Bao Borough")))
}

@Test func mapsURLEscapesANameWithSpacesAndSymbols() throws {
    let place = Place(name: "Fish & Chips #1", address: nil, latitude: 1, longitude: 2)
    let url = try #require(place.mapsURL)
    // A raw "&" or "#" would end the query or start a fragment.
    #expect(!url.absoluteString.contains("Chips #1"))
    let query = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
    #expect(query.contains(URLQueryItem(name: "q", value: "Fish & Chips #1")))
}

/// Stands in for the map, so the import path has a test that never goes out
/// to the network.
struct StubPlaceResolver: PlaceResolver {
    let places: [String: Place]
    func resolve(_ query: PlaceQuery) async -> Place? { places[query.name] }
}

@Test func aResolverAnswersPerQueryAndMayFindNothing() async {
    let found = Place(name: "Kagari", address: "Tokyo", latitude: 35.6, longitude: 139.7)
    let resolver = StubPlaceResolver(places: ["Kagari": found])
    #expect(await resolver.resolve(PlaceQuery(name: "Kagari", near: "Tokyo")) == found)
    #expect(await resolver.resolve(PlaceQuery(name: "Nowhere", near: nil)) == nil)
}
