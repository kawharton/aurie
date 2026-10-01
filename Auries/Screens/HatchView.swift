import SwiftUI
import PhotosUI

/// Hatch tab (mockup screen 2): take a photo (real camera on device), pick
/// one from the library, or tap a bundled sample; the pipeline runs, and the
/// egg flow opens full-screen over everything. With no hatches left, any
/// capture path opens the refill sheet instead (§11) — and since a hatch is
/// only consumed after a successful save, cancelling the camera, the picker,
/// or the egg never costs anything.
struct HatchView: View {
    @Environment(AppModel.self) private var model
    @State private var photoItem: PhotosPickerItem?
    @State private var showPicker = false
    @State private var showCamera = false
    @State private var showRefill = false
    @State private var preparing = false
    @State private var imageLoadFailed = false
    @State private var pending: PendingHatch?

    /// Bundled demo objects. Each carries its own known identity (label +
    /// category) so tapping it reliably shows object flavour (Layers 2-3) even
    /// though the images are canned and the Simulator can't run Vision. Labels
    /// match the hero entries in aurie_content.json so Layer 3 fires too.
    private struct Sample: Identifiable {
        let asset: String
        let recognized: RecognizedObject
        var id: String { asset }
    }
    private let samples: [Sample] = [
        Sample(asset: "sample_banana", recognized: .init(label: "banana", category: .food, confidence: 0.95)),
        Sample(asset: "sample_apple",  recognized: .init(label: "apple", category: .food, confidence: 0.95)),
        Sample(asset: "sample_mug",    recognized: .init(label: "mug", category: .container, confidence: 0.95)),
        Sample(asset: "sample_flower", recognized: .init(label: "flower", category: .plant, confidence: 0.95)),
        Sample(asset: "sample_book",   recognized: .init(label: "book", category: .paper, confidence: 0.95)),
        Sample(asset: "sample_teddy",  recognized: .init(label: "teddy", category: .toy, confidence: 0.95)),
    ]

    var body: some View {
        VStack(spacing: 12) {
            Spacer()

            Text("Who will hatch today?")
                .font(.title2.weight(.bold))
            Text("Take a photo of any object.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            // The live camera on real devices. The Simulator has no camera,
            // so there it opens the photo library instead of showing a
            // broken viewfinder (samples below stay the main sim flow).
            Button {
                #if targetEnvironment(simulator)
                requestCapture { showPicker = true }
                #else
                requestCapture { showCamera = true }
                #endif
            } label: {
                VStack(spacing: 10) {
                    Image(systemName: "camera")
                        .font(.system(size: 36))
                    Text("Tap to take photo")
                        .font(.footnote)
                }
                .foregroundStyle(.secondary)
                .frame(width: 190, height: 170)
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [7, 6]))
                        .foregroundStyle(.tertiary)
                )
            }
            .padding(.top, 24)

            Button {
                requestCapture { showPicker = true }
            } label: {
                Label("Choose from library", systemImage: "photo.on.rectangle")
                    .font(.subheadline)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial, in: Capsule())
            }
            .foregroundStyle(.primary)
            .padding(.top, 16)

            sampleRow
                .padding(.top, 20)

            Text("Good light · Fill the frame · Plain background · Hold steady")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .padding(.top, 16)

            Spacer()

            Text("Hatches left today: \(model.wallet.hatchesAvailable)")
                .font(.footnote)
                .foregroundStyle(.tertiary)
                .padding(.bottom, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay {
            if preparing { ProgressView().controlSize(.large) }
        }
        .onAppear { model.wallet.refreshDaily() }
        .photosPicker(isPresented: $showPicker, selection: $photoItem, matching: .images)
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task {
                preparing = true
                if let data = try? await item.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    pending = await model.prepareHatch(from: image)
                } else {
                    // Unsupported/inaccessible image: say so gently; nothing
                    // is consumed and the user can simply try another.
                    imageLoadFailed = true
                }
                preparing = false
                photoItem = nil
            }
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraCaptureView(
                onCapture: { image in
                    Task {
                        preparing = true
                        pending = await model.prepareHatch(from: image)
                        preparing = false
                    }
                },
                onUseLibrary: { showPicker = true }
            )
        }
        .alert("That photo couldn't be opened.", isPresented: $imageLoadFailed) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Try a different one — nothing was used up.")
        }
        .fullScreenCover(item: $pending) { EggHatchView(pending: $0) }
        #if DEBUG
        .task {
            // Capture aid: hatch from a synthesized swatch so a specific
            // family can be driven without the camera or a tap.
            guard let fam = ProcessInfo.processInfo
                .environment["AURIE_HATCH_DEMO"], pending == nil,
                  !HatchDebugHooks.demoFired
            else { return }
            HatchDebugHooks.demoFired = true
            // On a fresh install the first-run explainer is still up, and a
            // cover presented under it is dropped. Let the tab settle first.
            try? await Task.sleep(for: .seconds(1.8))
            // AURIE_HATCH_DEMO=<sample> ("apple", "mug", …) drives the
            // REAL bundled-sample flow — the same image and forced
            // recognition the sample button submits — so recognition-
            // dependent outcomes (Birth Charms) can be captured.
            if let sample = samples.first(where: {
                $0.asset == "sample_\(fam)"
            }) {
                pending = await model.prepareHatch(
                    from: UIImage(named: sample.asset) ?? UIImage(),
                    forcedRecognition: sample.recognized)
                NSLog("AURIE_HATCH prepared sample=%@", fam)
                return
            }
            let swatch: [String: UIColor] = [
                "dusk": UIColor(red: 0.47, green: 0.35, blue: 0.75, alpha: 1),
                "ember": UIColor(red: 0.86, green: 0.35, blue: 0.24, alpha: 1),
                "moss": UIColor(red: 0.43, green: 0.67, blue: 0.35, alpha: 1),
            ]
            guard let c = swatch[fam] else { return }
            let img = UIGraphicsImageRenderer(size: CGSize(width: 240, height: 240))
                .image { ctx in
                    c.setFill()
                    ctx.fill(CGRect(x: 0, y: 0, width: 240, height: 240))
                }
            pending = await model.prepareHatch(from: img)
            NSLog("AURIE_HATCH prepared=%@", fam)
        }
        #endif
        .sheet(isPresented: $showRefill) { RefillSheet() }
        #if DEBUG
        // Capture aid: AURIE_SHOW_REFILL=1 opens the refill sheet without
        // spending the wallet down; =packs also pushes the hatch-pack list.
        .task {
            guard ProcessInfo.processInfo.environment["AURIE_SHOW_REFILL"] != nil,
                  !HatchDebugHooks.refillFired else { return }
            HatchDebugHooks.refillFired = true
            try? await Task.sleep(for: .seconds(2))
            showRefill = true
        }
        #endif
        // Widget deep link: fold everything so Home is unobstructed. A
        // dismissed egg costs nothing — hatches are only spent at save.
        .onReceive(NotificationCenter.default.publisher(for: .auriesReturnHome)) { _ in
            showCamera = false
            showPicker = false
            showRefill = false
            pending = nil
        }
    }

    /// Every capture path goes through the gate: no hatches -> refill sheet.
    private func requestCapture(_ proceed: () -> Void) {
        model.wallet.refreshDaily()
        if model.wallet.hatchesAvailable > 0 {
            proceed()
        } else {
            showRefill = true
        }
    }

    /// Bundled sample objects so the whole flow works in the Simulator (§10).
    private var sampleRow: some View {
        VStack(spacing: 8) {
            Text("or try a sample")
                .font(.caption)
                .foregroundStyle(.tertiary)
            HStack(spacing: 10) {
                // Image(uiImage:) rather than Image(name): these are loose
                // bundle PNGs (not asset-catalog entries), which SwiftUI's
                // named lookup doesn't resolve.
                ForEach(samples) { sample in
                    if let image = UIImage(named: sample.asset) {
                        Button {
                            requestCapture {
                                Task {
                                    preparing = true
                                    pending = await model.prepareHatch(from: image,
                                                                       forcedRecognition: sample.recognized)
                                    preparing = false
                                }
                            }
                        } label: {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 48, height: 48)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                    }
                }
            }
        }
    }
}

#if DEBUG
/// Process-level latches for the capture hooks.
///
/// These MUST NOT be `@State`. SwiftUI rebuilds views freely — switching tabs
/// is enough — and a fresh `@State` guard let `AURIE_HATCH_DEMO` prepare a
/// second egg while one was already on screen, which looked like the app
/// hatching on its own. The environment variable lives as long as the
/// process, so the latch has to as well.
@MainActor enum HatchDebugHooks {
    static var refillFired = false
    static var demoFired = false
    static var autoCrackFired = false
    /// Timestamp of the fifth tap, for the burst timing trace.
    static var tapFive: CFAbsoluteTime = 0
}
#endif
