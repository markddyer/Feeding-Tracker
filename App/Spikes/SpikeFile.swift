#if FEEDING_DEV
import Foundation

/// Keeps a spike's results as JSON in the app's Documents folder. Copy them off the phone with
/// `xcrun devicectl device copy from --device <id> --domain-type appDataContainer
/// --domain-identifier com.tracker.feeding.dev --source Documents/<name> --destination <path>`.
enum SpikeFile {
    static func url(_ name: String) -> URL {
        URL.documentsDirectory.appending(path: name)
    }

    static func load<T: Decodable>(_ type: T.Type, from name: String) -> T? {
        guard let data = try? Data(contentsOf: url(name)) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(T.self, from: data)
    }

    static func save<T: Encodable>(_ value: T, to name: String) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(value) else { return }
        // Readable while the phone is locked after its first unlock, so the alarm's Stop button
        // can record the time overnight.
        try? data.write(to: url(name), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
}

extension Date {
    /// "+41 s", "+3 min 5 s" or "-2 s": how far `self` is from `reference`.
    func offset(from reference: Date) -> String {
        let seconds = Int(timeIntervalSince(reference).rounded())
        let sign = seconds < 0 ? "-" : "+"
        let value = abs(seconds)
        if value < 60 { return "\(sign)\(value) s" }
        return "\(sign)\(value / 60) min \(value % 60) s"
    }
}
#endif
