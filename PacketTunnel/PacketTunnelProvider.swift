import NetworkExtension

/// Milestone 1 stub: validates the config handoff and brings up the virtual interface.
///
/// WARNING: until a proxy core is wired in below, packets entering the tunnel go nowhere,
/// so the device will have no internet while "connected".
///
/// Milestone 2 (TODO): embed sing-box `Libbox.xcframework` (tools/build-cores.sh),
/// implement its PlatformInterface using `packetFlow` / the tun file descriptor,
/// and start the service with the JSON from `ConfigBuilder`.
final class PacketTunnelProvider: NEPacketTunnelProvider {

    override func startTunnel(options: [String: NSObject]?) async throws {
        guard let proto = protocolConfiguration as? NETunnelProviderProtocol,
              let config = proto.providerConfiguration?["config"] as? String,
              !config.isEmpty else {
            throw NSError(domain: "ZedSecure", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Missing config"])
        }

        let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: "127.0.0.1")

        let ipv4 = NEIPv4Settings(addresses: ["172.19.0.1"], subnetMasks: ["255.255.255.252"])
        ipv4.includedRoutes = [NEIPv4Route.default()]
        settings.ipv4Settings = ipv4

        let dns = NEDNSSettings(servers: ["1.1.1.1", "8.8.8.8"])
        dns.matchDomains = [""]
        settings.dnsSettings = dns
        settings.mtu = 1400

        try await setTunnelNetworkSettings(settings)

        // TODO: start the core with `config` here.
        _ = config
    }

    override func stopTunnel(with reason: NEProviderStopReason) async {
        // TODO: stop the core here.
    }
}
