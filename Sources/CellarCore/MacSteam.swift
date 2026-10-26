import Foundation

/// Kamen's native Steam for Mac (/Applications/Steam.app) holds ports 27060/27036 that Windows Steam also wants.
public enum MacSteam {
    public static let isRunning: @Sendable () -> Bool = {
        let p = Process()
        p.executableURL = URL(filePath: "/usr/bin/pgrep")
        p.arguments = ["-x", "steam_osx"]
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return false }
        p.waitUntilExit()
        return p.terminationStatus == 0
    }
}
