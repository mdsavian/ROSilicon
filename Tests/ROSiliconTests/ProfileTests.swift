import Foundation
import Testing
@testable import ROSilicon

struct ProfileTests {
    @Test func aNewStoreExposesTheLegacyInstallAsTheMainProfile() throws {
        let temp = try TemporaryDirectory()
        let store = ProfileStore(base: temp.url)

        #expect(store.profiles == [Profile(id: "main", name: "Main", root: temp.url)])
    }

    @Test func creatingAProfileUsesASafeStableFolderAndListsIt() throws {
        let temp = try TemporaryDirectory()
        let store = ProfileStore(base: temp.url)

        let profile = try store.create(name: "Conta Dois")

        #expect(profile.id == "conta-dois")
        #expect(profile.name == "Conta Dois")
        #expect(profile.root.path == temp.url.appending(path: "profiles/conta-dois").path)
        #expect(FileManager.default.isDirectory(atPath: profile.root.path))
        #expect(store.profiles.contains(profile))
    }

    @Test func duplicateProfileNamesAreRejected() throws {
        let temp = try TemporaryDirectory()
        let store = ProfileStore(base: temp.url)
        _ = try store.create(name: "Conta Dois")

        #expect(throws: ProfileStore.Error.duplicate) {
            _ = try store.create(name: "conta-dois")
        }
    }

    @Test func profileCanBeRenamedWithoutChangingItsInstallRoot() throws {
        let temp = try TemporaryDirectory()
        let store = ProfileStore(base: temp.url)
        let profile = try store.create(name: "Conta Dois")

        let renamed = try store.rename(profile, to: "Conta Principal")

        #expect(renamed.id == profile.id)
        #expect(renamed.name == "Conta Principal")
        #expect(renamed.root == profile.root)
        #expect(store.profiles.contains(renamed))
    }

    @Test func deletingProfileMovesOnlyThatProfileToTrash() throws {
        let temp = try TemporaryDirectory()
        let store = ProfileStore(base: temp.url)
        let first = try store.create(name: "Conta Um")
        let second = try store.create(name: "Conta Dois")

        _ = try store.delete(first)

        #expect(!FileManager.default.fileExists(atPath: first.root.path))
        #expect(FileManager.default.fileExists(atPath: second.root.appending(path: ".profile-name").path))
        #expect(store.profiles.contains(second))
    }
}
