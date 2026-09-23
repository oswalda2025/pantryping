//
//  ProductPhoto.swift
//  Pantry Ping
//

import PhotosUI
import SwiftUI
import UIKit

// Shrinks photos before saving so the database stays small (a phone photo can be 5 MB+).
enum ProductPhoto {
    static func jpegData(from image: UIImage, maxDimension: CGFloat = 1024) -> Data? {
        let longest = max(image.size.width, image.size.height)
        let scale = longest > maxDimension ? maxDimension / longest : 1
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        return resized.jpegData(compressionQuality: 0.7)
    }
}

// A square product photo, or a placeholder icon when there isn't one.
struct ProductThumbnail: View {
    let data: Data?
    var size: CGFloat = 44
    var placeholderSymbol = "takeoutbag.and.cup.and.straw"

    var body: some View {
        Group {
            if let data, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: placeholderSymbol)
                    .font(.system(size: size * 0.4))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(.secondarySystemFill))
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.2))
        .accessibilityHidden(true)
    }
}

// Lets the user pick a product photo from their library or take one with the camera.
// PhotosPicker runs in a separate system process, so no photo-library permission is needed.
struct ProductPhotoPicker: View {
    @Binding var photoData: Data?
    @State private var selection: PhotosPickerItem?
    @State private var isShowingCamera = false

    var body: some View {
        HStack(spacing: 14) {
            ProductThumbnail(data: photoData, size: 64, placeholderSymbol: "camera")
            VStack(alignment: .leading, spacing: 8) {
                PhotosPicker(photoData == nil ? "Choose Photo" : "Change Photo", selection: $selection, matching: .images)
                if CameraPicker.isAvailable {
                    Button("Take Photo") { isShowingCamera = true }
                }
                if photoData != nil {
                    Button("Remove Photo", role: .destructive) { photoData = nil }
                }
            }
            // Borderless buttons stay separately tappable inside a Form row.
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 4)
        // `.task(id:)` re-runs whenever a new photo is picked. Loading is async because the
        // image may need to be fetched (e.g. from iCloud Photos) before we can use it.
        .task(id: selection) {
            guard let selection,
                  let data = try? await selection.loadTransferable(type: Data.self),
                  let image = UIImage(data: data) else { return }
            photoData = ProductPhoto.jpegData(from: image)
        }
        .fullScreenCover(isPresented: $isShowingCamera) {
            CameraPicker { image in
                photoData = ProductPhoto.jpegData(from: image)
            }
            .ignoresSafeArea()
        }
    }
}

// SwiftUI has no built-in camera view, so this wraps UIKit's camera screen.
// UIViewControllerRepresentable is the bridge that lets a UIKit screen appear in SwiftUI.
struct CameraPicker: UIViewControllerRepresentable {
    static var isAvailable: Bool {
        UIImagePickerController.isSourceTypeAvailable(.camera)
    }

    let onCapture: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    // UIKit reports results through a delegate object; the Coordinator plays that role.
    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker

        init(parent: CameraPicker) {
            self.parent = parent
        }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage {
                parent.onCapture(image)
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}
