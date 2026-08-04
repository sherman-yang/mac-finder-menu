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

        return menu
    }

    // MARK: - Actions

    @objc func runCompress(_ sender: AnyObject?) {
        run(script: "compress")
    }

    @objc func runShowSize(_ sender: AnyObject?) {
        run(script: "showsize")
    }

    @objc func runVSCode(_ sender: AnyObject?) {
        run(script: "vscode")
    }

    @objc func runVSCodeAdd(_ sender: AnyObject?) {
        run(script: "vscode-add")
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

    private func run(script: String) {
        let paths = selectedPaths()
        guard !paths.isEmpty else {
            NSLog("AFSC: nothing selected")
            return
        }
        guard let scriptPath = Bundle.main.path(forResource: script, ofType: "zsh") else {
            NSLog("AFSC: bundled script \(script).zsh not found")
            return
        }

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/zsh")
        task.arguments = [scriptPath] + paths

        // The extension is sandboxed (pkd requires it), so surface anything the
        // child trips over instead of failing silently.
        let errPipe = Pipe()
        task.standardError = errPipe
        task.terminationHandler = { proc in
            let data = errPipe.fileHandleForReading.readDataToEndOfFile()
            let err = String(data: data, encoding: .utf8) ?? ""
            NSLog("AFSC: \(script).zsh exited \(proc.terminationStatus)"
                  + (err.isEmpty ? "" : " — stderr: \(err)"))
        }

        do {
            try task.run()
            NSLog("AFSC: launched \(script).zsh for \(paths.count) item(s)")
        } catch {
            NSLog("AFSC: failed to launch \(scriptPath): \(error)")
        }
    }
}
