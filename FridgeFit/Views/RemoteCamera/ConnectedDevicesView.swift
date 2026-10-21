//
//  ConnectedDevicesView.swift
//  FridgeFit
//

import SwiftUI

/// Presentation entry point for FridgeFit's existing two-device camera
/// system. Registration, discovery, and connection remain in the supplied
/// view models; this view only chooses which existing flow to open.
struct ConnectedDevicesView: View {
    @StateObject private var viewModel: ConnectedDevicesViewModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var isPresentingAvailableCameras = false
    @State private var isPresentingRemoteCamera = false

    init(identity: DeviceIdentity) {
        _viewModel = StateObject(wrappedValue: ConnectedDevicesViewModel(identity: identity))
    }

    /// For previews and tests, which supply an existing discovery model.
    init(viewModel: ConnectedDevicesViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        ChooseDeviceRoleView(
            deviceName: viewModel.identity.deviceName,
            availableCameraCount: viewModel.availableCameras.count,
            otherDevices: viewModel.otherDevices,
            status: viewModel.status(for:),
            isRegistering: viewModel.isRegistering,
            errorMessage: viewModel.errorMessage,
            isPresentingAvailableCameras: $isPresentingAvailableCameras,
            cameraDestination: {
                CameraModeView(identity: viewModel.identity)
            },
            remoteDestination: {
                AvailableCamerasView(viewModel: viewModel) { camera in
                    RemoteCameraView(
                        identity: viewModel.identity,
                        initialCamera: camera,
                        onPresentationChange: { isPresentingRemoteCamera = $0 }
                    )
                }
            }
        )
        .task { await viewModel.start() }
        .onChange(of: isPresentingAvailableCameras) { _, isPresented in
            // AvailableCamerasView stops the shared model as it leaves. Start
            // it again only once the chooser is visible after Back.
            guard !isPresented else { return }
            Task { await viewModel.start() }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                guard !isPresentingRemoteCamera else { return }
                Task { await viewModel.start() }
            case .inactive, .background:
                viewModel.stop()
            @unknown default:
                break
            }
        }
        .onDisappear {
            // Pushing Available Cameras reuses this model. Do not race its
            // initial `start()` with a parent `stop()`.
            guard !isPresentingAvailableCameras && !isPresentingRemoteCamera else { return }
            viewModel.stop()
        }
    }
}

/// Compact device metadata reused by the existing Remote Camera presentation.
struct DeviceRow: View {
    let device: RegisteredDevice
    let status: DeviceConnectionStatus

    var body: some View {
        HStack {
            Image(systemName: RemoteCameraPresentation.symbol(for: device.deviceRole))
                .foregroundStyle(FridgeFitTheme.ColorToken.primary)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(device.deviceName)
                    .font(FridgeFitTheme.Typography.cardTitle)
                    .foregroundStyle(FridgeFitTheme.ColorToken.textPrimary)
                Text(device.deviceRole.displayName)
                    .font(FridgeFitTheme.Typography.caption)
                    .foregroundStyle(FridgeFitTheme.ColorToken.textSecondary)
            }

            Spacer()

            Image(systemName: RemoteCameraPresentation.symbol(for: status))
                .foregroundStyle(RemoteCameraPresentation.tint(for: status))
                .accessibilityLabel(status.displayName)
        }
    }
}

#if DEBUG
#Preview {
    let identity = DeviceIdentity(deviceId: "preview-device", deviceName: "Kitchen iPhone")
    let registry = InMemoryDeviceRegistry(seedDevices: [
        identity.asRegisteredDevice(role: .controller),
        RegisteredDevice(
            deviceId: "camera-device",
            deviceName: "Fridge Camera",
            deviceRole: .camera,
            connectionStatus: .available,
            lastSeenAt: Date(),
            createdAt: Date()
        )
    ])
    return NavigationStack {
        ConnectedDevicesView(
            viewModel: ConnectedDevicesViewModel(identity: identity, registry: registry)
        )
    }
}
#endif
