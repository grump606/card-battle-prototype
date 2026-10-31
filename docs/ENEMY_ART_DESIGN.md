# Enemy art design

Enemies are drawn in code (`run/enemy_view.gd`, `class_name EnemyView`); no image assets. An enemy is a **bordered panel with a portrait window**, sharing the card styling (rounded frame, banner, near-black art window, pills) but in sooty oxblood and soot grey, so it never reads as a class card. Preview with `godot --path . -s res://tools/enemy_sheet.gd -- <out dir>` (needs a window, not headless): `enemies_all.png`, `enemies_states.png`, and `battle_1/2/3/warden_pair/boss.png` of the real battle screen.

## Panel layout (base 220x164, boss 300x164)

9 px of marker room on top, then: name banner (13 px, shrinks to 8), portrait window (66 px) with status chips in two columns beside the figure (never over it), HP bar (left) with a Block chip (right), intent strip. Panels are `EnemyView`s directly in the battle `EnemyRow`, which centers them (1 to 3 fit: 3 x 220 + gaps = 688 of 1120 px). The row is 164 px high, leaving the hand (168) and End Turn visible at 1152x648.

## Silhouettes (chosen by enemy name, `ART_KEYS`; unknown names draw a plain ghost)

| Enemy | Look | Hints at |
|---|---|---|
| Gate Warden | tall armoured figure, closed helm with an amber slit, gate bars on the chest, halberd | slow heavy hits, Block |
| Lost Shade | hooded ghost, hollow eyes, ragged hem, reaching arms | two even strikes |
| Skittering Wisp | flame orb on spider legs, circling sparks | fast small hits, then a big one |
| Hollow Colossus | slab torso, huge fists, tiny head, ember heart in a hollow chest | Block, then one crushing blow |
| Pale Whisperer | hooded pale face with many small murmuring mouths and sunken eyes, whisper arcs | Expose, then hits |
| Cinder Hound | side-on hound, ember eye and maw, embers in the fur and rising | steady biting |
| Mourning Crow | crow with raised wings, falling tear | two pecks, Expose, a stoop |
| The Conductor (boss) | coat, peaked cap, skull face, baton, watch chain, passengers behind | grander: see below |

The Conductor's figure lives in `run/conductor_figure.gd` (`ConductorFigure.draw(canvas_item, time, glow_level, phase, body, glow)`, about 70 units tall, feet at the origin, facing right). `EnemyView._art_conductor` just calls it, and the story scene draws the same figure larger (mirrored) so he looks the same everywhere.

## Palette tokens (`EnemyView.PALETTES`)

Normal: frame oxblood `(.52,.20,.17)`, fill soot `(.15,.12,.13)`, banner `(.33,.13,.12)`, accent `(.84,.38,.28)`, window `(.07,.06,.08)`. Boss: tarnished silver frame `(.66,.67,.73)`, near-black fill, crimson banner `(.46,.08,.13)` and accent `(.90,.20,.25)`, a second crimson line, corner diamonds, a wider panel and passenger ghosts. Silhouette body and glow colours per enemy are in `ART_COLORS`. Bars, kind colours and the gold target colour come from `CardView` (`HP_RED`, `kind_color`, `SELECT_GOLD`).

## States

- Normal; hover lightens the frame.
- Targeted: 3 px gold outline and a gold marker triangle above the panel (shape as well as colour).
- Intent shown: the strip is always on; a lunge animation plays when the enemy acts.
- Hit: white flash and a brief shake when HP drops.
- Defeated: dimmed and faded (0.6 s), a `DEFEATED` stamp over the window, empty HP bar, strip reads `Defeated`, no click, no tooltip.

## Intent icons (the kinds enemies use: Deal, Block, Expose)

Round badge in the kind colour: blade for any damage kind, shield for Block, crosshair for Expose, a diamond for anything else. The amount is large next to the badge and the full `CardEffect.describe()` text follows, so no detail is lost.

## Information kept from the old text panel

Name, `HP n/max`, `Block n` (dimmed at 0), intent text, the target marker, and the status tooltip (Exposed, Haunt, Hold, Thorns) as the panel's tooltip. Statuses are also shown as chips (`status_chips()`): Exposed, Haunt, Hold, Thorns with their numbers. Chips sit in the left and right columns of the portrait window (alternating, max two per column) outside `portrait_subject_rect()` (the middle 104 px, 112 px for the boss); `chip_rects()` gives their positions. They show full labels when those fit beside the subject (the Conductor), otherwise an icon plus the number (the tooltip names them).

## Animation

`advance(delta)` (called from `_process` only while visible in the tree) drives breathing, glow flicker (fixed-seed noise, no global RNG), embers, the flash, the lunge and the defeated fade. Each view has a `phase` so same-type enemies do not breathe in step.

## The Brakeman (mid-boss)

Key `brakeman` (name "The Brakeman"), listed in `EnemyView.BOSS_KEYS` with the Conductor, so it gets the 300x164 boss panel, the diamond studs and the second inner line. Its palette `midboss` swaps the Conductor's silver and crimson for a brass frame `(.78,.56,.24)`, soot-black oxblood fill and an orange-brass accent, so the two bosses read differently at a glance. Silhouette: broad hulking torso with a brass-buckled leather apron, huge pauldrons, a small helmet with a glowing visor slit, a spoked brass brake wheel raised in one gauntlet (it turns slowly) and a signal lantern swinging from the other, steam venting at the shoulders; dead signal posts stand faintly behind it where the Conductor has passenger ghosts. Status chips keep the beside-the-portrait layout (same subject width as the Conductor). `tools/enemy_sheet.gd` includes it in the contact, states and chips sheets and takes `battle_midboss.png`.
