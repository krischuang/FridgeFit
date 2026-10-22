//
//  AvailableCamerasView.swift
//  FridgeFit
//

import SwiftUI

/// Presents the existing live discovery results. It owns no registry or
/// connection logic; the supplied Connected Devices model remains the single
/// discovery owner, and the destination owns the single remote connection.
struct AvailableCamerasView<RemoteDestination: View>: View {
    @ObservedObject var viewModel: ConnectedDevicesViewModel
    private let remoteDestination: (RegisteredDevice) -> RemoteDestination

    init(
        viewModel: ConnectedDevicesViewModel,
        @ViewBuilder remoteDestination: @escaping (RegisteredDevice) -> RemoteDestination
    ) {
        self.viewModel = viewModel
        self.remoteDestination = remoteDestination
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: FridgeFitTheme.Spacing.large) {
                header

                if viewModel.availableCameras.isEmpty {
                    emptyState
                } else {
                    LazyVStack(spacing: FridgeFitTheme.Spacing.small) {
                        ForEach(viewModel.availableCameras) { camera in
                            NavigationLink(destination: remoteDestination(camera)) {
                                cameraCard(camera)
                            }
                            .buttonStyle(.plain)
                            .accessibilityHint("Opens Remote Camera for \(camera.deviceName)")
                        }
                    }
                }
            }
            .padding(.horizontal, FridgeFitTheme.Spacing.large)
            .padding(.vertical, FridgeFitTheme.Spacing.large)
        }
        .background(FridgeFitTheme.ColorToken.canvas.ignoresSafeArea())
        .navigationTitle("Available Cameras")
        .navigationBarTitleDisplayMode(.inline)
        // Reuses the same state object supplied by ConnectedDevicesView.
        // `start()` replaces the listener on that one model, so a navigation
        // push never creates a second discovery owner.
        .task { await viewModel.start() }
        .onDisappear { viewModel.stop() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: FridgeFitTheme.Spacing.small) {
            HStack(spacing: FridgeFitTheme.Spacing.small) {
                Image(systemName: "video.badge.waveform")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(FridgeFitTheme.ColorToken.primary)
                    .frame(width: 44, height: 44)
                    .background(FridgeFitTheme.ColorToken.successBackground, in: RoundedRectangle(cornerRadius: FridgeFitTheme.Radius.control, style: .continuous))

                Text("Live AI Camera")
                    .font(FridgeFitTheme.Typography.cardTitle)
                    .foregroundStyle(FridgeFitTheme.ColorToken.textPrimary)
            }

            Text("Choose a camera")
                .font(FridgeFitTheme.Typography.screenTitle)
                .foregroundStyle(FridgeFitTheme.ColorToken.textPrimary)
            Text("These are active FridgeFit cameras signed in to your account.")
                .font(FridgeFitTheme.Typography.supporting)
                .foregroundStyle(FridgeFitTheme.ColorToken.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func cameraCard(_ camera: RegisteredDevice) -> some View {
        HStack(spacing: FridgeFitTheme.Spacing.medium) {
            Image(systemName: "video.fill")
                .font(.title3.weight(.semibold))
                .foregroundStyle(FridgeFitTheme.ColorToken.primary)
                .frame(width: 48, height: 48)
                .background(FridgeFitTheme.ColorToken.successBackground, in: RoundedRectangle(cornerRadius: FridgeFitTheme.Radius.control, style: .continuous))

            VStack(alignment: .leading, spacing: FridgeFitTheme.Spacing.xSmall) {
                Text(camera.deviceName)
                    .font(FridgeFitTheme.Typography.cardTitle)
                    .foregroundStyle(FridgeFitTheme.ColorToken.textPrimary)
                    .lineLimit(2)

                ConnectionStatusLabel(status: viewModel.status(for: camera))
                    .font(FridgeFitTheme.Typography.caption.weight(.semibold))
            }

            Spacer(minLength: 0)

            VStack(alignment: .trailing, spacing: FridgeFitTheme.Spacing.xSmall) {
                Text("Select")
                    .font(FridgeFitTheme.Typography.metadata.weight(.semibold))
                    .foregroundStyle(FridgeFitTheme.ColorToken.primary)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(FridgeFitTheme.ColorToken.textSecondary)
            }
            .frame(width: 52, height: 44)
        }
        .padding(FridgeFitTheme.Spacing.medium)
        .frame(maxWidth: .infinity, alignment: .leading)
        .fridgeFitCardSurface()
        .contentShape(RoundedRectangle(cornerRadius: FridgeFitTheme.Radius.card, style: .continuous))
    }

    private var emptyState: some View {
        VStack(spacing: FridgeFitTheme.Spacing.medium) {
            emptyIllustration

            Text("No cameras available")
                .font(FridgeFitTheme.Typography.sectionTitle)
                .foregroundStyle(FridgeFitTheme.ColorToken.textPrimary)

            Text("Open FridgeFit on another phone, sign in to the same account, and start Camera Mode.")
                .font(FridgeFitTheme.Typography.supporting)
                .foregroundStyle(FridgeFitTheme.ColorToken.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: FridgeFitTheme.Spacing.small) {
                Text("How to set up a camera")
                    .font(FridgeFitTheme.Typography.cardTitle)
                    .foregroundStyle(FridgeFitTheme.ColorToken.textPrimary)

                setupStep(number: 1, text: "Open FridgeFit on another phone.")
                setupStep(number: 2, text: "Sign in with the same account.")
                setupStep(number: 3, text: "Start Camera Mode and keep it open.")

                NavigationLink {
                    PairingOnboardingView()
                } label: {
                    Label("View Setup Guide", systemImage: "list.number")
                }
                .buttonStyle(FridgeFitSecondaryButtonStyle())
                .padding(.top, FridgeFitTheme.Spacing.xSmall)
            }
            .padding(FridgeFitTheme.Spacing.medium)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(FridgeFitTheme.ColorToken.successBackground.opacity(0.72), in: RoundedRectangle(cornerRadius: FridgeFitTheme.Radius.control, style: .continuous))
        }
        .padding(FridgeFitTheme.Spacing.section)
        .frame(maxWidth: .infinity)
        .fridgeFitCardSurface()
        .accessibilityElement(children: .combine)
    }

    private var emptyIllustration: some View {
        HStack(spacing: FridgeFitTheme.Spacing.small) {
            Image(systemName: "iphone")
                .font(.title3.weight(.semibold))
                .foregroundStyle(FridgeFitTheme.ColorToken.primary)
                .frame(width: 52, height: 64)
                .background(FridgeFitTheme.ColorToken.successBackground, in: RoundedRectangle(cornerRadius: FridgeFitTheme.Radius.control, style: .continuous))

            Image(systemName: "arrow.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(FridgeFitTheme.ColorToken.primary)

            Image(systemName: "video.fill")
                .font(.title3.weight(.semibold))
                .foregroundStyle(FridgeFitTheme.ColorToken.primary)
                .frame(width: 58, height: 58)
                .background(FridgeFitTheme.ColorToken.card, in: Circle())
                .overlay { Circle().stroke(FridgeFitTheme.ColorToken.border, lineWidth: 1) }
        }
        .accessibilityHidden(true)
    }

    private func setupStep(number: Int, text: String) -> some View {
        HStack(alignment: .top, spacing: FridgeFitTheme.Spacing.small) {
            Text("\(number)")
                .font(FridgeFitTheme.Typography.caption.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 20, height: 20)
                .background(FridgeFitTheme.ColorToken.brandFill, in: Circle())
            Text(text)
                .font(FridgeFitTheme.Typography.metadata)
                .foregroundStyle(FridgeFitTheme.ColorToken.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

#if DEBUG
#Preview("Available Cameras") {
    let identity = DeviceIdentity(deviceId: "preview-controller", deviceName: "Preview iPhone")
    let registry = InMemoryDeviceRegistry(seedDevices: [
        RegisteredDevice(
            deviceId: "kitchen-camera",
            deviceName: "Kitchen iPhone",
            deviceRole: .camera,
            connectionStatus: .available,
            lastSeenAt: Date(),
            createdAt: Date()
        )
    ])
    return NavigationStack {
        AvailableCamerasView(
            viewModel: ConnectedDevicesViewModel(identity: identity, registry: registry)
        ) { _ in
            Text("Remote Camera")
        }
    }
}
#endif
