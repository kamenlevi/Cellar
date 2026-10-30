import Foundation

// Every error Cellar shows reads as a sentence, with the command that fixes it where there is one.

extension BottleError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidName(let name): "\"\(name)\" can't be a bottle name."
        case .exists(let name): "A bottle called \"\(name)\" already exists."
        case .notFound(let name): "There is no bottle called \"\(name)\"."
        case .setupFailed(let reason): "Setting up the bottle failed (\(reason))."
        }
    }

    public var recoverySuggestion: String? {
        switch self {
        case .invalidName: "Use up to 64 characters, without / or : and not starting with a dot."
        case .exists: "Pick another name, or run: cellar bottle list"
        case .notFound: "Run: cellar bottle list"
        case .setupFailed: "See the log in ~/Library/Logs/Cellar/"
        }
    }
}

extension EngineError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .checksumMismatch: "The engine download was damaged (its checksum doesn't match), so nothing was installed."
        case .badLayout(let reason): "The engine isn't laid out as expected (\(reason))."
        case .notInstalled(let id): "The engine \(id) isn't installed."
        case .invalidId(let id): "\"\(id)\" isn't a valid engine name."
        }
    }

    public var recoverySuggestion: String? {
        switch self {
        case .checksumMismatch: "Try again: cellar engine install"
        case .badLayout: nil
        case .notInstalled: "Run: cellar engine install"
        case .invalidId: "Run: cellar engine list"
        }
    }
}

extension D3DMetalError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .notFound(let source): "No D3DMetal was found in \(source)."
        case .mountFailed(let name): "The disk image \(name) couldn't be opened."
        }
    }

    public var recoverySuggestion: String? {
        "Download \"Evaluation environment for Windows games\" from \(Doctor.gptkURL) and import that .dmg."
    }
}

extension DoctorError: LocalizedError {
    public var errorDescription: String? { "Rosetta 2 is not installed." }
    public var recoverySuggestion: String? { "Run: softwareupdate --install-rosetta --agree-to-license" }
}

extension SteamError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .notInstalled: "Steam isn't installed in Cellar yet."
        case .badInstaller(let reason): "The Steam installer download wasn't valid (\(reason)), so nothing was run."
        case .installFailed(let reason): "Steam's installer finished but Steam.exe isn't there (\(reason))."
        case .noWindow: "Steam started but its window never appeared, even after one automatic restart."
        case .signedInElsewhere: "Steam is signed out, because your account signed in on Steam for Mac."
        }
    }

    public var recoverySuggestion: String? {
        switch self {
        case .notInstalled: "Run: cellar steam install"
        case .badInstaller: "Try again: cellar steam install"
        case .installFailed: "See the log: ~/Library/Logs/Cellar/Steam.log"
        case .noWindow: "Run: cellar steam restart. If it keeps happening, the log is ~/Library/Logs/Cellar/Steam.log"
        case .signedInElsewhere: "Quit Steam for Mac (Steam ▸ Quit Steam), then run: cellar steam"
        }
    }
}

extension RendererError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .d3dmetalNotImported: "This game needs Apple's D3DMetal, which isn't imported yet."
        case .d3dmetalNeeds64Bit(let name): "\(name) is a 32-bit program, and D3DMetal only runs 64-bit ones."
        }
    }

    public var recoverySuggestion: String? {
        switch self {
        case .d3dmetalNotImported: "Run: cellar d3dmetal import ~/Downloads/<Evaluation environment for Windows games>.dmg"
        case .d3dmetalNeeds64Bit: "Set its renderer to dxvk in games.json."
        }
    }
}

extension GameError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .unknownGame(let q): "Cellar doesn't know a game called \"\(q)\" yet."
        case .notInstalled(let name): "\(name) isn't installed in Cellar's Steam."
        case .stillDownloading(let name): "\(name) is still downloading."
        case .steamNotSignedIn: "Steam didn't sign in within 90 seconds."
        case .steamIgnoredLaunch(let name): "Steam didn't start \(name), even after Cellar restarted it."
        case .steamIgnoredLaunchBeside(let name, let other):
            "Steam didn't start \(name). Cellar didn't restart Steam, because \(other) is running beside it."
        case .steamStillInstalling(let name, let installer):
            "Steam is still installing something \(name) needs (\(installer)), so the game hasn't started yet."
        case .steamWaitingForYou(let name): "Steam is waiting for you to answer something in its window before it starts \(name)."
        }
    }

    public var recoverySuggestion: String? {
        switch self {
        case .unknownGame: "Known games: \(((try? GameProfiles.bundled()) ?? []).map(\.id).joined(separator: ", "))"
        case .notInstalled: "Install it in the Steam window first (open it with: cellar steam)."
        case .stillDownloading: "Wait until Steam shows it as ready, then try again."
        case .steamNotSignedIn: "Sign in in the Steam window (cellar steam), then try again."
        case .steamIgnoredLaunch: "Try Play in the Steam window (cellar steam). If that does nothing too, tell Claude."
        case .steamIgnoredLaunchBeside(_, let other): "Quit \(other), then try again."
        case .steamStillInstalling: "Let it finish (it may show a window of its own), then try again."
        case .steamWaitingForYou(let name): "Answer it in the Steam window (often a notice with an OK button); \(name) starts after that."
        }
    }
}
