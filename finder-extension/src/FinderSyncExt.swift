import AppKit
import FinderSync

// Principal class of the Finder Sync app extension. The @objc name keeps the
// runtime name stable so Info.plist can reference it without Swift's
// "<module>.<class>" mangling.
@objc(FinderSyncExt)
final class FinderSyncExt: FIFinderSync {

    override init() {
        super.init()
        // Watch the whole filesystem so the menu is offered everywhere.
        // Nothing is badged and no sidebar item is added.
        FIFinderSyncController.default().directoryURLs = [URL(fileURLWithPath: "/")]
    }

    // MARK: - Menu

    override func menu(for menuKind: FIMenuKind) -> NSMenu {
        let menu = NSMenu(title: "")

        switch menuKind {
        case .contextualMenuForItems, .contextualMenuForContainer:
            break
        default:
            return menu   // no toolbar / sidebar entries
        }

        // Order here is the order Finder shows within our block.
        let vscode = NSMenuItem(
            title: "Open in VS Code (New Window)",
            action: #selector(runVSCode(_:)),
            keyEquivalent: "")
        vscode.target = self
        menu.addItem(vscode)

        let addToWorkspace = NSMenuItem(
            title: "Add to VS Code Workspace",
            action: #selector(runVSCodeAdd(_:)),
            keyEquivalent: "")
        addToWorkspace.target = self
        menu.addItem(addToWorkspace)

        let compress = NSMenuItem(
            title: "Compress (APFS Transparent)",
            action: #selector(runCompress(_:)),
            keyEquivalent: "")
        compress.target = self
        menu.addItem(compress)

        let size = NSMenuItem(
            title: "Show Actual Size on Disk",
            action: #selector(runShowSize(_:)),
            keyEquivalent: "")
        size.target = self
        menu.addItem(size)

        return menu
    }

    // MARK: - Actions

    @objc func runVSCode(_ sender: AnyObject?) {
        run(script: "vscode")
    }

    @objc func runVSCodeAdd(_ sender: AnyObject?) {
        run(script: "vscode-add")
    }

    @objc func runCompress(_ sender: AnyObject?) {
        run(script: "compress")
    }

    @objc func runShowSize(_ sender: AnyObject?) {
        run(script: "showsize")
    }

    /// Selected paths come from the controller; when the user right-clicked the
    /// background of a window rather than an item, fall back to that container.
    private func selectedPaths() -> [String] {
        let controller = FIFinderSyncController.default()
        if let urls = controller.selectedItemURLs(), !urls.isEmpty {
            return urls.map { $0.path }
        }
        if let target = controller.targetedURL() {
            return [target.path]
        }
        return []
    }

    /// Broker pattern: the extension never runs the script itself. This appex is
    /// sandboxed (pkd requires that), and everything a script spawns inherits the
    /// sandbox — which silently killed the VS Code CLI: its detached Electron
    /// child could not run under the inherited seatbelt, while the CLI itself had
    /// already exited 0 (see docs/FINDINGS.md). Instead, hand the request to our
    /// own host app: LaunchServices parents it to launchd, and the host has no
    /// sandbox entitlement, so the script runs unrestricted.
    ///
    /// The request travels as a spool file, not as argv: LaunchServices does not
    /// deliver OpenConfiguration.arguments from a sandboxed caller (observed —
    /// the host launched straight into its no-arguments UI mode). The spool
    /// directory is the one home-relative path the extension's entitlements
    /// allow it to write.
    private func run(script: String) {
        let paths = selectedPaths()
        guard !paths.isEmpty else {
            NSLog("AFSC: nothing selected")
            return
        }

        // In the sandbox, NSHomeDirectory() AND FileManager.homeDirectory(forUser:)
        // both report the container as home (verified: requests written through
        // the latter landed in the container). getpwuid reads the account record
        // directly and is not virtualized, so it yields the real home — which is
        // where the entitlement's home-relative exception applies.
        guard let pw = getpwuid(getuid()), let dir = pw.pointee.pw_dir else {
            NSLog("AFSC: cannot resolve real home directory")
            return
        }
        let home = String(cString: dir)
        let spoolDir = home + "/Library/Application Support/AFSCFinderMenu/spool"

        do {
            try FileManager.default.createDirectory(
                atPath: spoolDir, withIntermediateDirectories: true)
            let request: [String: Any] = ["script": script, "paths": paths]
            let data = try JSONSerialization.data(withJSONObject: request)
            let file = spoolDir + "/req-\(UUID().uuidString).json"
            try data.write(to: URL(fileURLWithPath: file), options: .atomic)
        } catch {
            NSLog("AFSC: spool write failed: \(error)")
            return
        }

        let hostURL = Bundle.main.bundleURL                 // …/Host.app/Contents/PlugIns/X.appex
            .deletingLastPathComponent()                    // PlugIns
            .deletingLastPathComponent()                    // Contents
            .deletingLastPathComponent()                    // Host.app

        let cfg = NSWorkspace.OpenConfiguration()
        cfg.createsNewApplicationInstance = true
        cfg.activates = false

        NSWorkspace.shared.openApplication(at: hostURL, configuration: cfg) { _, error in
            if let error {
                NSLog("AFSC: broker launch failed: \(error)")
            } else {
                NSLog("AFSC: brokered \(script) for \(paths.count) item(s)")
            }
        }
    }
}
