import ImageIO
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

enum AvatarPhoto {
    static let maximumStoredBytes = 48 * 1024
    static let maximumInputBytes = 25 * 1024 * 1024

    /// Downsample before decoding, honor orientation, and discard source metadata.
    /// The small JPEG lives with its server identity, so removal needs no file cleanup.
    static func thumbnail(from data: Data) throws -> Data {
        guard data.count <= maximumInputBytes,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 256,
                kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary) else { throw ImportError.invalidImage }
        for quality in [0.8, 0.6, 0.4] {
            let output = NSMutableData()
            guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else {
                throw ImportError.invalidImage
            }
            CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
            if CGImageDestinationFinalize(destination), output.length <= maximumStoredBytes {
                return output as Data
            }
        }
        throw ImportError.invalidImage
    }

    enum ImportError: Error { case invalidImage }
}

struct SessionAvatar: View {
    let imageData: Data?
    let initials: String
    let color: Color
    let foreground: Color
    var size: CGFloat = 32
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            color
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Text(initials).font(.caption.weight(.semibold)).foregroundStyle(foreground)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().stroke(.white.opacity(0.18), lineWidth: 1))
        .onChange(of: imageData, initial: true) { image = imageData.flatMap(UIImage.init(data:)) }
        .accessibilityHidden(true)
    }
}

struct AvatarPhotoPicker: View {
    @Binding var imageData: Data?
    @State private var selection: PhotosPickerItem?
    @State private var errorMessage: String?
    @State private var isImporting = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                PhotosPicker(selection: $selection, matching: .images) {
                    Label("Choose Photo", systemImage: "photo")
                }
                .disabled(isImporting)
                Spacer()
                if isImporting { ProgressView() }
                if imageData != nil || isImporting {
                    Button("Remove Photo", role: .destructive) {
                        selection = nil
                        isImporting = false
                        imageData = nil
                        errorMessage = nil
                    }
                }
            }
            .frame(minHeight: 44)
            if let errorMessage {
                Text(errorMessage).font(.caption).foregroundStyle(.red)
            }
        }
        .task(id: selection) {
            guard let selection else { return }
            isImporting = true
            errorMessage = nil
            defer { if !Task.isCancelled { isImporting = false } }
            do {
                guard let data = try await selection.loadTransferable(type: Data.self) else {
                    throw AvatarPhoto.ImportError.invalidImage
                }
                try Task.checkCancellation()
                let thumbnail = try await Task.detached(priority: .userInitiated) {
                    try AvatarPhoto.thumbnail(from: data)
                }.value
                try Task.checkCancellation()
                imageData = thumbnail
                isImporting = false
                self.selection = nil
            } catch {
                guard !Task.isCancelled else { return }
                errorMessage = String(localized: "Could not import this photo. Choose an image smaller than 25 MB.")
                isImporting = false
                self.selection = nil
            }
        }
    }
}
