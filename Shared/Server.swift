import Foundation

/// A saved server. `rawLink` is the original share link (vless://, vmess://, trojan://, ss://, hy2://, ...).
/// Converting a link into a sing-box JSON config is done in `ConfigBuilder` (TODO).
struct Server: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var rawLink: String
}

enum ServerStore {
    static func load() -> [Server] {
        guard let data = UserDefaults.shared.data(forKey: AppConstants.serversKey),
              let list = try? JSONDecoder().decode([Server].self, from: data) else { return [] }
        return list
    }

    static func save(_ servers: [Server]) {
        if let data = try? JSONEncoder().encode(servers) {
            UserDefaults.shared.set(data, forKey: AppConstants.serversKey)
        }
    }
}
