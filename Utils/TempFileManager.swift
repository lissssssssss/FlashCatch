import Foundation

final class TempFileManager {

    static let shared = TempFileManager()

    private init() {}

    func createTempURL(prefix: String = "", extension ext: String = "mp4") -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("\(prefix)\(UUID().uuidString)")
            .appendingPathExtension(ext)
    }

    func cleanup(urls: [URL]) {
        for url in urls {
            try? FileManager.default.removeItem(at: url)
        }
    }

    func cleanupAllTempVideos() {
        let tmpDir = FileManager.default.temporaryDirectory
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: tmpDir,
            includingPropertiesForKeys: nil
        ) else { return }

        for file in files where file.pathExtension == "mp4" {
            try? FileManager.default.removeItem(at: file)
        }
    }
}
