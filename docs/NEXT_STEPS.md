# Next steps

Last updated at the end of the classes work. Everything below is on `main` and pushed (`4960c53`) unless noted.

## State

- Three characters (Deserter, Pickpocket, Medium) with class cards, a neutral pool, a character select screen, a pause menu and save/resume.
- Classes plan: Phases 1 to 6 done (infrastructure, select screen, the three classes' mechanics and cards, bots and balance). Phase 7 (story) not started. Details: `docs/CLASSES_PLAN.md`.
- Greedy-bot escape rates sit at 40 to 50% for every class (Deserter 47 HP, Pickpocket 34 HP, Medium 41 HP). Smart bot: about 75% / 62% / 56%.

## To do, in the order I would take it

1. **Playtest each class** and say how it feels. The numbers are tuned against bots, not people. Watch the Deserter (the skill-sensitive one) and the Medium (very HP-sensitive: 38 to 48 HP moved it from 28% to 68%).
2. **Phase 7: class-specific story.** Per-character boarding, Conductor and Last Light beats (why this passenger is aboard, what the Conductor says to them). `StoryContent.beat(character, index)` with a neutral fallback. The stop-line signature check must still pass.
3. **Card rewards rework** (you said rewards could use work). Not designed yet.
4. **Pause screen artwork** ("full cut scene"). Not designed yet.

## Smaller open items

- The battle damage preview only knows plain damage, so Bash, Cold Steel, Last Pocket and Reckoning show no preview number (their card text still says what they do).
- The bots do not sequence the Pickpocket's per-play cards optimally, so that class's bot numbers may understate it.
- Several cards are rarely played by the bots (Spree, Pocket Watch, Seance, Spirit Tithe, Reckoning); worth a look if they feel weak in play.
- Save-scumming (quit mid-fight, Continue replays the stop) is intentional.
- Economy (gold, vendor prices) is still untested beyond a back-of-envelope check.
- Bigger ideas: relics, a branching map, more enemies and an elite tier.

## How to run

- Play: open the project in Godot 4.7.2 and press F5 (or launch `Godot_v4.7.2-stable_win64.exe --path .`).
- Full check: `powershell -ExecutionPolicy Bypass -File scripts/check.ps1`
- Sim: `godot --headless --path . -s res://tools/run_sim.gd -- --runs 600 --seed 1 --character deserter --policy smart --card-stats`
