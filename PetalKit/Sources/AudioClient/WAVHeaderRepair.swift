import Foundation

/// `AVAudioRecorder` writes the RIFF and data sizes only when it stops, so a crash leaves them at zero.
enum WAVHeaderRepair {
    @discardableResult
    static func repair(_ url: URL) throws -> Bool {
        let handle = try FileHandle(forUpdating: url)
        defer { try? handle.close() }
        let fileSize = try handle.seekToEnd()
        try handle.seek(toOffset: 0)
        let header = try handle.read(upToCount: 65_536) ?? Data()
        guard header.count >= 12,
              header.prefix(4) == Data("RIFF".utf8),
              header[8 ..< 12] == Data("WAVE".utf8)
        else { return false }

        var offset = 12
        while offset + 8 <= header.count {
            let chunkSize = Int(littleEndianUInt32(in: header, at: offset + 4))
            guard header[offset ..< offset + 4] == Data("data".utf8) else {
                offset += 8 + chunkSize + chunkSize % 2
                continue
            }
            let dataStart = UInt64(offset + 8)
            guard fileSize >= dataStart else { return false }
            let dataSize = UInt32(clamping: fileSize - dataStart)
            let riffSize = UInt32(clamping: fileSize - 8)
            guard dataSize != UInt32(chunkSize) || riffSize != littleEndianUInt32(in: header, at: 4) else { return false }
            try write(riffSize, at: 4, to: handle)
            try write(dataSize, at: UInt64(offset + 4), to: handle)
            return true
        }
        return false
    }

    private static func littleEndianUInt32(in data: Data, at offset: Int) -> UInt32 {
        data[offset ..< offset + 4].enumerated().reduce(0) { $0 | UInt32($1.element) << (8 * $1.offset) }
    }

    private static func write(_ value: UInt32, at offset: UInt64, to handle: FileHandle) throws {
        try handle.seek(toOffset: offset)
        try handle.write(contentsOf: withUnsafeBytes(of: value.littleEndian) { Data($0) })
    }
}
