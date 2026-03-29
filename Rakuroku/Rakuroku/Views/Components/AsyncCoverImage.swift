import SwiftUI

struct AsyncCoverImage: View {
    let url: String?
    var width: CGFloat = 80
    var height: CGFloat = 120
    var cornerRadius: CGFloat = 0

    var body: some View {
        if let url, let imageURL = URL(string: url) {
            AsyncImage(url: imageURL) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().aspectRatio(contentMode: .fill)
                default:
                    Rectangle().fill(Theme.surface)
                }
            }
            .frame(width: width, height: height)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        } else {
            Rectangle()
                .fill(Theme.surface)
                .frame(width: width, height: height)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        }
    }
}
