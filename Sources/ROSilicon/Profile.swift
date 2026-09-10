import Foundation

struct Profile: Equatable, Identifiable, Sendable {
    let id: String
    let name: String
    let root: URL
}

struct ProfileStore: Sendable {
    enum Error: LocalizedError, Equatable {
        case emptyName
        case invalidName
        case duplicate
        case cannotModifyMain

        var errorDescription: String? {
            switch self {
            case .emptyName: "Profile name cannot be empty."
            case .invalidName: "Profile name must contain letters or numbers."
            case .duplicate: "A profile with that name already exists."
            case .cannotModifyMain: "The Main profile cannot be renamed or deleted."
            }
        }
    }

    let base: URL

    var profiles: [Profile] {
        var result = [Profile(id: "main", name: "Main", root: base)]
        let folder = base.appending(path: "profiles")
        let entries = (try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles])) ?? []
        for entry in entries.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            guard (try? entry.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true,
                  let name = try? String(contentsOf: entry.appending(path: ".profile-name"),
                                         encoding: .utf8),
                  !name.isEmpty
            else { continue }
            result.append(Profile(id: entry.lastPathComponent, name: name, root: entry))
        }
        return result
    }

    @discardableResult
    func create(name: String) throws -> Profile {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw Error.emptyName }
        let id = Self.slug(trimmed)
        guard !id.isEmpty else { throw Error.invalidName }
        guard !profiles.contains(where: { $0.id == id }) else { throw Error.duplicate }

        let root = base.appending(path: "profiles/\(id)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data(trimmed.utf8).write(to: root.appending(path: ".profile-name"), options: .atomic)
        return Profile(id: id, name: trimmed, root: root)
    }

    @discardableResult
    func rename(_ profile: Profile, to name: String) throws -> Profile {
        guard profile.id != "main" else { throw Error.cannotModifyMain }
        guard profiles.contains(where: {
            $0.id == profile.id && $0.root.standardizedFileURL == profile.root.standardizedFileURL
        }) else { throw Error.invalidName }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw Error.emptyName }
        let id = Self.slug(trimmed)
        guard !id.isEmpty else { throw Error.invalidName }
        guard !profiles.contains(where: { $0.id != profile.id && $0.id == id }) else {
            throw Error.duplicate
        }
        let renamed = Profile(id: profile.id, name: trimmed, root: profile.root)
        try Data(trimmed.utf8).write(
            to: profile.root.appending(path: ".profile-name"), options: .atomic)
        return renamed
    }

    @discardableResult
    func delete(_ profile: Profile) throws -> URL? {
        guard profile.id != "main" else { throw Error.cannotModifyMain }
        guard let stored = profiles.first(where: {
            $0.id == profile.id && $0.root.standardizedFileURL == profile.root.standardizedFileURL
        }) else { return nil }
        guard FileManager.default.fileExists(atPath: stored.root.path) else { return nil }
        var trashed: NSURL?
        try FileManager.default.trashItem(at: stored.root, resultingItemURL: &trashed)
        return trashed as URL?
    }

    private static func slug(_ name: String) -> String {
        name.lowercased()
            .replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }
}
