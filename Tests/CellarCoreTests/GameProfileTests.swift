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

@Test func launchModeDefaultsToDirect() throws {
    let json = #"[{"id":"x","name":"X","appid":1,"exe":"x.exe","renderer":"wined3d"}]"#
    let profiles = try JSONDecoder().decode([GameProfile].self, from: Data(json.utf8))
    #expect(profiles.first?.launch == .direct)
    #expect(profiles.first?.saves == nil)
}
