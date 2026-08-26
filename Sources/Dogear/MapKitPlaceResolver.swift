import DogearKit
import Foundation
import MapKit

/// Resolves a place with Apple's map search. MapKit ships with the system, so
/// this keeps the zero-dependency rule.
///
/// This lives in the app, not the kit: MKLocalSearch goes out to Apple's map
/// service and takes no stand-in, so the file could carry no test. The
/// `PlaceResolver` protocol it answers stays in the kit, where a stub covers
/// the import path.
struct MapKitPlaceResolver: PlaceResolver {
    func resolve(_ query: PlaceQuery) async -> Place? {
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
