import CryptoKit
import Foundation

enum BundledToolsError: LocalizedError {
    case missing(String, URL)

    var errorDescription: String? {
        switch self {
        case .missing(let name, let folder):
            Strings.errorBundledToolMissing(name, folder.path)
        }
    }
}

/// Every path and pinned version the launcher needs.
///
/// `root` is where the launcher installs: the prefix, the game and copies of the
/// bundled helper binaries, under ~/Library/Application Support/ROSilicon. Wine
/// is not among them — it runs from inside the app bundle, which also carries
/// DXVK, x87sidecar and the Steam stub, so the launcher downloads nothing but
/// the game client and can live anywhere, /Applications included.
struct Paths: Sendable {
    static let x87SidecarPreferenceKey = "x87SidecarEnabled"

    static let defaultClientURL = URL(string:
        "https://ro1patch.gnjoylatam.com/LIVE/client/LATAM_RO1_Live_20260601_091136.tar")!

    static var applicationSupportRoot: URL {
        FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(filePath: NSHomeDirectory()).appending(path: "Library/Application Support")
    }

    let root: URL

    init(root: URL) { self.root = root }

    /// Wine runs where it lies, inside the app bundle. Nothing writes to it:
    /// `build.sh` applies the wintrust patch when it assembles the app, so the
    /// tree under the signature is never touched afterwards.
    var wineRoot: URL { Self.bundledWineRoot }
    var wine: URL { wineRoot.appending(path: "bin/wine") }
    var wineserver: URL { wineRoot.appending(path: "bin/wineserver") }
    var wineExternalLibs: URL { wineRoot.appending(path: "lib/external") }

    /// One of Wine's own tools beside `wine` itself, e.g. winecfg.
    func wineTool(_ name: String) -> URL { wineRoot.appending(path: "bin/" + name) }

    var prefix: URL { root.appending(path: "wine") }
    var driveC: URL { prefix.appending(path: "drive_c") }
    var gameDir: URL { driveC.appending(path: "Gravity/Ragnarok") }
    var ragexe: URL { gameDir.appending(path: "Ragexe.exe") }

    /// True when the prefix has actually been booted, not merely created.
    ///
    /// Any wine invocation with WINEPREFIX set bootstraps the prefix, so the
    /// folder existing is not proof it is complete; these files are written at
    /// the end of that bootstrap. The 32-bit WoW64 tree matters because the
    /// Ragnarok client is a PE32 application; a prefix with only system32 can
    /// pass the old check and later fail with kernel32.dll status c0000135.
    var prefixInitialized: Bool {
        let fm = FileManager.default
        return fm.fileExists(atPath: prefix.appending(path: "system.reg").path)
            && fm.fileExists(atPath: driveC.appending(path: "windows/system32/kernel32.dll").path)
            && fm.fileExists(atPath: driveC.appending(path: "windows/syswow64/kernel32.dll").path)
    }

    /// Where the app keeps everything it ships with: the Wine runtime, DXVK,
    /// x87sidecar and the Steam stub.
    ///
    /// Normally the app's own Resources/. `RO_TOOLS` points somewhere else when
    /// the code runs outside a bundle, as it does under `swift run`.
    static let bundledTools: URL = {
        if let override = ProcessInfo.processInfo.environment["RO_TOOLS"] {
            return URL(filePath: override).standardizedFileURL
        }
        return Bundle.main.resourceURL ?? Bundle.main.bundleURL
    }()

    /// The Wine runtime inside the app bundle, put there by `build.sh`.
    static var bundledWineRoot: URL { bundledTools.appending(path: "Wine") }

    /// The three helper binaries, read where they lie in the app. The prefix
    /// links to the two Windows ones rather than holding copies; `prepare()`
    /// rewrites those links on every launch, so they follow the app when it
    /// moves.
    static var dxvkDLL: URL { bundledTools.appending(path: "d3d9.dll") }
    static var steamStub: URL { bundledTools.appending(path: "steam_stub.exe") }

    /// The arm64 helper Wine's loader re-execs itself under. nil when the app
    /// was built without it, which is the only way it can be absent.
    static var x87Sidecar: URL? {
        let sidecar = bundledTools.appending(path: "x87sidecar")
        return FileManager.default.isExecutableFile(atPath: sidecar.path) ? sidecar : nil
    }

    /// The sidecar is an optional Rosetta optimization. Its binary hooks
    /// Rosetta internals, so a release built for a different Rosetta revision
    /// must not be injected into Wine. Install/Repair records the probe result;
    /// an unset preference preserves the historical opt-in behavior until the
    /// first probe has completed.
    static var x87SidecarForWine: URL? {
        guard UserDefaults.standard.object(forKey: x87SidecarPreferenceKey) as? Bool ?? true
        else { return nil }
        return x87Sidecar
    }

    /// A separate Wine prefix must also get a separate Steam stub mutex so two
    /// profiles can launch concurrently without one stub treating the other as
    /// its already-running instance.
    private var steamMutexName: String {
        let digest = SHA256.hash(data: Data(root.standardizedFileURL.path.utf8))
        let suffix = digest.prefix(12).map { String(format: "%02x", $0) }.joined()
        return "Global\\ROSilicon-\(suffix)"
    }

    /// Everything the app must carry for an install to be possible. Throws
    /// naming the first one missing, which means a build that left it out.
    static func verifyBundledTools() throws {
        for name in ["d3d9.dll", "steam_stub.exe", "x87sidecar"] {
            let url = bundledTools.appending(path: name)
            guard FileManager.default.fileExists(atPath: url.path) else {
                throw BundledToolsError.missing(name, bundledTools)
            }
        }
    }

    var downloads: URL { root.appending(path: "downloads") }

    /// How the bundled runtime names itself, e.g. "11.13 (r15)", read from the
    /// lock the build embeds in the tree. nil when the app was built without a
    /// runtime, or the lock cannot be read.
    static var bundledWineVersion: String? {
        let lock = bundledWineRoot.appending(path: "share/wowsilicon/runtime-lock.json")
        guard let data = try? Data(contentsOf: lock),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let wine = (json["wine"] as? [String: Any])?["version"] as? String
        else { return nil }
        guard let revision = json["runtimeRevision"] as? Int else { return wine }
        return "\(wine) (r\(revision))"
    }

    /// Environment shared by every Wine invocation — the Swift side of `wine_env`.
    func wineEnvironment() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        env["WINEPREFIX"] = prefix.path
        env["WINELOADER"] = wine.path
        env["WINESERVER"] = wineserver.path
        env["RO_SILICON_MUTEX"] = steamMutexName
        // Wine's loader re-execs itself under `x87sidecar --cooperative` when
        // this is set. That is what makes the client's legacy x87 float code
        // fast on Apple Silicon, and unlike rosettax87 it needs no
        // task_for_pid privilege, so macOS never asks for a password.
        if let sidecar = Self.x87SidecarForWine { env["X87_SIDECAR_PATH"] = sidecar.path }
        // Wine dlopen()s freetype, gnutls, MoltenVK and SDL2 by leaf name; the
        // bundle keeps them here rather than relying on a system copy.
        let dyld = env["DYLD_LIBRARY_PATH"].map { ":\($0)" } ?? ""
        env["DYLD_LIBRARY_PATH"] = wineExternalLibs.path + dyld
        env["PATH"] = wineRoot.appending(path: "bin").path + ":" + (env["PATH"] ?? "/usr/bin:/bin")
        return env
    }

    /// Where the launcher installs, by default
    /// ~/Library/Application Support/ROSilicon. `RO_ROOT` overrides it.
    static var installRoot: URL {
        if let override = ProcessInfo.processInfo.environment["RO_ROOT"] {
            return URL(filePath: override).standardizedFileURL
        }
        return applicationSupportRoot.appending(path: "ROSilicon")
    }

    static func locateRoot() -> Paths { Paths(root: installRoot) }

    /// Creates the install folder. Called before installing and before showing
    /// the folder in Finder, so neither ever faces a missing directory.
    @discardableResult
    func createRoot() throws -> URL {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

}
