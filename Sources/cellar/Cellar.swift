import ArgumentParser
import CellarCore
import Foundation

@main
struct Cellar: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "cellar",
        abstract: "Run Windows games on this Mac.",
        version: "cellar 0.0.1 (M0)",
        subcommands: [EngineCommand.self]
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
