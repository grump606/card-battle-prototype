# Next steps

Last updated after the artwork pass. Everything below is on `main` and pushed (`10b35fc`) unless noted.

## State

- Three characters (Deserter, Pickpocket, Medium) with class cards, a neutral pool, a character select screen, a pause menu and save/resume.
- Classes plan: all seven phases done (infrastructure, select screen, the three classes' mechanics and cards, bots and balance, story). Per-character boarding, Conductor and Last Light beats live under `data/story/<id>/` with a neutral fallback (draft text, edit freely). Details: `docs/CLASSES_PLAN.md`.
- Card rewards: designs A and C are in (no repeats past 2 copies, skip pays 10 gold, free once-per-run Remove and Heal 12). See `docs/REWARDS_PROPOSAL.md`.
- Artwork is all code-drawn (no image assets): cards with class palettes and damage icon variants, character select panels, enemy portraits with status chips beside the figure, battle backdrop, vendor stall, pause scene, and rest stop, story and end-card scenes. Design notes are in `docs/*_ART_DESIGN.md` and `docs/SCREEN_ART_DESIGN.md`.
- The damage preview on cards matches the damage actually dealt (shared `CardEffect.raw_damage`).
- Sim escape rates: greedy bot about 48 / 46 / 43% (Deserter / Pickpocket / Medium); smart bot about 81 / 75 / 67% since the free Heal and Remove were added (they made the smart bot about 7 points easier).

## To do, in the order I would take it

1. **Playtest each class** and say how it feels. The numbers are tuned against bots, not people. Watch the Deserter (skill-sensitive) and the Medium (very HP-sensitive: 38 to 48 HP moved it from 28% to 68%). Also check the pause menu is centered in a normal F5 launch, and the new backdrop and screen scenes in motion.
2. **Retune from playtest feedback**: `REWARD_HEAL`, `HEAL_BELOW`, class HP, card costs. Use the sim to check any change.
3. **Polish items** (small, agent-sized):
   - The Conductor figure in the story and end scenes is generic; reuse the enemy portrait art.
   - The "empty platform" story beat (index 2) is never shown in play; use it or drop it.
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
- Bigger ideas: relics (the best replay value for the effort), a branching map, more enemies and an elite tier.

## How to run

- Play: open the project in Godot 4.7.2 and press F5 (or launch `Godot_v4.7.2-stable_win64.exe --path .`).
- Full check: `powershell -ExecutionPolicy Bypass -File scripts/check.ps1`
- Sim: `godot --headless --path . -s res://tools/run_sim.gd -- --runs 600 --seed 1 --character deserter --policy smart --card-stats`
