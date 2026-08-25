import AppKit
import DogearKit
import MapKit

/// Draws a small map of a place, so a place card looks like somewhere rather
/// than like a missing image. MapKit renders this on the Mac, so nothing
/// leaves the machine beyond the map tiles themselves.
enum PlaceSnapshot {
    /// Matches the thumbnail cache: it downsamples to 600 points anyway.
    static let size = CGSize(width: 600, height: 300)
    /// About four streets across, close enough to recognize the corner.
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
