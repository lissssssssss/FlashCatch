import Combine
import Foundation

struct RecordingRecord: Codable, Identifiable {
    let id: UUID
    let assetIdentifier: String
    let date: Date
    let duration: TimeInterval
}

final class RecordingHistoryStore: ObservableObject {

    private static let storageKey = "recordingHistory"

    @Published private(set) var records: [RecordingRecord] = []

    init() {
        records = Self.load()
    }

    func add(assetIdentifier: String, duration: TimeInterval) {
        let record = RecordingRecord(
            id: UUID(),
            assetIdentifier: assetIdentifier,
            date: Date(),
            duration: duration
        )
        records.insert(record, at: 0)
        save()
    }

    func remove(at index: Int) {
        guard records.indices.contains(index) else { return }
        records.remove(at: index)
        save()
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(records) else { return }
        UserDefaults.standard.set(data, forKey: Self.storageKey)
    }

    private static func load() -> [RecordingRecord] {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let records = try? JSONDecoder().decode([RecordingRecord].self, from: data)
        else { return [] }
        return records
    }
}
