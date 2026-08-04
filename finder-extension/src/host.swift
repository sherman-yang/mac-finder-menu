import AppKit

// The host app exists only to carry the Finder Sync extension bundle. Launching
// it just explains where to switch the extension on.
@main
enum Host {
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        app.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.messageText = "AFSC Finder Menu"
        alert.informativeText = """
        This app only hosts the Finder extension — there is nothing to configure here.

        Enable it in:
        System Settings → General → Login Items & Extensions → Extensions → Finder

        Once enabled, right-click any file or folder in Finder to get:
          • Compress (APFS Transparent)
          • Show Actual Size on Disk
        """
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
