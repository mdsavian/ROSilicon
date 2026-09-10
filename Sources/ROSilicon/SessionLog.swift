import Foundation

/// A per-profile diagnostic file. The launcher keeps the in-app log for the
/// current session, while this file survives a crash or a second instance
/// being disconnected by GameGuard.
struct SessionLog: Sendable {
    let fileURL: URL

    init(root: URL, sessionID: String = UUID().uuidString) {
        fileURL = root.appending(path: "logs").appending(path: "\(sessionID).log")
    }

    func append(_ line: String) {
        do {
            let directory = fileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: true)
            let data = Data((line + "\n").utf8)
            if FileManager.default.fileExists(atPath: fileURL.path) {
                let handle = try FileHandle(forWritingTo: fileURL)
                try handle.seekToEnd()
                try handle.write(contentsOf: data)
                try handle.close()
            } else {
                try data.write(to: fileURL, options: .atomic)
            }
        } catch {
            // Diagnostics must never prevent the game from launching.
        }
    }
}
