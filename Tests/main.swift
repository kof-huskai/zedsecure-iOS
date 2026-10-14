import Foundation

// Command-line checks for ConfigBuilder (no XCTest needed, runs on any Mac / CI runner).
//   swiftc -o out/linktests Shared/Constants.swift Shared/Server.swift Shared/ConfigBuilder.swift Tests/main.swift
//   out/linktests [dump-directory]
// When a directory is given, every generated config is written there so the CI can
// validate them with the real `sing-box check`.

var failures = 0

func check(_ condition: Bool, _ message: String) {
    if !condition {
        failures += 1
        print("FAIL: \(message)")
    }
}

let dumpDirectory: String? = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : nil
if let dumpDirectory {
    try? FileManager.default.createDirectory(atPath: dumpDirectory, withIntermediateDirectories: true)
}

func build(_ name: String, _ link: String) -> [String: Any]? {
    do {
        let text = try ConfigBuilder.build(for: Server(name: name, rawLink: link))
        if let dumpDirectory {
            try text.write(toFile: "\(dumpDirectory)/\(name).json", atomically: true, encoding: .utf8)
        }
        guard let object = try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any] else {
            check(false, "\(name): config is not a JSON object")
            return nil
        }
        return object
    } catch {
        check(false, "\(name): unexpected error \(error)")
        return nil
    }
}

func proxy(_ config: [String: Any]?) -> [String: Any] {
    guard let outbounds = config?["outbounds"] as? [[String: Any]], let first = outbounds.first else {
        return [:]
    }
    return first
}

func expectFailure(_ name: String, _ link: String) {
    do {
        _ = try ConfigBuilder.build(for: Server(name: name, rawLink: link))
        check(false, "\(name): expected an error")
    } catch {
        // expected
    }
}

let uuid = "11111111-1111-1111-1111-111111111111"
let realityKey = "AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8"

// 1. VLESS + Reality + Vision
do {
    let link = "vless://\(uuid)@example.com:443?type=tcp&security=reality&pbk=\(realityKey)&sid=ab12&sni=www.microsoft.com&fp=chrome&flow=xtls-rprx-vision#Reality%20Test"
    let config = build("vless-reality", link)
    let outbound = proxy(config)
    let tls = outbound["tls"] as? [String: Any]
    let reality = tls?["reality"] as? [String: Any]
    check(outbound["type"] as? String == "vless", "vless type")
    check(outbound["server"] as? String == "example.com", "vless server")
    check(outbound["server_port"] as? Int == 443, "vless port")
    check(outbound["uuid"] as? String == uuid, "vless uuid")
    check(outbound["flow"] as? String == "xtls-rprx-vision", "vless flow")
    check(tls?["server_name"] as? String == "www.microsoft.com", "reality sni")
    check(reality?["public_key"] as? String == realityKey, "reality key")
    check(reality?["short_id"] as? String == "ab12", "reality short id")
    check((tls?["utls"] as? [String: Any])?["fingerprint"] as? String == "chrome", "reality utls")
    check(outbound["transport"] == nil, "vless tcp has no transport")
}

// 2. VLESS + WS + TLS
do {
    let link = "vless://\(uuid)@cdn.example.com:443?type=ws&security=tls&sni=cdn.example.com&host=front.example.com&path=%2Fvl%3Fed%3D2048&alpn=h2,http/1.1&fp=firefox#WS"
    let outbound = proxy(build("vless-ws", link))
    let transport = outbound["transport"] as? [String: Any]
    let tls = outbound["tls"] as? [String: Any]
    check(transport?["type"] as? String == "ws", "ws type")
    check(transport?["path"] as? String == "/vl?ed=2048", "ws path decoded")
    check((transport?["headers"] as? [String: Any])?["Host"] as? String == "front.example.com", "ws host header")
    check(tls?["alpn"] as? [String] == ["h2", "http/1.1"], "alpn list")
    check(outbound["flow"] == nil, "no flow when absent")
}

// 3. VLESS over gRPC + IPv6 literal host
do {
    let link = "vless://\(uuid)@[2001:db8::1]:8443?type=grpc&serviceName=svc&security=tls#v6"
    let outbound = proxy(build("vless-grpc-v6", link))
    check(outbound["server"] as? String == "2001:db8::1", "ipv6 host without brackets")
    check(outbound["server_port"] as? Int == 8443, "ipv6 port")
    check((outbound["transport"] as? [String: Any])?["service_name"] as? String == "svc", "grpc service")
}

// 4. VMess (base64 JSON), WS + TLS
do {
    let payload = "{\"v\":\"2\",\"ps\":\"vm\",\"add\":\"vm.example.com\",\"port\":\"443\",\"id\":\"\(uuid)\",\"aid\":\"0\",\"scy\":\"auto\",\"net\":\"ws\",\"type\":\"none\",\"host\":\"vm.example.com\",\"path\":\"/ws\",\"tls\":\"tls\",\"sni\":\"vm.example.com\"}"
    let link = "vmess://" + Data(payload.utf8).base64EncodedString()
    let outbound = proxy(build("vmess-ws", link))
    check(outbound["type"] as? String == "vmess", "vmess type")
    check(outbound["server"] as? String == "vm.example.com", "vmess server")
    check(outbound["server_port"] as? Int == 443, "vmess port from string")
    check(outbound["security"] as? String == "auto", "vmess security")
    check(outbound["alter_id"] as? Int == 0, "vmess alter id")
    check((outbound["transport"] as? [String: Any])?["path"] as? String == "/ws", "vmess ws path")
    check((outbound["tls"] as? [String: Any])?["server_name"] as? String == "vm.example.com", "vmess sni")
}

// 5. Trojan (TLS is on by default), password with escaped characters
do {
    let link = "trojan://pass%40word@tj.example.com:443?sni=tj.example.com&type=ws&path=%2Ftj&host=tj.example.com#TJ"
    let outbound = proxy(build("trojan-ws", link))
    check(outbound["type"] as? String == "trojan", "trojan type")
    check(outbound["password"] as? String == "pass@word", "trojan password decoded")
    check((outbound["tls"] as? [String: Any])?["enabled"] as? Bool == true, "trojan tls default on")
}

// 6. Shadowsocks SIP002 and legacy
do {
    let credentials = Data("chacha20-ietf-poly1305:secret".utf8).base64EncodedString()
        .replacingOccurrences(of: "=", with: "")
    let sip002 = proxy(build("ss-sip002", "ss://\(credentials)@ss.example.com:8388#SS"))
    check(sip002["type"] as? String == "shadowsocks", "ss type")
    check(sip002["method"] as? String == "chacha20-ietf-poly1305", "ss method")
    check(sip002["password"] as? String == "secret", "ss password")
    check(sip002["server_port"] as? Int == 8388, "ss port")

    let legacyPayload = Data("aes-256-gcm:pw@legacy.example.com:1234".utf8).base64EncodedString()
    let legacy = proxy(build("ss-legacy", "ss://\(legacyPayload)#old"))
    check(legacy["method"] as? String == "aes-256-gcm", "legacy ss method")
    check(legacy["server"] as? String == "legacy.example.com", "legacy ss host")
    check(legacy["server_port"] as? Int == 1234, "legacy ss port")
}

// 7. Hysteria2 with salamander obfuscation
do {
    let link = "hysteria2://hy2pass@hy.example.com:443?sni=hy.example.com&insecure=1&obfs=salamander&obfs-password=obfspw#HY2"
    let outbound = proxy(build("hysteria2", link))
    let tls = outbound["tls"] as? [String: Any]
    let obfs = outbound["obfs"] as? [String: Any]
    check(outbound["type"] as? String == "hysteria2", "hy2 type")
    check(outbound["password"] as? String == "hy2pass", "hy2 password")
    check(tls?["insecure"] as? Bool == true, "hy2 insecure")
    check(obfs?["type"] as? String == "salamander", "hy2 obfs type")
    check(obfs?["password"] as? String == "obfspw", "hy2 obfs password")
    check(proxy(build("hy2-scheme", "hy2://pw@h.example.com:443#x"))["type"] as? String == "hysteria2", "hy2 alias scheme")
}

// 8. Shape of the generated config
do {
    let config = build("shape", "vless://\(uuid)@example.com:443?security=none&type=tcp#plain")
    let inbounds = config?["inbounds"] as? [[String: Any]]
    let route = config?["route"] as? [String: Any]
    let dns = config?["dns"] as? [String: Any]
    check(inbounds?.first?["type"] as? String == "tun", "tun inbound")
    check((inbounds?.first?["address"] as? [String])?.first == "172.19.0.1/30", "tun v4 address")
    check(route?["final"] as? String == "proxy", "route final")
    check(route?["default_domain_resolver"] as? String == "dns-direct", "default domain resolver")
    check(dns?["final"] as? String == "dns-remote", "dns final")
    let rules = route?["rules"] as? [[String: Any]]
    check(rules?.contains(where: { $0["action"] as? String == "hijack-dns" }) == true, "dns hijack rule")
}

// 9. Things we must refuse instead of silently misconfiguring
expectFailure("xhttp", "vless://\(uuid)@x.example.com:443?type=xhttp&security=tls#x")
expectFailure("vless-encryption", "vless://\(uuid)@x.example.com:443?encryption=mlkem768x25519plus.native.0rtt.abc&security=tls#x")
expectFailure("ss-plugin", "ss://" + Data("aes-256-gcm:pw".utf8).base64EncodedString() + "@x.example.com:443/?plugin=obfs-local%3Bobfs%3Dhttp#x")
expectFailure("hy2-pin", "hysteria2://pw@x.example.com:443?pinSHA256=AA:BB#x")
expectFailure("reality-no-key", "vless://\(uuid)@x.example.com:443?security=reality&sni=a.com#x")
expectFailure("garbage", "not a link")
expectFailure("bad-port", "vless://\(uuid)@x.example.com:99999#x")
expectFailure("unknown-scheme", "wireguard://x@y.example.com:51820#x")

if failures == 0 {
    print("All ConfigBuilder checks passed")
} else {
    print("\(failures) check(s) failed")
    exit(1)
}
