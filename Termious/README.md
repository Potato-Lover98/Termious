# Termious

A sandboxed terminal emulator for iOS, written entirely in Swift. It ships a
**custom shell** (not bash, not zsh — a small one written from scratch) that
runs inside the app sandbox and can operate on folders you grant from the iOS
Files app. Includes **aero** — a custom package manager that downloads from
GitHub — plus **sudo**, **chown**, and 50+ commands.

> ⚠️ iOS does not expose the system shell to third-party apps. Termious
> implements its own tokenizer, parser, and builtin commands so everything
> runs inside the app sandbox — no JIT, no private APIs, no jailbreak.

## Features

### Custom shell
- Tokenizer (quotes, escapes, pipes, redirects), parser, pipeline executor
- Pipes (`|`), output redirect (`>`, `>>`), input redirect (`<`), statements (`;`)
- Alias expansion, environment variables, command history
- Tab completion, ANSI-colored output

### Aero package manager (`aero`)
A custom package manager that downloads repositories from GitHub:
```
aero install torvalds/linux                 # download a repo
aero install torvalds/linux --name kernel   # name it locally
aero install owner/repo --ref dev           # specific branch
aero search "terminal emulator"             # search GitHub
aero list                                   # installed packages
aero info <name>                            # package details
aero files <name>                           # list package files
aero path <name>                            # show install path
aero delete <name>                          # remove a package
aero update <name>                          # re-download latest
```
Downloads use the GitHub codeload API (zipball), extracted with a built-in
zip decoder (STORED + DEFLATE via Compression framework). Manifest is
persisted in Application Support.

### Sudo (`sudo`)
Password-protected privilege elevation. Default password is `alpine`.
```
sudo ls -la          # prompts for password, then runs as root
sudo -k              # invalidate session
sudo -l              # list privileges
passwd               # change password (presents dialog)
passwd newpassword   # set password directly
```
Session stays authenticated for 5 minutes. Password is hashed (SHA-256 +
salt, 1000 iterations) and stored in UserDefaults.

### Virtual file ownership
- `chown owner[:group] file...`  — change virtual owner/group
- `chgrp group file...`           — change group
- `chmod 755 file...`             — change permissions (octal)
- `ls -l` shows owner, group, and permissions

### 50+ builtin commands
**Files:** `ls cd pwd cat mkdir rm cp mv touch ln tree find stat du file basename dirname realpath`
**Text:** `head tail wc grep sed awk cut tr sort uniq rev paste tac nl diff`
**Archives:** `zip unzip tar`
**Network:** `wget curl ping`
**System:** `whoami id uname hostname uptime df free env export date sleep`
**Crypto:** `hash (md5/sha256) base64`
**Shell:** `echo clear exit history alias which man time watch reboot info credits colors seq yes`
**Package:** `aero`
**Privilege:** `sudo passwd chown chmod chgrp`
**Files app:** `open bookmarks`

### Legal Files-app access
Uses `UIDocumentPickerViewController` + security-scoped bookmarks. Type
`open` to grant access to a folder — it becomes the new root `/`.

## Project layout

```
Termious/
├── project.yml                         # XcodeGen spec
├── .github/workflows/build-ipa.yml     # AltStore IPA CI
└── Termious/
    ├── TermiousApp.swift
    ├── Support/
    │   ├── Info.plist
    │   ├── Termious.entitlements
    │   ├── PasswordManager.swift       # Sudo password (hashed)
    │   ├── SudoSession.swift           # Sudo auth session
    │   ├── FileMetadataStore.swift     # Virtual ownership/permissions
    │   ├── AeroPackageManager.swift    # GitHub downloader + zip extractor
    │   └── MD5.swift                   # MD5 implementation
    ├── Shell/
    │   ├── VirtualFileSystem.swift
    │   ├── Tokenizer.swift
    │   ├── Parser.swift
    │   └── ShellHost.swift             # Pipeline + signal handling
    ├── Commands/
    │   ├── CommandRegistry.swift
    │   ├── CoreCommands.swift          # ls, cd, pwd, echo, cat, help…
    │   ├── FileCommands.swift           # mkdir, rm, cp, mv, touch
    │   ├── TextCommands.swift           # head, tail, wc, grep, sort, find…
    │   ├── AeroCommand.swift            # aero package manager
    │   ├── SudoCommands.swift           # sudo, passwd, chown, chmod, chgrp
    │   ├── NetworkCommands.swift        # wget, curl, zip, unzip, tar
    │   └── AdvancedCommands.swift       # sed, awk, diff, ping, hash, man…
    └── UI/
        ├── Theme.swift
        ├── TerminalViewController.swift # Password alerts, man pages, watch
        ├── ConsoleView.swift
        └── InputBar.swift
```

## Build locally

Requirements: macOS 14+, Xcode 15+, [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```sh
brew install xcodegen
cd Termious
xcodegen generate
open Termious.xcodeproj
```

## Sideload via AltStore

1. Push a tag `v1.0.0` to trigger the **Build IPA for AltStore** workflow.
2. The workflow produces an unsigned `Termious.ipa` + `altstore.json` manifest.
3. In AltStore: add your GitHub releases URL as a source, or sideload the `.ipa` directly.
4. AltStore re-signs with your personal Apple ID and installs.

## License

MIT