import Foundation

public enum InstallState: Equatable, Sendable {
    case installed(folder: URL)
    case downloading
    case notInstalled
}

/// What Steam's own manifests say about a game in the Steam bottle.
public enum SteamLibrary {
    /// steamapps/appmanifest_<appid>.acf: "StateFlags" 4 means fully installed; "installdir" names its folder in steamapps/common.
    public static func state(appid: Int, steamFolder: URL) -> InstallState {
        let apps = steamFolder.appending(path: "steamapps", directoryHint: .isDirectory)
        guard let text = try? String(contentsOf: apps.appending(path: "appmanifest_\(appid).acf"), encoding: .utf8) else {
            return .notInstalled
        }
        guard value("StateFlags", in: text) == "4", let dir = value("installdir", in: text) else { return .downloading }
        return .installed(folder: apps.appending(path: "common/\(dir)", directoryHint: .isDirectory))
    }

    /// `"key"<tabs>"value"` on one line of a Valve KeyValues file.
    static func value(_ key: String, in text: String) -> String? {
        for line in text.split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: "\"", omittingEmptySubsequences: false)
            if parts.count >= 4, parts[1] == key { return String(parts[3]) }
        }
        return nil
    }
}
