import Foundation

public enum WineMode: Sendable {
    /// No windows, no sound: for setup steps, scripts and tests on a Mac someone is working on.
    case headless
    /// A normal run the player sees and hears.
    case interactive
}

public enum WineEnvironment {
    public static func make(
        engine: InstalledEngine,
        prefix: URL,
        mode: WineMode,
        base: [String: String] = ProcessInfo.processInfo.environment
    ) -> [String: String] {
        var env = base
        env["WINEPREFIX"] = prefix.path
        env["WINEDEBUG"] = "-all"
        // The engine's libraries are found through the fallback path, not baked-in rpaths.
        env["DYLD_FALLBACK_LIBRARY_PATH"] = [
            engine.frameworks.path,
            engine.frameworks.appending(path: "GStreamer.framework/Versions/1.0/lib").path,
            engine.root.appending(path: "wine/lib/wine/x86_64-unix").path,
            "/usr/lib",
        ].joined(separator: ":")
        env["PATH"] = [engine.wineBinary.deletingLastPathComponent().path, base["PATH"] ?? "/usr/bin:/bin"]
            .joined(separator: ":")

        // No Mono or Gecko install prompts during setup.
        var overrides = ["mscoree,mshtml="]
        if mode == .headless {
            overrides += ["winemac.drv=d", "winecoreaudio.drv=d"]
        }
        env["WINEDLLOVERRIDES"] = overrides.joined(separator: ";")
        return env
    }
}
