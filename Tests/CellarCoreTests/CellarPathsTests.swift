import Foundation
import Testing
@testable import CellarCore

@Test func defaultRootIsApplicationSupport() {
    let p = CellarPaths(environment: [:], home: URL(filePath: "/Users/k"))
    #expect(p.root.path == "/Users/k/Library/Application Support/Cellar")
    #expect(p.logs.path == "/Users/k/Library/Logs/Cellar")
    #expect(p.bottle("Outer Wilds").path == "/Users/k/Library/Application Support/Cellar/bottles/Outer Wilds")
}

@Test func cellarHomeOverridesEverything() {
    let p = CellarPaths(environment: ["CELLAR_HOME": "/tmp/ch"], home: URL(filePath: "/Users/k"))
    #expect(p.root.path == "/tmp/ch")
    #expect(p.logs.path == "/tmp/ch/logs")
    #expect(p.engine("sikarugir-10.0_6-c1").path == "/tmp/ch/engines/sikarugir-10.0_6-c1")
    #expect(p.d3dmetal.path == "/tmp/ch/renderers/d3dmetal")
    #expect(p.downloads.path == "/tmp/ch/downloads")
}
