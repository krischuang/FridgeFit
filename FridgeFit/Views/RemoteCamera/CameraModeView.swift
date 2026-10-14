//
//  CameraModeView.swift
//  FridgeFit
//

import SwiftUI

/// Screen B: this iPhone as the remote fridge camera.
///
/// The camera starts in `.task` - i.e. only once the user has navigated here
/// deliberately - and stops on disappear or when the app leaves the
/// foreground. iOS does not allow background camera capture, and this screen
/// does not try to pretend otherwise.
struct CameraModeView: View {
    @StateObject private var viewModel: CameraModeViewModel
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dismiss) private var dismiss

    init(identity: DeviceIdentity) {
        _viewModel = StateObject(wrappedValue: CameraModeViewModel(identity: identity))
    }

    init(viewModel: CameraModeViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                VideoSurface(
                    track: viewModel.localVideoTrack,
                    isLive: viewModel.isReceivingFrames,
                    placeholder: viewModel.isActive
                        ? "Starting the camera…"
                        : "The camera is off. Camera Mode starts it when this screen opens.",
                    isMirrored: viewModel.cameraPosition == .front
                )

                statusCard
                controls

                if let summary = viewModel.lastCaptureSummary {
                    Label(summary, systemImage: "checkmark.circle")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Text(viewModel.connectivityCaveat)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding()
        }
        .navigationTitle("Camera Mode")
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.activate() }
        .onDisappear {
            Task { await viewModel.deactivate() }
        }
        .onChange(of: scenePhase) { _, phase in
            // Backgrounding ends the session rather than leaving the
            // controller connected to a camera iOS has already suspended.
            guard phase == .background || phase == .inactive else { return }
            Task { await viewModel.deactivate() }
        }
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                ConnectionStatusLabel(status: viewModel.status)
                Spacer()
                Text(viewModel.cameraPosition.displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            LabeledContent("This device", value: viewModel.identity.deviceName)

            LabeledContent("Controller") {
                Text(viewModel.connectedControllerName ?? "Not connected")
                    .foregroundStyle(viewModel.connectedControllerName == nil ? .secondary : .primary)
            }
        }
        .font(.subheadline)
        .padding()
        .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 12))
    }

    private var controls: some View {
        VStack(spacing: 12) {
            Button {
                Task { await viewModel.switchCamera(announce: true) }
            } label: {
                Label("Switch Camera", systemImage: "arrow.triangle.2.circlepath.camera")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(!viewModel.canSwitchCamera)

            Button(role: .destructive) {
                Task {
                    await viewModel.deactivate()
                    dismiss()
                }
            } label: {
                Label("Stop Camera", systemImage: "stop.circle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!viewModel.isActive)
        }
    }
}

#Preview {
    // No camera in the Simulator, so this previews the refused state - which
    // is the point: Camera Mode explains itself rather than showing black.
    NavigationStack {
        CameraModeView(
            viewModel: CameraModeViewModel(
                identity: DeviceIdentity(deviceId: "preview-device", deviceName: "Preview iPhone"),
                registry: InMemoryDeviceRegistry(),
                transport: InMemorySignalingTransport()
            )
        )
    }
}
