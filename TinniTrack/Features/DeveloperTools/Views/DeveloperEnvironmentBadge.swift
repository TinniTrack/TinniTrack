//
//  DeveloperEnvironmentBadge.swift
//  TinniTrack
//

import SwiftUI

#if DEBUG
struct DeveloperEnvironmentBadge: View {
    let environment: SupabaseEnvironmentDescriptor

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(environment.isProduction ? Color.red : Color.green)
                .frame(width: 8, height: 8)

            Text(environment.badgeText)
                .font(.caption2)
                .fontWeight(.semibold)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.thinMaterial)
        .clipShape(Capsule())
        .accessibilityIdentifier("debug_environment_badge")
    }
}
#endif
