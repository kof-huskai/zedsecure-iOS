import Foundation

// Turns a share link (vless://, vmess://, trojan://, ss://, hysteria2://, hy2://)
// into a complete sing-box (v1.13) JSON config with a TUN inbound.
//
// Pure Foundation, no UIKit/NetworkExtension, so it compiles in both targets
// and in the command-line tests under Tests/.

enum ConfigError: LocalizedError {
    case invalid(String)
    case unsupported(String)

    var errorDescription: String? {
        switch self {
        case let .invalid(message): return "Invalid link: \(message)"
        case let .unsupported(message): return "Not supported yet: \(message)"
        }
    }
}

struct ParsedLink {
    var scheme: String
    var userinfo: String
    var host: String
    var port: Int
    var query: [String: String]
    var fragment: String
}

enum LinkParser {
    static func decodeBase64(_ input: String) -> Data? {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let padding = (4 - text.count % 4) % 4
        text += String(repeating: "=", count: padding)
        return Data(base64Encoded: text)
    }

    static func decodeBase64String(_ input: String) -> String? {
        guard let data = decodeBase64(input) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func parseQuery(_ query: String) -> [String: String] {
        var result: [String: String] = [:]
        for pair in query.split(separator: "&") {
            let parts = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard let first = parts.first else { continue }
            let key = String(first).removingPercentEncoding ?? String(first)
            let rawValue = parts.count > 1 ? String(parts[1]) : ""
            result[key] = rawValue.removingPercentEncoding ?? rawValue
        }
        return result
    }

    /// Splits scheme://userinfo@host:port?query#fragment without URLComponents,
    /// which rejects many real-world share links (unescaped unicode, odd characters).
    static func parse(_ link: String) throws -> ParsedLink {
        let trimmed = link.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let schemeRange = trimmed.range(of: "://") else {
            throw ConfigError.invalid("missing scheme")
        }
        let scheme = String(trimmed[..<schemeRange.lowerBound]).lowercased()
        var rest = String(trimmed[schemeRange.upperBound...])

        var fragment = ""
        if let hash = rest.firstIndex(of: "#") {
            let raw = String(rest[rest.index(after: hash)...])
            fragment = raw.removingPercentEncoding ?? raw
            rest = String(rest[..<hash])
        }

        var queryString = ""
        if let mark = rest.firstIndex(of: "?") {
            queryString = String(rest[rest.index(after: mark)...])
            rest = String(rest[..<mark])
        }
        while rest.hasSuffix("/") {
            rest.removeLast()
        }

        var userinfo = ""
        if let at = rest.lastIndex(of: "@") {
            userinfo = String(rest[..<at])
            rest = String(rest[rest.index(after: at)...])
        }

        var host = ""
        var portText = ""
        if rest.hasPrefix("[") {
            guard let close = rest.firstIndex(of: "]") else {
                throw ConfigError.invalid("bad IPv6 address")
            }
            host = String(rest[rest.index(after: rest.startIndex) ..< close])
            let after = rest[rest.index(after: close)...]
            if after.hasPrefix(":") {
                portText = String(after.dropFirst())
            }
        } else if let colon = rest.lastIndex(of: ":") {
            host = String(rest[..<colon])
            portText = String(rest[rest.index(after: colon)...])
        } else {
            host = rest
        }

        guard !host.isEmpty else { throw ConfigError.invalid("missing host") }
        guard let port = Int(portText), port > 0, port < 65536 else {
            throw ConfigError.invalid("bad port")
        }

        return ParsedLink(
            scheme: scheme,
            userinfo: userinfo.removingPercentEncoding ?? userinfo,
            host: host,
            port: port,
            query: parseQuery(queryString),
            fragment: fragment
        )
    }
}

enum ConfigBuilder {
    static let proxyTag = "proxy"

    /// Full sing-box config (JSON text) for one server.
    static func build(for server: Server) throws -> String {
        let outbound = try makeOutbound(from: server.rawLink)

        let config: [String: Any] = [
            "log": ["level": "warn", "timestamp": true],
            "dns": [
                "servers": [
                    ["type": "https", "tag": "dns-remote", "server": "1.1.1.1", "detour": proxyTag],
                    ["type": "local", "tag": "dns-direct"],
                ],
                "final": "dns-remote",
                "strategy": "ipv4_only",
            ],
            "inbounds": [
                [
                    "type": "tun",
                    "tag": "tun-in",
                    "address": ["172.19.0.1/30", "fdfe:dcba:9876::1/126"],
                    "mtu": 1400,
                    "auto_route": true,
                ],
            ],
            "outbounds": [
                outbound,
                ["type": "direct", "tag": "direct"],
            ],
            "route": [
                "auto_detect_interface": true,
                "default_domain_resolver": "dns-direct",
                "final": proxyTag,
                "rules": [
                    ["action": "sniff"],
                    ["protocol": "dns", "action": "hijack-dns"],
                    ["ip_is_private": true, "action": "route", "outbound": "direct"],
                ],
            ],
        ]

        let data = try JSONSerialization.data(
            withJSONObject: config,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        )
        guard let text = String(data: data, encoding: .utf8) else {
            throw ConfigError.invalid("could not encode config")
        }
        return text
    }

    // MARK: - Outbounds

    static func makeOutbound(from link: String) throws -> [String: Any] {
        let trimmed = link.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let schemeEnd = trimmed.range(of: "://") else {
            throw ConfigError.invalid("missing scheme")
        }
        let scheme = String(trimmed[..<schemeEnd.lowerBound]).lowercased()
        switch scheme {
        case "vless": return try vless(trimmed)
        case "vmess": return try vmess(trimmed)
        case "trojan": return try trojan(trimmed)
        case "ss": return try shadowsocks(trimmed)
        case "hysteria2", "hy2": return try hysteria2(trimmed)
        default: throw ConfigError.unsupported("\(scheme):// links")
        }
    }

    private static func vless(_ link: String) throws -> [String: Any] {
        let parsed = try LinkParser.parse(link)
        let query = parsed.query
        guard !parsed.userinfo.isEmpty else { throw ConfigError.invalid("missing uuid") }
        if let encryption = query["encryption"], !encryption.isEmpty, encryption != "none" {
            throw ConfigError.unsupported("VLESS encryption")
        }

        var outbound: [String: Any] = [
            "type": "vless",
            "tag": proxyTag,
            "server": parsed.host,
            "server_port": parsed.port,
            "uuid": parsed.userinfo,
            "packet_encoding": "xudp",
        ]
        if let flow = query["flow"], !flow.isEmpty {
            outbound["flow"] = flow
        }
        if let tls = try tlsOptions(query, defaultSecurity: "none") {
            outbound["tls"] = tls
        }
        if let transport = try transportOptions(query) {
            outbound["transport"] = transport
        }
        return outbound
    }

    private static func trojan(_ link: String) throws -> [String: Any] {
        let parsed = try LinkParser.parse(link)
        guard !parsed.userinfo.isEmpty else { throw ConfigError.invalid("missing password") }

        var outbound: [String: Any] = [
            "type": "trojan",
            "tag": proxyTag,
            "server": parsed.host,
            "server_port": parsed.port,
            "password": parsed.userinfo,
        ]
        if let tls = try tlsOptions(parsed.query, defaultSecurity: "tls") {
            outbound["tls"] = tls
        }
        if let transport = try transportOptions(parsed.query) {
            outbound["transport"] = transport
        }
        return outbound
    }

    private static func vmess(_ link: String) throws -> [String: Any] {
        let body = String(link.dropFirst("vmess://".count))
        let payload = body.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false).first.map { String($0) } ?? body
        guard let data = LinkParser.decodeBase64(payload),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            throw ConfigError.invalid("vmess payload is not base64 JSON")
        }

        func text(_ key: String) -> String {
            guard let value = object[key] else { return "" }
            if let string = value as? String { return string }
            if let number = value as? NSNumber { return number.stringValue }
            return ""
        }

        let host = text("add")
        guard !host.isEmpty, let port = Int(text("port")), port > 0, port < 65536 else {
            throw ConfigError.invalid("vmess address or port")
        }
        let uuid = text("id")
        guard !uuid.isEmpty else { throw ConfigError.invalid("missing uuid") }

        var query: [String: String] = [:]
        let network = text("net").isEmpty ? "tcp" : text("net")
        query["type"] = network
        query["host"] = text("host")
        query["path"] = text("path")
        if network == "grpc" {
            query["serviceName"] = text("path")
        }
        if text("type") == "http" {
            query["headerType"] = "http"
        }
        query["security"] = text("tls") == "tls" ? "tls" : "none"
        query["sni"] = text("sni")
        query["alpn"] = text("alpn")
        query["fp"] = text("fp")
        if text("allowInsecure") == "1" || text("insecure") == "1" {
            query["allowInsecure"] = "1"
        }

        var outbound: [String: Any] = [
            "type": "vmess",
            "tag": proxyTag,
            "server": host,
            "server_port": port,
            "uuid": uuid,
            "security": text("scy").isEmpty ? "auto" : text("scy"),
            "alter_id": Int(text("aid")) ?? 0,
        ]
        if let tls = try tlsOptions(query, defaultSecurity: "none") {
            outbound["tls"] = tls
        }
        if let transport = try transportOptions(query) {
            outbound["transport"] = transport
        }
        return outbound
    }

    private static func shadowsocks(_ link: String) throws -> [String: Any] {
        var method = ""
        var password = ""
        var host = ""
        var port = 0
        var query: [String: String] = [:]

        let afterScheme = String(link.dropFirst("ss://".count))
        if afterScheme.contains("@") {
            // SIP002: ss://userinfo@host:port/?plugin=...#name
            let parsed = try LinkParser.parse(link)
            host = parsed.host
            port = parsed.port
            query = parsed.query
            let credentials: String
            if parsed.userinfo.contains(":") {
                credentials = parsed.userinfo
            } else if let decoded = LinkParser.decodeBase64String(parsed.userinfo) {
                credentials = decoded
            } else {
                throw ConfigError.invalid("shadowsocks credentials")
            }
            guard let colon = credentials.firstIndex(of: ":") else {
                throw ConfigError.invalid("shadowsocks credentials")
            }
            method = String(credentials[..<colon])
            password = String(credentials[credentials.index(after: colon)...])
        } else {
            // Legacy: ss://BASE64(method:password@host:port)#name
            let payload = afterScheme.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false).first.map { String($0) } ?? afterScheme
            guard let decoded = LinkParser.decodeBase64String(payload),
                  let at = decoded.lastIndex(of: "@"),
                  let colon = decoded[..<at].firstIndex(of: ":"),
                  let hostColon = decoded[decoded.index(after: at)...].lastIndex(of: ":"),
                  let parsedPort = Int(decoded[decoded.index(after: hostColon)...])
            else {
                throw ConfigError.invalid("legacy shadowsocks payload")
            }
            method = String(decoded[..<colon])
            password = String(decoded[decoded.index(after: colon) ..< at])
            host = String(decoded[decoded.index(after: at) ..< hostColon])
            port = parsedPort
        }

        if let plugin = query["plugin"], !plugin.isEmpty {
            throw ConfigError.unsupported("Shadowsocks plugins (\(plugin.split(separator: ";").first ?? ""))")
        }
        guard !method.isEmpty, !password.isEmpty, !host.isEmpty, port > 0, port < 65536 else {
            throw ConfigError.invalid("shadowsocks fields")
        }
        return [
            "type": "shadowsocks",
            "tag": proxyTag,
            "server": host,
            "server_port": port,
            "method": method,
            "password": password,
        ]
    }

    private static func hysteria2(_ link: String) throws -> [String: Any] {
        let parsed = try LinkParser.parse(link)
        let query = parsed.query
        guard !parsed.userinfo.isEmpty else { throw ConfigError.invalid("missing password") }
        if let pin = query["pinSHA256"], !pin.isEmpty {
            throw ConfigError.unsupported("hysteria2 pinSHA256")
        }

        var tls: [String: Any] = ["enabled": true, "alpn": ["h3"]]
        if let sni = query["sni"], !sni.isEmpty {
            tls["server_name"] = sni
        }
        if isTrue(query["insecure"]) || isTrue(query["allowInsecure"]) {
            tls["insecure"] = true
        }

        var outbound: [String: Any] = [
            "type": "hysteria2",
            "tag": proxyTag,
            "server": parsed.host,
            "server_port": parsed.port,
            "password": parsed.userinfo,
            "tls": tls,
        ]
        if let obfs = query["obfs"], !obfs.isEmpty {
            guard obfs == "salamander" else { throw ConfigError.unsupported("hysteria2 obfs \(obfs)") }
            outbound["obfs"] = ["type": "salamander", "password": query["obfs-password"] ?? ""]
        }
        return outbound
    }

    // MARK: - Shared pieces

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value = value, !value.isEmpty else { return nil }
        return value
    }

    private static func isTrue(_ value: String?) -> Bool {
        guard let value = value?.lowercased() else { return false }
        return value == "1" || value == "true"
    }

    private static func tlsOptions(_ query: [String: String], defaultSecurity: String) throws -> [String: Any]? {
        let security = (nonEmpty(query["security"]) ?? defaultSecurity).lowercased()
        if security == "none" { return nil }
        guard security == "tls" || security == "reality" else {
            throw ConfigError.unsupported("security=\(security)")
        }

        var tls: [String: Any] = ["enabled": true]
        if let sni = query["sni"] ?? query["peer"], !sni.isEmpty {
            tls["server_name"] = sni
        }
        if isTrue(query["allowInsecure"]) || isTrue(query["insecure"]) {
            tls["insecure"] = true
        }
        if let alpn = query["alpn"], !alpn.isEmpty {
            tls["alpn"] = alpn.split(separator: ",").map { String($0) }
        }

        var fingerprint = query["fp"] ?? ""
        if fingerprint == "none" { fingerprint = "" }
        if security == "reality" {
            guard let publicKey = query["pbk"], !publicKey.isEmpty else {
                throw ConfigError.invalid("reality needs pbk")
            }
            if fingerprint.isEmpty { fingerprint = "chrome" }
            tls["reality"] = [
                "enabled": true,
                "public_key": publicKey,
                "short_id": query["sid"] ?? "",
            ]
        }
        if !fingerprint.isEmpty {
            tls["utls"] = ["enabled": true, "fingerprint": fingerprint]
        }
        return tls
    }

    private static func transportOptions(_ query: [String: String]) throws -> [String: Any]? {
        let type = (nonEmpty(query["type"]) ?? "tcp").lowercased()
        let host = query["host"] ?? ""
        let path = nonEmpty(query["path"]) ?? "/"

        switch type {
        case "tcp", "raw":
            if query["headerType"] == "http" {
                throw ConfigError.unsupported("TCP HTTP header obfuscation")
            }
            return nil
        case "ws":
            var transport: [String: Any] = ["type": "ws", "path": path]
            if !host.isEmpty {
                transport["headers"] = ["Host": host]
            }
            return transport
        case "grpc":
            return ["type": "grpc", "service_name": query["serviceName"] ?? ""]
        case "http", "h2":
            var transport: [String: Any] = ["type": "http", "path": path]
            if !host.isEmpty {
                transport["host"] = host.split(separator: ",").map { String($0) }
            }
            return transport
        case "httpupgrade":
            var transport: [String: Any] = ["type": "httpupgrade", "path": path]
            if !host.isEmpty {
                transport["host"] = host
            }
            return transport
        case "xhttp", "splithttp":
            throw ConfigError.unsupported("XHTTP transport (needs the Xray core)")
        default:
            throw ConfigError.unsupported("transport \(type)")
        }
    }
}
