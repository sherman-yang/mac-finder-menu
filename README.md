# mac-finder-menu

Finder right-click menu items for macOS transparent file compression (AFSC / decmpfs).

Two actions, both at the **top level** of the context menu:

| Menu item | What it does |
|---|---|
| **Compress (APFS Transparent)** | Recursively applies AFSC compression to the selection via `applesauce`, then reports before / after / savings |
| **Show Actual Size on Disk** | Reports real on-disk usage vs logical size, plus compression coverage: how many files are compressed, how many are not, and how much those still occupy |

Files stay in place, keep their names, and open normally in every app. Only the
disk footprint shrinks — the kernel decompresses on read.

## Why

macOS has had transparent per-file compression since 10.6 and it works on APFS,
but unlike NTFS there is **no directory attribute that auto-compresses new
files**. Compression is applied per file, once, by a userspace tool. This repo
wraps that tool in a right-click menu so it is a two-click operation instead of
a terminal command.

See [docs/FINDINGS.md](docs/FINDINGS.md) for the measured behaviour of AFSC on
macOS 26.6 — what survives a copy, what silently drops compression, and how to
detect compressed files.

## Requirements

- macOS 26.0 or later (built and verified on 26.6, Apple Silicon)
- Xcode **Command Line Tools** (`swiftc`, `codesign`) — full Xcode is not needed
- [`applesauce`](https://github.com/Dr-Emann/applesauce):
  ```
  brew install Dr-Emann/homebrew-tap/applesauce
  ```
  The compress action expects it at `/opt/homebrew/bin/applesauce` and shows a
  dialog with install instructions if it is missing.

No Apple Developer account is required — the extension is ad-hoc signed.

## Install

```
./install.sh
```

This builds and installs two front-ends:

1. **FinderSync extension** → `/Applications/AFSC Finder Menu.app`, registered
   with `pluginkit`. Produces the top-level menu items.
2. **Automator Quick Actions** → `~/Library/Services/`. Same two actions in the
   Services submenu, as a fallback for iCloud-managed locations (see
   Limitations).

Finder restarts at the end. If the extension does not appear, check it is
enabled under **System Settings → General → Login Items & Extensions →
Extensions → Finder**.

## Uninstall

```
./uninstall.sh
```

Already-compressed files are untouched and stay readable — compression is a
filesystem feature, not something this tool has to be present for. To undo
compression itself:

```
applesauce decompress <path>
```

## Limitations

- **iCloud Desktop & Documents.** When "Desktop & Documents Folders" sync is on,
  Finder's own CloudDocs menu provider suppresses FinderSync extension items.
  The Quick Actions in the Services submenu still work there — that is why both
  front-ends are installed.
- **Editing a file drops its compression.** Any app that rewrites the file
  writes it back uncompressed. Re-run the action after changes. This makes AFSC
  a good fit for archives and a poor fit for active working directories.
- **Incompressible files are re-read on every run.** Files that cannot be
  compressed get no marker, so each run reads them again to find out. Measured:
  400 MB of incompressible data costs ~1 s every time. Do not point this at a
  large photo or video library repeatedly.
- **Already-compressed files are skipped instantly** — those *do* carry the
  `UF_COMPRESSED` flag, so re-running on a mostly-compressed tree is nearly
  free.

## Guards

The compress action refuses to touch:

| Guard | How it is detected |
|---|---|
| SIP-protected system paths | `SF_RESTRICTED` (`0x80000`) on the target — no hardcoded path list |
| Volume roots | the target is itself a mount point |
| Home folder root | target equals `${HOME:A}` |
| Non-APFS/HFS+ volumes | filesystem type from `mount`, matched to the longest containing mount point |

Skipped items are listed with their reason in the result dialog; the rest of the
selection is still processed.

`applesauce --verify` is enabled: every file is read back and compared before the
compressed version replaces the original. Measured cost on mixed data: +32 %
wall clock.

## Layout

```
scripts/              compress.zsh, showsize.zsh — the actual logic, single source of truth
finder-extension/     Swift FinderSync app extension (top-level menu items)
  src/                FinderSyncExt.swift, host.swift
  ext.entitlements    sandbox + temporary exception (both mandatory, see FINDINGS)
  build.sh
quick-actions/        Automator .workflow builder (Services submenu fallback)
install.sh
uninstall.sh
docs/FINDINGS.md      measured macOS behaviour behind every design decision
```

Both front-ends embed the same two scripts from `scripts/` at build time, so
there is one place to edit. Re-run `./install.sh` after changing them.

## License

MIT
