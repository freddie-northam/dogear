import CoreImage.CIFilterBuiltins
import Foundation

public enum QRCode {
    /// A QR code for the string, scaled up 10x with nearest-neighbor
    /// sampling so the modules stay crisp when the UI enlarges it.
    public static func image(for string: String) -> CGImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        guard let output = filter.outputImage else { return nil }
        let scaled = output.samplingNearest()
            .transformed(by: CGAffineTransform(scaleX: 10, y: 10))
        return CIContext().createCGImage(scaled, from: scaled.extent)
    }
}
