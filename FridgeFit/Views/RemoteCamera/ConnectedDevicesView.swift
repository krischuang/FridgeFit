//
//  ConnectedDevicesView.swift
//  FridgeFit
//

import SwiftUI

/// Screen A: what this device is, what else is signed into the same account,
/// and the two ways into the prototype.
struct ConnectedDevicesView: View {
    @StateObject private var viewModel: ConnectedDevicesViewModel
    @Environment(\.scenePhase) private var scenePhase

    init(identity: DeviceIdentity) {
        _viewModel = StateObject(wrappedValue: ConnectedDevicesViewModel(identity: identity))
    }

    /// For previews and tests, which supply doubles.
    init(viewModel: ConnectedDevicesViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        List {
            thisDeviceSection
            availableDevicesSection
            modesSection

            if let errorMessage = viewModel.errorMessage {
                Section {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("Connected Devices")
        .task { await viewModel.start() }
        // Stops heartbeating when the app leaves the foreground, so a
        // backgrounded phone drops off the other device's list instead of
        // sitting there as an unreachable camera.
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                Task { await viewModel.start() }
            case .inactive, .background:
                viewModel.stop()
            @unknown default:
                break
            }
        }
        .onDisappear { viewModel.stop() }
    }

    private var thisDeviceSection: some View {
        Section("This Device") {
            LabeledContent("Name", value: viewModel.identity.deviceName)

            Picker("Role", selection: Binding(
                get: { viewModel.role },
                set: { newRole in Task { await viewModel.setRole(newRole) } }
            )) {
                ForEach(DeviceRole.allCases, id: \.self) { role in
                    Label(role.displayName, systemImage: RemoteCameraPresentation.symbol(for: role))
                        .tag(role)
                }
            }

            if viewModel.isRegistering {
                Label("Registering…", systemImage: "arrow.triangle.2.circlepath")
                    .foregroundStyle(.secondary)
                    .font(.footnote)
            }
        }
    }

    private var availableDevicesSection: some View {
        Section {
            if viewModel.otherDevices.isEmpty {
                Text("""
                No other devices yet. Sign in to the same FridgeFit account on \
                your other iPhone and open this screen there.
                """)
                .font(.footnote)
                .foregroundStyle(.secondary)
            } else {
                ForEach(viewModel.otherDevices) { device in
                    DeviceRow(device: device, status: viewModel.status(for: device))
                }
            }
        } header: {
            Text("Available Devices")
        } footer: {
            Text("""
            Devices disappear from this list about \
            \(Int(RegisteredDevice.presenceWindow)) seconds after they stop \
            checking in, so a phone that quit or lost its connection doesn't \
            keep showing as available.
            """)
            .font(.caption)
        }
    }

    private var modesSection: some View {
        Section {
            NavigationLink {
                CameraModeView(identity: viewModel.identity)
            } label: {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Camera Mode")
                        Text("Use this iPhone as the fridge camera")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "camera")
                }
            }

            NavigationLink {
                RemoteCameraView(identity: viewModel.identity)
            } label: {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Remote Camera")
                        Text("View and capture from your other iPhone")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "video")
                }
            }
        } header: {
            Text("Modes")
        } footer: {
            Text(WebRTCConfiguration.current.connectivityCaveat)
                .font(.caption)
        }
    }
}

/// One row in the device list: name, role, and the status it is actually in.
struct DeviceRow: View {
    let device: RegisteredDevice
    let status: DeviceConnectionStatus

    var body: some View {
        HStack {
            Image(systemName: RemoteCameraPresentation.symbol(for: device.deviceRole))
                .foregroundStyle(.secondary)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(device.deviceName)
                Text(device.deviceRole.displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: RemoteCameraPresentation.symbol(for: status))
                .foregroundStyle(RemoteCameraPresentation.tint(for: status))
                .accessibilityLabel(status.displayName)
        }
    }
}

#Preview {
    let identity = DeviceIdentity(deviceId: "preview-device", deviceName: "Preview iPhone")
    let registry = InMemoryDeviceRegistry(seedDevices: [
        identity.asRegisteredDevice(role: .controller),
        RegisteredDevice(
            deviceId: "other-device",
            deviceName: "Kitchen iPhone",
            deviceRole: .camera,
            connectionStatus: .available,
            lastSeenAt: Date(),
            createdAt: Date()
        ),
    ])
    return NavigationStack {
        ConnectedDevicesView(
            viewModel: ConnectedDevicesViewModel(identity: identity, registry: registry)
        )
    }
}
