import Foundation

public struct InventorySnapshot: Codable, Sendable {
    public var ingredients: [Ingredient]
    public var events: [InventoryEvent]

    public init(ingredients: [Ingredient], events: [InventoryEvent]) {
        self.ingredients = ingredients
        self.events = events
    }
}

public protocol InventoryPersisting: Sendable {
    func load() throws -> InventorySnapshot?
    func save(_ snapshot: InventorySnapshot) throws
}

public struct JSONInventoryPersistence: InventoryPersisting {
    private let fileURL: URL

    public init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? FileManager.default.temporaryDirectory
            self.fileURL = directory.appendingPathComponent("SmartFridgeInventory.json")
        }
    }

    public func load() throws -> InventorySnapshot? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        let data = try Data(contentsOf: fileURL)
        return try JSONDecoder.smartFridge.decode(InventorySnapshot.self, from: data)
    }

    public func save(_ snapshot: InventorySnapshot) throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try JSONEncoder.smartFridge.encode(snapshot)
        try data.write(to: fileURL, options: [.atomic])
    }
}

private extension JSONEncoder {
    static var smartFridge: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

private extension JSONDecoder {
    static var smartFridge: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
