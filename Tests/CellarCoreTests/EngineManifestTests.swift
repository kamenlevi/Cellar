import Foundation
import Testing
@testable import CellarCore

@Test func bundledManifestPinsTheOneEngine() throws {
    let m = try EngineManifest.bundled()
    #expect(m.defaultEngine.id == "sikarugir-10.0_6-c1")
    #expect(m.defaultEngine.url.host() == "github.com")
    #expect(m.defaultEngine.url.path().hasPrefix("/kamenlevi/Cellar/releases/download/"))
    #expect(m.defaultEngine.sha256.count == 64)
    #expect(m.engines.filter(\.isDefault).count == 1)
}
