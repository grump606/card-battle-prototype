# Continuous integration

`.github/workflows/check.yml` runs on every push to `main` and every pull request, on a
`windows-latest` runner. It downloads the pinned Godot engine, then runs
`scripts/check.ps1` (import, headless tests, main-scene smoke load, all UI tests). The job
fails if the script exits non-zero. Permissions are `contents: read`, the job times out after
30 minutes, and a newer run on the same ref cancels the older one.

Everything runs headless (`--headless`), so no GPU or display is needed.

## Run it locally

The script finds the engine in this order: `-Godot` parameter, `GODOT_EXE`, `GODOT`, then
`Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe` in the repo root.

```powershell
$env:GODOT_EXE = 'C:\path\to\Godot_v4.7.2-stable_win64_console.exe'
powershell -ExecutionPolicy Bypass -File scripts/check.ps1
# or
powershell -ExecutionPolicy Bypass -File scripts/check.ps1 -Godot 'C:\path\to\...console.exe'
```

`scripts/build_installer.ps1` also honours `GODOT_EXE`.

## Update the engine version

In `.github/workflows/check.yml`:

1. Change `GODOT_VERSION` (for example `4.7.3-stable`).
2. Copy the SHA512 of `Godot_v<version>_win64.exe.zip` from
   `https://github.com/godotengine/godot-builds/releases/download/<version>/SHA512-SUMS.txt`
   into `GODOT_ZIP_SHA512`. The cache key includes both values, so a change refetches.
3. Update the local path in `scripts/check.ps1` and `scripts/build_installer.ps1` if you
   want the local default to match.
