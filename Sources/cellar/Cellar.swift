import ArgumentParser
import CellarCore

@main
struct Cellar: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "cellar",
        abstract: "Run Windows games on this Mac.",
        version: "cellar 0.0.1 (M0)"
    )
}
