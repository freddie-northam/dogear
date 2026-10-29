import SwiftUI

/// Shows a thumbnail, or the placeholder until it loads off the main actor. A nil id shows only the placeholder.
struct Thumbnail<Content: View, Placeholder: View>: View {
    @EnvironmentObject private var model: AppModel
    let id: UUID?
    @ViewBuilder let content: (Image) -> Content
    @ViewBuilder let placeholder: () -> Placeholder
    // The id travels with the image, so a view that now shows another bookmark never shows the old picture.
    @State private var loaded: (id: UUID, image: CGImage)?

    var body: some View {
        if let id, let image = loaded?.id == id ? loaded?.image : model.thumbnails.cachedImage(for: id) {
            content(Image(decorative: image, scale: 1))
        } else {
            placeholder().task(id: id) {
                guard let id, let image = await model.thumbnails.loadImage(for: id) else { return }
                loaded = (id, image)
            }
        }
    }
}
