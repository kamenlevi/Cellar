import Foundation
import Testing
@testable import CellarCore

private func exe(_ data: Data) throws -> URL {
    let url = FileManager.default.temporaryDirectory.appending(path: "cellar-exe-\(UUID().uuidString).exe")
    try data.write(to: url)
    return url
}

@Test func sixtyFourBitD3D11GameIsRead() throws {
    let facts = try ExeFacts.read(try exe(PEFixture.make(machine: 0x8664, imports: ["KERNEL32.dll", "d3d11.dll", "dxgi.dll"])))
    #expect(facts.is64Bit)
    #expect(facts.imports.contains("d3d11.dll"))
    #expect(facts.imports.contains("kernel32.dll"))
    #expect(facts.directX == 11)
}

@Test func thirtyTwoBitIsNotSixtyFour() throws {
    #expect(try !ExeFacts.read(try exe(PEFixture.make(machine: 0x14c, imports: ["d3d11.dll"]))).is64Bit)
}

@Test func d3d10ImportMeansDirectX10() throws {
    #expect(try ExeFacts.read(try exe(PEFixture.make(machine: 0x8664, imports: ["d3d10_1.dll"]))).directX == 10)
}

@Test func noDirectXImportIsNil() throws {
    #expect(try ExeFacts.read(try exe(PEFixture.make(machine: 0x8664, imports: ["user32.dll"]))).directX == nil)
}

@Test func textFileIsNotAWindowsProgram() throws {
    #expect(throws: ExeFactsError.notAWindowsProgram) { try ExeFacts.read(try exe(Data("hello".utf8))) }
    // A real header cut short is not a Windows program either, and must not trap.
    let cut = PEFixture.make(machine: 0x8664, imports: ["d3d11.dll"]).prefix(0x90)
    #expect(throws: ExeFactsError.notAWindowsProgram) { try ExeFacts.read(try exe(Data(cut))) }
}

@Test func brokenImportTableKeepsTheBitness() throws {
    // A packed 32-bit exe whose import table points past the end of the file: still 32-bit, imports unknown.
    let cut = PEFixture.make(machine: 0x14c, imports: ["d3d11.dll"]).prefix(0x200 + 8)
    let facts = try ExeFacts.read(try exe(Data(cut)))
    #expect(!facts.is64Bit)
    #expect(facts.imports.isEmpty)
}
