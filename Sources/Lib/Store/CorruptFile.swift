import Foundation

enum CorruptFile {
    /// Keeps an unreadable store file beside the original so the next save does not destroy it.
    static func quarantine(_ url: URL, store: String) {
        let backup = url.deletingPathExtension().appendingPathExtension("corrupt.json")
        try? FileManager.default.removeItem(at: backup)
        do {
            try FileManager.default.copyItem(at: url, to: backup)
            DebugLog.shared.log("\(store): could not decode \(url.lastPathComponent); copied to \(backup.lastPathComponent)")
        } catch {
            DebugLog.shared.log("\(store): could not decode \(url.lastPathComponent); backup failed: \(error.localizedDescription)")
        }
    }
}
