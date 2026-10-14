import SwiftUI

struct EmptyKitchenView: View {
    let title: String
    let message: String
    let actionTitle: String?
    let action: (() -> Void)?

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "refrigerator")
                .font(.system(size: 36, weight: .regular))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            Text(title)
                .font(.title3.weight(.semibold))

            Text(message)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderedProminent)
                    .tint(SmartFridgeTheme.warmAccent)
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: 330)
        .frame(maxWidth: .infinity, minHeight: 260)
        .padding(.horizontal, 28)
    }
}
