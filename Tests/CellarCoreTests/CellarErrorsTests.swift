import Foundation
import Testing
@testable import CellarCore

@Test func bottleErrorsReadAsSentences() {
    #expect(BottleError.invalidName("a/b").errorDescription == #""a/b" can't be a bottle name."#)
    #expect(BottleError.invalidName("a/b").recoverySuggestion == "Use up to 64 characters, without / or : and not starting with a dot.")
    #expect(BottleError.notFound("Journey").errorDescription == #"There is no bottle called "Journey"."#)
    #expect(BottleError.notFound("Journey").recoverySuggestion == "Run: cellar bottle list")
    #expect(BottleError.exists("Journey").errorDescription == #"A bottle called "Journey" already exists."#)
}

@Test func engineErrorsSayWhatToRun() {
    #expect(EngineError.notInstalled("sikarugir-10.0_6-c1").recoverySuggestion == "Run: cellar engine install")
    #expect(EngineError.checksumMismatch(expected: "a", actual: "b").errorDescription
            == "The engine download was damaged (its checksum doesn't match), so nothing was installed.")
}

@Test func noErrorDescriptionLooksLikeSwift() {
    let all: [any LocalizedError] = [
        BottleError.invalidName("x"), BottleError.exists("x"), BottleError.notFound("x"), BottleError.setupFailed("wineboot exited 1"),
        EngineError.badLayout("x"), EngineError.invalidId("x"), EngineError.notInstalled("x"),
        EngineError.checksumMismatch(expected: "a", actual: "b"),
        D3DMetalError.notFound("/x"), D3DMetalError.mountFailed("x.dmg"), DoctorError.rosettaMissing,
    ]
    for e in all {
        #expect(!(e.errorDescription ?? "").contains("(\""), "\(e)")
        #expect(e.errorDescription?.hasSuffix(".") == true, "\(e)")
    }
}
