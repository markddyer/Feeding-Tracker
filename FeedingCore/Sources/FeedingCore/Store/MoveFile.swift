import Foundation

/// The move file (docs/planning/08-going-live.md): Feeding Dev writes it, the parent saves it to
/// Files, and the real app on the same phone reads it in. One file, so it is one thing to save:
///
///     "FEEDMOVE"                 8 bytes
///     the contents' length       8 bytes, big-endian
///     the contents               a `HouseholdMove`, as JSON
///     each photo or video        its file, then its thumbnail, at the places the contents name
///
/// The files are copied a piece at a time, so a long video never has to fit in memory.
public enum MoveFile {
    public static let fileExtension = "feedingmove"
    static let magic = Data("FEEDMOVE".utf8)
    static let headerLength: Int64 = 16
    static let piece = 1 << 20
    /// The longest list of contents read: years of entries fit many times over.
    static let longestContents: UInt64 = 64 << 20

    public enum Problem: Error, Hashable, Sendable {
        /// Not a move file, or cut short.
        case notAMoveFile
        /// Made by a newer build of Feeding Dev.
        case newerVersion
        /// A photo or video's file changed or went while the file was being made.
        case itemChanged(String)
    }

    /// One photo or video on this phone, to carry.
    public struct Item: Sendable {
        public let id: String
        public let file: URL
        public let thumbnail: URL

        public init(id: String, file: URL, thumbnail: URL) {
            self.id = id
            self.file = file
            self.thumbnail = thumbnail
        }
    }

    /// A safe item ID: it names files on the phone that reads it, so only letters, digits and "-".
    public static func isSafe(_ id: String) -> Bool {
        !id.isEmpty && id.count <= 64 && id.unicodeScalars.allSatisfy { $0.isASCII && (CharacterSet.alphanumerics.contains($0) || $0 == "-") }
    }

    /// The bytes `items` take in a file, before the list of contents.
    public static func bytes(of items: [Item]) throws -> Int64 {
        try items.filter { isSafe($0.id) }.reduce(Int64(0)) { $0 + (try size(of: $1.file)) + (try size(of: $1.thumbnail)) }
    }

    /// Writes `move` and `items` to `url`, replacing anything there. It is written beside it first
    /// and put in place only once whole, so a file cut short by a full phone or a stop is never
    /// left under the name (Codex review of the move).
    public static func write(_ move: HouseholdMove, items: [Item], to url: URL) throws {
        let part = url.deletingLastPathComponent().appendingPathComponent(".\(UUID().uuidString).part")
        do {
            try writeWhole(move, items: items, to: part)
            _ = try? FileManager.default.removeItem(at: url)
            try FileManager.default.moveItem(at: part, to: url)
        } catch {
            try? FileManager.default.removeItem(at: part)
            throw error
        }
    }

    private static func writeWhole(_ move: HouseholdMove, items: [Item], to url: URL) throws {
        var move = move
        var offset: Int64 = 0
        var media: [MovedMedia] = []
        for item in items where isSafe(item.id) {
            let file = try size(of: item.file)
            let thumbnail = try size(of: item.thumbnail)
            media.append(MovedMedia(id: item.id, file: ByteRange(offset: offset, length: file),
                                    thumbnail: ByteRange(offset: offset + file, length: thumbnail)))
            offset += file + thumbnail
        }
        move.media = media
        let contents = try encoder.encode(move)
        guard FileManager.default.createFile(atPath: url.path, contents: nil) else { throw CocoaError(.fileWriteUnknown) }
        let out = try FileHandle(forWritingTo: url)
        defer { try? out.close() }
        try out.write(contentsOf: magic)
        var length = UInt64(contents.count).bigEndian
        try out.write(contentsOf: Data(bytes: &length, count: 8))
        try out.write(contentsOf: contents)
        for (item, entry) in zip(items.filter { isSafe($0.id) }, media) {
            guard try copy(from: item.file, to: out) == entry.file.length,
                  try copy(from: item.thumbnail, to: out) == entry.thumbnail.length else {
                throw Problem.itemChanged(item.id)
            }
        }
        try out.synchronize()
    }

    /// Reads a move file's contents; `extract` then copies each item out.
    public struct Reader: Sendable {
        public let move: HouseholdMove
        let url: URL
        let start: Int64
        let total: Int64

        public init(url: URL) throws {
            self.url = url
            let total = try MoveFile.size(of: url)
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            guard let header = try handle.read(upToCount: Int(MoveFile.headerLength)), header.count == MoveFile.headerLength,
                  header.prefix(8) == MoveFile.magic else { throw Problem.notAMoveFile }
            let length = header.suffix(8).reduce(UInt64(0)) { $0 << 8 | UInt64($1) }
            guard length <= MoveFile.longestContents, length <= UInt64(total - MoveFile.headerLength),
                  let contents = try handle.read(upToCount: Int(length)), contents.count == Int(length) else {
                throw Problem.notAMoveFile
            }
            struct Probe: Decodable { var v: Int }
            guard let probe = try? MoveFile.decoder.decode(Probe.self, from: contents) else { throw Problem.notAMoveFile }
            guard probe.v <= HouseholdMove.currentVersion else { throw Problem.newerVersion }
            guard let move = try? MoveFile.decoder.decode(HouseholdMove.self, from: contents) else { throw Problem.notAMoveFile }
            start = MoveFile.headerLength + Int64(length)
            self.total = total
            // Every item is named safely, once, and laid out as the writer lays them: each file
            // then its thumbnail, one after another, all inside the file.
            let room = total - start
            var next: Int64 = 0
            var seen = Set<String>()
            for item in move.media {
                guard MoveFile.isSafe(item.id), seen.insert(item.id).inserted else { throw Problem.notAMoveFile }
                for range in [item.file, item.thumbnail] {
                    guard range.offset == next, range.length >= 0 else { throw Problem.notAMoveFile }
                    let (end, overflow) = next.addingReportingOverflow(range.length)
                    guard !overflow, end <= room else { throw Problem.notAMoveFile }
                    next = end
                }
            }
            self.move = move
        }

        /// Copies one range of the file to `target`, replacing anything there.
        public func extract(_ range: ByteRange, to target: URL) throws {
            guard range.offset >= 0, range.length >= 0, range.offset <= total - start - range.length else {
                throw Problem.notAMoveFile
            }
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            try handle.seek(toOffset: UInt64(start + range.offset))
            guard FileManager.default.createFile(atPath: target.path, contents: nil) else { throw CocoaError(.fileWriteUnknown) }
            let out = try FileHandle(forWritingTo: target)
            defer { try? out.close() }
            var left = range.length
            while left > 0 {
                guard let chunk = try handle.read(upToCount: Int(min(Int64(MoveFile.piece), left))), !chunk.isEmpty else {
                    throw Problem.notAMoveFile
                }
                try out.write(contentsOf: chunk)
                left -= Int64(chunk.count)
            }
        }
    }

    // MARK: Helpers

    static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .millisecondsSince1970
        return encoder
    }

    static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return decoder
    }

    static func size(of url: URL) throws -> Int64 {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes[.size] as? NSNumber)?.int64Value ?? 0
    }

    /// Appends `source` to `out`, a piece at a time. Returns the bytes copied.
    static func copy(from source: URL, to out: FileHandle) throws -> Int64 {
        let input = try FileHandle(forReadingFrom: source)
        defer { try? input.close() }
        var copied: Int64 = 0
        while let chunk = try input.read(upToCount: piece), !chunk.isEmpty {
            try out.write(contentsOf: chunk)
            copied += Int64(chunk.count)
        }
        return copied
    }
}
