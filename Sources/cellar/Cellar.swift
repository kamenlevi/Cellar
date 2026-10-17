import ArgumentParser
import CellarCore
import Foundation

@main
struct Cellar: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "cellar",
        abstract: "Run Windows games on this Mac.",
        version: "cellar 0.0.1 (M0)",
        subcommands: [EngineCommand.self, BottleCommand.self, Run.self]
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
        let result = try await bottleStore().run(BottleName(bottle), program: program, arguments: arguments,
                                                 mode: headless ? .headless : .interactive)
        print(result.output, terminator: "")
        throw ExitCode(result.exitCode)
    }
}
