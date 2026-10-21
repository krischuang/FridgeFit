//
//  RemoteCameraHelpView.swift
//  FridgeFit
//

import SwiftUI

/// Presentation-only troubleshooting for the existing Live AI Camera flow.
struct RemoteCameraHelpView: View {
    private let questions: [RemoteCameraFAQ] = [
        .init(
            question: "How does Live AI Camera work?",
            answer: "Use two phones signed in to the same FridgeFit account. One phone acts as your kitchen camera, while the other lets you view and control its live feed."
        ),
        .init(
            question: "Can I use an older phone as the camera?",
            answer: "Yes, as long as the phone supports FridgeFit and camera access. An older phone can make a great kitchen camera. Keep it powered, connected to the internet, and in Camera Mode while using it."
        ),
        .init(
            question: "Why can't I see my camera?",
            answer: "Check that both phones are signed in to the same FridgeFit account. On your kitchen phone, open Camera Mode and keep it active. Make sure both devices have an internet connection, then check Available Cameras again."
        ),
        .init(
            question: "Do both phones need the same account?",
            answer: "Yes. Both phones must be signed in to the same FridgeFit account so they can discover each other. For the most reliable connection, use the same Wi-Fi network when possible."
        ),
        .init(
            question: "Why is camera permission required?",
            answer: "FridgeFit needs camera permission on the kitchen phone to capture and share its live video. You can manage camera permissions in your iPhone's Settings."
        ),
        .init(
            question: "What if the camera goes offline?",
            answer: "Check your kitchen phone's internet connection and reopen Camera Mode. Keep Camera Mode active, then return to Available Cameras on your other phone. The camera should reappear once it becomes available again."
        ),
        .init(
            question: "What if the connection fails?",
            answer: "Check that both phones are connected to the internet. For the best results, connect them to the same Wi-Fi network. Then try connecting again. Some network configurations may prevent a connection."
        ),
        .init(
            question: "How do I reconnect or switch cameras?",
            answer: "Use Reconnect to retry a disconnected camera when that option is available. Switch Remote Camera changes the kitchen phone's front or rear camera. To connect to a different phone, return to Available Cameras and select another available device."
        )
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: FridgeFitTheme.Spacing.large) {
                header

                LazyVStack(spacing: FridgeFitTheme.Spacing.small) {
                    ForEach(questions) { item in
                        DisclosureGroup {
                            Text(item.answer)
                                .font(FridgeFitTheme.Typography.supporting)
                                .foregroundStyle(FridgeFitTheme.ColorToken.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.top, FridgeFitTheme.Spacing.small)
                        } label: {
                            Text(item.question)
                                .font(FridgeFitTheme.Typography.cardTitle)
                                .foregroundStyle(FridgeFitTheme.ColorToken.textPrimary)
                                .padding(.vertical, FridgeFitTheme.Spacing.xSmall)
                        }
                        .tint(FridgeFitTheme.ColorToken.primary)
                        .padding(FridgeFitTheme.Spacing.medium)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fridgeFitCardSurface()
                    }
                }
            }
            .padding(.horizontal, FridgeFitTheme.Spacing.large)
            .padding(.vertical, FridgeFitTheme.Spacing.large)
        }
        .background(FridgeFitTheme.ColorToken.canvas.ignoresSafeArea())
        .navigationTitle("Live AI Help")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: FridgeFitTheme.Spacing.small) {
            Image(systemName: "questionmark.bubble.fill")
                .font(.title2.weight(.semibold))
                .foregroundStyle(FridgeFitTheme.ColorToken.primary)
                .frame(width: 52, height: 52)
                .background(FridgeFitTheme.ColorToken.successBackground, in: RoundedRectangle(cornerRadius: FridgeFitTheme.Radius.control, style: .continuous))

            Text("FAQ & troubleshooting")
                .font(FridgeFitTheme.Typography.screenTitle)
                .foregroundStyle(FridgeFitTheme.ColorToken.textPrimary)

            Text("Helpful answers for setting up, finding, and reconnecting your kitchen camera.")
                .font(FridgeFitTheme.Typography.supporting)
                .foregroundStyle(FridgeFitTheme.ColorToken.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(FridgeFitTheme.Spacing.large)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(FridgeFitTheme.ColorToken.successBackground.opacity(0.7), in: RoundedRectangle(cornerRadius: FridgeFitTheme.Radius.largeCard, style: .continuous))
    }
}

private struct RemoteCameraFAQ: Identifiable {
    let question: String
    let answer: String

    var id: String { question }
}

#if DEBUG
#Preview("Live AI Help") {
    NavigationStack {
        RemoteCameraHelpView()
    }
}
#endif
