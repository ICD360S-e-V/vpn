// ICD360SVPN — Models/Health.swift
// MARK: - Health wire model
//
// Mirrors the JSON shape returned by `GET /v1/health`.

import Foundation

/// Liveness + dependency-status snapshot from the agent.
public struct Health: Codable {
    /// `"ok"` if every dependency is up, `"degraded"` otherwise.
    public let status: String

    /// True if `wg show wg0` succeeded.
    public let wgUp: Bool

    /// True if AdGuard Home's `/control/status` returned 200.
    public let adguardUp: Bool

    /// Seconds since the agent process started.
    public let uptimeSeconds: Int64

    /// Build version string of the agent (e.g. `"0.0.1-m2-fix2"`).
    public let agentVersion: String

    /// Server's wall-clock time at the moment the response was built.
    public let serverTime: Date

    enum CodingKeys: String, CodingKey {
        case status
        case wgUp          = "wg_up"
        case adguardUp     = "adguard_up"
        case uptimeSeconds = "uptime_seconds"
        case agentVersion  = "agent_version"
        case serverTime    = "server_time"
    }
}
