import SwiftUI
import NetworkExtension

struct ContentView: View {
    @EnvironmentObject private var tunnel: TunnelManager
    @State private var servers: [Server] = ServerStore.load()
    @State private var selected: Server.ID?
    @State private var errorText: String?

    private var isOn: Bool { tunnel.status == .connected || tunnel.status == .connecting }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                List(selection: $selected) {
                    ForEach(servers) { server in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(server.name).font(.headline)
                            Text(server.rawLink).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                        .tag(server.id)
                    }
                    .onDelete { idx in
                        servers.remove(atOffsets: idx)
                        ServerStore.save(servers)
                    }
                }

                if let errorText {
                    Text(errorText).font(.footnote).foregroundStyle(.red).padding(.horizontal)
                }

                Button(action: toggle) {
                    Text(isOn ? "Disconnect" : "Connect")
                        .frame(maxWidth: .infinity)
                        .padding()
                }
                .buttonStyle(.borderedProminent)
                .tint(isOn ? .red : .accentColor)
                .disabled(selected == nil && !isOn)
                .padding()
            }
            .navigationTitle("ZedSecure")
            .toolbar {
                Button(action: pasteFromClipboard) {
                    Label("Paste", systemImage: "doc.on.clipboard")
                }
            }
    }

    private func pasteFromClipboard() {
        guard let text = UIPasteboard.general.string?.trimmingCharacters(in: .whitespacesAndNewlines),
              text.contains("://") else {
            errorText = "Clipboard does not contain a share link."
            return
        }
        errorText = nil
        let name = URLComponents(string: text)?.fragment?.removingPercentEncoding ?? "Server \(servers.count + 1)"
        servers.append(Server(name: name, rawLink: text))
        ServerStore.save(servers)
    }

    private func toggle() {
        if isOn {
            tunnel.disconnect()
            return
        }
        guard let server = servers.first(where: { $0.id == selected }) else { return }
        Task {
            do {
                errorText = nil
                try await tunnel.connect(config: ConfigBuilder.build(for: server))
            } catch {
                errorText = error.localizedDescription
            }
        }
    }
}
