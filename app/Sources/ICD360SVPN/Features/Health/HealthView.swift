// ICD360SVPN — Features/Health/HealthView.swift
// MARK: - Live health dashboard
//
// Polls /v1/health every 5 seconds while the view is visible.

import SwiftUI

struct HealthView: View {
    let client: APIClient

    @State private var health: Health?
    @State private var lastError: String?

    var body: some View {
        Form {
            if let health {
                Section("Status") {
                    HStack {
                        Text("Overall")
                        Spacer()
                        StatusBadge.forStatus(health.status)
                    }
                    LabeledRow(label: "WireGuard", up: health.wgUp)
                    LabeledRow(label: "AdGuard Home", up: health.adguardUp)
                }
                Section("Server") {
                    HStack {
                        Text("Uptime")
                        Spacer()
                        Text(formatUptime(health.uptimeSeconds))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    HStack {
                        Text("Agent version")
                        Spacer()
                        Text(health.agentVersion)
                            .foregroundStyle(.secondary)
                            .font(.body.monospaced())
                    }
                    HStack {
                        Text("Server time")
                        Spacer()
                        Text(health.serverTime.formatted(date: .abbreviated, time: .standard))
                            .foregroundStyle(.secondary)
                    }
                }
            } else if let lastError {
                Text(lastError)
                    .foregroundStyle(.red)
            } else {
                ProgressView("Loading…")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Health")
        .task { await refreshLoop() }
    }

    private func refreshLoop() async {
        while !Task.isCancelled {
            do {
                let h = try await client.health()
                health = h
                lastError = nil
            } catch {
                lastError = error.localizedDescription
            }
            do {
                try await Task.sleep(for: .seconds(5))
            } catch {
                return  // cancelled
            }
        }
    }

    private func formatUptime(_ seconds: Int64) -> String {
        let totalSeconds = Int(seconds)
        let days  = totalSeconds / 86400
        let hours = (totalSeconds % 86400) / 3600
        let mins  = (totalSeconds % 3600) / 60
        let secs  = totalSeconds % 60
        if days > 0 {
            return "\(days)d \(hours)h \(mins)m"
        }
        if hours > 0 {
            return "\(hours)h \(mins)m \(secs)s"
        }
        return "\(mins)m \(secs)s"
    }
}

private struct LabeledRow: View {
    let label: String
    let up: Bool
    var body: some View {
        HStack {
            Text(label)
            Spacer()
            Image(systemName: up ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(up ? .green : .red)
                .font(.title3)
        }
    }
}
