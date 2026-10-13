import Foundation
import NetworkExtension

@MainActor
final class TunnelManager: ObservableObject {
    @Published private(set) var status: NEVPNStatus = .disconnected
    private var manager: NETunnelProviderManager?
    private var observer: NSObjectProtocol?

    func load() async {
        do {
            let all = try await NETunnelProviderManager.loadAllFromPreferences()
            if let m = all.first {
                manager = m
                observe(m)
                status = m.connection.status
            }
        } catch {
            print("load failed: \(error)")
        }
    }

    func connect(config: String) async throws {
        let m = manager ?? NETunnelProviderManager()

        let proto = NETunnelProviderProtocol()
        proto.providerBundleIdentifier = AppConstants.tunnelBundleId
        proto.serverAddress = "ZedSecure"
        proto.providerConfiguration = ["config": config]

        m.protocolConfiguration = proto
        m.localizedDescription = "ZedSecure"
        m.isEnabled = true

        try await m.saveToPreferences()
        try await m.loadFromPreferences()

        manager = m
        observe(m)
        try (m.connection as? NETunnelProviderSession)?.startVPNTunnel()
    }

    func disconnect() {
        manager?.connection.stopVPNTunnel()
    }

    private func observe(_ m: NETunnelProviderManager) {
        if let observer { NotificationCenter.default.removeObserver(observer) }
        status = m.connection.status
        observer = NotificationCenter.default.addObserver(
            forName: .NEVPNStatusDidChange, object: m.connection, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.status = m.connection.status }
        }
    }
}
