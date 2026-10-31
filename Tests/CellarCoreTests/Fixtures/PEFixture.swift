import Foundation

/// A minimal Windows exe: DOS stub, PE header, one section holding an import directory that names `imports`.
/// `machine` 0x8664 writes a 64-bit (PE32+) header, anything else a 32-bit (PE32) one.
enum PEFixture {
    static func make(machine: UInt16, imports: [String]) -> Data {
        var d = Data(count: 0x200 + 0x1000)
        func put16(_ v: UInt16, _ at: Int) { withUnsafeBytes(of: v.littleEndian) { d.replaceSubrange(at..<at + 2, with: $0) } }
        func put32(_ v: UInt32, _ at: Int) { withUnsafeBytes(of: v.littleEndian) { d.replaceSubrange(at..<at + 4, with: $0) } }
        let wide = machine == 0x8664
        let optionalSize = wide ? 240 : 224
        d[0] = 0x4D; d[1] = 0x5A; put32(0x80, 0x3C)
        d.replaceSubrange(0x80..<0x84, with: [0x50, 0x45, 0, 0])
        let coff = 0x84
        put16(machine, coff); put16(1, coff + 2); put16(UInt16(optionalSize), coff + 16)
        let optional = coff + 20
        put16(wide ? 0x20b : 0x10b, optional)
        let directories = optional + (wide ? 112 : 96)
        put32(16, directories - 4)  // NumberOfRvaAndSizes
        let section = optional + optionalSize
        d.replaceSubrange(section..<section + 6, with: Array(".idata".utf8))
        put32(0x1000, section + 8); put32(0x1000, section + 12); put32(0x1000, section + 16); put32(0x200, section + 20)

        // Import descriptors (20 bytes each, then a zero one), then the names.
        let table = 0x1000
        var name = table + 20 * (imports.count + 1)
        for (i, dll) in imports.enumerated() {
            put32(UInt32(name), 0x200 + table - 0x1000 + 20 * i + 12)
            let bytes = Array(dll.utf8) + [0]
            d.replaceSubrange(0x200 + name - 0x1000..<0x200 + name - 0x1000 + bytes.count, with: bytes)
            name += bytes.count
        }
        put32(UInt32(table), directories + 8); put32(UInt32(20 * (imports.count + 1)), directories + 12)
        return d
    }
}
