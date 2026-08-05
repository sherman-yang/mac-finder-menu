# mac-finder-menu

Add your own items to the macOS Finder right-click menu.

Each menu item is a plain `zsh` script that receives the selected file and
folder paths as arguments. The project handles the part that is actually hard:
getting an item to show up in Finder's context menu at all.

## Menu items included

Four ship with the project today.

| Menu item | What it does | Also in Services submenu |
|---|---|---|
| **Open in VS Code (New Window)** | Opens the selection as a fresh workspace window | no |
| **Add to VS Code Workspace** | Sends the selection to the last active window instead | no |
| **Compress (APFS Transparent)** | Applies AFSC transparent compression to the selection | yes |
| **Show Actual Size on Disk** | Real on-disk usage vs logical size, plus compression coverage | yes |

The Services-submenu copies exist for iCloud-managed Desktop/Documents, where
Finder suppresses top-level extension items. The VS Code items skip them — a
submenu duplicate of something already at the top level is noise — at the cost
of not being offered in those iCloud locations.

### Compress (APFS Transparent)

Recursively applies AFSC compression to the selection via
[`applesauce`](https://github.com/Dr-Emann/applesauce), then reports before /
after / savings. Files keep their names and open normally in every app — the
kernel decompresses on read. Only the disk footprint shrinks.

Runs with `--verify`, so every file is read back and compared before the
compressed version replaces the original. Measured cost on mixed data: +32 %
wall clock.

Refuses to touch:

| Guard | How it is detected |
|---|---|
| SIP-protected system paths | `SF_RESTRICTED` (`0x80000`) on the target — no hardcoded path list |
| Volume roots | the target is itself a mount point |
| Home folder root | target equals `${HOME:A}` |
| Non-APFS/HFS+ volumes | filesystem type from `mount`, matched to the longest containing mount point |
| Files open for writing | `lsof` snapshot refreshed between batches (≤5 s stale); compression swaps the inode, so a writer on the old one would lose data. Only w/u modes are excluded — replacing under a reader is safe |

Skipped items are listed with their reason in the result dialog; the rest of the
selection is still processed.

### Open in VS Code (New Window) / Add to VS Code Workspace

Two separate actions, both accepting files and folders.

*New Window* runs `code --new-window` on the whole selection, so it always lands
in a fresh workspace window.

*Add to Workspace* sends the selection to the last active window instead. The
two kinds of item mean different things there, so they take different flags:
folders go through `--add` to become workspace roots (VS Code documents `--add`
as taking a `<folder>`), files through `--reuse-window` to open as editors in
that same window. A mixed selection gets both. With no VS Code running there is
no window to add to, so the selection is simply opened.

The `code` CLI is only ever used against an already-running VS Code, where it
does nothing but IPC. When VS Code is not running, the selection goes through
`open -a` instead, so LaunchServices launches it — never the sandboxed Finder
extension, whose sandbox a child VS Code would inherit. Whether it is running
is read via `NSRunningApplication` (through `osascript`), not `pgrep`: the
sandbox blocks reading other processes' command lines, which makes `pgrep -f`
return nothing there (docs/FINDINGS.md).

### Show Actual Size on Disk

Reports real on-disk usage vs logical size, plus compression coverage: how many
files are compressed, how many are not, and how much those still occupy. Finder
itself shows only the logical size, so this is the way to see whether a folder
is actually compressed and how much is left on the table.

## How menu items get into Finder

macOS offers exactly two placements, and this project installs both because
neither covers every case.

| Front-end | Placement | Mechanism |
|---|---|---|
| `finder-extension/` | **Top level** of the context menu | FinderSync app extension (`FIFinderSync`) — the same route Dropbox and BetterZip use |
| `quick-actions/` | Services / Quick Actions submenu | Automator `.workflow` bundles |

Services and Quick Actions can never be promoted out of their submenu — a
FinderSync extension is the only supported way to reach the top level. The
Quick Actions exist as a fallback because Finder suppresses FinderSync items in
iCloud-managed locations (see Limitations).

The extension itself never runs the scripts: pkd forces it into the App
Sandbox, which everything it spawns would inherit — that silently broke any
action whose tooling spawns further processes (the VS Code CLI, for one). On a
menu click it writes the request to a spool directory and launches the **host
app** bare through LaunchServices; the host — unsandboxed, parented to
launchd — drains the spool and runs the script with normal user rights. (A
spool file rather than argv because LaunchServices strips
`OpenConfiguration.arguments` from sandboxed callers.) Details in
[docs/FINDINGS.md](docs/FINDINGS.md).

Both front-ends embed the same scripts from `scripts/` at build time, so a menu
item's logic has one home. Within the top-level block, items appear in the
order they are added in `menu(for:)` — the two VS Code items first. The
Services submenu is sorted alphabetically by macOS; item order there is not
controllable.

## Adding your own menu item

1. Write `scripts/<name>.zsh`. It receives the selected paths as `"$@"`. Show a
   result with `osascript` if the action needs one — `vscode.zsh` is the
   shortest example, `showsize.zsh` the most complete.
2. Register it:
   - `finder-extension/src/FinderSyncExt.swift` — add an `NSMenuItem` in
     `menu(for:)` plus an `@objc` action calling `run(script:)`
   - `quick-actions/build_quickactions.py` — add an entry to `ACTIONS` only if
     the item should also appear in the Services submenu (the iCloud
     Desktop/Documents fallback)
3. `./install.sh` — it also removes previously installed Quick Actions that are
   no longer built, keyed on the `MacFinderMenuOwned` marker

The build copies every `scripts/*.zsh` into the extension, so there is nothing
to edit in `build.sh`. Menu items are declared in source rather than in a config
file, so adding one means editing those two places.

## Requirements

- macOS 26.0 or later (built and verified on 26.6, Apple Silicon)
- Xcode **Command Line Tools** (`swiftc`, `codesign`) — full Xcode is not needed
- **No Apple Developer account.** The extension is ad-hoc signed. It must be
  sandboxed, which is a hard requirement of `pkd`, but a signing identity is not.
Per-menu-item requirements, each reported in a dialog if missing:

- **Compress (APFS Transparent)** needs `applesauce` at
  `/opt/homebrew/bin/applesauce`:
  ```
  brew install Dr-Emann/homebrew-tap/applesauce
  ```
- **Open in VS Code (New Window)** and **Add to VS Code Workspace** need Visual
  Studio Code in `/Applications` or `~/Applications` (Spotlight is used as a
  fallback). Adding to an existing workspace additionally needs the bundled
  `code` CLI, since LaunchServices cannot express it.

## Install

```
./install.sh
```

Builds and installs both front-ends, registers the extension with `pluginkit`,
and restarts Finder. If the top-level items do not appear, check the extension
is enabled under **System Settings → General → Login Items & Extensions →
Extensions → Finder**.

## Uninstall

```
./uninstall.sh
```

Files compressed by the bundled action are untouched and stay readable —
compression is a filesystem feature, not something this tool has to be present
for. To undo compression itself: `applesauce decompress <path>`.

## Limitations

- **iCloud Desktop & Documents.** With "Desktop & Documents Folders" sync on,
  Finder's own CloudDocs menu provider suppresses FinderSync extension items.
  The Services submenu still works there — that is why both front-ends are
  installed.
- **The extension must live in `/Applications`.** `pkd` does not discover
  extensions in `~/Applications`.
- Specific to the bundled compress action: editing a file drops its
  compression, and incompressible files are re-read on every run because they
  carry no "already tried" marker. Details and measurements in
  [docs/FINDINGS.md](docs/FINDINGS.md).

**If you used a build from before the broker change**, compressed files were
created by a sandboxed process and so were stamped with `com.apple.quarantine`,
which makes Gatekeeper block native extensions (`.so`, `.dylib`) on load — a
virtualenv compressed by such a build stops importing. Audit and repair:

```sh
find ~/your-projects -type f -xattrname com.apple.quarantine   # single fast pass
xattr -dr com.apple.quarantine <dir>                           # strip
```

## Layout

```
scripts/              the menu item scripts — single source of truth
finder-extension/     Swift FinderSync app extension (top-level menu items)
  src/                FinderSyncExt.swift, host.swift
  ext.entitlements    app-sandbox only (pkd requires it; actions run in the host)
  build.sh
quick-actions/        Automator .workflow builder (Services submenu)
install.sh
uninstall.sh
docs/FINDINGS.md      measured macOS behaviour behind every design decision
```

## License

MIT
