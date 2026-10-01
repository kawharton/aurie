import SwiftUI
import AVFoundation
import UIKit

/// Full-screen portrait camera for the hatch flow (§8A): live AVFoundation
/// preview, one big capture button, and friendly permission/unavailable
/// states that always leave the user a way forward (Settings, the photo
/// library, or plain cancel). The captured photo is handed back in memory
/// only — nothing is written to disk or to the user's Photos library.
///
/// HatchView never presents this in the Simulator (no broken camera UI
/// there — the library picker and bundled samples stand in), but the view
/// still degrades gracefully to `.unavailable` if a device has no camera.
struct CameraCaptureView: View {
    /// A photo was taken; the caller runs it through the hatch pipeline.
    var onCapture: (UIImage) -> Void
    /// "Use photo library instead" from the denied/unavailable states.
    var onUseLibrary: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var controller = CameraController()
    @State private var status: CameraController.Status = .checking
    @State private var capturing = false
    @State private var captureFailed = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            switch status {
            case .checking:
                ProgressView().tint(.white)
            case .ready:
                CameraPreview(session: controller.session)
                    .ignoresSafeArea()
                captureControls
            case .denied:
                blockedView(
                    title: "Aurie needs the camera to see your object.",
                    message: "Allow camera access in Settings, or hatch from a photo instead.",
                    showSettings: true
                )
            case .unavailable:
                blockedView(
                    title: "This device's camera isn't available.",
                    message: "You can still hatch from a photo in your library.",
                    showSettings: false
                )
            }

            // Cancel is always available, whatever state the camera is in.
            VStack {
                HStack {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                            .background(.black.opacity(0.45), in: Circle())
                    }
                    .accessibilityLabel("Cancel")
                    Spacer()
                }
                Spacer()
            }
            .padding()
        }
        .preferredColorScheme(.dark)
        .statusBarHidden()
        .task {
            // Re-checked on every presentation, so permission revoked later
            // in Settings is picked up the next time the camera opens.
            status = await controller.prepare()
        }
        .onDisappear { controller.stop() }
    }

    // MARK: Live-preview controls

    private var captureControls: some View {
        VStack {
            Spacer()
            Text(captureFailed ? "That didn't work — try again."
                               : "Fill the frame with your object")
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.9))
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(.black.opacity(0.4), in: Capsule())
                .padding(.bottom, 14)
            Button {
                Task { await takePhoto() }
            } label: {
                ZStack {
                    Circle().strokeBorder(.white, lineWidth: 4).frame(width: 76, height: 76)
                    Circle().fill(.white).frame(width: 62, height: 62)
                    if capturing { ProgressView().tint(.black) }
                }
            }
            .disabled(capturing)
            .accessibilityLabel("Take photo")
            .padding(.bottom, 30)
        }
    }

    private func takePhoto() async {
        capturing = true
        captureFailed = false
        if let image = await controller.capture() {
            onCapture(image)
            dismiss()
        } else {
            captureFailed = true
        }
        capturing = false
    }

    // MARK: Denied / unavailable

    private func blockedView(title: String, message: String, showSettings: Bool) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "camera.on.rectangle")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.headline)
                .multilineTextAlignment(.center)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if showSettings, let url = URL(string: UIApplication.openSettingsURLString) {
                Link("Open Settings", destination: url)
                    .buttonStyle(.borderedProminent)
                    .padding(.top, 6)
            }
            Button("Use photo library instead") {
                dismiss()
                onUseLibrary()
            }
            .buttonStyle(.bordered)
        }
        .padding(30)
    }
}

// MARK: - Session controller

/// Owns the AVFoundation capture session. The still photo exists only as
/// in-memory data on its way to a UIImage — it is never written to a file
/// and never saved to the Photos library.
///
/// `nonisolated`: the app defaults to MainActor isolation, but this object's
/// work (and the photo-output delegate callback) lives on capture queues.
nonisolated final class CameraController: NSObject, AVCapturePhotoCaptureDelegate {

    enum Status { case checking, ready, denied, unavailable }

    let session = AVCaptureSession()
    private let output = AVCapturePhotoOutput()
    private let sessionQueue = DispatchQueue(label: "com.kwharton.auries.camera")
    private var captureContinuation: CheckedContinuation<UIImage?, Never>?

    /// Ask for permission if needed, then configure the back camera.
    func prepare() async -> Status {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            break
        case .notDetermined:
            guard await AVCaptureDevice.requestAccess(for: .video) else { return .denied }
        case .denied, .restricted:
            return .denied
        @unknown default:
            return .denied
        }
        return await withCheckedContinuation { cont in
            sessionQueue.async { [self] in
                guard let device = AVCaptureDevice.default(.builtInWideAngleCamera,
                                                           for: .video, position: .back),
                      let input = try? AVCaptureDeviceInput(device: device) else {
                    cont.resume(returning: .unavailable)
                    return
                }
                session.beginConfiguration()
                session.sessionPreset = .photo
                guard session.canAddInput(input), session.canAddOutput(output) else {
                    session.commitConfiguration()
                    cont.resume(returning: .unavailable)
                    return
                }
                session.addInput(input)
                session.addOutput(output)
                session.commitConfiguration()
                session.startRunning()
                cont.resume(returning: .ready)
            }
        }
    }

    /// One still, returned as a UIImage (nil on failure). Portrait app, so
    /// the capture connection is rotated upright when supported.
    func capture() async -> UIImage? {
        await withCheckedContinuation { cont in
            sessionQueue.async { [self] in
                guard captureContinuation == nil else {
                    cont.resume(returning: nil)   // a capture is already in flight
                    return
                }
                captureContinuation = cont
                if let connection = output.connection(with: .video),
                   connection.isVideoRotationAngleSupported(90) {
                    connection.videoRotationAngle = 90
                }
                output.capturePhoto(with: AVCapturePhotoSettings(), delegate: self)
            }
        }
    }

    func photoOutput(_ output: AVCapturePhotoOutput,
                     didFinishProcessingPhoto photo: AVCapturePhoto,
                     error: Error?) {
        let image = error == nil
            ? photo.fileDataRepresentation().flatMap(UIImage.init(data:))
            : nil
        captureContinuation?.resume(returning: image)
        captureContinuation = nil
    }

    func stop() {
        sessionQueue.async { [self] in
            if session.isRunning { session.stopRunning() }
        }
    }
}

// MARK: - Preview layer host

private struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        if let connection = view.previewLayer.connection,
           connection.isVideoRotationAngleSupported(90) {
            connection.videoRotationAngle = 90   // portrait-only app
        }
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {}
}
