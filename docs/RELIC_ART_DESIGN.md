# Relic art and UI

Relics are drawn in code like cards (see `docs/CARD_ART_DESIGN.md`): no image assets, no animation, so no `advance(delta)`.

## Badge (`run/relic_view.gd`, `RelicView`)

A round 36x36 badge scaled by `view_scale`: a frame ring, a face in the class stock colour, a thin accent ring, and one glyph chosen by `RelicData.Kind`. Palettes come from `CardView.PALETTES` through `RelicData.character` (frame = `frame`, face = `stock`, glyph = `ink`, detail = `accent`); neutral relics are cream ticket stock with dark ink, so a badge reads as a class at a glance. `GLYPH_NAMES` maps every Kind to a glyph and a test keeps it in step with the enum (new kinds are appended, so add a glyph with them).

| Kind | Glyph |
|---|---|
| MAX_HP | flask |
| WIN_GOLD | coin purse |
| WIN_HEAL | ticket stub with a cross |
| FIGHT_START_BLOCK | dog tag on a chain |
| TURN_START_THORNS | twisted barbed wire |
| TURN_START_BLOCK | ration tin |
| FIRST_PLAY_DRAW | glove |
| FIRST_TURN_ENERGY | skeleton key |
| PLAYS_BLOCK | fan of three cards |
| FIGHT_START_HAUNT | grave-dirt mound, spade, wisp |
| TURN_START_HEAL_PER_HAUNTED | planchette |
| HAUNT_BONUS | rosary |

`dimmed` darkens the badge (sold or unaffordable offers). Hover brightens it and shows the engine tooltip: name, effect, then "Neutral relic" or "<Class> relic". The engine keeps tooltips inside the window, so nothing clips at the screen edges. The badge uses `MOUSE_FILTER_PASS` (it needs the mouse for the tooltip, but never swallows clicks).

## Strip (`run/relic_strip.gd`, `RelicStrip`)

An `HBoxContainer` of badges in purchase order; `RelicStrip.create(relics, scale)` builds one, `set_relics` refills it. It hides itself when empty so a screen keeps one in its layout for free.

## Placement

- Battle screen: a `PlayerRow` holds the player's HP label with a strip beside it (0.85 scale). The run hands the relics over like `character_id`: `battle.relics = run.relics`.
- Run header: a strip beside the header line on every stop except fights (the battle screen shows them there) and the select/continue screens.
- Vendor: one plate to the right of the three card offers with the badge at 1.5x, name, effect, price and a Buy button. Sold or unaffordable: badge dimmed, button disabled, "Sold" in place of the price. No offer (the pool is owned): no plate.
- Pause menu: a "Relics" line with a strip when any are owned. After Continue the header strip shows the saved relics.

## Checking it

`godot --path . -s res://tools/relic_sheet.gd -- <dir>` (needs a window) saves the glyphs in every palette, the twelve relics beside a mock tooltip, and the vendor and battle screens per class. `tests/ui_relic_view_test.gd` runs in `scripts/check.ps1`.
