//
//  SummaryCard.swift
//  HarvestPlus
//
//  Created by Razvan Politic on 15/04/2026.
//

import SwiftUI

// MARK: - Summary Card

struct SummaryCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)

            Text(value)
                .font(.title3)
                .fontWeight(.semibold)
                .monospacedDigit()

            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, AppSpacing.md)
        .harvestSurface(cornerRadius: AppRadius.md)
    }
}
