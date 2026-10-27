import AppKit
import DogearKit
import MapKit

enum PlaceSnapshot {
    static let size = CGSize(width: 600, height: 300)
    static let span = MKCoordinateSpan(latitudeDelta: 0.004, longitudeDelta: 0.004)

    static func pngData(for place: Place) async -> Data? {
        let options = MKMapSnapshotter.Options()
        options.region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: place.latitude, longitude: place.longitude),
            span: span)
        options.size = size
        options.showsBuildings = true
        guard let snapshot = try? await MKMapSnapshotter(options: options).start() else { return nil }
        guard let tiff = snapshot.image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff) else { return nil }
        return bitmap.representation(using: .png, properties: [:])
    }
}
