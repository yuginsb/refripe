import Foundation

/// What the sell flow keeps on disk between two openings of « Vendre » (everything but the photos,
/// which are stored next to it as JPEG files).
struct SellDraftSnapshot: Codable, Equatable {
    var step: Int
    var itemType: ItemType?
    var gender: Gender?
    var sizeType: SizeType?
    var sizeValue: String?
    var condition: ItemCondition?
    var brand: String?
    var color: String?
    var title: String
    var description: String
    var defectComment: String
    var price: FCFA
    var negotiable: Bool
    var minOffer: FCFA
    var delivery: [DeliveryMethod]
    var autoTitle: String?
    var savedAt: Date
}

/// Single draft in Application Support/SellDraft: `draft.json` + `photo-0.jpg` … `photo-7.jpg`.
/// Best effort: any I/O error just means no draft.
enum SellDraftStore {
    private static var directory: URL? {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        return base.appendingPathComponent("SellDraft", isDirectory: true)
    }

    private static var jsonURL: URL? { directory?.appendingPathComponent("draft.json") }

    static var exists: Bool {
        guard let url = jsonURL else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }

    static func save(_ snapshot: SellDraftSnapshot, photos: [Data]) {
        guard let dir = directory, let json = jsonURL else { return }
        let fm = FileManager.default
        do {
            try? fm.removeItem(at: dir)
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            for (index, data) in photos.enumerated() {
                try data.write(to: dir.appendingPathComponent("photo-\(index).jpg"), options: .atomic)
            }
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(snapshot).write(to: json, options: .atomic)
        } catch {
            clear()
        }
    }

    static func load() -> (snapshot: SellDraftSnapshot, photos: [Data])? {
        guard let dir = directory, let json = jsonURL, let data = try? Data(contentsOf: json) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let snapshot = try? decoder.decode(SellDraftSnapshot.self, from: data) else {
            clear()
            return nil
        }
        var photos: [Data] = []
        for index in 0..<Catalog.sellPhotoMax {
            guard let jpeg = try? Data(contentsOf: dir.appendingPathComponent("photo-\(index).jpg")) else { break }
            photos.append(jpeg)
        }
        return (snapshot, photos)
    }

    static func clear() {
        guard let dir = directory else { return }
        try? FileManager.default.removeItem(at: dir)
    }
}
