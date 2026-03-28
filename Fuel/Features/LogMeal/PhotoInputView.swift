import SwiftUI
import PhotosUI

struct PhotoInputView: View {
    @Binding var image: UIImage?

    @State private var photoItem: PhotosPickerItem?
    @State private var showCamera = false

    var body: some View {
        VStack(spacing: 16) {
            if let img = image {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity)
                    .frame(height: 220)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .clipped()

                Button("Retake / Choose Different") { image = nil }
                    .font(.caption)
                    .foregroundStyle(FuelTheme.textSecondary)
            } else {
                RoundedRectangle(cornerRadius: 12)
                    .fill(FuelTheme.backgroundSecondary)
                    .frame(height: 180)
                    .overlay {
                        VStack(spacing: 10) {
                            Image(systemName: "camera.viewfinder")
                                .font(.system(size: 40))
                                .foregroundStyle(FuelTheme.textSecondary)
                            Text("Photograph your meal")
                                .font(.subheadline)
                                .foregroundStyle(FuelTheme.textSecondary)
                        }
                    }

                HStack(spacing: 12) {
                    Button {
                        showCamera = true
                    } label: {
                        Label("Camera", systemImage: "camera.fill")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(FuelTheme.backgroundSecondary)
                            .foregroundStyle(FuelTheme.textPrimary)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)

                    PhotosPicker(selection: $photoItem, matching: .images) {
                        Label("Library", systemImage: "photo.on.rectangle")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(FuelTheme.backgroundSecondary)
                            .foregroundStyle(FuelTheme.textPrimary)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .onChange(of: photoItem) { _, item in
            Task {
                if let data = try? await item?.loadTransferable(type: Data.self),
                   let uiImage = UIImage(data: data) {
                    image = uiImage
                }
            }
        }
        .sheet(isPresented: $showCamera) {
            CameraPickerView(image: $image)
        }
    }
}

// MARK: - Camera UIViewControllerRepresentable

struct CameraPickerView: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPickerView
        init(_ parent: CameraPickerView) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            parent.image = info[.originalImage] as? UIImage
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}
