import Foundation

enum AppConstants {
    // Must match the App Group in project.yml and your Apple Developer account.
    static let appGroup = "group.com.zedsecure"
    // Must match the PacketTunnel bundle id.
    static let tunnelBundleId = "com.zedsecure.PacketTunnel"
    static let selectedConfigKey = "selectedConfigJSON"
    static let serversKey = "servers"
}

extension UserDefaults {
    static var shared: UserDefaults {
        UserDefaults(suiteName: AppConstants.appGroup) ?? .standard
    }
}
