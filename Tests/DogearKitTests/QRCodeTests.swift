import Foundation
import Testing
@testable import DogearKit

@Test func qrCodeRendersASquareImageAtTenTimesScale() throws {
    let image = try #require(QRCode.image(for: "https://a.com/pasta"))
    #expect(image.width == image.height)
    #expect(image.width % 10 == 0)
    #expect(image.width > 0)
}
