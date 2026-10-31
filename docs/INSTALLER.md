# Windows installer

Build: `powershell -ExecutionPolicy Bypass -File scripts/build_installer.ps1`
Output: `build/CardBattlePrototype-Setup-<version>.exe` (the `build/` folder is git-ignored).

## One-time setup on a build machine

- Godot 4.7.2 export templates, installed under `%APPDATA%\Godot\export_templates\4.7.2.stable\` (Editor > Manage Export Templates, or extract the official `.tpz`).
- Inno Setup 6: `winget install JRSoftware.InnoSetup`.

## Releasing a new version

1. Bump `config/version` in `project.godot` (dotted numbers, e.g. `0.2.0`).
2. Run the build script.
3. Publish `build/CardBattlePrototype-Setup-<version>.exe` as a GitHub release tagged `v<version>` (for example `gh release create v0.2.0 build/CardBattlePrototype-Setup-0.2.0.exe`).

## What the installer does

- Per-user install by default (no admin prompt), Start Menu entry, optional desktop shortcut, uninstaller.
- Same app id on every build, so running a newer setup upgrades in place; saves live in Godot's user data folder and are untouched.
- Running an older setup over a newer install is refused with a message.
- On launch it asks the GitHub API for the latest release. If that is newer than the setup being run, it offers to open the download page. Skipped silently when offline, in silent mode, or when the repository is private (GitHub answers 404 without credentials). A token is deliberately not embedded in the installer.

## Limits

- The exe is unsigned, so Windows SmartScreen may warn on first run.
- The exe has the default Godot icon (needs rcedit and an `.ico` to change).
- The game's own `exclude_filter` leaves out tests, tools, scripts and docs; the export is the full game in one embedded-pck exe (about 110 MB, 28 MB compressed).
