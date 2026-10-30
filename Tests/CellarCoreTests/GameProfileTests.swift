import Foundation
import Testing
@testable import CellarCore

@Test func bundledProfilesIncludeOuterWildsAndAnimalWell() throws {
    let profiles = try GameProfiles.bundled()
    let outerWilds = try #require(profiles.first { $0.appid == 753640 })
    #expect(outerWilds.id == "outer-wilds")
    #expect(outerWilds.exe == "OuterWilds.exe")
    let animalWell = try #require(profiles.first { $0.appid == 813230 })
    #expect(animalWell.renderer == .d3dmetal)
}

@Test(arguments: ["outer-wilds", "753640", "outer wilds", "Outer Wilds"])
func findByIdAppidOrName(_ query: String) throws {
    let profiles = try GameProfiles.bundled()
    #expect(GameProfiles.find(query, in: profiles)?.appid == 753640)
}

@Test func unknownGameIsNotFound() throws {
    #expect(GameProfiles.find("nope", in: try GameProfiles.bundled()) == nil)
}

@Test func gamesLaunchThroughSteamByDefault() throws {
    let json = #"[{"id":"x","name":"X","appid":1,"exe":"x.exe","renderer":"wined3d"}]"#
    let profiles = try JSONDecoder().decode([GameProfile].self, from: Data(json.utf8))
    #expect(profiles.first?.launch == .throughSteam)
    #expect(try GameProfiles.bundled().allSatisfy { $0.launch == .throughSteam })
    #expect(profiles.first?.saves == nil)
}

@Test func rainWorldNeeds60fpsAndOthersTheDisplay() throws {
    let profiles = try GameProfiles.bundled()
    #expect(GameProfiles.find("rain-world", in: profiles)?.fps == 60)
    #expect(GameProfiles.find("animal-well", in: profiles)?.fps == nil)
}

@Test func everyTargetGameHasAProfile() throws {
    let profiles = try GameProfiles.bundled()
    let journey = try #require(GameProfiles.find("journey", in: profiles))
    #expect(journey.appid == 638230 && journey.exe == "Journey.exe")
    #expect(journey.saves == "AppData/Local/Annapurna Interactive/Journey")
    #expect(GameProfiles.find("638230", in: profiles) == journey)
    let chants = try #require(GameProfiles.find("chants of sennaar", in: profiles))
    #expect(chants.id == "chants-of-sennaar" && chants.appid == 1931770 && chants.exe == "Chants Of Sennaar.exe")
    #expect(chants.saves == "AppData/LocalLow/Rundisc/Chants Of Sennaar")
    let leapYear = try #require(GameProfiles.find("leap-year", in: profiles))
    #expect(leapYear.appid == 2951770 && leapYear.exe == "Leap Year.exe" && leapYear.saves == nil)
    // Outer Wilds' physics runs at 60 Hz; 120 needs the game's own PhysicsRate file.
    #expect(GameProfiles.find("outer-wilds", in: profiles)?.fps == 60)
    #expect(profiles.allSatisfy { $0.renderer == .d3dmetal })
}
