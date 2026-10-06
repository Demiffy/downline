# Subterra Clone

A Subterranauts-style co-op horror scavenger in Godot 4.7, currently solo only. Research notes are in [docs/subterranauts-research.md](docs/subterranauts-research.md).

```
godot --path .            # play
godot --path . -e         # open in the editor
```

## The loop
1. Start at the **checkpoint**. Use the terminal at the front of the train and type `LEAVE_CHECKPOINT`.
2. `MAP`, `VIEW_STATION B`, then `ROUTE_TO B`. Each assignment is 3 stations, then the checkpoint.
3. At a station, follow the ELEVATOR signs and ride down. Find scrap, haul it back up, and drop it **inside the train**.
4. The 20:00 warning means head back. The train leaves at 24:00 with or without you.
5. After 3 stations, `ROUTE_TO CHECKPOINT`. Throw scrap into the **shredder**, pull the lever, and meet the per-resource quota.
   Leaving with the quota unmet means the train rams the gate. Game over.

## Progression & terminal
- **Upgrades** (permanent for the run, bought at a checkpoint: the shop container's terminal or `UPGRADES` / `BUY_UPGRADE`):
  BETTER_BOOTS, WEATHERVANE, MINIMAP, STORAGE_CAR, QUICK_DELIVERY, BATTERY_PACK, DIGITAL_CLOCK.
- **Deliveries:** `BUY` orders roll in on a handcar at the back of the train (~45 s, a few seconds with QUICK_DELIVERY).
- **Security cameras:** `LIST_CAMS`, `VIEW_CAM n`, `NEXT_CAM`/`PREV_CAM`, `TOGGLE_LIGHT`, `EXIT_CAMS`. Arrow keys pan the feed.
- **Maps:** `MINIMAP` shows the whole site (rooms, bulkhead codes, scrap, entities, you). With the upgrade you also get a HUD minimap underground.
- **Data disks:** found in facilities. Click one while on the train to upload it, then `LIST_LOGS` / `READ <log>`. The lore lives in `data.gd`.
- **Run stats:** shown on game over. The best run is saved to `user://best_run.json`.

## Controls
| | |
|---|---|
| WASD / Shift / Ctrl / Space | move / sprint (7 s stamina) / crouch (silent) / jump |
| E (hold for some) | pick up, use, call/ride the elevator, manual bulkhead override (loud) |
| LMB / RMB | use held item (toggle light; held equipment → equip it) |
| F or MMB | scan (needs Scanner equipped) |
| 1–6, wheel | select slot |
| Q / C | drop item / drop equipment |
| Esc | release mouse / leave terminal |
| R | restart after game over |

## Code map (`src/`)
- `data.gd`: **all content** (scrap, items, prices, facility themes, weather). Make it yours here.
- `main.gd`: game state, day clock, travel (the world slides past the train), shredder, terminal commands, lighting/fog.
- `art.gd`: **procedural pixel textures and the prop kit** (crates, barrels, shelves, lamps, houses, trees…). No image files.
- `train.gd`: locomotive + crew car + flatcar, with animated wheels, rods, steam and headlight.
- `elevator.gd`: shaft, cage cab, lifting gate, call buttons; the ride carries you and your loot.
- `level.gd`: a station (platform, surface, houses, elevator, facility, spawns) or the checkpoint (shredder, robot, gate).
- `facility.gd`: procedural room-grid generator, room dressing per theme, and monster pathing.
- `paint.gd`: weathered world text (stencil / old signage / typewriter / chalk), rendered from system fonts and aged procedurally.
- `merge.gd`: folds static primitives into one mesh per material per 6 m chunk (facility, surface, items). Primitive geometry is generated on the CPU (no GPU readback) and tiny clutter doesn't cast shadows. Animated nodes are marked with `Merge.live()` / the A.spin/sway/bob helpers and left alone.
- `items.gd`: a hand-built model for every scrap item and tool (60 scrap types). Add new scrap in `data.gd` + a branch here.
- `viewmodel.gd`: first-person sleeve, glove and held-item models (flashlight, lantern).
- `player.gd`, `hud.gd` (visor HUD), `terminal.gd` (amber CRT), `pickup.gd`, `build.gd` (basic boxes), `sfx.gd` (synthesized sounds).
- `monster.gd`: shared monster base (walking, facing, "is anyone looking at me?", limbs). Monsters, one file each:
  `roomba` (laser tripwire, explodes), `pulsator` (blind, hunts by sound, bursts), `statue` (moves only when nobody looks),
  `marionette` (moves only while watched), `mimic` (barrel that bites, then runs off), `warden` (sees only what its searchlight hits),
  `leviathan` (surface worm, late in the day; noise during a rumble = death without a roof), `snatcher` (ceiling vent, drags you elsewhere),
  `bear_trap`, `scrapper` (shy scrap pile; catch it for loot), `gloe` (friendly light that follows you).

## Tests
```
tests/run.sh 60 --headless --path . -s tests/check.gd     # logic: terminal, generator, data
tests/run.sh 240 --headless --path . -s tests/smoke.gd    # plays a full assignment headless
tests/run.sh 300 --headless --path . -s tests/monsters.gd # every monster's behaviour
tests/run.sh 200 --path . -s tests/gallery.gd -- /tmp/g   # close-up of every monster (opens a window)
tests/run.sh 200 --path . -s tests/scrap_gallery.gd -- /tmp/s  # every item model, 6 per shot
tests/run.sh 200 --path . -s tests/props_gallery.gd -- /tmp/p  # furniture + props, 4 per shot
tests/run.sh 900 --path . -s tests/playtest.gd -- /tmp/play 180  # a bot plays a station in real time: screenshots + log.txt
tests/run.sh 120 --path . -s tests/shots.gd -- /tmp/shots # screenshots (opens a window)
```
`run.sh` adds a hard timeout, because macOS has no `timeout` command.
