import AppKit

// The host app has three jobs.
//
// Spool mode (launched by the Finder extension): the sandboxed extension cannot
// run menu item scripts itself — everything it spawns inherits the sandbox —
// and LaunchServices does not deliver OpenConfiguration.arguments from a
// sandboxed caller. So the extension writes the request to a spool directory
// and launches this app bare; drain the spool, run each request's script
// unsandboxed, and exit. Requests are claimed by atomic rename so concurrent
// instances never run one twice, and anything older than a minute is discarded
// as stale rather than replayed.
//
// `--run <script> <path>…`: same execution path, arguments supplied directly.
// Kept for command-line testing.
//
// UI mode (double-clicked, spool empty): explain where to switch the extension
// on.
@main
enum Host {
    // The extension aims for the real-home spool, but home resolution inside the
    // sandbox has already burned us once (both NSHomeDirectory() and
    // homeDirectory(forUser:) report the container). Draining the container's
    // view of the same path as well makes delivery independent of which home the
    // extension ended up with.
    static let spoolDirs = [
        NSHomeDirectory() + "/Library/Application Support/AFSCFinderMenu/spool",
        NSHomeDirectory() + "/Library/Containers/local.afsc.FinderMenu.Extension"
            + "/Data/Library/Application Support/AFSCFinderMenu/spool",
    ]

    static func main() {
        let args = CommandLine.arguments

        if let flag = args.firstIndex(of: "--run"), flag + 1 < args.count {
            let script = args[flag + 1]
            let paths = Array(args[(flag + 2)...])
            exit(runScript(script, paths: paths))
        }

        if let status = drainSpool() {
            exit(status)
        }

        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        app.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.messageText = "AFSC Finder Menu"
        alert.informativeText = """
        This app hosts the Finder extension and runs its menu actions — there is \
        nothing to configure here.

        Enable the extension in:
        System Settings → General → Login Items & Extensions → Extensions → Finder

        Then right-click any file or folder in Finder.
        """
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    /// Returns nil when there was nothing to process (→ UI mode).
    private static func drainSpool() -> Int32? {
        var processed = false
        var status: Int32 = 0

        for dir in spoolDirs {
            if let rc = drain(dir: dir) {
                processed = true
                if rc != 0 { status = rc }
            }
        }

        return processed ? status : nil
    }

    /// Returns nil when this directory yielded no requests.
    private static func drain(dir spoolDir: String) -> Int32? {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(atPath: spoolDir),
              !entries.isEmpty
        else { return nil }

        var processed = false
        var status: Int32 = 0

        for name in entries.sorted() where name.hasSuffix(".json") {
            let path = spoolDir + "/" + name
            let claimed = path + ".claimed-\(getpid())"
            // Atomic claim: whichever instance wins the rename owns the request.
            guard (try? fm.moveItem(atPath: path, toPath: claimed)) != nil else { continue }
            defer { try? fm.removeItem(atPath: claimed) }

            if let age = try? fm.attributesOfItem(atPath: claimed)[.modificationDate] as? Date,
               Date().timeIntervalSince(age) > 60 {
                NSLog("AFSC host: discarding stale request \(name)")
                continue
            }

            guard let data = fm.contents(atPath: claimed),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let script = obj["script"] as? String,
                  let paths = obj["paths"] as? [String]
            else {
                NSLog("AFSC host: malformed request \(name)")
                continue
            }

            processed = true
            let rc = runScript(script, paths: paths)
            if rc != 0 { status = rc }
        }

        return processed ? status : nil
    }

    private static func runScript(_ script: String, paths: [String]) -> Int32 {
        // Script names are internal identifiers, never paths.
        guard !script.contains("/"), !paths.isEmpty,
              let scriptPath = Bundle.main.path(forResource: script, ofType: "zsh")
        else {
            NSLog("AFSC host: bad request: \(script) \(paths)")
            return 1
        }

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/zsh")
        task.arguments = [scriptPath] + paths
        do {
            try task.run()
        } catch {
            NSLog("AFSC host: failed to run \(scriptPath): \(error)")
            return 1
        }
        task.waitUntilExit()
        return task.terminationStatus
    }
}
