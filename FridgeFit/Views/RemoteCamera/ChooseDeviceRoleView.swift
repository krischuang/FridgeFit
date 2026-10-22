//
//  ChooseDeviceRoleView.swift
//  FridgeFit
//

import SwiftUI

/// Fresh Botanical role selection for the existing Camera Mode and Remote
/// Camera destinations. Selecting a card navigates only; it does not change
/// device registration or start capture by itself.
struct ChooseDeviceRoleView<CameraDestination: View, RemoteDestination: View>: View {
    let deviceName: String
    let availableCameraCount: Int
    let otherDevices: [RegisteredDevice]
    let status: (RegisteredDevice) -> DeviceConnectionStatus
    let isRegistering: Bool
    let errorMessage: String?
    @Binding private var isPresentingAvailableCameras: Bool
    private let cameraDestination: () -> CameraDestination
    private let remoteDestination: () -> RemoteDestination

    init(
        deviceName: String,
        availableCameraCount: Int,
        otherDevices: [RegisteredDevice],
        status: @escaping (RegisteredDevice) -> DeviceConnectionStatus,
        isRegistering: Bool,
        errorMessage: String?,
        isPresentingAvailableCameras: Binding<Bool>,
        @ViewBuilder cameraDestination: @escaping () -> CameraDestination,
        @ViewBuilder remoteDestination: @escaping () -> RemoteDestination
    ) {
        self.deviceName = deviceName
        self.availableCameraCount = availableCameraCount
        self.otherDevices = otherDevices
        self.status = status
        self.isRegistering = isRegistering
        self.errorMessage = errorMessage
        _isPresentingAvailableCameras = isPresentingAvailableCameras
        self.cameraDestination = cameraDestination
        self.remoteDestination = remoteDestination
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: FridgeFitTheme.Spacing.xLarge) {
                header

                hero

                NavigationLink(destination: cameraDestination) {
                    roleCard(
                        title: "Use as Camera",
                        detail: "Keep this phone in the kitchen and let another FridgeFit device watch its live view.",
                        systemImage: "video.fill",
                        accent: FridgeFitTheme.ColorToken.primary,
                        action: "Start Camera Mode"
                    )
                }
                .buttonStyle(.plain)
                .accessibilityHint("Opens Camera Mode")

                // Driven by a binding rather than a value route: the parent
                // watches the same flag to restart discovery on Back, and
                // `navigationDestination(isPresented:)` clears it on pop the
                // way the deprecated `NavigationLink(isActive:)` did.
                Button {
                    isPresentingAvailableCameras = true
                } label: {
                    roleCard(
                        title: "Use as Remote Camera",
                        detail: "Choose another signed-in phone to view and control its kitchen camera.",
                        systemImage: "viewfinder",
                        accent: FridgeFitTheme.ColorToken.primaryMuted,
                        action: "Choose a Camera"
                    )
                }
                .buttonStyle(.plain)
                .accessibilityHint("Shows available FridgeFit cameras")
                .navigationDestination(isPresented: $isPresentingAvailableCameras) {
                    remoteDestination()
                }

                discoveryStatus

                registrationStatus

                HStack(spacing: FridgeFitTheme.Spacing.small) {
                    NavigationLink {
                        PairingOnboardingView()
                    } label: {
                        Label("How It Works", systemImage: "list.number")
                    }
                    .buttonStyle(FridgeFitSecondaryButtonStyle())

                    NavigationLink {
                        RemoteCameraHelpView()
                    } label: {
                        Label("FAQ", systemImage: "questionmark.circle")
                    }
                    .buttonStyle(FridgeFitSecondaryButtonStyle())
                }

                if !otherDevices.isEmpty {
                    otherDevicesSection
                }
            }
            .padding(.horizontal, FridgeFitTheme.Spacing.large)
            .padding(.vertical, FridgeFitTheme.Spacing.large)
        }
        .background(FridgeFitTheme.ColorToken.canvas.ignoresSafeArea())
        .navigationTitle("Connected Devices")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: FridgeFitTheme.Spacing.medium) {
            deviceIllustration

            Text("Turn a spare phone into your kitchen camera")
                .font(FridgeFitTheme.Typography.screenTitle)
                .foregroundStyle(FridgeFitTheme.ColorToken.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            Text("Use another FridgeFit device to watch the live view and control the camera when you are away from the kitchen.")
                .font(FridgeFitTheme.Typography.supporting)
                .foregroundStyle(FridgeFitTheme.ColorToken.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(FridgeFitTheme.Spacing.large)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [
                    FridgeFitTheme.ColorToken.successBackground,
                    FridgeFitTheme.ColorToken.card
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: FridgeFitTheme.Radius.largeCard, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: FridgeFitTheme.Radius.largeCard, style: .continuous)
                .stroke(FridgeFitTheme.ColorToken.controlBorder, lineWidth: 1)
        }
    }

    private var deviceIllustration: some View {
        HStack(spacing: FridgeFitTheme.Spacing.small) {
            illustrationDevice(symbol: "video.fill", label: "Kitchen camera")

            Image(systemName: "arrow.left.and.right")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(FridgeFitTheme.ColorToken.primary)
                .frame(width: 30, height: 30)
                .background(FridgeFitTheme.ColorToken.card, in: Circle())

            illustrationDevice(symbol: "viewfinder", label: "Your remote")

            Spacer(minLength: 0)

            Image(systemName: "sparkles")
                .font(.title3.weight(.semibold))
                .foregroundStyle(FridgeFitTheme.ColorToken.warningText)
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Two FridgeFit phones connected: a kitchen camera and a remote controller")
    }

    private func illustrationDevice(symbol: String, label: String) -> some View {
        VStack(spacing: 2) {
            Image(systemName: symbol)
                .font(.body.weight(.semibold))
                .foregroundStyle(FridgeFitTheme.ColorToken.primary)
                .frame(width: 42, height: 42)
                .background(FridgeFitTheme.ColorToken.card, in: RoundedRectangle(cornerRadius: FridgeFitTheme.Radius.control, style: .continuous))
            Text(label)
                .font(FridgeFitTheme.Typography.caption)
                .foregroundStyle(FridgeFitTheme.ColorToken.textSecondary)
                .lineLimit(1)
        }
    }

    private var header: some View {
        HStack(spacing: FridgeFitTheme.Spacing.small) {
            Image(systemName: "iphone.gen3.radiowaves.left.and.right")
                .font(.title3.weight(.semibold))
                .foregroundStyle(FridgeFitTheme.ColorToken.primary)
                .frame(width: 44, height: 44)
                .background(FridgeFitTheme.ColorToken.successBackground, in: RoundedRectangle(cornerRadius: FridgeFitTheme.Radius.control, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text("Live AI Camera")
                    .font(FridgeFitTheme.Typography.cardTitle)
                    .foregroundStyle(FridgeFitTheme.ColorToken.textPrimary)
                Text("Use your FridgeFit devices together")
                    .font(FridgeFitTheme.Typography.caption)
                    .foregroundStyle(FridgeFitTheme.ColorToken.textSecondary)
            }
        }
    }

    private func roleCard(
        title: String,
        detail: String,
        systemImage: String,
        accent: Color,
        action: String
    ) -> some View {
        HStack(alignment: .center, spacing: FridgeFitTheme.Spacing.medium) {
            Image(systemName: systemImage)
                .font(.title3.weight(.semibold))
                .foregroundStyle(FridgeFitTheme.ColorToken.primary)
                .frame(width: 52, height: 52)
                .background(accent.opacity(0.24), in: RoundedRectangle(cornerRadius: FridgeFitTheme.Radius.control, style: .continuous))

            VStack(alignment: .leading, spacing: FridgeFitTheme.Spacing.xSmall) {
                Text(title)
                    .font(FridgeFitTheme.Typography.sectionTitle)
                    .foregroundStyle(FridgeFitTheme.ColorToken.textPrimary)
                Text(detail)
                    .font(FridgeFitTheme.Typography.supporting)
                    .foregroundStyle(FridgeFitTheme.ColorToken.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                Label(action, systemImage: "arrow.right")
                    .font(FridgeFitTheme.Typography.metadata.weight(.semibold))
                    .foregroundStyle(FridgeFitTheme.ColorToken.primary)
                    .padding(.top, FridgeFitTheme.Spacing.xSmall)
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(FridgeFitTheme.ColorToken.textSecondary)
                .frame(width: 44, height: 44)
        }
        .padding(FridgeFitTheme.Spacing.medium)
        .frame(maxWidth: .infinity, alignment: .leading)
        .fridgeFitCardSurface()
        .contentShape(RoundedRectangle(cornerRadius: FridgeFitTheme.Radius.card, style: .continuous))
    }

    private var discoveryStatus: some View {
        HStack(alignment: .top, spacing: FridgeFitTheme.Spacing.small) {
            Image(systemName: availableCameraCount == 0 ? "info.circle" : "checkmark.circle.fill")
                .foregroundStyle(FridgeFitTheme.ColorToken.primary)
            Text(
                availableCameraCount == 0
                    ? "No active camera is currently available on your account. Open Camera Mode on another signed-in phone to make it discoverable."
                    : "\(availableCameraCount) \(availableCameraCount == 1 ? "camera is" : "cameras are") currently available."
            )
            .font(FridgeFitTheme.Typography.metadata)
            .foregroundStyle(FridgeFitTheme.ColorToken.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(FridgeFitTheme.Spacing.medium)
        .background(FridgeFitTheme.ColorToken.successBackground.opacity(0.72), in: RoundedRectangle(cornerRadius: FridgeFitTheme.Radius.card, style: .continuous))
    }

    @ViewBuilder
    private var registrationStatus: some View {
        if isRegistering {
            HStack(spacing: FridgeFitTheme.Spacing.small) {
                ProgressView()
                    .controlSize(.small)
                    .tint(FridgeFitTheme.ColorToken.primary)
                Text("Checking your connected devices…")
                    .font(FridgeFitTheme.Typography.metadata)
                    .foregroundStyle(FridgeFitTheme.ColorToken.textSecondary)
            }
            .padding(FridgeFitTheme.Spacing.medium)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(FridgeFitTheme.ColorToken.successBackground.opacity(0.72), in: RoundedRectangle(cornerRadius: FridgeFitTheme.Radius.card, style: .continuous))
            .accessibilityElement(children: .combine)
        }

        if let errorMessage {
            HStack(alignment: .top, spacing: FridgeFitTheme.Spacing.small) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(FridgeFitTheme.ColorToken.warningText)
                VStack(alignment: .leading, spacing: FridgeFitTheme.Spacing.xSmall) {
                    Text("Connected Devices needs attention")
                        .font(FridgeFitTheme.Typography.cardTitle)
                        .foregroundStyle(FridgeFitTheme.ColorToken.textPrimary)
                    Text(errorMessage)
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
    }

    private var otherDevicesSection: some View {
        VStack(alignment: .leading, spacing: FridgeFitTheme.Spacing.small) {
            Text("Other signed-in devices")
                .font(FridgeFitTheme.Typography.sectionTitle)
                .foregroundStyle(FridgeFitTheme.ColorToken.textPrimary)

            ForEach(otherDevices) { device in
                HStack(spacing: FridgeFitTheme.Spacing.small) {
                    Image(systemName: RemoteCameraPresentation.symbol(for: device.deviceRole))
                        .foregroundStyle(FridgeFitTheme.ColorToken.primary)
                        .frame(width: 28, height: 28)
                        .background(FridgeFitTheme.ColorToken.successBackground, in: RoundedRectangle(cornerRadius: FridgeFitTheme.Radius.small, style: .continuous))

                    VStack(alignment: .leading, spacing: 1) {
                        Text(device.deviceName)
                            .font(FridgeFitTheme.Typography.cardTitle)
                            .foregroundStyle(FridgeFitTheme.ColorToken.textPrimary)
                        Text(device.deviceRole.displayName)
                            .font(FridgeFitTheme.Typography.caption)
                            .foregroundStyle(FridgeFitTheme.ColorToken.textSecondary)
                    }

                    Spacer(minLength: 0)

                    ConnectionStatusLabel(status: status(device))
                        .font(FridgeFitTheme.Typography.caption)
                }
                .padding(.vertical, FridgeFitTheme.Spacing.xSmall)
            }
        }
        .padding(FridgeFitTheme.Spacing.medium)
        .fridgeFitCardSurface()
    }
}

#if DEBUG
#Preview("Choose Device Role") {
    NavigationStack {
        ChooseDeviceRoleView(
            deviceName: "Shelly's iPhone",
            availableCameraCount: 1,
            otherDevices: [
                RegisteredDevice(
                    deviceId: "preview-kitchen-camera",
                    deviceName: "Kitchen iPhone",
                    deviceRole: .camera,
                    connectionStatus: .available,
                    lastSeenAt: Date(),
                    createdAt: Date()
                )
            ],
            status: { $0.effectiveStatus() },
            isRegistering: false,
            errorMessage: nil,
            isPresentingAvailableCameras: .constant(false),
            cameraDestination: { Text("Camera Mode") },
            remoteDestination: { Text("Available Cameras") }
        )
    }
}
#endif
