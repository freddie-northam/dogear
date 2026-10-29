import DogearKit
import SwiftUI

struct Thumbnail<Content: View, Placeholder: View>: View {
    @EnvironmentObject private var model: AppModel
    let bookmark: Bookmark
    @ViewBuilder let content: (Image) -> Content
    @ViewBuilder let placeholder: () -> Placeholder
    @State private var loaded: (id: UUID, image: CGImage)?

    var body: some View {
        let id = bookmark.id
        if bookmark.hasThumbnail, let image = loaded?.id == id ? loaded?.image : model.thumbnails.cachedImage(for: id) {
            content(Image(decorative: image, scale: 1))
        } else {
            placeholder().task(id: id) {
                guard bookmark.hasThumbnail, let image = await model.thumbnails.loadImage(for: id) else { return }
                loaded = (id, image)
            }
        }
    }
}
