import DogearKit
import Foundation
import MapKit

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
