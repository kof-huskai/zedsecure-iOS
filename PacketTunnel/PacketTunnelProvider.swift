import Foundation
import Libbox
import NetworkExtension

/// Runs sing-box inside the Network Extension. The app hands over a ready sing-box
/// JSON config through `providerConfiguration["config"]` (see ConfigBuilder).
final class PacketTunnelProvider: NEPacketTunnelProvider {
    private var commandServer: LibboxCommandServer?
    private lazy var platformInterface = PlatformInterface(self)
    private var configContent: String?

    override func startTunnel(options _: [String: NSObject]?) async throws {
        guard let proto = protocolConfiguration as? NETunnelProviderProtocol,
              let config = proto.providerConfiguration?["config"] as? String,
              !config.isEmpty
        else {
            throw TunnelError("missing config")
        }
        configContent = config

        guard let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: AppConstants.appGroup) else {
            throw TunnelError("app group container unavailable: \(AppConstants.appGroup)")
        }
        let basePath = container.path
        let workingPath = container.appendingPathComponent("Working", isDirectory: true).path
        let tempPath = container.appendingPathComponent("Caches", isDirectory: true).path

        let setup = LibboxSetupOptions()
        setup.basePath = basePath
        setup.workingPath = workingPath
        setup.tempPath = tempPath
        setup.logMaxLines = 3000

        var setupError: NSError?
        LibboxSetup(setup, &setupError)
        if let setupError {
            throw TunnelError("setup: \(setupError.localizedDescription)")
        }

        // Network Extensions are killed at ~50 MB on iOS; this makes the Go runtime respect that.
        LibboxSetMemoryLimit(true)

        var serverError: NSError?
        commandServer = LibboxNewCommandServer(platformInterface, platformInterface, &serverError)
        if let serverError {
            throw TunnelError("create command server: \(serverError.localizedDescription)")
        }
        do {
            try commandServer!.start()
        } catch {
            throw TunnelError("start command server: \(error.localizedDescription)")
        }

        try await startService()
    }

    private func startService() async throws {
        guard let config = configContent else {
            throw TunnelError("missing config")
        }
        let overrideOptions = LibboxOverrideOptions()
        do {
            try commandServer!.startOrReloadService(config, options: overrideOptions)
        } catch {
            throw TunnelError("start service: \(error.localizedDescription)")
        }
    }

    func stopService() {
        do {
            try commandServer?.closeService()
        } catch {
            writeMessage("stop service: \(error.localizedDescription)")
        }
        platformInterface.reset()
    }

    func reloadService() async throws {
        writeMessage("reloading service")
        reasserting = true
        defer { reasserting = false }
        try await startService()
    }

    override func stopTunnel(with reason: NEProviderStopReason) async {
        writeMessage("stopping, reason: \(reason.rawValue)")
        stopService()
        if let server = commandServer {
            try? await Task.sleep(nanoseconds: 100 * NSEC_PER_MSEC)
            server.close()
            commandServer = nil
        }
    }

    override func sleep() async {
        commandServer?.pause()
    }

    override func wake() {
        commandServer?.wake()
    }

    func writeMessage(_ message: String) {
        commandServer?.writeMessage(2, message: "(packet-tunnel) " + message)
    }
}

struct TunnelError: LocalizedError {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var errorDescription: String? {
        "(packet-tunnel) error: \(message)"
    }
}
