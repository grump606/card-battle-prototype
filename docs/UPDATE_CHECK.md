# Update check

On launch the game asks GitHub whether a newer release exists. If one does, a small bar at the bottom of the first screen (character select, or the saved-run Continue prompt) says `Update available: v0.3.1 (you have 0.3.0)` with a **Download** button (opens the releases page in the browser) and an **x** to dismiss it. It never blocks play, and it is not shown once a run is under way.

## Privacy

The game contacts `api.github.com` once per launch: a single HTTPS `GET https://api.github.com/repos/grump606/card-battle-prototype/releases/latest` with a `User-Agent: card-battle-prototype/<version>` header and an `Accept` header. Nothing else is sent: no identifiers, no save data, no tokens, no telemetry. GitHub sees the usual connection details (IP address) like for any web request. The reply is read, never executed, and nothing is downloaded.

## Turning it off

Set the environment variable `CARD_BATTLE_NO_UPDATE_CHECK` to any non-empty value before launching, for example `$env:CARD_BATTLE_NO_UPDATE_CHECK = "1"`. The check is also skipped on its own in headless runs (tests, CI, the sims), so those never touch the network.

## Behaviour and safety

- The request is asynchronous (a worker thread, 5 s timeout, reply capped at 64 KB), so the game never waits on it.
- Every failure is silent: offline, timeout, HTTP error or rate limit (anything but 200), a reply that is not JSON, a missing or odd `tag_name`. No notice, no dialog, no warning in the log.
- The reply is untrusted. Only `tag_name` is read, and only if it matches `^[vV]?[0-9]{1,4}(\.[0-9]{1,4}){0,3}$`. The page Download opens is the constant `https://github.com/grump606/card-battle-prototype/releases/latest`; no URL from the reply is ever used.

## Version comparison

The running version is `application/config/version` in `project.godot`. Versions are compared as dotted numbers, group by group, with missing groups counted as 0, like the installer's `CompareVersions`: `1.2.10` is newer than `1.2.9`, `0.3.1` is newer than `0.3`, and `0.3` equals `0.3.0`. A notice shows only when the release is strictly newer. If either side is not a valid version there is no notice.

## Code and tests

- `run/update_check.gd` (`UpdateCheck`): the pure logic (enable rules, tag validation, version compare, reply parsing, notice text).
- `run/update_notice.gd` (`UpdateNotice`): the bar and the `HTTPRequest`. `handle_response(code, body)` takes a reply directly, which is how tests and `tools/update_sheet.gd` (screenshots) work without a network.
- Tests: `tests/update_check_tests.gd` (in `run_tests.gd`) and `tests/ui_update_notice_test.gd` (`scripts/check.ps1`).
