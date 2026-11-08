import Foundation

/// Safe local utilities adapted from Cinder27 Kit.swift and ModTools.swift.
/// No private APIs, exploit triggers, sandbox bypasses, or kernel operations.
enum Cinder27SafeTools {
    static func hexDump(_ data: Data, limit: Int = 4096) -> String {
        let bytes = [UInt8](data.prefix(limit))
        var output = ""
        var offset = 0
        while offset < bytes.count {
            let end = min(offset + 16, bytes.count)
            let slice = bytes[offset..<end]
            let hex = slice.map { String(format: "%02x", $0) }.enumerated()
                .map { $0.offset == 7 ? $0.element + " " : $0.element }.joined(separator: " ")
            let ascii = slice.map { ($0 >= 0x20 && $0 < 0x7f) ? String(UnicodeScalar($0)) : "." }.joined()
            output += String(format: "%08x  ", offset) + hex.padding(toLength: 48, withPad: " ", startingAt: 0) + "  " + ascii + "\n"
            offset = end
        }
        if data.count > limit { output += "... (\(data.count) bytes total)\n" }
        return output
    }

    static func machoReport(_ data: Data) -> String? {
        guard data.count >= 28 else { return nil }
        let b = [UInt8](data.prefix(32))
        let raw = u32(b, 0, true)
        let is64: Bool
        let little: Bool
        switch raw {
        case 0xfeedfacf: is64 = true; little = true
        case 0xfeedface: is64 = false; little = true
        case 0xcffaedfe: is64 = true; little = false
        case 0xcefaedfe: is64 = false; little = false
        default: return nil
        }
        let headerSize = is64 ? 32 : 28
        guard data.count >= headerSize else { return nil }
        let cpu = u32(b, 4, little), subtype = u32(b, 8, little)
        let fileType = u32(b, 12, little), ncmds = u32(b, 16, little)
        let commandBytes = u32(b, 20, little)
        guard ncmds <= 8192, Int(commandBytes) <= data.count - headerSize else {
            return "Mach-O başlığı tanındı, amma load-command ölçüləri fayl sərhədini aşır."
        }
        var offset = headerSize
        var valid = 0
        for _ in 0..<Int(ncmds) {
            guard offset + 8 <= data.count else { break }
            let chunk = [UInt8](data[offset..<(offset + 8)])
            let size = Int(u32(chunk, 4, little))
            guard size >= 8, size <= data.count - offset else { break }
            valid += 1
            offset += size
        }
        return """
        Format: Mach-O
        Ölçü: \(data.count) bayt
        Header: \(is64 ? "64-bit" : "32-bit") / \(little ? "little-endian" : "big-endian")
        CPU: 0x\(String(cpu, radix: 16)) · subtype: 0x\(String(subtype, radix: 16))
        File type: \(fileType)
        Load commands: \(ncmds) (sərhədlər daxilində: \(valid))
        Load-command bytes: \(commandBytes)
        """
    }

    static func hexSelfTest() throws -> String {
        var bytes = Data((0..<96).map { UInt8($0 & 0xff) })
        let needle = Data([0xde, 0xad, 0xbe, 0xef])
        bytes.replaceSubrange(20..<24, with: needle)
        bytes.replaceSubrange(60..<64, with: needle)
        let hits = offsets(of: needle, in: bytes)
        guard hits == [20, 60] else { throw ToolError.failed("HEX test: iki uyğunluq tapılmadı.") }
        let replacement = Data([0x11, 0x22, 0x33, 0x44])
        for offset in hits.reversed() { bytes.replaceSubrange(offset..<(offset + 4), with: replacement) }
        guard offsets(of: needle, in: bytes).isEmpty, offsets(of: replacement, in: bytes) == [20, 60] else {
            throw ToolError.failed("HEX əvəzləmə yoxlaması uğursuz oldu.")
        }
        return "HEX self-test uğurlu: 2 uyğunluq tapıldı və əvəzləndi."
    }

    static func zipSelfTest() throws -> String {
        var writer = ZipWriter()
        let payload = Data("Cinder27 ZIP round-trip fixture".utf8)
        writer.add("fixture.txt", payload)
        let archive = writer.build()
        guard archive.count > 50,
              archive.prefix(4) == Data([0x50, 0x4b, 0x03, 0x04]),
              archive.range(of: Data([0x50, 0x4b, 0x01, 0x02])) != nil,
              archive.suffix(22).prefix(4) == Data([0x50, 0x4b, 0x05, 0x06]) else {
            throw ToolError.failed("ZIP header / central directory / EOCD yoxlaması uğursuz oldu.")
        }
        let crc = ZipWriter.crc32([UInt8](payload))
        let crcBytes = Data([UInt8(crc & 255), UInt8((crc >> 8) & 255), UInt8((crc >> 16) & 255), UInt8((crc >> 24) & 255)])
        guard archive.range(of: crcBytes) != nil else { throw ToolError.failed("ZIP CRC32 tapılmadı.") }
        return "ZIP writer self-test uğurlu: header, central directory, EOCD və CRC32 təsdiqləndi (\(archive.count) bayt)."
    }

    static func backupRestoreSelfTest() throws -> String {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ProFiles-Cinder27-\(UUID().uuidString)", isDirectory: true)
        let source = root.appendingPathComponent("source.txt")
        let backup = root.appendingPathComponent("backup.txt")
        let restored = root.appendingPathComponent("restored.txt")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let marker = Data("Cinder27 backup restore verification".utf8)
        try marker.write(to: source, options: .atomic)
        try FileManager.default.copyItem(at: source, to: backup)
        try FileManager.default.removeItem(at: source)
        try FileManager.default.copyItem(at: backup, to: restored)
        guard try Data(contentsOf: restored) == marker else { throw ToolError.failed("Bərpa edilmiş fayl uyğun gəlmir.") }
        return "Backup/restore self-test uğurlu: müvəqqəti fayl bərpa olundu və bayt-bayt təsdiqləndi."
    }

    private static func offsets(of needle: Data, in haystack: Data) -> [Int] {
        guard !needle.isEmpty, needle.count <= haystack.count else { return [] }
        let a = [UInt8](haystack), b = [UInt8](needle)
        return (0...(a.count - b.count)).compactMap { i in
            Array(a[i..<(i + b.count)]) == b ? i : nil
        }
    }

    private static func u32(_ b: [UInt8], _ i: Int, _ little: Bool) -> UInt32 {
        guard i >= 0, i + 4 <= b.count else { return 0 }
        if little {
            return UInt32(b[i]) | (UInt32(b[i + 1]) << 8) | (UInt32(b[i + 2]) << 16) | (UInt32(b[i + 3]) << 24)
        }
        return (UInt32(b[i]) << 24) | (UInt32(b[i + 1]) << 16) | (UInt32(b[i + 2]) << 8) | UInt32(b[i + 3])
    }

    private enum ToolError: LocalizedError {
        case failed(String)
        var errorDescription: String? { if case let .failed(s) = self { return s }; return "Cinder27 tool test failed." }
    }

    // Stored-entry ZIP writer adapted from Cinder27 ModTools.swift.
    private struct ZipWriter {
        struct Entry { let name: String; let data: Data }
        private var entries: [Entry] = []
        mutating func add(_ name: String, _ data: Data) { entries.append(Entry(name: name, data: data)) }

        static func crc32(_ bytes: [UInt8]) -> UInt32 {
            var table = [UInt32](repeating: 0, count: 256)
            for i in 0..<256 {
                var c = UInt32(i)
                for _ in 0..<8 { c = (c & 1) != 0 ? (0xedb88320 ^ (c >> 1)) : (c >> 1) }
                table[i] = c
            }
            var crc: UInt32 = 0xffffffff
            for byte in bytes { crc = table[Int((crc ^ UInt32(byte)) & 255)] ^ (crc >> 8) }
            return crc ^ 0xffffffff
        }

        func build() -> Data {
            var local = Data()
            var central = Data()
            for entry in entries {
                let name = Array(entry.name.utf8)
                let body = [UInt8](entry.data)
                let crc = Self.crc32(body)
                let size = UInt32(body.count)
                let offset = UInt32(local.count)
                local.append(contentsOf: [0x50,0x4b,0x03,0x04])
                local.le16(20); local.le16(0x0800); local.le16(0); local.le16(0); local.le16(0)
                local.le32(crc); local.le32(size); local.le32(size)
                local.le16(UInt16(name.count)); local.le16(0)
                local.append(contentsOf: name); local.append(contentsOf: body)

                central.append(contentsOf: [0x50,0x4b,0x01,0x02])
                central.le16(20); central.le16(20); central.le16(0x0800)
                central.le16(0); central.le16(0); central.le16(0)
                central.le32(crc); central.le32(size); central.le32(size)
                central.le16(UInt16(name.count)); central.le16(0); central.le16(0)
                central.le16(0); central.le16(0); central.le32(0); central.le32(offset)
                central.append(contentsOf: name)
            }
            let centralOffset = UInt32(local.count)
            local.append(central)
            local.append(contentsOf: [0x50,0x4b,0x05,0x06])
            local.le16(0); local.le16(0)
            local.le16(UInt16(entries.count)); local.le16(UInt16(entries.count))
            local.le32(UInt32(central.count)); local.le32(centralOffset); local.le16(0)
            return local
        }
    }
}

private extension Data {
    mutating func le16(_ v: UInt16) { append(contentsOf: [UInt8(v & 255), UInt8((v >> 8) & 255)]) }
    mutating func le32(_ v: UInt32) {
        append(contentsOf: [UInt8(v & 255), UInt8((v >> 8) & 255), UInt8((v >> 16) & 255), UInt8((v >> 24) & 255)])
    }
}
