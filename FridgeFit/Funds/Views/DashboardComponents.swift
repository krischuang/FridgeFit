//
//  DashboardComponents.swift
//  FridgeFit
//

import SwiftUI

// ring showing % of budget spent, value + label in the middle. fraction can go
// past 1.0 when overspent - it just turns red instead of drawing past a full lap.
struct BudgetRingView: View {
    let fraction: Double
    let centerTitle: String
    let centerSubtitle: String

    private var clampedFraction: Double {
        min(max(fraction, 0), 1)
    }

    private var ringColor: Color {
        fraction > 1 ? .red : .blue
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color(.systemGray5), lineWidth: 14)

            Circle()
                .trim(from: 0, to: clampedFraction)
                .stroke(ringColor, style: StrokeStyle(lineWidth: 14, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.4), value: fraction)

            VStack(spacing: 4) {
                Text(centerTitle)
                    .font(.title.bold())
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                Text(centerSubtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(28)
        }
        .frame(width: 180, height: 180)
    }
}

// icon + title + value row, reused across the dashboard for things like "left today"
// and "money in fridge"
struct DashboardStat: View {
    let icon: String
    let title: String
    let value: String
    var subtitle: String? = nil
    let tint: Color

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(tint)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.title3.bold())
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()
        }
        .padding()
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
    }
}
