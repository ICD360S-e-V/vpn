// ICD360SVPN — Features/Main/MainView.swift
// MARK: - Sidebar + detail layout for the connected state

import SwiftUI

struct MainView: View {
    let client: APIClient

    @State private var selection: SidebarItem? = .peers

    var body: some View {
        NavigationSplitView {
            List(SidebarItem.allCases, selection: $selection) { item in
                Label(item.title, systemImage: item.systemImage)
                    .tag(item as SidebarItem?)
            }
            .navigationSplitViewColumnWidth(min: 160, ideal: 180)
            .navigationTitle("ICD360S VPN")
        } detail: {
            switch selection {
            case .peers, .none:
                PeersView(client: client)
            case .health:
                HealthView(client: client)
            case .settings:
                SettingsView()
            }
        }
    }
}

enum SidebarItem: String, CaseIterable, Identifiable, Hashable {
    case peers, health, settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .peers:    return "Peers"
        case .health:   return "Health"
        case .settings: return "Settings"
        }
    }

    var systemImage: String {
        switch self {
        case .peers:    return "person.2"
        case .health:   return "heart.text.square"
        case .settings: return "gear"
        }
    }
}
