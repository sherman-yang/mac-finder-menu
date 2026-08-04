# Measured behaviour

Everything here was measured on this machine, not recalled from documentation.

**Test environment:** macOS 26.6 (build 25G72), Apple Silicon, APFS,
`applesauce` 0.5.28, August 2026.

Sections 1–3 cover getting a custom item into the Finder context menu at all —
the part of this project that is reusable for any menu item. Section 4 covers
the compression behaviour behind the two items that ship with it.

---

## 1. Getting an item into the Finder context menu

### Services and Quick Actions cannot be promoted

Automator Quick Actions and Services always render inside their submenu. The
only supported route to a **top-level** context menu item is a **FinderSync app
extension** (`FIFinderSync`) — which is what Dropbox, BetterZip, Beyond Compare
and similar apps use.

`defaults write -g NSServicesMinimumItemCountForContextSubmenu -int 999` flattens
the Services submenu inline. The key still exists in the macOS 26.6 AppKit
(the string is present in the dyld shared cache). It is global, though: on a
machine with 17 file/folder services it produces a worse menu than the submenu.

### pkd requires a sandboxed extension — but not a Developer ID

This was the whole ballgame, and `pluginkit` gives no useful feedback: it exits
0 and registers nothing. The reason only shows up in the log:

```
pkd: Registering plugin at [...]
pkd: plugin UNINSTALLED; bundleID: [...], contained in [(null)]
```

Comparing field by field against a working extension on the same machine left
two differences: a `teamID`, and the sandbox entitlement. Adding
**`com.apple.security.app-sandbox`** to the ad-hoc signature made it register
immediately.

**An ad-hoc signature (`codesign -s -`) is sufficient. No Apple Developer
account is needed. Sandboxing is mandatory.**

To watch this for yourself:

```sh
log stream --style compact --predicate 'process == "pkd"'
```

### A sandboxed extension can still do the work

The sandbox does not have to be a dead end.
`com.apple.security.temporary-exception.files.absolute-path.read-write = /`
grants the extension — and any child process it spawns — read-write access
everywhere. Verified end-to-end: right-click → Compress on a 17 MB folder
produced 88 KB on disk with `UF_COMPRESSED` set on files in subdirectories, no
sandbox denials logged.

This is what makes "menu item = shell script" viable at all: the extension
spawns `/bin/zsh` with the selected paths as arguments, and the child inherits
the sandbox *including* the exception.

### Other requirements found by comparison

The `.appex` `Info.plist` needs all of these, or pkd discovers the plug-in and
then drops it:

- `NSPrincipalClass = NSApplication`
- `LSUIElement = true`
- `CFBundleSupportedPlatforms = [MacOSX]`
- `CFBundlePackageType = XPC!`

Build notes:

- Link the extension with `-Xlinker -e -Xlinker _NSExtensionMain` — app
  extensions enter through `NSExtensionMain`, not `main()`.
- Use `@objc(FinderSyncExt)` on the principal class so `Info.plist` can name it
  without Swift's `<module>.<class>` mangling.
- Sign inside-out: extension first, then the containing app. Only the extension
  carries the entitlements.

### Install location matters

`pkd` does **not** pick up extensions from `~/Applications`. The same bundle in
`/Applications` registers immediately.

### iCloud Desktop & Documents suppresses FinderSync items

With "Desktop & Documents Folders" sync on, `~/Desktop` is a CloudDocs-managed
location (`~/Library/Mobile Documents/com~apple~CloudDocs/Desktop` is a symlink
to it, and the context menu grows *Remove Download* / *Keep Downloaded*).
FinderSync extension items do not appear there. The same folder moved to a plain
local path shows them immediately.

The Services submenu **is** present on iCloud items, so Automator Quick Actions
remain a working fallback for those locations. This is the reason this project
installs both front-ends rather than just the extension.

---

## 2. Automator gotchas

**`inputMethod` is inverted from the obvious reading.** In the Run Shell Script
action: `0` = pass input to **stdin**, `1` = pass input as **arguments**. With
`0`, `"$@"` is empty and the script silently does nothing.

---

## 3. zsh gotchas

Two zsh-specific traps hit while writing the menu item scripts:

- **`path` is a special variable** tied to `$PATH` as an array. A local named
  `path` makes `${path[1,5]}` do array subscripting instead of string slicing,
  so prefix comparisons silently never match. Use `[[ $tgt == "$m"/* ]]` and a
  different variable name.
- **`status` is read-only** (an alias for `$?`). Assigning to it aborts the
  script.

---

## 4. AFSC compression — the behaviour behind the bundled menu items

Transparent compression (AFSC / `decmpfs`) exists on both HFS+ and APFS. The
kernel decompresses on read, so files keep their names, sizes and behaviour.

| Input | Result |
|---|---|
| 20 MB repetitive text | 19532 KB → 136 KB on disk (99.3 %) |
| 20 MB `/dev/urandom` | 0.0 %, flag not set — skipped |
| 30 MB zip of random data | not compressed |
| Real JPEG (8.9 MB) | not compressed |

`applesauce` has **no extension blacklist**. It attempts compression on every
file and discards the result unless it beats the `-r 0.95` ratio threshold.
Content decides, not the filename.

### The NTFS difference

NTFS marks a *directory*; the filesystem driver then compresses every new file
written into it. macOS has nothing equivalent.

```
compress a directory, then create a new file inside it
  → the new file is NOT compressed
append one line to a compressed file
  → compression is lost, file returns to full size on disk
```

This is the single most important behavioural difference and the reason AFSC
suits archives rather than active working directories.

### What survives a copy

| Operation | Compression preserved? |
|---|---|
| Finder drag-copy / Duplicate | yes |
| `ditto` | yes |
| `cp -c` (APFS clone) | yes |
| `tar` (bsdtar round-trip) | yes |
| `cp` | **no** |
| `cp -p` | **no** |
| `rsync -a` (openrsync, macOS 26) | **no** |

`rsync -aX` produced no file at all — `-X` is not supported by the openrsync
that ships with macOS 26.

`ditto --hfsCompression <src> <dst>` compresses during the copy without any
third-party tool. Apple's own man page scopes this narrowly: it is *"only
intended to be used in installation and backup scenarios that involve system
files."*

### Detecting compressed files

Compression status is the `UF_COMPRESSED` flag (`0x20`) in `st_flags`, **not** an
extended attribute — `xattr` does not list `com.apple.decmpfs`.

```sh
ls -lO file                            # 5th column shows "compressed"
stat -f '%N %f' file                   # 32 = compressed, 0 = not
find DIR -type f ! -flags compressed   # every uncompressed file in a tree
```

In awk, test the bit without bitwise functions (BSD awk has none):
`int(flags / 32) % 2 == 1`.

### Re-running is cheap; incompressible data is not

Already-compressed files carry the flag and are skipped without reading:

```
run 2 (1 already compressed + 1 new):  New Files Compressed: 1 (2 total)
run 3 (all compressed, 24 MB):         0.113 s
```

Incompressible files get **no** marker, so every run reads them again:

```
400 MB of random data — run 1: 1.23 s   run 2: 1.04 s   run 3: 0.78 s
```

### `--verify` cost

406 MB of mixed data: 0.552 s without, 0.727 s with. **+32 %**, not the doubling
one might assume. Cheap enough to leave on.

### SIP detection

`SF_RESTRICTED` (`0x80000`) identifies SIP-protected paths without maintaining a
path list:

| Path | Restricted |
|---|---|
| `/System` `/usr` `/bin` `/sbin` | yes |
| `/` `/Applications` `/Library` `/usr/local` `~` `~/Library` | no |
