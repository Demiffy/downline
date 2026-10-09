# DOWNLINE

A co-op horror scavenger in Godot 4.7: ride the Bureau's train down the line, strip dead facilities for scrap and get back aboard before the dark gets you. Solo, or a crew of up to 6 over IP with proximity voice. Research notes on the game that inspired it are in [docs/subterranauts-research.md](docs/subterranauts-research.md).

```
godot --path .                          # play
godot --path . -e                       # open in the editor
godot --path . -- playground [LAB]      # monster playground: spawn monsters, god mode, labels (TAB for the panel)
```

## The loop
1. Start at the **checkpoint**. Use the terminal at the front of the train and type `LEAVE_CHECKPOINT`.
2. `MAP`, `VIEW_STATION B`, then `ROUTE_TO B`. Each assignment is 3 stations, then the checkpoint.
3. At a station, follow the ELEVATOR signs and ride down. Find scrap, haul it back up, and drop it **inside the train**.
4. The 20:00 warning means head back. The train leaves at 24:00 with or without you. Step off once it's moving and you can still climb back aboard, but once it has fully pulled away you're left behind.
   **Dying doesn't end the run**: a replacement wakes aboard at the same stop an hour later. The cargo aboard is untouched. Your remains lie where you fell, with whatever you were holding (the scanner shows them); carry them back aboard and the Bureau pays a 20 cr recovery fee.
   **Being left behind** doesn't end it either: you're recovered at the next stop and all the scrap you had, carried and aboard, is written off.
5. After 3 stations, `ROUTE_TO CHECKPOINT`. Throw scrap into the **shredder**, pull the lever, and meet the per-resource quota.
   Leaving with the quota unmet means the train rams the gate. Game over.

## Progression & terminal
- **Upgrades** (permanent for the run, bought at a checkpoint: the shop container's terminal or `UPGRADES` / `BUY_UPGRADE`):
  BETTER_BOOTS, WEATHERVANE, MINIMAP, STORAGE_CAR, QUICK_DELIVERY, BATTERY_PACK, DIGITAL_CLOCK, GAS_FILTER, ACID_SHIELD, HEADLAMP, NIGHT_VISION, ARMORED_SUIT, INFIRMARY, CARGO_HARNESS, SIGNAL_BOOSTER, LIFT_MOTOR, OVERTIME_PERMIT, MARKET_CONTACTS, SOFT_SOLES.
- **Shop items** (`SHOP`, `BUY`): flashlight, lantern, scanner, backpack, crowbar, fire axe, shotgun, medkit (heals to full; some lie about the sites), road flare (throw it: red light for a minute), noisemaker (throw it: it rings and draws anything that hunts by sound), adrenaline shot, door wedge (jam a swing door shut; creatures have to bash it loose), walkie-talkie (hold it and your voice goes out over the radio to anyone carrying one, at any range).
- **Helmet damage:** your visor cracks as you take hits, on screen and on your suit for the crew to see, until you're patched back to full.
- **Charging rack** on the train's back wall: hold E to top up every battery you carry, the helmet cell and the shotgun's shells.
- **Creature parts:** wardens, observers, marionettes, mimics and pulsators leave something valuable when they die; the wraith loses its helmet the first time your light takes it apart.
- **Deliveries:** `BUY` orders roll in on a handcar at the back of the train (~45 s, a few seconds with QUICK_DELIVERY).
- **Security cameras:** `LIST_CAMS`, `VIEW_CAM n`, `NEXT_CAM`/`PREV_CAM`, `TOGGLE_LIGHT`, `EXIT_CAMS`. Arrow keys pan the feed.
- **Maps:** `MINIMAP` shows the whole site (rooms, bulkhead codes, and the scrap and creatures your scanner has found). With the upgrade you also get a HUD minimap underground: the rooms, the lift, what you've scanned, and a ping of your crew every five seconds.
- **Data disks:** found in facilities. Click one while on the train to upload it, then `LIST_LOGS` / `READ <log>`. The lore lives in `data.gd`.
- **Field guide:** scanning a creature logs it (the leviathan is logged when it surfaces). `GUIDE` lists what's identified, `GUIDE <name>` reads an entry: where it lives, its signs, its habits, how to deal with it, and how many you've killed. Kept across runs in `user://field_guide.json`.
- **Photos:** the Observer's photos can be picked up, held up close (click), and pinned to the train walls (E). The run-over screen lays out every pinned photo as the run's memento.
- **Run stats:** shown on game over (which now only happens when you ram the gate). The best run is saved to `user://best_run.json`.

## Scrap loop
- **Heavy scrap** (engine blocks, transformers, cable drums, office safes): both hands, slow, no sprinting or jumping, [Q] sets it down. Worth 9–10 resources.
- **Supply crates** against walls: hold E to pry open. Usually one or two items, sometimes nothing.
- **The vault**: the furthest dead end, behind its own bulkhead (marked VAULT). A heavy prize and the best scrap. Open it from the terminal or with the loud manual override.
- **Mezzanines** in some rooms: stairs up to a steel deck with shelves and scrap.
- **Vents**: low duct openings between rooms that otherwise don't connect.
- **Payload rank** at the checkpoint: shred more than the quota is worth for rank B/A/S and a one-off Bureau bonus.

## Big rooms
Every site merges a few cells into bigger rooms: 2x1, L-shaped, and now and then 2x2, with ceiling headers and pilasters where the walls would have been. Each gets a set piece of its own (`halls.gd`):
- **Lab:** a reception (front desk, B.R.M. feature wall, waiting area, turnstiles, directory), a canteen, a lab hall with a spine of specimen tanks, a server hall (rows of racks, raised floor, console).
- **Factory:** a warehouse (back-to-back pallet racks, lane lines, a forklift), an assembly line (conveyor, stamping presses, workstations; it turns the corner in an L), a canteen.
- **Flesh:** the gut hall (a beating heart with arteries into the ceiling, veins across the floor, flesh pillars, a ribcage over everything), an overgrown canteen.
- **Backrooms:** a pillar hall (and a doorframe standing on its own, a chair facing nothing, an EXIT sign over a blank wall), an open-plan office.
Set pieces never block a doorway; the site map and minimap draw big rooms as one space.

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

## Weapons
CROWBAR (45), FIRE_AXE (85), SHOTGUN (240) in the shop; crowbars and the odd axe also turn up in facilities. Click to swing or fire.
Melee hits the nearest creature in front of you; the shotgun throws 8 pellets and is heard across the site (6 shells, restocked aboard the train).
Creatures have health and react to being hit (wardens hunt you, observers and scrappers run, a poked mimic bites) and die with their own death animation; the bodies stay.
The statue is stone and the wraith is cloth and cold: weapons do nothing to either. Light is the wraith's weakness.

## Fear
Your breathing and heartbeat play inside the helmet: calm when it's quiet; heavier and faster when something nearby is hunting you, when you're hurt, or after a sprint.

## Scanner
Equip the scanner and press F (or middle mouse). A soft blue wave rolls out from where you stand across every surface within 16 m. Everything it reaches lights up, through walls, for about five seconds. Scrap glows blue with a lock-on ring and a tag showing its name, what it shreds into and roughly what it's worth today. Entities glow red. The main breaker and airdrops glow amber. The HUD also keeps a list of what was found.

## Crew (multiplayer) and proximity voice
The title screen offers **SOLO SHIFT**, **HOST A CREW** and **JOIN A CREW** (up to 6 players).
- **Host:** pick a port (default **24565**) and press HOST A CREW. To play over the internet, forward **UDP 24565** (or your port) on your router to this machine. Give friends your public IP. Press START THE SHIFT when everyone is in. People can still join later, and they're brought aboard wherever the train is.
- **Join:** type the host's address (`1.2.3.4` or `1.2.3.4:24565`) and press JOIN A CREW (or Enter).
- The host runs the world: creatures, scrap, hazards, the clock and the money. Everyone builds the same station from the host's seed. Doors, the lift, bulkheads, the breaker and crates are shared. Terminal commands that change the run (ROUTE_TO, BUY, SELL, LEAVE_CHECKPOINT...) run on the host. A dead crewmate drops remains and wakes aboard, and anyone can carry the remains back.
- **Voice:** your microphone (macOS asks for permission the first time) plays from your helmet. It fades with distance, rings in the room's reverb, and goes round corners through open doorways, quieter and duller. One wall leaves a dull murmur; more walls, nothing. Creatures hear you when you talk loudly. SETTINGS > AUDIO has VOICES volume, MICROPHONE on/off, open mic or push-to-talk (**V**), MIC LEVEL and the OPEN MIC GATE. A crewmate's name tag turns green while they talk, and the crew list on the left of the HUD lights up whoever is speaking (with your own mic level under it). Everyone sees the same station, down to the furniture and how each creature looks, its swings, flashes and bites, and each other's blood on the floor.
- Esc doesn't pause the game in a crew; it has LEAVE CREW. Only the host can restart.

## Settings
Esc opens the pause menu (resume, settings, restart, quit). Settings are saved to `user://settings.cfg`: mouse sensitivity, invert look, head bob, fullscreen, vsync, field of view, brightness, quality (LOW / MEDIUM / HIGH), and master / effects / ambience volume.

## Controls
| | |
|---|---|
| WASD / Shift / Ctrl / Space | move / sprint (7 s stamina) / crouch (silent) / jump |
| E (hold for some) | pick up, use, call/ride the elevator, manual bulkhead override (loud) |
| LMB / RMB | use held item (toggle light; held equipment → equip it) |
| F or MMB | scan (needs Scanner equipped) |
| 1–7, wheel | select slot |
| T / N | headlamp / night vision (with the upgrades) |
| Q / C | drop item / drop equipment |
| Esc | pause menu + settings / leave terminal |
| F11, Alt/Option+Enter, or Cmd+Ctrl+F (Mac) | fullscreen on/off (the UI scales to any resolution) |
| V | push-to-talk (when VOICE is set to push-to-talk) |
| R | restart after game over |

## Code map (`src/`)
- `data.gd`: **all content** (scrap, items, prices, facility themes, weather). Make it yours here.
- `main.gd`: game state, day clock, travel (the world slides past the train), shredder, terminal commands, lighting/fog.
- `art.gd`: **procedural pixel textures and the prop kit** (crates, barrels, shelves, lamps, houses, trees…). No image files.
- `train.gd`: locomotive + crew car + flatcar, with animated wheels, rods, steam and headlight.
- `elevator.gd`: shaft, cage cab, lifting gate, call buttons; the ride carries you and your loot.
- `level.gd`: a station (platform, surface, houses, elevator, facility, spawns) or the checkpoint (shredder, robot, gate).
- `facility.gd`: procedural room-grid generator, room dressing per theme, and monster pathing (a navigation mesh baked per site from the real collision, both floors and the stairs, with links across open bulkheads; the old room graph is the fallback).
- `pathdebug.gd`: path gizmos for the playground ([P]): navmesh edges, each monster's route, waypoint and goal, the room graph, shut bulkheads, and red posts where the stuck failsafe fired.
- `paint.gd`: weathered world text (stencil / old signage / typewriter / chalk), rendered from system fonts and aged procedurally.
- `merge.gd`: folds static primitives into one mesh per material per 6 m chunk (facility, surface, items). Primitive geometry is generated on the CPU (no GPU readback) and tiny clutter doesn't cast shadows. Animated nodes are marked with `Merge.live()` / the A.spin/sway/bob helpers and left alone.
- `playground.gd`: the monster playground (spawn panel, god mode, freeze, state labels, noise pings, noclip, fullbright [B], hazard events).
- `hazards.gd`: flooded / gassed rooms, steam lines, live cables, the main breaker, and the power failure / tremor / airdrop events.
- `net.gd` (crew hub at `/root/Net`: lobby, ENet, entity mirroring, events, host requests), `lobby.gd` (title/lobby screen), `puppet.gd` (a crewmate's body), `voice.gd` (mic capture and clean-up, 24 kHz 16-bit frames, jitter buffer, 3D playback, wall occlusion).
- `menu.gd`, `settings.gd`: the Esc pause menu and the saved settings.
- `scanfx.gd`: the scanner pulse (depth-based wave on the camera, through-wall glow, lock-on rings and tags).
- `items.gd`: a hand-built model for every scrap item and tool (60 scrap types). Add new scrap in `data.gd` + a branch here.
- `viewmodel.gd`: first-person sleeve, glove and held-item models (flashlight, lantern).
- `player.gd`, `hud.gd` (visor HUD), `terminal.gd` (amber CRT), `pickup.gd`, `build.gd` (basic boxes), `sfx.gd` (synthesized sounds).
- `monster.gd`: shared monster base (walking, facing, "is anyone looking at me?", limbs). Monsters, one file each:
  `roomba` (laser tripwire, explodes), `pulsator` (blind, hunts by sound, bursts), `statue` (moves only when nobody looks),
  `marionette` (moves only while watched), `mimic` (barrel that bites, then runs off), `warden` (sees only what its searchlight hits),
  `leviathan` (surface worm, late in the day; noise during a rumble = death without a roof), `snatcher` (ceiling vent, drags you elsewhere),
  `bear_trap`, `scrapper` (shy scrap pile; catch it for loot), `gloe` (friendly light that follows you),
  `observer` (bellows camera on harvestman tripod legs; follows behind you clicking; look back and it whines up its flash, blinds you, runs, and leaves a real photo of you on the floor),
  `wraith` (a dead miner's shroud that carries the dark: lamps die as it passes, visor frosts; hold a flashlight beam on it to burn it off, a lantern keeps it at arm's length; faster in a power failure).

## Tests
```
tests/all.sh                                              # every headless suite side by side (~30 s); `tests/all.sh full` for the 3-station smoke
tests/run.sh 60 --headless --path . -s tests/check.gd     # logic: terminal, generator, data
tests/run.sh 120 --headless --path . -s tests/smoke.gd -- quick   # one station end to end (~4 s); drop `-- quick` for three (~7 s)
tests/run.sh 300 --headless --path . -s tests/monsters.gd # every monster's behaviour
tests/run.sh 150 --headless --path . -s tests/stranded.gd # stepping off mid-trip, climbing back on, left behind/death write-offs
tests/run.sh 120 --headless --path . -s tests/loop.gd     # heavy items, supply crates, the vault, payload rank
tests/run.sh 150 --headless --path . -s tests/hazards.gd  # hazards, events, habitats, pause menu, settings
tests/run.sh 400 --headless --path . -s tests/levels.gd   # two floors: monsters in and out of pits, onto mezzanines, lift <-> farthest basement room
tests/run.sh 200 --headless --path . -s tests/creatures2.gd  # the siren (a crewmate's stolen voice) and the husk (the dead get up)
tests/mp.sh                                               # two real processes over ENet: lobby, travel, mirroring, pick/drop/kill/doors, voice, death
tests/mp_late.sh                                          # joining a shift already at a station
tests/mp_shots.sh /tmp/mps [quick]                        # two windows: the client photographs the host's body (holds, swings, shots, talking, blood) and every creature's copy and its moves
tests/run.sh 120 --headless --path . -s tests/voice.gd    # voice codec, capture filter, occlusion (same room / wall / doorway / far)
tests/run.sh 150 --path . -s tests/lower_shots.gd -- /tmp/b LAB  # the lower floor: stairwells and basement rooms
tests/run.sh 150 --path . -s tests/detail_shots.gd -- /tmp/d LAB  # close-ups: lift landings, pendant lamp, stairwell, basement doorway, vent spill, door glass
tests/run.sh 300 --path . -s tests/perf.gd -- FACTORY        # frame time in a facility, and what each feature costs
tests/run.sh 200 --path . -s tests/surface_shots.gd -- /tmp/s  # control desk, loco, houses, pumpjack, horizon, lift panel
tests/run.sh 200 --headless --path . -s tests/zfight_scan.gd -- FACTORY  # lists coplanar overlapping box faces (z-fighting) in a facility
tests/run.sh 60 --path . -s tests/anim_sheet.gd -- pumpjack /tmp/pj.png 3.0 8   # animation contact sheet: engine, engine_side, engine_close, pumpjack, shed
tests/run.sh 150 --path . -s tests/levels_shots.gd -- /tmp/l  # stairs, catwalks and doors (fullbright)
tests/run.sh 150 --path . -s tests/hazard_shots.gd -- /tmp/h LAB  # screenshots of every hazard and event
tests/run.sh 90 --path . -s tests/menu_shot.gd -- /tmp/m   # pause menu + settings pages
tests/run.sh 150 --path . -s tests/fx_shots.gd -- /tmp/fx   # scanner pulse and a steam line's whole cycle, frame by frame
tests/run.sh 200 --path . -s tests/gallery.gd -- /tmp/g   # close-up of every monster (opens a window)
tests/run.sh 600 --path . -s tests/halls_shots.gd -- /tmp/h LAB   # every big room: a wide shot and a plan
tests/run.sh 900 --path . -s tests/path_probe.gd -- /tmp/pp 40 FACTORY LAB   # 12 walkers roam each theme: report.txt of stuck spots + shots with path gizmos
tests/run.sh 240 --path . -s tests/nav_shots.gd -- /tmp/n FACTORY   # the navigation mesh drawn round every stair
tests/run.sh 240 --path . -s tests/feature_shots.gd -- /tmp/f   # blood, field-guide scans + terminal, memento board
tests/run.sh 200 --path . -s tests/creature_shots.gd -- /tmp/c   # observer + wraith: model close-ups, the flash, the photo, stalking, burning
tests/run.sh 200 --path . -s tests/scrap_gallery.gd -- /tmp/s  # every item model, 6 per shot
tests/run.sh 200 --path . -s tests/props_gallery.gd -- /tmp/p  # furniture + props, 4 per shot
tests/run.sh 900 --path . -s tests/playtest.gd -- /tmp/play 180  # a bot plays a station in real time: screenshots + log.txt
```
The smoke test sets Engine meta `fast_test`, which `Data.pace()` turns into short travel/elevator animations.
`run.sh` adds a hard timeout, because macOS has no `timeout` command.
