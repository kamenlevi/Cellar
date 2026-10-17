import ArgumentParser
import CellarCore
import Foundation

@main
struct Cellar: AsyncParsableCommand {
    /// Cellar's own errors print as a sentence and the fix, not as Swift values.
    static func main() async {
        do {
            var command = try parseAsRoot()
            if var asyncCommand = command as? AsyncParsableCommand {
                try await asyncCommand.run()
            } else {
                try command.run()
            }
        } catch let error as LocalizedError where error.errorDescription != nil {
            var message = "Error: \(error.errorDescription!)"
            if let fix = error.recoverySuggestion { message += "\n  \(fix)" }
            FileHandle.standardError.write(Data((message + "\n").utf8))
            Foundation.exit(1)
        } catch {
            exit(withError: error)
        }
    }

    static let configuration = CommandConfiguration(
        commandName: "cellar",
        abstract: "Run Windows games on this Mac.",
        version: "cellar 0.0.1 (M0)",
        subcommands: [DoctorCommand.self, SteamCommand.self, EngineCommand.self, BottleCommand.self, Run.self, D3DMetalCommand.self]
    )
}

struct EngineCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "engine",
        abstract: "Install and manage Wine engines.",
        subcommands: [Install.self, List.self, Remove.self]
    )

    struct Install: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Download and install an engine (the default one if no id is given).")
        @Argument var id: String?

        func run() async throws {
            let manifest = try EngineManifest.bundled()
            let entry: EngineEntry
            if let id {
                guard let match = manifest.engines.first(where: { $0.id == id }) else {
                    throw ValidationError("No engine called \(id). Known: \(manifest.engines.map(\.id).joined(separator: ", "))")
                }
                entry = match
            } else {
                entry = manifest.defaultEngine
            }
            print("Installing \(entry.id) (Wine \(entry.wineVersion), \(entry.size / 1_000_000) MB)…")
            let engine = try await EngineStore(paths: CellarPaths()).install(entry)
            print("Installed at \(engine.root.path)")
        }
    }

    struct List: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "List installed engines.")
        func run() throws {
            let engines = try EngineStore(paths: CellarPaths()).installed()
            if engines.isEmpty { print("No engines installed. Run: cellar engine install") }
            for engine in engines { print(engine.id) }
        }
    }

    struct Remove: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Move an installed engine to the Trash.")
        @Argument var id: String
        func run() throws {
            try EngineStore(paths: CellarPaths()).remove(id: id)
            print("Moved \(id) to the Trash.")
        }
    }
}

func bottleStore() -> BottleStore {
    let paths = CellarPaths()
    return BottleStore(paths: paths, engines: EngineStore(paths: paths))
}

struct BottleCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "bottle",
        abstract: "Create and manage bottles (one Windows setup each).",
        subcommands: [Create.self, List.self, Remove.self, Kill.self]
    )

    struct Create: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Create a bottle.")
        @Argument var name: String
        @Option(help: "Engine id (default: the pinned default engine).") var engine: String?
        func run() async throws {
            try Doctor(paths: CellarPaths()).requireRosetta()
            let info = try await bottleStore().create(BottleName(name), engineId: engine)
            print("Created bottle \"\(info.name)\" on \(info.engineId).")
        }
    }

    struct List: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "List bottles.")
        func run() throws {
            let bottles = try bottleStore().list()
            if bottles.isEmpty { print("No bottles yet. Run: cellar bottle create <name>") }
            for b in bottles { print("\(b.name)\t\(b.engineId)") }
        }
    }

    struct Remove: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Move a bottle to the Trash.")
        @Argument var name: String
        func run() throws {
            try bottleStore().remove(BottleName(name))
            print("Moved bottle \"\(name)\" to the Trash.")
        }
    }

    struct Kill: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Stop everything running in one bottle (and nothing else).")
        @Argument var name: String
        func run() async throws {
            try await bottleStore().kill(BottleName(name))
            print("Stopped everything in \"\(name)\".")
        }
    }
}

struct Run: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Run a Windows program in a bottle.")
    @Flag(help: "No windows and no sound (for scripts and tests).") var headless = false
    @Argument var bottle: String
    @Argument var program: String
    @Argument(parsing: .captureForPassthrough) var arguments: [String] = []

    func run() async throws {
        try Doctor(paths: CellarPaths()).requireRosetta()
        let result = try await bottleStore().run(BottleName(bottle), program: program, arguments: arguments,
                                                 mode: headless ? .headless : .interactive)
        print(result.output, terminator: "")
        throw ExitCode(result.exitCode)
    }
}

struct DoctorCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "doctor", abstract: "Check this Mac has what Cellar needs.")
    func run() throws {
        let checks = try Doctor(paths: CellarPaths()).run()
        for c in checks {
            print("\(c.ok ? "✓" : (c.optional ? "–" : "✗")) \(c.name)\(c.optional && !c.ok ? " (optional for now)" : "")")
            if !c.ok, let fix = c.fix { print("    \(fix)") }
        }
        if checks.contains(where: { !$0.ok && !$0.optional }) { throw ExitCode(1) }
    }
}

struct D3DMetalCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "d3dmetal",
        abstract: "Apple's DirectX-to-Metal layer, from your own Game Porting Toolkit download.",
        subcommands: [Import.self, Status.self]
    )

    struct Import: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Import D3DMetal from the Game Porting Toolkit .dmg (or a folder).")
        @Argument(help: "The .dmg you downloaded from Apple, or a folder containing redist/lib.") var source: String
        func run() async throws {
            let url = URL(filePath: (source as NSString).expandingTildeInPath)
            let imported = try await D3DMetalStore(paths: CellarPaths()).importFrom(url)
            print("Imported D3DMetal \(imported.version).")
        }
    }

    struct Status: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Show which D3DMetal is imported.")
        func run() throws {
            if let current = try D3DMetalStore(paths: CellarPaths()).current() {
                print("D3DMetal \(current.version), imported \(current.importedAt.formatted()) from \(current.source)")
            } else {
                print("Not imported. Sign in at \(Doctor.gptkURL), download the Game Porting Toolkit .dmg, then run: cellar d3dmetal import ~/Downloads/<file>.dmg")
            }
        }
    }
}

func steamStore() -> SteamStore {
    let paths = CellarPaths()
    let engines = EngineStore(paths: paths)
    return SteamStore(paths: paths, bottles: BottleStore(paths: paths, engines: engines), engines: engines)
}

struct SteamCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "steam",
        abstract: "Windows Steam, in Cellar's shared \"Steam\" bottle. You sign in yourself.",
        subcommands: [Start.self, Install.self, Stop.self, Restart.self, Status.self],
        defaultSubcommand: Start.self
    )

    static func say(_ outcome: StartOutcome) {
        switch outcome {
        case .started: print("Starting Steam. Sign in with your own account in the Steam window.")
        case .broughtForward: print("Steam is already running; bringing its window forward.")
        case .clearedStaleStateThenStarted: print("Cleared a stuck Steam session, then started Steam.")
        }
    }

    static func warnAboutMacSteam() {
        if MacSteam.isRunning() {
            print("Note: Steam for Mac is running too. If Windows Steam can't connect, quit Steam for Mac (Steam ▸ Quit Steam) and run: cellar steam restart")
        }
    }

    struct Install: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Install Windows Steam into the \"Steam\" bottle.")
        func run() async throws {
            try Doctor(paths: CellarPaths()).requireRosetta()
            print("Installing Steam into the \"Steam\" bottle…")
            try await steamStore().install()
            print("Steam is installed. Start it with: cellar steam start")
        }
    }

    struct Start: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Start Steam, or bring its window forward if it's running.")
        func run() async throws {
            try Doctor(paths: CellarPaths()).requireRosetta()
            SteamCommand.warnAboutMacSteam()
            SteamCommand.say(try await steamStore().start())
        }
    }

    struct Stop: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Quit Steam and everything in its bottle.")
        func run() async throws {
            try Doctor(paths: CellarPaths()).requireRosetta()
            try await steamStore().stop()
            print("Steam stopped.")
        }
    }

    struct Restart: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Stop Steam, then start it again.")
        func run() async throws {
            try Doctor(paths: CellarPaths()).requireRosetta()
            SteamCommand.warnAboutMacSteam()
            SteamCommand.say(try await steamStore().restart())
        }
    }

    struct Status: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Is Steam installed, running, signed in and healthy?")
        func run() async throws {
            try Doctor(paths: CellarPaths()).requireRosetta()
            for line in try await steamStore().status().lines() { print(line) }
        }
    }
}
