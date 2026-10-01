import SwiftUI

/// Settings (§6): featured creature, sound, notifications, how to play, about.
struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var showTutorial = false
    @State private var notificationsBusy = false

    var body: some View {
        @Bindable var store = model.store
        NavigationStack {
            List {
                if !model.store.auries.isEmpty {
                    Section("Featured creature") {
                        featuredPicker
                    }
                }
                Section {
                    Toggle("Sound", isOn: $store.settings.soundOn)
                    Toggle("Notifications", isOn: Binding(
                        get: { model.store.settings.notificationsOn },
                        set: { enableNotifications($0) }
                    ))
                    .disabled(notificationsBusy)
                } footer: {
                    Text("A gentle once-a-day reminder to hatch something.")
                }
                Section {
                    Button("How to play") { showTutorial = true }
                }
                // Physical shaking is the primary Snow Globe interaction.
                // This is the alternative for anyone who cannot or would
                // rather not shake the device — it runs the SAME sequence,
                // not a second implementation. (Home also carries a Snow
                // Globe chip; both call the one code path.)
                Section("Accessibility") {
                    Button {
                        dismiss()
                        // Home is behind this sheet; let it come forward
                        // before the sequence starts.
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                            NotificationCenter.default.post(
                                name: .wonderShakeRequested, object: nil)
                        }
                    } label: {
                        Label("Shake without moving your phone",
                              systemImage: "wand.and.stars")
                    }
                    Text("Swirls the Snow Globe as if you had shaken your Aurie.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("About") {
                    LabeledContent("Version",
                                   value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                    Text("Aurie is a cozy, feel-good companion for everyone. It's here for warm moments. It does not provide therapy or medical advice.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("Done") { dismiss() } }
        }
        .fullScreenCover(isPresented: $showTutorial) { TutorialView() }
    }

    /// One row per Aurie; tap to feature (crown marks the current one).
    private var featuredPicker: some View {
        ForEach(model.store.auries) { aurie in
            Button {
                model.store.setFeatured(aurie)
            } label: {
                HStack(spacing: 12) {
                    Image(uiImage: AssetLoader.portrait(for: aurie))
                        .resizable()
                        .scaledToFit()
                        .frame(width: 40, height: 40)
                        .background(Color(aurie.auraColor, brightness: 0.3),
                                    in: RoundedRectangle(cornerRadius: 9))
                    Text(aurie.name)
                        .foregroundStyle(.primary)
                    Spacer()
                    if aurie.id == model.store.featured?.id {
                        Image(systemName: "crown.fill")
                            .foregroundStyle(.yellow)
                    }
                }
            }
        }
    }

    private func enableNotifications(_ on: Bool) {
        guard !notificationsBusy else { return }
        if on {
            notificationsBusy = true
            Task {
                // Only stays on if the system permission is actually granted.
                let granted = await Notifications.enable()
                model.store.settings.notificationsOn = granted
                notificationsBusy = false
            }
        } else {
            Notifications.disable()
            model.store.settings.notificationsOn = false
        }
    }
}
