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
        // Wine settings from the user's shell (WINESERVER, WINELOADER, DYLD_LIBRARY_PATH…) would point
        // Cellar's prefix at someone else's Wine, so none of them get through.
        var env = base.filter { !$0.key.hasPrefix("WINE") && !$0.key.hasPrefix("DYLD_") }
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

        // No Mono or Gecko install prompts during setup, and no menu shortcuts written into the real home.
        var overrides = ["mscoree,mshtml=", "winemenubuilder.exe=d"]
        if mode == .headless {
            overrides += ["winemac.drv=d", "winecoreaudio.drv=d"]
        }
        env["WINEDLLOVERRIDES"] = overrides.joined(separator: ";")
        return env
    }
}
