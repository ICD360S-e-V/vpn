// ICD360SVPN — Components/StatusBadge.swift
// MARK: - Reusable colored capsule

import SwiftUI

struct StatusBadge: View {
    let text: String
    let color: Color

    init(_ text: String, color: Color) {
        self.text = text
        self.color = color
    }

    var body: some View {
        Text(text.uppercased())
            .font(.caption2.bold())
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .foregroundStyle(.white)
            .background(color)
            .clipShape(Capsule())
    }

    /// Convenience: maps `Health.status` to a color.
    static func forStatus(_ status: String) -> StatusBadge {
        switch status.lowercased() {
        case "ok":       return StatusBadge(status, color: .green)
        case "degraded": return StatusBadge(status, color: .orange)
        default:         return StatusBadge(status, color: .red)
        }
    }
}

#Preview {
    HStack(spacing: 8) {
        StatusBadge.forStatus("ok")
        StatusBadge.forStatus("degraded")
        StatusBadge.forStatus("error")
    }
    .padding()
}
