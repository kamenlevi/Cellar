import Foundation
import Testing
@testable import CellarCore

/// `pmset -g assertions` while Rain World plays music (the coreaudiod line is from the M2 spike).
let pmsetWhilePlaying = """
2026-10-29 15:35:18 +0200
Assertion status system-wide:
   PreventUserIdleSystemSleep     1
Listed by owning process:
   pid 358(powerd): [0x0017344c000198a5] 00:08:54 PreventUserIdleSystemSleep named: "Powerd - Prevent sleep while display is on"
   pid 427(coreaudiod): [0x001734f100019a89] 00:00:43 PreventUserIdleSystemSleep named: "com.apple.audio.80-C3-BA-52-BD-A5:output.context.preventuseridlesleep"
	Resources: audio-out 80-C3-BA-52-BD-A5:output
   pid 427(coreaudiod): [0x001734f100019a90] 00:00:05 PreventUserIdleSystemSleep named: "com.apple.audio.BuiltInMicrophoneDevice:input.context.preventuseridlesleep"
	Resources: audio-in BuiltInMicrophoneDevice:input
Kernel Assertions: 0x104=USB,MAGICWAKE
"""

@Test func audioAssertionOnlyIfStartedSinceTheGame() {
    #expect(MacFacts.audioPlaying(assertions: pmsetWhilePlaying, startedWithin: 60))
    // 43 s old: sound on that output started before a 30 s-old game did, so it isn't the game's.
    #expect(!MacFacts.audioPlaying(assertions: pmsetWhilePlaying, startedWithin: 30))
    // The 5 s-old microphone assertion is input, not sound playing.
    #expect(!MacFacts.audioPlaying(assertions: pmsetWhilePlaying, startedWithin: 10))
    #expect(!MacFacts.audioPlaying(assertions: "", startedWithin: 60))
}

@Test func librariesAreBasenames() {
    let lsof = """
    p81300
    fcwd
    n/Users/kamen/Library/Application Support/Cellar/bottles/Steam/prefix/drive_c/Program Files (x86)/Steam/steamapps/common/Rain World
    ftxt
    n/Users/kamen/Library/Application Support/Cellar/renderers/d3dmetal/3.0/external/D3DMetal.framework/Versions/A/D3DMetal
    ftxt
    n/Users/kamen/Library/Application Support/Cellar/renderers/d3dmetal/3.0/wine/x86_64-windows/d3d11.dll
    f12
    nlocalhost:52100->localhost:27060
    """
    let libraries = MacFacts.loadedLibraries(lsof: lsof)
    #expect(libraries.contains("D3DMetal"))
    #expect(libraries.contains("d3d11.dll"))
    #expect(!libraries.contains { $0.contains("/") || $0.contains("localhost") })
}

@Test func gamePidComesFromItsExePath() {
    let ps = """
      81290 C:\\windows\\system32\\conhost.exe --server 0x3c
      81300 /Users/kamen/Library/Application Support/Cellar/bottles/Steam/prefix/drive_c/Program Files (x86)/Steam/steamapps/common/Rain World/RainWorld.exe
      81301 grep RainWorld.exe now
      81400 C:\\Program Files (x86)\\Steam\\steamapps\\common\\Animal Well\\Animal Well.exe
    """
    #expect(MacFacts.pid(ofExe: "RainWorld.exe", ps: ps) == 81300)
    #expect(MacFacts.pid(ofExe: "Animal Well.exe", ps: ps) == 81400)
    #expect(MacFacts.pid(ofExe: "OuterWilds.exe", ps: ps) == nil)
}
