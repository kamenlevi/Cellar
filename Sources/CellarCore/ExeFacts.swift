import Foundation

public enum ExeFactsError: Error, Equatable {
    case notAWindowsProgram
}

/// What a game's exe says about itself: 64-bit or not, and the DLLs it imports. D3DMetal ships 64-bit DLLs only, and
/// the imports show which DirectX a game asks for (a Unity player loads its d3d11 at run time, so it shows none).
public struct ExeFacts: Equatable, Sendable {
    public var is64Bit: Bool
    /// Lowercased DLL names, e.g. "d3d11.dll".
    public var imports: Set<String>

    /// The highest DirectX the exe imports: 12, 11, 10 or 9; nil when it imports none.
    public var directX: Int? {
        if imports.contains("d3d12.dll") { return 12 }
        if imports.contains("d3d11.dll") { return 11 }
        if imports.contains(where: { $0.hasPrefix("d3d10") }) { return 10 }
        if imports.contains("d3d9.dll") { return 9 }
        return nil
    }

    public static func read(_ exe: URL) throws -> ExeFacts {
        try parse(Data(contentsOf: exe, options: .alwaysMapped))
    }

    /// The PE format: "MZ", the PE header's offset at 0x3C, "PE\0\0", the COFF header, the optional header (PE32 or
    /// PE32+) whose data directory 1 is the import table, then the section table that maps RVAs to file offsets.
    static func parse(_ data: Data) throws -> ExeFacts {
        let bytes = [UInt8](data)
        func u16(_ at: Int) throws -> Int {
            guard at >= 0, at + 2 <= bytes.count else { throw ExeFactsError.notAWindowsProgram }
            return Int(bytes[at]) | Int(bytes[at + 1]) << 8
        }
        func u32(_ at: Int) throws -> Int { try u16(at) | u16(at + 2) << 16 }

        guard bytes.starts(with: [0x4D, 0x5A]) else { throw ExeFactsError.notAWindowsProgram }
        let pe = try u32(0x3C)
        guard try u32(pe) == 0x4550 else { throw ExeFactsError.notAWindowsProgram }  // "PE\0\0"
        let sectionCount = try u16(pe + 6)
        let optionalSize = try u16(pe + 20)
        let optional = pe + 24
        let wide: Bool
        switch try u16(optional) {
        case 0x20b: wide = true
        case 0x10b: wide = false
        default: throw ExeFactsError.notAWindowsProgram
        }
        let directories = optional + (wide ? 112 : 96)

        // From here on nothing throws: a packed exe or a damaged import table still says how wide it is.
        func r32(_ at: Int) -> Int? { try? u32(at) }
        struct Section { var va, size, raw: Int }
        let sections: [Section] = (0..<sectionCount).compactMap { i in
            let s = optional + optionalSize + 40 * i
            guard let va = r32(s + 12), let size = r32(s + 16), let raw = r32(s + 20), raw != 0 else { return nil }
            return Section(va: va, size: size, raw: raw)
        }
        // Only bytes that are in the file: a section's zero-filled tail (VirtualSize past SizeOfRawData) has none.
        func offset(_ rva: Int) -> Int? {
            sections.first { rva >= $0.va && rva - $0.va < $0.size }.map { rva - $0.va + $0.raw }
        }

        var imports = Set<String>()
        let importRVA = (r32(directories - 4) ?? 0) > 1 ? r32(directories + 8) ?? 0 : 0
        if importRVA != 0, var descriptor = offset(importRVA) {
            for _ in 0..<1024 {
                guard let nameRVA = r32(descriptor + 12), nameRVA != 0 else { break }
                if let start = offset(nameRVA), start < bytes.count {
                    let name = bytes[start..<min(start + 256, bytes.count)].prefix { $0 != 0 }
                    imports.insert(String(decoding: name, as: UTF8.self).lowercased())
                }
                descriptor += 20
            }
        }
        return ExeFacts(is64Bit: wide, imports: imports)
    }
}
