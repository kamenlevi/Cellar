import Foundation
import Testing
@testable import CellarCore

/// An appmanifest in Steam's real format (Windows line endings), e.g. for Outer Wilds.
func appManifest(appid: Int, name: String, installdir: String, stateFlags: Int) -> String {
    """
    "AppState"\r
    {\r
    \t"appid"\t\t"\(appid)"\r
    \t"name"\t\t"\(name)"\r
    \t"StateFlags"\t\t"\(stateFlags)"\r
    \t"installdir"\t\t"\(installdir)"\r
    \t"SizeOnDisk"\t\t"34878352"\r
    }\r

    """
}

private func steamFolder(_ tmp: TempRoot, flags: Int?, exe: Bool = true) throws -> URL {
    let steam = tmp.url.appending(path: "Steam")
    let apps = steam.appending(path: "steamapps")
    try FileManager.default.createDirectory(at: apps.appending(path: "common/Outer Wilds"), withIntermediateDirectories: true)
    if exe { try Data("MZ".utf8).write(to: apps.appending(path: "common/Outer Wilds/OuterWilds.exe")) }
    if let flags {
        try Data(appManifest(appid: 753640, name: "Outer Wilds", installdir: "Outer Wilds", stateFlags: flags).utf8)
            .write(to: apps.appending(path: "appmanifest_753640.acf"))
    }
    return steam
}

@Test func installedManifestIsFound() throws {
    let tmp = try TempRoot()
    let steam = try steamFolder(tmp, flags: 4)
    #expect(SteamLibrary.state(appid: 753640, steamFolder: steam)
            == .installed(folder: steam.appending(path: "steamapps/common/Outer Wilds", directoryHint: .isDirectory)))
}

@Test func downloadingManifestIsNotPlayable() throws {
    let tmp = try TempRoot()
    #expect(SteamLibrary.state(appid: 753640, steamFolder: try steamFolder(tmp, flags: 1026)) == .downloading)
}

@Test func missingManifestIsNotInstalled() throws {
    let tmp = try TempRoot()
    #expect(SteamLibrary.state(appid: 753640, steamFolder: try steamFolder(tmp, flags: nil)) == .notInstalled)
}
