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
            VStack(alignment: .leading, spacing: FridgeFitTheme.Spacing.large) {
                header
                cameraPreview
                cameraInformation
                controls

                if let summary = viewModel.lastCaptureSummary {
                    Label(summary, systemImage: "checkmark.circle.fill")
                        .font(FridgeFitTheme.Typography.metadata)
                        .foregroundStyle(FridgeFitTheme.ColorToken.primary)
                        .padding(FridgeFitTheme.Spacing.medium)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(FridgeFitTheme.ColorToken.successBackground, in: RoundedRectangle(cornerRadius: FridgeFitTheme.Radius.control, style: .continuous))
                }

                if let errorMessage = viewModel.errorMessage {
                    errorCard(errorMessage)
                }

                Label(connectionRecommendation, systemImage: "info.circle")
                    .font(FridgeFitTheme.Typography.caption)
                    .foregroundStyle(FridgeFitTheme.ColorToken.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, FridgeFitTheme.Spacing.large)
            .padding(.vertical, FridgeFitTheme.Spacing.large)
        }
        .background(FridgeFitTheme.ColorToken.canvas.ignoresSafeArea())
        .navigationTitle("Kitchen Camera")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(FridgeFitTheme.ColorToken.canvas, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
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

    private var header: some View {
        HStack(alignment: .center, spacing: FridgeFitTheme.Spacing.medium) {
            Image(systemName: "video.fill")
                .font(.title3.weight(.semibold))
                .foregroundStyle(FridgeFitTheme.ColorToken.primary)
                .frame(width: 44, height: 44)
                .background(FridgeFitTheme.ColorToken.successBackground, in: RoundedRectangle(cornerRadius: FridgeFitTheme.Radius.control, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(viewModel.identity.deviceName)
                    .font(FridgeFitTheme.Typography.sectionTitle)
                    .foregroundStyle(FridgeFitTheme.ColorToken.textPrimary)
                Text("Kitchen Camera Mode")
                    .font(FridgeFitTheme.Typography.caption)
                    .foregroundStyle(FridgeFitTheme.ColorToken.textSecondary)
            }

            Spacer(minLength: FridgeFitTheme.Spacing.small)

            statusBadge
        }
        .accessibilityElement(children: .combine)
    }

    private var statusBadge: some View {
        Label(cameraStatusTitle, systemImage: cameraStatusSymbol)
            .font(FridgeFitTheme.Typography.caption.weight(.semibold))
            .foregroundStyle(cameraStatusTint)
            .padding(.horizontal, FridgeFitTheme.Spacing.small)
            .padding(.vertical, FridgeFitTheme.Spacing.xSmall)
            .background(cameraStatusTint.opacity(0.14), in: Capsule())
            .accessibilityLabel("Camera status: \(cameraStatusTitle)")
    }

    private var cameraPreview: some View {
        Group {
            if usesCompactUnavailablePreview {
                videoSurface
                    .frame(width: 168)
            } else {
                videoSurface
                    .frame(maxWidth: .infinity)
                    .overlay(alignment: .topLeading) {
                        Label(viewModel.identity.deviceName, systemImage: "camera")
                            .font(FridgeFitTheme.Typography.caption.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.92))
                            .padding(.horizontal, FridgeFitTheme.Spacing.small)
                            .padding(.vertical, FridgeFitTheme.Spacing.xSmall)
                            .background(.black.opacity(0.48), in: Capsule())
                            .padding(FridgeFitTheme.Spacing.medium)
                    }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var videoSurface: some View {
        VideoSurface(
            track: viewModel.localVideoTrack,
            isLive: viewModel.isReceivingFrames,
            placeholder: cameraPlaceholder,
            isMirrored: viewModel.cameraPosition == .front
        )
        .overlay {
            RoundedRectangle(cornerRadius: FridgeFitTheme.Radius.card, style: .continuous)
                .stroke(FridgeFitTheme.ColorToken.border.opacity(0.55), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: FridgeFitTheme.Radius.card, style: .continuous))
    }

    private var cameraInformation: some View {
        VStack(alignment: .leading, spacing: FridgeFitTheme.Spacing.medium) {
            Text("Camera information")
                .font(FridgeFitTheme.Typography.cardTitle)
                .foregroundStyle(FridgeFitTheme.ColorToken.textPrimary)

            infoRow(title: "Camera lens", value: viewModel.cameraPosition.displayName, systemImage: "camera.rotate")
            Divider().overlay(FridgeFitTheme.ColorToken.border)
            infoRow(
                title: "Remote controller",
                value: viewModel.connectedControllerName ?? "No controller connected",
                systemImage: "iphone.gen3"
            )
        }
        .padding(FridgeFitTheme.Spacing.medium)
        .fridgeFitCardSurface()
    }

    private func infoRow(title: String, value: String, systemImage: String) -> some View {
        HStack(spacing: FridgeFitTheme.Spacing.small) {
            Image(systemName: systemImage)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(FridgeFitTheme.ColorToken.primary)
                .frame(width: 28, height: 28)
                .background(FridgeFitTheme.ColorToken.successBackground, in: RoundedRectangle(cornerRadius: FridgeFitTheme.Radius.small, style: .continuous))

            Text(title)
                .font(FridgeFitTheme.Typography.metadata)
                .foregroundStyle(FridgeFitTheme.ColorToken.textSecondary)

            Spacer(minLength: FridgeFitTheme.Spacing.small)

            Text(value)
                .font(FridgeFitTheme.Typography.metadata.weight(.semibold))
                .foregroundStyle(FridgeFitTheme.ColorToken.textPrimary)
                .multilineTextAlignment(.trailing)
        }
        .accessibilityElement(children: .combine)
    }

    private var controls: some View {
        VStack(spacing: FridgeFitTheme.Spacing.small) {
            Button {
                Task { await viewModel.switchCamera(announce: true) }
            } label: {
                Label("Switch Camera", systemImage: "arrow.triangle.2.circlepath.camera")
            }
            .buttonStyle(FridgeFitSecondaryButtonStyle())
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
            .font(FridgeFitTheme.Typography.button)
            .foregroundStyle(FridgeFitTheme.ColorToken.danger)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(FridgeFitTheme.ColorToken.card, in: RoundedRectangle(cornerRadius: FridgeFitTheme.Radius.control, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: FridgeFitTheme.Radius.control, style: .continuous)
                    .stroke(FridgeFitTheme.ColorToken.errorText, lineWidth: 1)
            }
            .disabled(!viewModel.isActive)
        }
    }

    private func errorCard(_ message: String) -> some View {
        HStack(alignment: .top, spacing: FridgeFitTheme.Spacing.small) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(FridgeFitTheme.ColorToken.warningText)
            VStack(alignment: .leading, spacing: FridgeFitTheme.Spacing.xSmall) {
                Text(errorTitle)
                    .font(FridgeFitTheme.Typography.cardTitle)
                    .foregroundStyle(FridgeFitTheme.ColorToken.textPrimary)
                Text(message)
                    .font(FridgeFitTheme.Typography.metadata)
                    .foregroundStyle(FridgeFitTheme.ColorToken.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(FridgeFitTheme.Spacing.medium)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(FridgeFitTheme.ColorToken.warningBackground.opacity(0.72), in: RoundedRectangle(cornerRadius: FridgeFitTheme.Radius.card, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private var cameraStatusTitle: String {
        viewModel.isActive && !viewModel.isReceivingFrames ? "Starting" : viewModel.status.displayName
    }

    private var cameraStatusSymbol: String {
        viewModel.isActive && !viewModel.isReceivingFrames
            ? "ellipsis.circle"
            : RemoteCameraPresentation.symbol(for: viewModel.status)
    }

    private var cameraStatusTint: Color {
        viewModel.isActive && !viewModel.isReceivingFrames
            ? FridgeFitTheme.ColorToken.warningText
            : RemoteCameraPresentation.tint(for: viewModel.status)
    }

    private var cameraPlaceholder: String {
        if let errorMessage = viewModel.errorMessage {
            return errorMessage
        }
        return viewModel.isActive
            ? "Starting the camera…"
            : "Kitchen Camera Mode is unavailable."
    }

    private var usesCompactUnavailablePreview: Bool {
        !viewModel.isActive && viewModel.status == .offline
    }

    private var errorTitle: String {
        viewModel.isActive ? "Camera needs attention" : "Kitchen Camera Mode couldn't start"
    }

    private var connectionRecommendation: String {
        "For the most reliable connection, use the same Wi-Fi network on both phones. Some networks may prevent a connection."
    }
}
