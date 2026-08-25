import Foundation
import MapKit

/// Resolves a place with Apple's map search. MapKit ships with the system, so
/// this keeps the zero-dependency rule.
public struct MapKitPlaceResolver: PlaceResolver {
    public init() {}

    public func resolve(_ query: PlaceQuery) async -> Place? {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query.searchText
        request.resultTypes = [.pointOfInterest, .address]
        guard let response = try? await MKLocalSearch(request: request).start(),
              let item = response.mapItems.first else { return nil }
        let placemark = item.placemark
        let coordinate = placemark.coordinate
        guard CLLocationCoordinate2DIsValid(coordinate) else { return nil }
        return Place(
            name: item.name ?? query.name,
            address: placemark.title,
            latitude: coordinate.latitude,
            longitude: coordinate.longitude
        )
    }
}
