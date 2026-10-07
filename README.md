# Subterra Clone

A Subterranauts-style co-op horror scavenger in Godot 4.7, currently solo only. Research notes are in [docs/subterranauts-research.md](docs/subterranauts-research.md).

```
godot --path .                          # play
godot --path . -e                       # open in the editor
godot --path . -- playground [LAB]      # monster playground: spawn monsters, god mode, labels (TAB for the panel)
```

## The loop
1. Start at the **checkpoint**. Use the terminal at the front of the train and type `LEAVE_CHECKPOINT`.
2. `MAP`, `VIEW_STATION B`, then `ROUTE_TO B`. Each assignment is 3 stations, then the checkpoint.
3. At a station, follow the ELEVATOR signs and ride down. Find scrap, haul it back up, and drop it **inside the train**.
4. The 20:00 warning means head back. The train leaves at 24:00 with or without you, and stepping off once it is moving gets you left behind too.
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

## Scrap loop
- **Heavy scrap** (engine blocks, transformers, cable drums, office safes): both hands, slow, no sprinting or jumping, [Q] sets it down. Worth 9–10 resources.
- **Supply crates** against walls: hold E to pry open. Usually one or two items, sometimes nothing.
- **The vault**: the furthest dead end, behind its own bulkhead (marked VAULT). A heavy prize and the best scrap. Open it from the terminal or with the loud manual override.
- **Mezzanines** in some rooms: stairs up to a steel deck with shelves and scrap.
- **Vents**: low duct openings between rooms that otherwise don't connect.
- **Payload rank** at the checkpoint: shred more than the quota is worth for rank B/A/S and a one-off Bureau bonus.

## Two floors
Facilities have a lower floor (B-2) of basement rooms (boiler rooms, pipe galleries, maintenance bays, flooded stores) with their own doorways. Pit rooms open into it at the bottom; factories reach it through their pits, and labs, backrooms and flesh sites get stairwell rooms (an opening in the floor with stairs down along the wall, marked B-2 DOWN). Loot and monsters spawn down there too, the site map draws it in blue under the main floor, and the HUD minimap shows whichever floor you're on. Monsters path across both floors: they line up at a flight of stairs, take it, and step off.

## Hazards & events
Each facility type has its own hazards and its own residents (`Data.SITE_HAZARDS`, `Data.HABITAT`); `VIEW_STATION` lists both.
- **Flooded rooms** (factory, lab, backrooms): knee-deep water, slow and loud. Some have a **live cable** that arcs through the water every few seconds.
- **Toxic gas** (lab, flesh): chokes you and makes you cough (monsters hear it). A **gas mask** anywhere in your pack keeps you safe; every gassed site has one lying around.
- **Burst steam lines** (factory, flesh): the pressure gauge creeps into the red, the joint rattles and spits, then it blasts across the room or tunnel (fast white core, billowing plume, spray, a cloud off the far wall, heat shimmer) and sputters out into a hanging mist. Standing in it scalds you and fogs your visor. Wait it out or crouch under the jet.
- **Power failure**: lights die, the lift crawls on emergency power, cameras and bulkheads go offline, live cables go dead. Find the **main breaker** (scanner and site map show it) and hold E.
- **Tremor**: shaking, dust, falling ceiling (sometimes scrap falls with it), and every listening monster hears it. Can knock the power out.
- **Airdrop**: a Bureau crate parachutes onto the surface under a red flare. Prying it open is loud.

Habitats: no roombas, mimics or wardens in the backrooms (more marionettes, statues and gloes there); the flesh is thick with snatchers and pulsators; factories get more wardens, mimics and scrappers; labs get more roombas and statues.

## Scanner
Equip the scanner and press F (or middle mouse). A soft blue wave rolls out from where you stand across every surface within 16 m. Everything it reaches lights up, through walls, for about five seconds. Scrap glows blue with a lock-on ring and a tag showing its name, what it shreds into and roughly what it's worth today. Entities glow red. The main breaker and airdrops glow amber. The HUD also keeps a list of what was found.

## Settings
Esc opens the pause menu (resume, settings, restart, quit). Settings are saved to `user://settings.cfg`: mouse sensitivity, invert look, head bob, fullscreen, vsync, field of view, brightness, quality (LOW / MEDIUM / HIGH), and master / effects / ambience volume.

## Controls
| | |
|---|---|
| WASD / Shift / Ctrl / Space | move / sprint (7 s stamina) / crouch (silent) / jump |
| E (hold for some) | pick up, use, call/ride the elevator, manual bulkhead override (loud) |
| LMB / RMB | use held item (toggle light; held equipment → equip it) |
| F or MMB | scan (needs Scanner equipped) |
| 1–6, wheel | select slot |
| Q / C | drop item / drop equipment |
| Esc | pause menu + settings / leave terminal |
| F11, Alt/Option+Enter, or Cmd+Ctrl+F (Mac) | fullscreen on/off (the UI scales to any resolution) |
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
- `playground.gd`: the monster playground (spawn panel, god mode, freeze, state labels, noise pings, noclip, fullbright [B], hazard events).
- `hazards.gd`: flooded / gassed rooms, steam lines, live cables, the main breaker, and the power failure / tremor / airdrop events.
- `menu.gd`, `settings.gd`: the Esc pause menu and the saved settings.
- `scanfx.gd`: the scanner pulse (depth-based wave on the camera, through-wall glow, lock-on rings and tags).
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
tests/all.sh                                              # every headless suite side by side (~30 s); `tests/all.sh full` for the 3-station smoke
tests/run.sh 60 --headless --path . -s tests/check.gd     # logic: terminal, generator, data
tests/run.sh 120 --headless --path . -s tests/smoke.gd -- quick   # one station end to end (~4 s); drop `-- quick` for three (~7 s)
tests/run.sh 300 --headless --path . -s tests/monsters.gd # every monster's behaviour
tests/run.sh 150 --headless --path . -s tests/stranded.gd # stepping off mid-trip leaves you behind, never in the void
tests/run.sh 120 --headless --path . -s tests/loop.gd     # heavy items, supply crates, the vault, payload rank
tests/run.sh 150 --headless --path . -s tests/hazards.gd  # hazards, events, habitats, pause menu, settings
tests/run.sh 400 --headless --path . -s tests/levels.gd   # two floors: monsters in and out of pits, onto mezzanines, lift <-> farthest basement room
tests/run.sh 150 --path . -s tests/lower_shots.gd -- /tmp/b LAB  # the lower floor: stairwells and basement rooms
tests/run.sh 150 --path . -s tests/detail_shots.gd -- /tmp/d LAB  # close-ups: lift landings, pendant lamp, stairwell, basement doorway, vent spill, door glass
tests/run.sh 300 --path . -s tests/perf.gd -- FACTORY        # frame time in a facility, and what each feature costs
tests/run.sh 200 --path . -s tests/surface_shots.gd -- /tmp/s  # control desk, loco, houses, pumpjack, horizon, lift panel
tests/run.sh 150 --path . -s tests/levels_shots.gd -- /tmp/l  # stairs, catwalks and doors (fullbright)
tests/run.sh 150 --path . -s tests/hazard_shots.gd -- /tmp/h LAB  # screenshots of every hazard and event
tests/run.sh 90 --path . -s tests/menu_shot.gd -- /tmp/m   # pause menu + settings pages
tests/run.sh 150 --path . -s tests/fx_shots.gd -- /tmp/fx   # scanner pulse and a steam line's whole cycle, frame by frame
tests/run.sh 200 --path . -s tests/gallery.gd -- /tmp/g   # close-up of every monster (opens a window)
tests/run.sh 200 --path . -s tests/scrap_gallery.gd -- /tmp/s  # every item model, 6 per shot
tests/run.sh 200 --path . -s tests/props_gallery.gd -- /tmp/p  # furniture + props, 4 per shot
tests/run.sh 900 --path . -s tests/playtest.gd -- /tmp/play 180  # a bot plays a station in real time: screenshots + log.txt
```
The smoke test sets Engine meta `fast_test`, which `Data.pace()` turns into short travel/elevator animations.
`run.sh` adds a hard timeout, because macOS has no `timeout` command.
