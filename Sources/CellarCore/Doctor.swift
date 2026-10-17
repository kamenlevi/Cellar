import Foundation

public struct Check: Sendable, Equatable {
    public let name: String
    public let ok: Bool
    public let fix: String?
    /// An optional check failing does not make `cellar doctor` fail.
    public let optional: Bool
}

public enum DoctorError: Error, CustomStringConvertible {
    case rosettaMissing

    public var description: String {
        "Rosetta 2 is not installed. Run: softwareupdate --install-rosetta --agree-to-license"
    }
}

/// Checks the Mac has what Cellar needs, and says exactly how to fix what's missing.
public struct Doctor: Sendable {
    public static let minimumFreeBytes: Int64 = 5_000_000_000
    public static let gptkURL = "https://developer.apple.com/games/game-porting-toolkit/"

    let paths: CellarPaths
    let rosettaProbe: @Sendable () -> Bool
    let freeBytes: @Sendable () -> Int64

    public init(paths: CellarPaths,
                rosettaProbe: @escaping @Sendable () -> Bool = Doctor.systemRosettaProbe,
                freeBytes: @escaping @Sendable () -> Int64 = Doctor.systemFreeBytes) {
        self.paths = paths
        self.rosettaProbe = rosettaProbe
        self.freeBytes = freeBytes
    }

    public func run() throws -> [Check] {
        let engineInstalled = try !EngineStore(paths: paths).installed().isEmpty
        let d3dmetal = try D3DMetalStore(paths: paths).current()
        return [
            Check(name: "Rosetta 2", ok: rosettaProbe(),
                  fix: "Run: softwareupdate --install-rosetta --agree-to-license", optional: false),
            Check(name: "Engine", ok: engineInstalled, fix: "Run: cellar engine install", optional: false),
            Check(name: "D3DMetal", ok: d3dmetal != nil,
                  fix: "Sign in at \(Self.gptkURL) (free Apple account), download the Game Porting Toolkit .dmg, then run: cellar d3dmetal import ~/Downloads/<file>.dmg",
                  optional: true),
            Check(name: "Free disk space ≥ 5 GB", ok: freeBytes() >= Self.minimumFreeBytes,
                  fix: "Free up space on the startup disk", optional: false),
        ]
    }

    public func requireRosetta() throws {
        guard rosettaProbe() else { throw DoctorError.rosettaMissing }
    }

    public static let systemRosettaProbe: @Sendable () -> Bool = {
        let p = Process()
        p.executableURL = URL(filePath: "/usr/bin/arch")
        p.arguments = ["-x86_64", "/usr/bin/true"]
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return false }
        p.waitUntilExit()
        return p.terminationStatus == 0
    }

    public static let systemFreeBytes: @Sendable () -> Int64 = {
        let values = try? URL(filePath: "/").resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage ?? 0
    }
}
