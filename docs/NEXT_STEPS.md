# Next steps

Last updated after the longer run. Everything below is on `main` and pushed (`89aa78e`) unless noted. The v0.2.0 release predates the longer run.

## State

- Three characters (Deserter, Pickpocket, Medium) with class cards, a neutral pool, a character select screen, a pause menu and save/resume.
- Classes plan: all seven phases done (infrastructure, select screen, the three classes' mechanics and cards, bots and balance, story). Per-character boarding, Conductor and Last Light beats live under `data/story/<id>/` with a neutral fallback (draft text, edit freely). Details: `docs/CLASSES_PLAN.md`.
- Card rewards: designs A and C are in (no repeats past 2 copies, skip pays 10 gold, free once-per-run Remove and Heal 12). See `docs/REWARDS_PROPOSAL.md`.
- Artwork is all code-drawn (no image assets): cards with class palettes and damage icon variants, character select panels, enemy portraits with status chips beside the figure, battle backdrop, vendor stall, pause scene, and rest stop, story and end-card scenes. Design notes are in `docs/*_ART_DESIGN.md` and `docs/SCREEN_ART_DESIGN.md`.
- The damage preview on cards matches the damage actually dealt (shared `CardEffect.raw_damage`).
- Relics: 12 relics (3 per class, 3 neutral) sold one per vendor visit, so at most three per run (three vendors). Combat hooks, vendor stock, save support and code-drawn badges with a strip on the battle and run screens are in. Design: `docs/RELICS_DESIGN.md`, `docs/RELIC_ART_DESIGN.md`.
- Windows installer: `scripts/build_installer.ps1` builds `build/CardBattlePrototype-Setup-<version>.exe` (Inno Setup, upgrades in place, refuses downgrades). Its GitHub update check only works once the repo is public. Details: `docs/INSTALLER.md`. v0.2.0 (relics, the select screen's Back button, the installer) is published as a GitHub release with the setup exe attached; the repo is private, so only people with repo access can download it. To ship a new version: bump `config/version`, run the build script, and `gh release create v<version> build/CardBattlePrototype-Setup-<version>.exe`.
- The character select screen has a Back button when it is reached from the Continue prompt or the end card (none on a first launch with no save).
- The run is 21 stops: 8 regular fights, the Brakeman as a mid-boss at stop 9 (pays gold plus 15, offers a card, the run continues), the Conductor last, 3 vendors, 4 rests and story beats 0 to 3 (the "empty platform" beat now shows after the mid-boss). Regular fights ramp 1.2% HP and damage per fight number, so later fights are tougher. Old 12-stop saves are rejected cleanly. Design and results: `docs/LEVELS_DESIGN.md`.
- To make the longer line reachable the agent also changed `REST_HEAL` 24 to 36, Deserter max HP 47 to 52, Medium 41 to 56 and Conductor HP 108 to 96.
- Sim escape rates on the 21-stop line (600 runs): smart bot about 58 / 60 / 57% and greedy bot about 33 / 20 / 21% (Deserter / Pickpocket / Medium). Before the longer run they were smart 81 / 77 / 69% and greedy 52 / 47 / 47%.

## To do, in the order I would take it

1. **Playtest each class** and say how it feels. The numbers are tuned against bots, not people. The greedy bot is probably the closer guide to a new player, and it escapes only about 20% of runs as the Pickpocket or Medium, so the longer run may be too hard. Watch the Deserter (skill-sensitive) and the Medium (very HP-sensitive). Also check the Brakeman fight, the pause menu is centered in a normal F5 launch, and the new backdrop and screen scenes in motion.
2. **Retune from playtest feedback**: `REWARD_HEAL`, `HEAL_BELOW`, class HP, card costs. Use the sim to check any change.
3. **Polish items** (small, agent-sized):
   - The Conductor figure in the story and end scenes is generic; reuse the enemy portrait art.
   - `Combat._check_end` reports a win when Thorns kill the last enemy on the same action that kills the player; `RunState.complete_combat` works around it by treating a win with a dead player as a defeat. Fix it in `combat/combat.gd`.
   - The Medium's mid-boss loss rate is low (2.7% for the smart bot against a target of 8 to 15%), the greedy bot loses about 37% to the Brakeman as the Deserter or Pickpocket (it never plays around Expose), and the tier 1 single-enemy pool is built but unused by this line.
   - `docs/LEVELS_DESIGN.md` explains the rest placement; the empty-platform beat has no per-character versions.
   - A hovered card loses its highlight when the hand rebuilds.
   - The remove picker does not scroll for decks over about 30 cards.
   - Deck cards on the select screen are small (scale 0.62).
   - The class tint on the battle backdrop is faint (`TINT_AMOUNT` 14%).
   - Enemy art is keyed by display name (`ART_KEYS` in `run/enemy_view.gd`); a new enemy needs an entry.

## Smaller open items

- The bots do not sequence the Pickpocket's per-play cards optimally, so that class's bot numbers may understate it.
- Several cards are rarely played by the bots (Spree, Pocket Watch, Seance, Spirit Tithe, Reckoning); worth a look if they feel weak in play.
- Save-scumming (quit mid-fight, Continue replays the stop) is intentional.
- Economy (gold, vendor prices) is still untested beyond a back-of-envelope check.
- Relics: playtest the feel and prices (Brass Token Purse is the bots' favorite at 50 gold); the bots only buy relics and do not play around them, so sim numbers understate them. The barbed-wire badge reads closer to a chain. Tooltips have not been seen in a real run. More relic sources (elites, a free pick after a fight) are an option.
- Bigger ideas: a branching map, more enemies and an elite tier (which could also drop relics).

## How to run

- Play: open the project in Godot 4.7.2 and press F5 (or launch `Godot_v4.7.2-stable_win64.exe --path .`).
- Full check: `powershell -ExecutionPolicy Bypass -File scripts/check.ps1`
- Sim: `godot --headless --path . -s res://tools/run_sim.gd -- --runs 600 --seed 1 --character deserter --policy smart --card-stats`
