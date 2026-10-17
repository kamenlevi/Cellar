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
