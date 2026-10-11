# DOWNLINE: Handoff

Everything someone needs to pick this project up cold: what the game is, how to run it, how the code is put together, every system, the tools, the conventions, and what is still open.

- **Engine:** Godot 4.7.2 (Forward+ renderer, Jolt physics), GDScript only.
- **Assets:** none. Every mesh, texture, sound and font render is generated at runtime from code.
- **Size:** about 23,000 lines in `src/` (63 scripts) and about 5,700 in `tests/`.
- **Git:** https://github.com/Demiffy/downline (private), branch `main`. Everything is pushed, this file included. Clone it and carry on.
- **Platform:** developed on macOS (Apple M5, Metal) until 2026-10-08. Development continues on the owner's Windows PC (see §2 for Windows setup, §11 for the Windows build).
- **Name:** DOWNLINE (renamed from "Subterra Clone"; the folder on the Mac was `subterra-clone`).

---

## 1. What the game is

**DOWNLINE**: a co-op horror scavenger (solo, or a crew of up to 6 over IP with proximity voice) inspired by **Subterranauts**, built with the owner's own content and art direction. Research notes on the original are in `docs/subterranauts-research.md`.

You are an employee of the **Bureau of Reclaimed Materials (B.R.M.)**, a grim corporate scrap outfit. You live on a small diesel train that runs between ruined surface stations. Under each station, a mine-shaft lift goes down into a procedurally generated facility full of scrap and monsters.

- **The aim:** haul scrap back onto the train before it leaves at midnight.
- **Quota:** at the checkpoint you shred the scrap to meet a quota for four resources: steel, copper, rubber and plastic.
- **The loop:** meet the quota, get a new assignment, repeat until something kills you or you miss the train.

**Tone and art direction** (the owner has been explicit about this):
- Abandoned, weathered and industrial, with chunky low-poly geometry and procedural pixel-ish textures.
- No modern or clean look.
- **No floating billboard text.** World text is weathered paint on surfaces (`paint.gd`). Glowing `Label3D` is only for actual displays.
- UI text stays the bold mono HUD font (Menlo, Consolas or DejaVu Sans Mono).
- The owner reviews screenshots closely and catches z-fighting, floating geometry, gaps and anything that "looks gamey". Verify visually before claiming something is done (see the tools in §8).

Multiplayer **is** implemented: host-authoritative ENet over plain IP with proximity voice. The architecture is in §10, and player-facing hosting and joining are in the README.

---

## 2. Running it

```bash
godot --path .                                  # play
godot --path . -e                               # open in the editor
godot --path . -- playground                    # monster playground (factory)
godot --path . -- playground LAB                # ...or FACTORY / LAB / FLESH / BACKROOMS
```

On exit, a harmless "ObjectDB instances leaked" warning prints.

### Setting up on Windows (new machine)
1. **Godot 4.7.2 stable, standard build** (not .NET): from https://godotengine.org/download/archive/ (4.7.2-stable, Windows 64-bit). It is a single exe; no installer.
2. **Put it on PATH as `godot`.** The scripts and docs call `godot`. Either rename `Godot_v4.7.2-stable_win64.exe` to `godot.exe` in a folder on PATH, or alias it in Git Bash (`alias godot="/c/path/Godot_v4.7.2-stable_win64.exe"` in `~/.bashrc`). Keep the `_console.exe` next to it if you want console output in cmd.
3. **Git for Windows** (includes Git Bash and perl): needed for the `tests/*.sh` scripts and `tests/run.sh`, which uses perl for its timeout. Run tests from **Git Bash**, not cmd/PowerShell.
4. **Clone:** `git clone https://github.com/Demiffy/downline.git` (private, so sign in with the Demiffy GitHub account, e.g. via `gh auth login`).
5. **Git identity in the clone** (Vercel and the owner's rule): `git config user.name "Demík"` and `git config user.email "velnertomas78@gmail.com"`.
6. **First open:** `godot --path . -e` once (or `godot --headless --path . --import`) so the `.godot/` import cache builds, then `godot --path .` to play.
7. **Windows Firewall** asks the first time the game hosts or joins: allow it on private networks. Windows may ask for **microphone** access (Settings → Privacy → Microphone → allow desktop apps).
8. **Paths:** the Mac commands in this file use `/tmp/...` for screenshot output. On Windows use any folder, e.g. `C:/Users/<you>/shots`. In Git Bash, `/tmp` works too.

### Controls

| Key | Action |
|---|---|
| WASD / Shift / Ctrl / Space | move / sprint (7 s stamina) / crouch (silent) / jump |
| E (hold for some) | pick up, use, call or ride the elevator, pry crates, manual bulkhead override (loud), reset breaker |
| LMB / RMB | use held item (toggle light; held equipment equips it) |
| F or MMB | scan (needs the Scanner equipped) |
| 1–7, wheel | select slot (uses the physical key, so it works on any keyboard layout) |
| T / N | helmet headlamp / night-vision goggles (with the HEADLAMP / NIGHT_VISION upgrades; they share the helmet cell) |
| V | push-to-talk (when VOICE is set to push-to-talk) |
| Q / C | drop item / drop equipment (heavy items are set down, not thrown) |
| Esc | pause menu + settings / leave the terminal |
| F11, Alt/Option+Enter, Cmd+Ctrl+F (Mac) | fullscreen (the UI scales via canvas_items stretch) |
| R | restart after game over |

**Playground** (`-- playground [THEME]`; from PowerShell `& "C:\Users\velne\bin\godot.exe" --path . -- playground LAB`). Styled like the pause menu (it borrows `menu._theme()`). A slim status strip under the quota shows the place, creature count, clock and which toggles are on (H hides it). TAB opens the tool panel on the right, four tabs, every hotkey also a button (F-keys need Fn on a Mac):
- **CREATURES:** spawn any of the 15 at the crosshair (siren and husk included), a body that gets up as a husk in 3 s, a body that stays down, freeze (F2), state labels (F3), clear (F4), a noise at the crosshair (F8; N stays night vision).
- **ITEMS:** every piece of gear (wedge and walkie included), random / valuable / heavy scrap (G for random), a photograph.
- **PLAYER:** god mode (F1), noclip (F7), heal, take 25 (turns god mode off, to see the visor crack), recharge everything, +500 credits, headlamp + night vision, back to the lift.
- **WORLD:** fullbright (B), path gizmos (P), slow motion (F6), day/night (F5), up/down (F9), to the breaker, **checkpoint** (builds it with scrap in the shredder's hopper and you at the lever) and back to the station, the events (power failure, reset breaker, tremor, airdrop), rebuild as any theme (F10 cycles).
- Screenshots: `tests/run.sh 300 --path . -s tests/playground_shots.gd -- <dir> playground LAB`.

---

## 3. The game loop

1. **Checkpoint.** The terminal is at the front of the crew car. `LEAVE_CHECKPOINT` issues an assignment with a quota and opens the gate.
2. **Route.** `MAP` shows 3 stages of 2–3 station choices each. `VIEW_STATION <letter>` lists facility, size, surface biome, weather (needs WEATHERVANE), hazards and the monsters you'll likely meet. `ROUTE_TO <letter>` departs: the world slides past the train.
3. **Station.**
   - Day runs 08:00 → 24:00 over 720 real seconds, with one warning two hours before departure (`main.depart_hour()`: 24:00, or 01:00 with OVERTIME_PERMIT). There is no clock on the HUD or in the pause menu (the owner's call): the train's clocks and the terminal tell the time.
   - **Minimap** (MINIMAP upgrade, `main.draw_minimap`): underground only. The plan of both floors is built once per site (`_mm_build`) and drawn with one transform, at 20 Hz. It shows scrap and creatures only where the scanner found them (`main.scanned`, filled in `scan()`; creature marks fade over 20 s), crewmates as a ping every 5 s, and no remains marker. The terminal site map follows the same rule.
   - **Spawning:** no creature spawns within 25 m of the train or 20 m of a player (`level._spawn` moves it out of sight or drops it); surface pulsators only ≥40 m from everyone, out of sight (`_surface_hidden`). Host-only spot picking uses its own RNG (`_spot_rng`) so a crewmate's build stays in step.
   - Follow the ELEVATOR signposts from the station house to the lift headframe and ride down 60 m into the facility.
   - Scrap goes **inside the train** to count.
   - The train leaves at 24:00. Stepping off while it's moving puts you in the (now awake) level; climb back aboard before it has fully pulled away or you're "LEFT BEHIND". Hopping off while it rolls in to a stop is harmless.
   - **Death doesn't end the run** (`main._on_died`): a replacement wakes aboard at the same stop, +1 h. Cargo aboard is never touched (the owner asked: no impound). A REMAINS ragdoll (heavy, scan target) lies where you fell with what you held scattered round it; bringing it aboard pays `RECOVERY_PAY` (20 cr, `_check_remains`). The dead player's puppet is hidden (`puppet.set_pose`): the ragdoll is the only body. **LEFT BEHIND** (`main._write_off`) sends you to the next stop and writes off only the scrap you were carrying. Game over only comes from ramming the gate.
   - **Combat:** weapons are `kind: "weapon"` items (CROWBAR, FIRE_AXE, SHOTGUN). `player._attack/_melee/_shoot` call `monster.take_hit(dmg, from, by)`; monsters have `health`, `hit_kind`, `react_to_hit`, `die` + `death_anim` (bodies stay, group "corpses"). Statue and wraith override `take_hit` (immune). Weapons aim at `monster.hitbox`, a box fitted to the model at rest on layer 64 (`HITBOX`, meta "monster"), as well as the walking capsule. Kills drop `Data.DROPS` parts; the wraith drops MINERS_HELMET the first time light dissolves it; the scrapper drops its shell itself.
   - **Explosions** (`main.explode`) only hurt players with a clear line from the blast to their head, chest or knees (`_blast_reaches`).
   - **Creatures stay off the train and out of the lift cab:** invisible walls on layer 32 (`B.MOB_BARRIER`, only monsters collide; `train._mob_barrier`, the cab's in `elevator.build`), and `monster.forbidden()` stops the stuck-failsafe teleporting them in.
   - **Items in use:** MEDKIT (heal to 100, consumed; 1–3 lie about each facility), ADRENALINE (20 s of unlimited stamina, +15% speed), FLARE and NOISEMAKER are thrown with `extra.active` so `pickup._activate` runs on every machine (flare: red light 60 s + hiss noise; noisemaker: rings 6 s after 3, noise radius 32; only the host's noise counts).
   - **Charging:** nothing charges by itself any more. The charging rack on the crew car's back wall (`train.add_charger`, hold E) tops up every battery you carry, the helmet cell and the shotgun's shells (`player.recharge`).
   - **Photos** are PHOTO pickups; `pickup.extra` carries the picture (`{"tex": ImageTexture}`) through pick-up/drop; click to hold it up (`viewmodel.set_inspect`). Over the network the picture goes as a JPEG (~20 KB). The observer drops it on solid floor where it stood, or right beside it if it was straddling a pit (`observer._drop_photo`). Every photo taken goes into `main.photo_log` (the host sends each one to the crew, and the whole album to a latecomer); the pause menu shows them as prints, click one to hold it up.
   - **Fall guard:** a pickup that ends up below y = -75 (`pickup.LOWEST`, under any basement) goes back to where it last lay still.
   - **Fear audio:** `player._fear_sounds` (heartbeat loop) from nearby monsters' `is_hunting()` and HP. The breathing loop was removed (the owner heard it as a constant sweeping noise).
   - **Field guide:** `Data.GUIDE` (keyed by creature script name), unlocked in `main.scan` via `guide_seen()` (monsters + group "fauna": snatcher, bear trap, gloe; leviathan on eruption), kills via `monster.die()` -> `guide_killed()`. Saved to `user://field_guide.json` only when main is the current scene (tests never touch it). Terminal `GUIDE [name]`.
   - **Memento:** `game_over` passes `main.pinned_photos()` to `hud.memento()`, a board of crooked prints with stamps along the bottom of the run-over screen.
   - **Ragdoll/suit:** `suit.gd` builds the employee in 11 jointed parts (standing, limp, per-part); `ragdoll.gd` makes REMAINS a ragdoll (top-level RigidBodies + joints) that still acts like a pickup.
   - **Big rooms:** `facility.gen_layout` -> `_pick_groups` merges cells (2x1 / L / 2x2, never the lift room, never the vault, no bulkhead inside); `layout.groups/group_of`. In `build()` internal edges get `Halls.header()` instead of a wall, grouped cells skip `_dress` and get `Halls.light()`; then `Halls.dress()` per group places the set piece in a frame (u along, v across) with `room_for()` checks against door zones and `fac.crates`. `cell_walls[c]` keeps each cell's walls ([4] = open to the same room). Hazards skip grouped cells; `random_point` picks open floor in them; map/minimap merge them.
   - **Navmesh pathing:** `facility._bake_nav()` bakes one NavigationMesh per site from static colliders (layers 1 + 16), agent radius 0.3, swing doors read standing open, lift shaft blocked out, a NavigationLink3D across each bulkhead enabled while it's open. `facility.nav_path()` pushes route bends off corners for wider bodies. `monster.walk_to` follows `nav_path` and glides stair segments to their end; falls back to the old room graph when there's no route. Railing `solid` panels are full-height invisible boxes on layer 16 (BARRIER: blocks bodies, not sight/sound rays). Doors never swing into stair rooms (and none between two stair rooms). NOTE: the nav map only answers for a freshly loaded site after it syncs (~a dozen physics frames). Probe (`tests/path_probe.gd`): 12 walkers x 4 themes went from 291 arrivals / 173 stuck events to ~1000 / ~60; the `levels` failsafe count from 1-8 to 0.
   - **Path gizmos:** playground [P] (`pathdebug.gd`).
   - **Bulkheads cut pathing:** `facility._door_link` disconnects the A* edge while shut; `reachable()`; wander points avoid sealed rooms.
4. **Back at the checkpoint** after 3 stations (`ROUTE_TO CHECKPOINT`).
   - Throw scrap into the **shredder** hopper and throw the MAIN DRIVE lever. Credits are paid at the day's prices, item by item as it chews (`shredder.gd`, see §5).
   - **Payload rank** compares what you shredded against the quota's value: B ≥ 1.0×, A ≥ 1.5×, S ≥ 2.0×, each with a one-off bonus (30 / 80 / 150 cr).
   - Quota met: the gate opens. Leaving without it: the train rams the gate, game over.
5. **Game over** shows run stats. The best run is saved to `user://best_run.json`.

**Shop and upgrades:**
- **Shop:** the shop container at the checkpoint, or the terminal (`SHOP`, `BUY <item> [n]` with prefix completion).
  - Items: FLASHLIGHT 35, LANTERN 55, SCANNER 90, BACKPACK 80, CROWBAR 45, FIRE_AXE 85, SHOTGUN 240, MEDKIT 40, FLARE 15, NOISEMAKER 25, ADRENALINE 35, DOOR_WEDGE 20, WALKIE 50.
  - **Door wedge:** click a shut swing door to jam it (`main.wedge_door`, request/event "wedge"). Creatures can't shove it; they bash at it and the host breaks the wedge after about 10 s (`door._bash`). E pulls it out and gives it back. The stuck failsafe never skips a creature past a wedged door (`monster._wedged_between`).
  - **Walkie-talkie:** while held and charged, your voice frames carry flag 1 (radio, `voice.packet` header is [seq u16][flags u8]) and drain its battery. Anyone carrying a charged walkie hears it at any range on the "Radio" bus: band-limited, overdriven, hissing, with a squelch on key-up and release (`voice._radio_push`). HUD shows RADIO / ON AIR.
  - **Helmet damage:** `player.crack_tier` (hp below 75/45/20 → 1/2/3) holds until you're back to full. A full-screen crack overlay (`hud.visor_cracks`, `cracks.gd`) and the same cracks on your suit's visor (`Suit.set_cracks`, pose[13] for crewmates), with a glass-crack sound per new tier.
  - Orders arrive on the pump handcar behind the train after 18 s (5 s with QUICK_DELIVERY). `train.make_handcar` + `_handcar_tick`: wheels, crank, rod and walking beam all follow how far it rolled.
- **Upgrades** (`UPGRADES`, `BUY_UPGRADE`, at a checkpoint only), permanent for the run:
  - BETTER_BOOTS 215
  - WEATHERVANE 150
  - MINIMAP 375
  - STORAGE_CAR 250 (adds a walk-in car)
  - QUICK_DELIVERY 120
  - BATTERY_PACK 140
  - DIGITAL_CLOCK 90 (7-segment display with a departure countdown)
  - GAS_FILTER 120 (gas immunity, `hazards.has_mask`), ACID_SHIELD 110 (acid rain harmless)
  - HEADLAMP 160 [T], NIGHT_VISION 600 [N]: both run off the helmet cell (`player.helmet_charge`, 300 s, x1.6 with BATTERY_PACK); night vision is a screen shader in `hud.gd` plus a faint IR omni on the camera
  - ARMORED_SUIT 300 (-25% damage), INFIRMARY 180 (heal to 100 aboard), CARGO_HARNESS 220 (+1 hand slot, up to 7 with the backpack)
  - SIGNAL_BOOSTER 140 (scan 26 m, 3 s cooldown), LIFT_MOTOR 150 (lifts twice as fast), OVERTIME_PERMIT 250 (departs 01:00)
  - MARKET_CONTACTS 200 (+15% shred pay), SOFT_SOLES 170 (footstep noise halved)
- Acid rain: 4 s of grace out in it, then 0.75 HP/s (`main._acid_t`).

**All terminal commands:** HELP, BALANCE, MARKET, SHOP, BUY, MAP, VIEW_STATION, ROUTE_TO, LEAVE_CHECKPOINT, SCAN_TRAIN, SCAN_SURFACE, SCAN_FACILITY, OPEN_BULKHEAD, CLOSE_BULKHEAD, UPGRADES, BUY_UPGRADE, LIST_CAMS, VIEW_CAM, NEXT_CAM, PREV_CAM, TOGGLE_LIGHT, EXIT_CAMS, MINIMAP, EXIT_MINIMAP, LIST_LOGS, READ, CLEAR.
- The terminal has history (↑↓), Tab completion, live usage hints and typo suggestions ("did you mean").
- PgUp/PgDn scroll. It refocuses its input after each command.
- The train's in-world CRT mirrors the terminal text.

---

## 4. Code map (`src/`)

| File | Lines | What it does |
|---|---|---|
| `main.gd` | 1209 | Game state, day clock, travel (the world slides past the train), shredder and payload rank, terminal commands, environment/fog/sky per biome and weather, ambience beds and reverb space, noise propagation, scanning, site map + minimap drawing, game over, settings and menu hookup. |
| `data.gd` | ~200 | **All content.** 60+ scrap items with resources, sizes and heavy/rare flags; tools; upgrades; lore logs; shop; facility themes; `HABITAT` (spawn weights per monster per theme); `SITE_HAZARDS`; weathers; `pace()` (test speed-up). |
| `facility.gd` | 1642 | Procedural facility: room-grid layout from a seed (main floor + lower floor B-2); room archetypes and dressing; vault, mezzanines, pits, stairwells, crawl vents, bulkheads, swing doors; lights with flicker; cameras; cross-floor monster pathing (A*, stair routes, around the lift shaft, front-on doorways). |
| `level.gd` | 835 | One stop: surface (terrain, houses, sheds, signposts, scenery, arctic dressing) + elevator + facility + spawns + hazards, or the checkpoint yard. Spawn director (more pulsators over time, statue after 15:00, leviathan after 17:00, surface pulsators after 18:00). |
| `props.gd` | 1719 | Prop kit: furniture, machines, generator (static half), pumpjack (static half), tin shed, rocks/spires/arches/mesas/boulders, fences, shipping containers, shop container, supply crate, wall fixtures, and more. |
| `art.gd` | 1039 | Procedural textures (64 px pixel-ish, nearest + anisotropic). Material cache, box/cyl/sphere/seg/ring/prism primitives, walls with holes, lamps (pendant, wall, fluorescent; `bind_glow` so bulbs dim with their light), houses (4 styles), pines, snow caps. |
| `train.gd` | 1132 | Diesel road-switcher + crew car + flatcar (+ storage car): bogies and wheels, roof, cab, plow, ditch lights. Control desk with live gauges, horn, idle and compressor sounds, analog clock + digital clock upgrade, CRT screen. |
| `hazards.gd` | 1101 | Flooded rooms (water, doorway/vent spills, live cables), gas rooms, steam lines, main breaker, and the power failure / tremor / airdrop events. |
| `elevator.gd` | ~430 | Mine-shaft lift: headframe, cab, landing portals with enamel signs and arrow lamps, car operating panel, bulkhead lamps. Doors are driven per landing. Crawls on emergency power. Carries riders and cargo. |
| `sfx.gd` | 812 | Every sound is synthesized: filters, modal synthesis, horns, diesel idle, ambience beds per theme, footsteps per surface, creature loops. Buses `World` (with reverb) and `Ambience`. |
| `terminal.gd` | 527 | The amber CRT terminal UI + monitor feed (cameras, map). |
| `menu.gd` / `settings.gd` | 494 / ~60 | Esc pause menu (Bureau-console style) and settings saved to `user://settings.cfg`. |
| `scanfx.gd` | ~200 | Scanner pulse: depth-based blue wave shader, through-wall glow overlay, lock-on rings, name/value tags. |
| `player.gd` | ~470 | First-person controller: stamina, crouch, heavy carry, wading, surface footsteps, flashlight (light cull mask skips the viewmodel layer), inventory. |
| `viewmodel.gd` | ~220 | First-person sleeve, glove and held items, on render layer 2. |
| `hud.gd` | ~300 | Helmet-visor HUD: clock/compass, quota, HP ring, battery, feed, alerts, scan list, visor fog, minimap. |
| `paint.gd` | ~160 | Weathered world text from system fonts (stencil / plate / type / chalk). |
| `merge.gd` | ~125 | Bakes static primitives into one mesh per material per chunk. Skips `live` nodes, nodes with scripts and moving bodies. `Engine.set_meta("no_merge", true)` disables it for debugging. |
| `genset.gd` | ~200 | Moving half of the generator: an open-frame 4-cylinder engine with crank kinematics, valve timing, governor, flywheel, RPM needle and sound. Stalls on power failure. |
| `pumpjack.gd` | ~120 | Moving half of the pumpjack: one crank angle drives everything; the beam angle is solved from the pitman linkage. |
| `door.gd` | ~100 | Double swing doors with see-through wired-glass windows. Monsters shove them open. |
| `save.gd` | ~230 | Saving and continuing a run (§5). |
| `shredder.gd` | ~640 | The checkpoint shredder: model, cycle, sounds, network events (§5). |
| `pickup.gd` | ~60 | Physical item (RigidBody) with impact sounds and noise. |
| `items.gd` | 705 | A hand-built model for every item. |
| `monster.gd` | ~250 | Shared monster base: `walk_to` (pathing, stair routes, sidestep when pinned, unseen unstuck failsafe, out-of-world guard), `sees`, `seen_by`, `observed`, `presence` sound loops. |
| monsters | | `roomba` `pulsator` `statue` `marionette` `mimic` `warden` `leviathan` `snatcher` `bear_trap` `scrapper` `gloe` `siren` `husk`, one file each. |
| `cracks.gd` | ~110 | Procedural visor-crack textures (three tiers, cached), for the HUD and the suit's visor. |
| `playground.gd` | ~380 | Debug playground (§2). |
| `build.gd` | ~110 | Basic boxes, interactables, labels, displays, omni lights (with distance fade: `B.fade`). |

### Monsters

| Monster | Behaviour |
|---|---|
| Roomba | Patrols. Breaking its red laser beam arms it; it then explodes. |
| Pulsator | A glowing sac on three arms that lights the dark round it, gurgles and has a heartbeat you hear from afar. Blind: hunts by sound; bursts on contact (clear line) or 3 s after it locks on. 110 damage, 4.5 m, walls stop the blast. The director adds one every 110 s up to a small cap, only ≥24 m from everyone and out of sight (`level._hidden_spot`). |
| Statue | Wakes when first seen and moves only while nobody looks. Strangles. |
| Marionette | Moves only *while* watched. Instant kill. |
| Mimic | A barrel with tells (drool puddle, lid ajar with teeth, a swell when you're near, wet twitches). Within 1.25 m it lashes a segmented barbed tongue up out of the lid and over at your face (0.6 s, 35 damage), then runs off to hide; any hit sends it running. |
| Warden | Sees only what its searchlight hits. Can't climb. |
| Leviathan | Surface worm, active late in the day. Noise during a rumble kills you unless you're under a roof. |
| Snatcher | Ceiling vent that drags you elsewhere. Drips. |
| Observer | Bellows camera on harvestman tripod legs (2-bone IK, planted feet). Follows behind you, clicking. Look at it: 0.65 s flash whine (look away to cancel), then a white-out (`player.blind`), a noise, and it flees, leaving a real photo (SubViewport snapshot) of you on the floor. |
| Wraith | Dead miner in a shroud and cracked hard hat; spawns after 16:00 (director). Carries the dark: negative light, nearby lamps dimmed via `facility.haunt()`, visor frost. Flashlight beam: recoils, and comes apart after 1.6 s (drains battery 3x). Lit lantern holds it at 3.4 m. In the dark: 45 damage, then gone ~25 s. Faster in a power failure. |
| Bear trap | Holds and hurts you until pried open. |
| Siren | Grey, eyeless, a slit of a mouth down its whole face. Moves three ways, blended: hunched and swaying with sudden head jerks; creeping low with long reaching strides; on all fours at a lope when it runs. Seen for 0.3 s (`SPOOK`) it bolts at 9 m/s (a sprint is 6.5), away from you and not past you, re-picking if you chase it; out of sight again, it moves to a hidden spot elsewhere (`level._hidden_spot`). Cornered within reach, it lunges instead. Noises draw it over (`hear`). The host keeps short clips of what each crewmate said (`voice.clips`, 0.7–5 s, 6 each); the siren plays one, in that voice, to the nearest player within 28 m who can't see it (`ent_event "say"`, 12 kHz), then creeps closer while unseen. Seen for 2.5 s, or hit: it flees. Close and unseen: lunges, 45 damage. No voices yet: it fakes a sound (steps, a cough, a door). |
| Husk | A REMAINS body left lying in the facility for 90 s (`level._possessions`, `POSSESS_AFTER`) quietly gets up, looking exactly like a crewmate: the normal suit, a crewmate's walk and footsteps, no sounds of its own; the one tell is that no name shows over its helmet. Some sites also have an earlier crew's body lying in the facility that gets up 30-70 s after you arrive (`level._old_crew`). Wanders; seeing you, it comes to 2.4 m and stares for 4–6 s, head tilting, then attacks (40) and backs off to stare again. Killed, it drops a body that never gets up again (`no_possess`). |
| Scrapper | Shy scrap-shelled creature. Catch it calm for a valuable shell. |
| Gloe | Friendly light that follows you. |

**Habitat weights per facility theme** (`Data.HABITAT`):
- **Backrooms:** no roombas, mimics or wardens; more marionettes, statues and gloes.
- **Flesh:** thick with snatchers and pulsators; no roombas or gloes.
- **Factory:** more wardens, mimics and scrappers.
- **Lab:** more roombas and statues.

**Hearing** (`main._carries`): a clear line carries the full range; through a wall or a shut bulkhead, 30% of it; otherwise the walkable route round corners (navmesh) must be under 60% of the range. Shelving and pallet racks are on layer 16 (solid to bodies, not to sight), so creatures that move only unseen (statue) stay put when you can see them through a shelf; `monster.observed` samples 12 points across the body.

---

## 5. Systems in detail

### Saving the run (`save.gd`)
- One run on disk, `user://run.save` (`FileAccess.store_var`, binary; photos as JPEG bytes). Written by solo or the host only: on every arrival (`_travel`), every 2 minutes (`AUTOSAVE_EVERY`), after a shredder cycle, and from the pause menu (SAVE & EXIT TO TITLE, SAVE & QUIT TO DESKTOP). Never while the train is moving or the shredder is running. Game over and RESTART RUN delete it. `main.autosaves` is only on in the real game (tests turn it on with their own `save_path`).
- Kept: `net_state()` (credits, quota, route, upgrades, clock...), the stop and its seed, every pickup aboard the train ("T") or at the stop ("L") with charge, extra, transform and pin, REMAINS (as a body where it lies), open supply crates (`facility.supplies`, `mark_opened`), the host's pockets and health, `crew_pockets` (by name), and `photo_log`.
- `Save.restore`: frees the starter kit and the checkpoint, rebuilds the stop from the seed, swaps the stop's fresh items for the saved ones, drops today's hazard events that already happened, puts you aboard the train. Creatures come back fresh from the seed.
- Crew: on each autosave the host broadcasts "pockets?" and clients answer with `request("pockets")`; the next save keeps them. Continuing with a crew: the host presses CONTINUE THE SAVED RUN in the lobby (`lobby._start(true)`), and `net._welcome` → `main.net_welcomed` grants each crewmate their pockets by name and sends the photo album.
- Title screen: CONTINUE RUN (solo) with the save's assignment, place, time and credits (`Save.peek`).

### The shredder (`shredder.gd`)
- A twin-shaft shredder built after real ones: a flared hopper with a rubber flap curtain, two shafts of hooked cutter discs (5 teeth each, spacer collars) turning into each other at different speeds (0.78x), stripper combs between the discs, a finned motor with a fan cowl driving a spoked pulley by V-belt into the gearbox, a discharge conveyor (moving cleats) up into the skip, a rotating amber beacon and a klaxon horn on the gantry.
- Control pedestal: an ammeter (needle follows the load), POWER/RUN/OVERLOAD lamps, an emergency-stop mushroom (decor), and the MAIN DRIVE lever on a toothed quadrant (ratchets down, clunks, springs back up when the cycle ends).
- A cycle (`run`, host): klaxon, beacon, motor spools up (`shred_motor` loop pitched by speed); each item in the hopper (light first, heavy last) is frozen, dragged down to the nip, then shudders and sinks into the teeth while it's chewed (`shred_metal` with sparks for metal-heavy items, `shred_soft` otherwise, dust, a camera shake nearby, shafts slow under load). Heavy items jam it first: the drive stalls, OVERLOAD lights, it reverses, then goes at it again. `main.shred_item` pays each item as it goes (the readout shows SHREDDING +N CR), `main.shred_done` sums up, ranks the payload and opens the gate. The shreds ride the belt and pile up in the skip (just for show, local, capped at 70). Anyone in the throat while it turns takes 30 and is thrown clear.
- Everyone sees it through `net.event("shredder", [...])` (start / jam / chew / paid / stop); only the host moves items and pays. An empty hopper runs it up and down again (`dry_run`).
- Static parts are built straight into the level (so they merge); `shredder.gd` keeps only the moving parts.

### Facility generation (`facility.gd`)
**Layout:**
- The main floor is a grid of 12 m cells grown from the lift room, with extra loop links, bulkheads (coded, opened from the terminal or with a loud manual override) and crawl vents (1.1 m) between unlinked neighbours.
- The **vault** is the furthest dead end, behind its own bulkhead, with the best loot. It opens only with the **VAULT KEYCARD**: no terminal, no manual override. `level._place_keycard()` leaves one per site well away from the vault (14 m+), preferring mezzanine loot spots and the lower floor, furthest from the lift, with a bear trap beside it when it's on the floor (same draws on every machine; the host spawns). The card glows faintly red and is a scan target. Hold it and press E at the reader outside the door (`facility._vault_swipe`, host-side; `Interact.who_now`'s held item; a crewmate's card is taken back with `to_owner "take"`) and the door opens (`open_vault`: the reader lamp goes green). Saves keep `vault_open`.
- **The strongroom** (`facility._vault`): brushed-steel walls with rails, banks of deposit boxes on three walls (two big ones per wall to pry open, `_deposit_box` / `_open_deposit`, hold E 1.6 s: 1-2 of GOLD_BAR, CASH_BOX, BEARER_BONDS; they're in `supplies` so saves remember them), a steel table under a green-shaded lamp with gold bars and a cash box or bonds on it, a mesh cage at the back round the heavy prize with shelving, yellow floor lines and a STRONGROOM 7 stencil, cold strip lights and two red lamps. Outside: a riveted steel surround with hazard chevrons, a locking wheel and bolts on both faces of the door, AUTHORISED PERSONNEL ONLY, an amber caged lamp. GOLD_BAR / CASH_BOX / BEARER_BONDS are `no_spawn` (vault only).

**Room kinds:**
- storage, machine (generators), pit, collapsed, break, office, lab, server, empty, atrium (mezzanine deck + stairs), tunnel (ribbed corridor on straights), vault, stairwell.
- Themes FACTORY / LAB / FLESH / BACKROOMS change textures, lights and the room mix.

**Lower floor (B-2)** grows out from pits and stairwells into basement rooms: boiler, pipes, maintenance, storage, flooded.
- Its meshes go on render layer `LOWER_BIT`, and upstairs lights skip that layer, so light doesn't pass through floors.
- `_clear_holes()` removes clutter from stairwell openings.

**Pathing:**
- A* over nodes for upper and lower rooms, linked at vertical stairs.
- `stair_route()` returns a fixed point sequence: line up, onto the flight, along it, step off. Monsters glide along the flight.
- Other rules: walk the catwalk arms in pits, go round the lift shaft, approach doorways from the front, detour round the side of a flight.

**Placement helpers:**
- `_solid` / `crates` keep furniture apart.
- `_inside()` keeps floor decals within their room.
- `_wall_layer`, `_scatter` and `_fill` furnish rooms.
- `_on_wall` stops wall decor overlapping.

### Hazards and events (`hazards.gd`, per station, seeded)
**Rooms:**
- **Flood:** wading is slow and splashes. Water spills through doorways and vents into a fading sheet; bulkheads hold it back. Live cables arc through the water.
- **Gas:** a GAS_MASK in your pack protects you, and one always spawns somewhere.
- **Steam:** gauge, hiss, then a layered jet with shimmer and visor fog.

**Events,** scheduled by the hour:
- **Power failure:** lights and emissive surfaces dark, red emergency lights, lift at 1/3 speed, cameras and bulkheads offline, cables dead, generators stall. Fixed by the MAIN BREAKER, which is shown on the scanner and map.
- **Tremor:** dust and falling debris, sometimes scrap; can trigger a power failure.
- **Airdrop:** a crate falls under a red flare and is loud to open.

### Surface (`level.gd`)
- **Terrain:** rolling dunes, flattened along the track, around the lift and under houses.
- **Buildings:** a walk-through station house and other houses (§6), signposts to the lift with distances, tin sheds.
- **Scenery:** car wrecks, ruin walls, scrap heaps, fences that follow the ground, a water tower, windmills, a pumpjack, an arch frame, telephone poles with sagging wires.
- **Distant landmarks:** banded rock spires and arches past the edge, stepped mesas on the horizon.
- **Biomes:** DESERT (sand, warm light) or ARCTIC, 25% of stations. Arctic gets:
  - cold light and spruce woods (some trees dead or snapped)
  - snow on roofs and caps on granite rocks, spires and mesas
  - drifts, frozen ponds, and plough banks along the track
- **Weather:** CLEAR, SANDSTORM (desert) or BLIZZARD (arctic), ACID_RAIN (hurts unless roofed).

### Train (`train.gd`)
- **Locomotive:** a road-switcher with a long hood (radiators, spinning fans, exhaust stack with soft smoke), cab with windows and number boards, short nose with headlights, and a pilot with V plow, chevrons, anticlimber, ditch lights and hoses. Walkways have yellow rails; bogies have spinning wheels.
- **Crew car:**
  - **Engineer's desk:** six live gauges (RPM, speed, brake, load, fuel, oil), warning lamps, throttle quadrant, horn valve.
  - **Furniture:** terminal, railway clock, enamel station plate, chalkboard, cargo shelves.
- **Sound:** synthesized five-chime horn (K5LA chord with bloom and sag), diesel idle that revs with speed, compressor cycle with an air-release blowdown, rail clacks every 12 m.

### Rendering and performance
- **Merging and culling:** static geometry is merged per chunk. Lights use distance fade: shadows within 12 m, lights off past 45 m, dual-paraboloid omni shadows. That took facility frames from 25 ms to about 9–10 ms (`tests/perf.gd`).
- **Occlusion culling** (on in `project.godot`): `facility._occluders()` puts a BoxOccluder3D in every thin, big (≥ 2.4 m) wall, floor and ceiling box. Facility floor/ceiling slabs don't cast lamp shadows (`Merge.bake(..., indoors = true)`), and merged chunks stop drawing at 140 m (`Merge.FAR`). Fixed site (`perf.gd` seeds its RNG): 14.5 → 12.2 ms average, 17.5 → 14.8 ms worst. Splitting small detail into its own LOD chunks was tried and reverted (it doubled draw calls). FPS counter: VIDEO settings.
- **Lighting rules:** explosion and electric-arc lights cast shadows so they stop at walls. Flickering lamps dim their bulb materials too.
- **Quality setting:** LOW / MEDIUM / HIGH changes render scale, shadow atlas size, SSAO and glow.
- **Environment:** ACES tonemap, volumetric fog (dense per weather), glow, SSAO. SSR is off (it made blocky reflections).

---

### Sounds measured off real recordings
Freely licensed recordings (Wikimedia Commons, CC0 / CC BY / CC BY-SA: footsteps, metal hits, doors, drops, glass, drips, train horns, a diesel railcar, a gunshot, thunder, a siren, a heartbeat, a tiger, a scream, wind) were measured with `tools/sound_analyze.py` (envelope, attack/decay, octave bands, centroid, the strongest modes and their decay rates, pitch track, onsets, slow modulation), then our synthesized sounds were rebuilt to match (`tests/sfx_dump.gd` writes ours to WAV for the same analysis). No recording is in the game or the repo.
- Footsteps (`Sfx._step`): heel strike, then toe/scuff 70-110 ms later; concrete grit, tile click, metal plate ring and grate rattle, hollow wood knock (sometimes a creak), sand and snow crunch. Four takes per sound (`TAKES`, `_has_takes`: steps, thunk, clank, door_shut, drip), used in turn, each seeded by its name (the same on every machine).
- thunk (dropped things: 200/700/1800 Hz knocks + click), clank (a free bar's partials 1 : 2.76 : 5.40 : 8.93 + structure hum), door_shut (`_slam`: the 128-360 Hz woody cluster + thump + latch), door_open (latch + hinge), drip (rising bubble plink), crack_glass (crack + tinkle tail), heartbeat/heart (lub ~105 Hz, dub ~138 Hz), diesel (39 Hz firing, 78 Hz strongest, below 900 Hz), horn (reedier, brighter, swells in faster).
- Creature voices (`_voice`: a rough wandering sawtooth with a throat flutter through three formants, breath under it): roar (warden, leviathan), growl, and shriek (mimic, pulsator, siren; the train's brakes keep the mechanical screech).

### Holding things, models, upgrades you can see
- **First person** (`viewmodel.gd`): the glove is rebuilt per item (`_fist(radius, wrap)`). Bars, pipes and handles: fingers close all round at the item's own thickness. Tall slim things (bottles, cans, thermos, spray cans): the hand turns upright round the body, knuckles out, thumb across the front (`grip.rotation`, the forearm from a wrist below the knuckles). Anything else: taken by its right-hand edge, thumb on top, fingers flat underneath. Wide or heavy things: both hands (`_left_hand`, a mirrored glove and sleeve) on its two sides. Every item switch rebuilds the forearm.
- **Crewmates** (`puppet._hold_upright`, `_reach`): two-bone arm IK puts the fists on the item; small things in the right hand, wide or heavy ones with a hand on each side, the left hand on a shotgun's forend or up an axe haft.
- **Dust and weather motes** (`player._particles`): soft round dots that fade out within ~1 m of the camera (they used to be cubes that filled the screen up close).
- **Upgrades on show:** INFIRMARY (cot, pillow, drip stand, med cabinet in the crew car, `train.show_upgrade`), WEATHERVANE (on the crew car roof, turning), ARMORED_SUIT (steel plates on chest, belly, shoulders and shins: `Suit.set_armor`, crewmates and the photo/camera suit), NIGHT_VISION (goggles on the helmet's brow: `Suit.set_goggles`, flipped down when on), LIFT_MOTOR (the Bureau's winch truck parked by the headframe with its cable up to the sheave: `winch_truck.gd`). Suit parts are named now (`find_child("torso")`).
- **Train doors** (`train.set_doors`): the platform doors' leaves are moving, solid pieces with see-through windows; they roll shut as the train pulls out (after the horn) and open on arrival.
- **Item models fixed** (seen on turntables, `tests/item_sheet.gd`): door wedge (the slab's edges faced inwards: `slab` now orients them from the centre), gas mask, red copper pan (round), work boot, water bottle label, milk jug handle, thermos cap, keyboard keys, cast ingots (`Items.ingot`; gold polished), hot water bottle.
- Visual tools: `tests/item_sheet.gd` (every item from four angles on a plain sky), `tests/hand_sheet.gd` (every item in first person and in a crewmate's hands), `tests/upgrade_shots.gd` (every visible upgrade close up, the winch truck from four sides), `tests/door_shot.gd`, `tests/item_bounds.gd` (models off-centre or bigger than their physics box).

## 6. Content highlights (visual)
- **Houses** (`A.wood_house`): weathered planks, painted clapboard (six faded colours), brick with a flat roof and parapet, or a tin shack with a lean-to roof. One or two storeys, closed gable roofs with ridge cap and fascia, porch, boarded or broken windows, furnished inside.
- **Tin shed** (`P.tin_shed`): timber frame, overlapping corrugated sheets (some missing or rusted), lean-to roof on rafters, door off one hinge, stovepipe, workbench.
- **Generator:** an engine you can watch work: crank throws, conrods, crossheads, piston rods into finned cylinders, rocking valve gear, flyball governor, flywheel, belt-driven fan, alternator, live RPM needle.
- **Pumpjack:** samson post, horsehead arc, bridle, pitman arms, counterweighted crank, wellhead, prime mover.
- **Lift:** steel portals, enamel LIFT plate with level, arrow lamps, lit call buttons, ribbed doors with vision slots, car panel with an amber readout.
- **Pause menu:** soot-black panel with a hazard stripe, a sepia scanline blur of the game behind, amber accents, "SHIFT PAUSED".

---

## 7. Conventions and gotchas
- **No asset files.** Build geometry from `A.box` / `A.cyl` / `A.seg` / `A.ring` / `A.prism` / `A.sphere`, textures from `art.gd` `_px` kinds (adding a kind is a `match` branch), sounds from `sfx.gd` `_make` (add a name; add it to `LOOPS` if it loops).
- **Typing:** GDScript can't infer types from Variant. `var x := dict.thing` or `var x := array_of_variant[...]` fails to parse; use explicit types (`var x: Vector3 = ...`). This is by far the most common error here, and one parse error breaks the whole level ("nothing generates"). After edits, run `tests/run.sh 60 --headless --path . -s tests/check.gd` or `godot --headless --path . --check-only -s src/<file>.gd`.
- **Await on tweens:** guard with `if tw.is_running(): await tw.finished`, because a long frame can finish the tween first and the await then never returns.
- **Gameplay timers:** use `get_tree().create_timer(t, false)` so they respect the pause.
- **Z-fighting:** never leave coplanar faces of different materials. Offset decals by millimetres; floor decals sit at 5–20 mm. Prop bottoms on floors are fine. `tests/zfight_scan.gd` lists offenders.
- **Merging:** anything animated or swapped at runtime needs `Merge.live(node)`, or must live under a scripted node, which the merge skips (`genset.gd`, `pumpjack.gd`).
- **Lower floor:** meshes under `facility.low_root` get `LOWER_BIT`. New lights upstairs are masked off it automatically at the end of `build()`.
- **Test speed:** `Data.pace()` returns 0.1 when Engine meta `fast_test` is set (tests and playground loading), shortening travel, elevator and door animations. The elevator ride floors it at 0.3.
- **No `timeout` on Mac:** `tests/run.sh <secs> <godot args>` wraps godot with a perl alarm. Same on Windows in Git Bash (Git for Windows ships perl).
- **Multiplayer determinism:** anything random during a level build must come from the global RNG in the same order on every machine (see §10 "Same world everywhere"). Never call `randomize()` or use unseeded `RandomNumberGenerator`s in build or creature `_ready` code. Use `rng.seed = randi()`.
- **Multiplayer authority:** world-changing code checks `main.net.authority()` (true in solo and on the host). Effects aimed at a specific player go through the player/puppet methods (`hurt`, `say`, `fog_visor`, ...) so they reach the right person.

---

## 8. Tests and visual tools

```bash
tests/all.sh          # 13 headless suites in parallel (~3-5 min): check smoke stranded monsters loop hazards levels lift voice_play kit creatures2 save photo_drop
tests/all.sh full     # with the 3-station smoke
tests/mp.sh           # multiplayer: two headless processes over ENet on localhost (lobby, travel, mirroring, pick/drop/kill/doors, same build, voice, blood, death)
tests/mp_late.sh      # joining a shift already at a station
tests/run.sh 120 --headless --path . -s tests/voice.gd   # voice codec, the capture filter, voice occlusion
tests/mp_photo.sh     # an observer photo across a crew: lands where the host has it, picture and all
tests/mp_save.sh      # two rounds: play and save with a crew, then continue it (pockets, album, station)
tests/mp_shots.sh <dir> [quick]   # two WINDOWS: the client photographs the host's body and every creature copy (look at the PNGs)
```
State before the move to Windows (2026-10-08): all of the above pass. All 7 suites, `mp.sh` twice in a row, `mp_late.sh` and `voice.gd`. Also all passing on the Windows PC (2026-10-08, Git Bash). The mp tests pick a random UDP port in 24600–24990 on localhost.

| Suite | Covers |
|---|---|
| `check.gd` | terminal parsing, generator, data |
| `smoke.gd -- quick` | one station end to end (~4 s; drop `quick` for 3 stations) |
| `stranded.gd` | stepping off mid-trip leaves you behind, never in the void |
| `monsters.gd` | every monster's behaviour in a real room |
| `loop.gd` | heavy items, supply crates, vault (one keycard far from it, the terminal refused, the reader refusing an empty hand and opening with the card, deposit boxes paying out), mezzanines, payload rank |
| `hazards.gd` | habitats, flood, cables, gas, steam, power failure + breaker + generator stall, tremor, airdrop, lift doors, wall-muffled hearing, scanner highlight, pause menu, settings |
| `levels.gd` | two-level rooms and B-2: monsters through pits, mezzanines, lift ↔ farthest basement room; the unstuck failsafe must fire ≤ 6 times |
| `lift.gd` | the lift carries you, scrap and a body; cab contents sync from the cab ("E"); creatures stop outside the cab and the train |
| `voice_play.gd` | a crewmate's voice frames reach their player at full level from the very first game (voice.main used to stay null) |
| `kit.gd` | medkit, adrenaline, flare, noisemaker, charging rack, headlamp, upgrades, creature drops, weapon hit boxes, door wedge |
| `save.gd` | a run saved mid-station comes back the same in a fresh game: stop, site, credits, clock, upgrades, items left and aboard, a pinned photo, pockets, the album, an open crate, past events; the pause menu album; game over deletes it |
| `photo_drop.gd` | observer photos land on the floor (30 drops and 4 real flashes); an item that falls out of the world comes back |
| `creatures2.gd` | the siren (calls in a stolen voice from behind a wall, backs off when seen, lunges unseen, fakes a sound with no voices) and the husk (a body left lying gets up, comes close, stares, attacks, dies back into a body). Same site every run (seeded); creatures are placed on clear floor in line of sight (`clear_spot`). |

The `hazards` suite is a little flaky under the parallel load of `all.sh` (a different tremor/gas check now and then); rerun it alone before chasing it.

**Visual tools** (need a window). Screenshots go to the directory given.

| Command | Shows |
|---|---|
| `tests/run.sh 60 --path . -s tests/anim_sheet.gd -- pumpjack /tmp/pj.png 3.0 8` | animation contact sheet: `engine`, `engine_side`, `engine_close`, `pumpjack`, `shed` (turntable); span in s, frame count |
| `tests/run.sh 200 --path . -s tests/surface_shots.gd -- /tmp/s` | control desk, loco front/side, houses, pumpjack, horizon, lift panel |
| `tests/run.sh 150 --path . -s tests/arctic_shots.gd -- /tmp/a` | arctic station, clear and in a blizzard |
| `tests/run.sh 150 --path . -s tests/detail_shots.gd -- /tmp/d LAB` | lift landings, pendant, stairwell, basement doorway, vent spill, door glass |
| `tests/run.sh 150 --path . -s tests/lower_shots.gd -- /tmp/b LAB` | stairwells and basement rooms |
| `tests/run.sh 150 --path . -s tests/levels_shots.gd -- /tmp/l` | pit and mezzanine stairs (fullbright), doors |
| `tests/run.sh 150 --path . -s tests/hazard_shots.gd -- /tmp/h LAB` | every hazard and event |
| `tests/run.sh 150 --path . -s tests/fx_shots.gd -- /tmp/fx` | scanner pulse, steam cycle, flood doorway, tunnel grate |
| `tests/run.sh 150 --path . -s tests/zfight_shots.gd -- /tmp/z LAB` | walls, doorways and doors close up |
| `tests/run.sh 90 --path . -s tests/menu_shot.gd -- /tmp/m` | pause menu + settings pages, the photo album (and one held up), the title screen's CONTINUE RUN |
| `tests/run.sh 300 --path . -s tests/perf.gd -- FACTORY` | frame time, plus what each feature costs |
| `tests/run.sh 200 --headless --path . -s tests/zfight_scan.gd -- FACTORY` | text list of coplanar overlapping faces |
| `gallery.gd`, `scrap_gallery.gd`, `props_gallery.gd`, `shots.gd`, `progress_shot.gd`, `headframe_shot.gd` | monster, item and prop galleries, older shot sets |
| `tests/run.sh 900 --path . -s tests/playtest.gd -- /tmp/play 180` | a bot plays a station in real time (screenshots + log). Its pathing is limited; the owner said to leave it be. |
| `tests/run.sh 300 --path . -s tests/checkpoint_shots.gd -- <dir>` | the shredder (front, hopper, readout, sign, controls, drive, conveyor) and a whole cycle (lever thrown, chewing, conveyor, readout, skip), the delivery handcar |
| `tests/run.sh 300 --path . -s tests/carry_shots.gd -- <dir>` | first-person lantern/flashlight/body/heavy item/typewriter, crewmates holding things, turning their heads, looking down and up |
| `tests/run.sh 150 --path . -s tests/pulsator_shots.gd -- <dir>` | the pulsator calm, close, swelling, and glowing in the dark |
| `tests/run.sh 240 --path . -s tests/gear_shots.gd -- <dir>` | charging rack, new items, minimap (surface and facility), headlamp, night vision |
| `tests/run.sh 200 --path . -s tests/new_shots.gd -- <dir>` | siren, husk, visor cracks (first person and on the suit), walkie-talkie, wedged door |
| `tests/run.sh 240 --path . -s tests/vault_shots.gd -- <dir> [THEME]` | the vault door and reader outside, the strongroom from the door, the deposit wall, a pried box, the table and cage, the keycard where it lies |
| `tests/run.sh 200 --path . -s tests/siren_shots.gd -- <dir>` | the siren side on: lurking, walking, creeping, loping; the husk walking with a name tag |

**Workflow that has worked:** make the change → check-only/`check.gd` for parse errors → a targeted shot script, then look at the images → the relevant suite (all of `all.sh` when gameplay code changed) → commit. The owner said not to rerun suites for purely visual changes that don't touch them.

---

## 9. Owner preferences (important)
- **Git identity:** commit and push only as `Demík <velnertomas78@gmail.com>`. **Never** add Co-Authored-By, "Generated with Claude Code" or any other attribution. The repo is already configured with this identity.
- **Prefers big, thorough passes** ("make it really good") with screenshots as proof, then reports issues from their own play sessions with screenshots.
- **You are the continuing developer**, not a consultant: do the work, don't write handoffs unless asked.
- **Always commit finished work to `main` and push it** (`git push origin main`). Work on a branch or worktree if you like, but land it on `main`.
- **Runs the game itself**, now on Windows (`godot --path . -- playground FACTORY` and so on) and plays it with a friend over the internet.
- **Disliked, and fixed:**
  - billboard text, modern-looking fonts, pixel fonts for world text
  - floating or untextured viewmodels
  - flat boxy props, z-fighting, gaps in water and doors
  - gamey sounds
  - lights whose bulbs stay lit while the light flickers
  - parts of animations coming apart

---

## 10. Status and open items
**Working and tested:** the full loop, all 13 monsters, two-floor facilities with cross-floor pathing, all hazards and events, upgrades, terminal, cameras, maps, scanner, pause menu and settings, fullscreen scaling, biomes and weathers.

**Known rough edges and ideas not done yet:**
- The cross-floor pathing has a failsafe: a monster stuck for 3 s while unseen skips ahead to its next waypoint. It fires 0–6 times per test run (`levels.gd` prints where). Places it has shown up: lift-room corners, mezzanine tops, near basement doorways. Worth tightening further.
- Arctic in clear weather is quite hazy, because of the fog density and white fog albedo. Could be lighter.
- Save/continue of a run, a death/end-of-run recap screen, and more crafting uses for scrap were all discussed but not built.
- The playtest bot gets stuck in pits; it was deliberately left as is.
- **Multiplayer (crew) is in.** See the README section. Architecture (`src/net.gd`, the hub at `/root/Net`, survives scene reloads):
  - ENet, host-authoritative. The host runs the monsters, items, hazards, clock and economy. Each client owns only its own player body.
  - Levels are rebuilt from the host's seed on every machine. `main.level_seed` and `level_serial` keep late messages off the wrong level.
  - Entities: `net.register(node, info)` names a node `E<id>`. Spawn messages carry a frame tag (T train, L level, W world) and a local transform. Transforms sync at 15 Hz in chunks. Monster script vars are synced so mirrors animate via `net_visual(delta)`. `ent_event` carries one-offs (die, hitfx, extra, pin, leviathan state).
  - Players send their pose at 30 Hz, measured from the train ("T"), the stop ("L"), the lift cab ("E", so riders stay on the floor of everyone's own cab) or the world. Puppets play back between buffered poses 0.1 s behind (`puppet._sampled`); mirrors likewise 0.13 s behind (`net._buffered`). Puppets turn the head before the body (`NECK`), hang a held lantern from the fist, carry bodies over the shoulder and heavy items against the belly, and show the headlamp (pose[12]). Weapons and the flashlight are held by their grip (working end out of the fist); everything else is held upright facing them, as you see it in your own hands (`puppet._hold_upright`), and anything over 30 cm in both hands in front of the chest. The holding arm follows the look (down is down). In first person, things over 30 cm are held out in both hands at up to 42 cm (they used to shrink to a 16 cm preview). Remote players are `puppet.gd` nodes in group "players" with the fields monsters read. On the host, monster effects on a puppet (hurt, blind, trap, teleport...) go to the owner via `net.to_owner`.
  - Shared state is a 4 Hz snapshot (`main.net_state` / `net_apply_state`). Broadcasts go through `net.event`, handled by `main.net_event`. Client asks go through `net.request`, handled by `main.net_request`.
  - Interactables are keyed by root plus local position in cm (`interact.gd net_key()`). Shared ones run on every peer via the host. Authority side effects are gated by `spawn_item` returning null on clients.
  - Terminal `main.NET_CMDS` run on the host, and the output comes back.
  - Sounds: `Sfx.net_hook` forwards entity sounds and your own player's sounds.
  - Voice (`voice.gd`): mic -> 90 Hz high-pass -> three Butterworth low-passes at 9.6 kHz -> resampled to 24 kHz -> a gate with a 40 ms look-back and a fade -> smooth auto gain (max 4x) -> soft limiter -> 20 ms frames of 16-bit PCM with a sequence number (about 48 KB/s per person talking). Receiving: a jitter buffer per speaker (starts at 60 ms, grows to 160 ms on a bumpy line, shrinks again), frames played in sequence order, lost ones covered with a fade of the last. Playback is an AudioStreamPlayer3D at the puppet's head on the "Voice" bus, which goes straight to Master with a light reverb of its own. Occlusion uses ray-counted walls plus a short navmesh route round corners. Loud talk calls `main.noise`. The tests force open mic (they read the machine's own settings file).
  - Tests: `tests/mp.sh`, `tests/mp_late.sh`, `tests/voice.gd`.
  - Same world everywhere: `main._load_level` seeds the global RNG with the level seed for the whole build. `level._spawn` draws two numbers on every machine (a per-creature "look" seed and a resume seed), so builds stay in step. `Sfx.stream` reseeds after synthesis, so cached and uncached sounds don't shift the sequence. Shared interactables whose results are random (supply crates) decide on the host only.
  - Creature one-offs: `monster.show_act(what, args)` runs `act()` here and on every copy (statue pose, warden swing, mimic twitch, observer flash). Node3D creatures use `ent_event` directly (snatcher "snatch") or a synced var (bear trap `shut`). Copies follow state in `net_visual` (wraith dissolve/reform, haunted lamps and visor frost near you; observer whine; roomba ring; scrapper legs; gloe glow). `die(how)` shares the death animation's randomness.
  - Mob vars are delta-sent (floats at 5 Hz, full resend about once a second). Untyped vars holding a player (`_prey`, `victim`, `friend`) go over as peer ids (`@name`).
  - Effects for a specific player go through player/puppet methods: `say`, `fog_visor`, `ring_ears`, `drain`, `hurt`, `shake`, `move_to`. `hud.msg` sends lines from a shared button to whoever pressed it (`Interact.who_now`).
  - Player actions: `net.act("swing"/"shoot")` drives the puppet's swing and recoil, and the puppet has a muzzle flash. `net.blood` shares blood decals. The puppet holds items by their grip (models point +z), with two-handed shotgun and axe holds, a jump pose, and a small fixed-size name tag.
  - Visual check: `tests/mp_shots.sh <dir>` runs two windows; the client photographs the host's puppet and every creature copy.
- The player has a third-person suit (`player._suit`, render layer `BODY_LAYER`) that only other cameras see: observer photos and the security-camera feeds.
- `docs/subterranauts-research.md` has notes on the original game for any further features.

---

## 11. Windows build (portable, to send to friends)

`export_presets.cfg` has one preset, **"Windows"**: Windows Desktop, x86_64, **`binary_format/embed_pck=false`**: `Downline.exe` (the engine, 110 MB, only changes with Godot) plus `Downline.pck` (the game, about 1 MB). Portable, nothing to install. `tests/`, `docs/`, `build/` and `*.md` are excluded. Output goes to `build/windows/` (`build/` is git-ignored).

**One command:** `tools/export_windows.sh` (Git Bash) stamps the commit into `src/version.gd` (`BUILD` = short hash, `SEQ` = commit count; put back afterwards), exports, boots the exe once headless to catch script errors, and zips exe + pck + `docs/HOW TO PLAY.txt` to `build/Downline-<commit>.zip`. It also writes `build/version.json` (version, seq, base, Godot version, pck URL, sha256, size). `debug` also builds `Downline_debug.exe`. **`tools/export_windows.sh release`** (from a clean, pushed main; needs `gh` logged in) publishes the build as the latest GitHub Release of the public repo `Demiffy/downline`: the pck, version.json and the zip. Never publish without the owner asking.

**Auto-update (`src/updater.gd`, `updater.tscn` is `run/main_scene`):** on launch it loads a pack it downloaded earlier (`user://updates/Downline-<seq>.pck`, listed in `current.json`, sha256 checked) if that's newer than the exe's own, then fetches `releases/latest/download/version.json`; a higher `seq` with the same `base` and Godot version is downloaded to a `.part`, checked against its sha256, renamed and loaded, then `main.tscn` starts. Nothing of the game is loaded before that, so all of it comes from the newest pack. An update **cannot change `project.godot` or the engine**: when you change project settings, bump `BASE` in `version.gd`, and players are told to get the full zip (a Godot upgrade is caught by the version check on its own). Offline or a failed download: the game starts as it is (Esc skips a download). **The intro** (`src/intro.gd`) plays meanwhile: a CRT terminal boots and logs the checks (memory, GPU, mic, then the update check and download as their own lines), then an amber line runs across drawing DOWNLINE (stroke letters) and splits into rails with sleepers; the screen fades into the menu. Full the first time and after an update (`user://updates/intro_seen.txt`), quicker otherwise, any key hurries it, `-- --intro` forces the full one; sounds are synthesised in it. It must not load game scripts (anything the launcher loads stays the exe's version). Godot's boot logo is off (`boot_splash/show_image=false`, soot background). Frames: `tests/intro_shots.gd`. **The title screen** (`lobby.gd`) sits over slow cinematic shots of the checkpoint (`src/title_cam.gd`: four dolly shots relative to the train, handheld sway, a lean toward the mouse, depth of field, dips through dark, a caption naming each), with a dark wash under the menu, letterbox bars, the stroke logo drawn in again (`Intro.draw_logo`), and the menu's lines fading in one by one; starting a shift slides the menu off and flies the camera into the player's eyes (`fly_to`, through dark if the player is far off). The HUD is hidden until then. Frames: `tests/title_shots.gd`. `"dev"` (running from the project), headless and `-- --no-update` skip it all; `-- --update-url=<url>` reads another version.json (testing: serve a pack from `python -m http.server`). The launcher reads `version.gd` uncached, so the game's own `preload` gets the update's. The multiplayer handshake (`net._hello`) refuses a client on a different `BUILD`. (A few friends may still have the first updater, from 2026-10-10: it still fetches new packs from `pck_url` but checks nothing and reports the wrong build in multiplayer, so they should get the zip once.)

1. **Export templates (once, about 1.3 GB):** in the editor, `Editor → Manage Export Templates → Download and Install` (it fetches `Godot_v4.7.2-stable_export_templates.tpz` from the official mirrors). Or download that file from the godotengine/godot GitHub release `4.7.2-stable` and use "Install from File".
2. **Build:**
   ```bash
   godot --headless --path . --export-release "Windows" build/windows/Downline.exe
   ```
   (`mkdir -p build/windows` first if Godot complains about the folder.)
3. **Try it:** run `build/windows/Downline.exe` (keep the pck next to it). Settings and saves go to `%APPDATA%/Godot/app_userdata/Downline/`.
4. **Package for a friend:** zip `Downline.exe` and `Downline.pck` with a short `HOW TO PLAY.txt`:
   - Run Downline.exe and allow it through the firewall (private networks) and the microphone if asked.
   - Type your name, choose **JOIN A CREW** and enter the host's public IP (or `ip:port`).
   - Voice: open mic by default. SETTINGS → AUDIO has push-to-talk on **V**, mic level, voice volume and the open-mic gate.
   - The host chooses **HOST A CREW** and must forward **UDP 24565** on their router to their PC (and allow it through the firewall).
5. **Notes:**
   - `application/modify_resources=false`, so the exe keeps Godot's default icon and version info. That avoids needing rcedit. To brand it, set `application/icon` (a .ico) and turn `modify_resources` on, which needs `rcedit` configured in Editor Settings → Export → Windows.
   - The exe is unsigned, so SmartScreen will say "Windows protected your PC". Friends click **More info → Run anyway**.
   - Both players must run the **same build**. The level is rebuilt from a shared seed, so different code versions will desync.
   - Audio input is enabled in `project.godot` (`audio/driver/enable_input=true`). Proximity voice needs it.
   - Debug build for testing: `--export-debug "Windows" build/windows/Downline_debug.exe`. Set `debug/export_console_wrapper=1` in the preset if you want a console window with logs.

## 12. Look and feel added 2026-10-11

- **Sky and weather** (`src/weather.gd`): a sky shader (drifting cloud by weather, stars at night, the sun disc, dawn gold), weathers OVERCAST/RAIN/STORM besides the old ones; rain and roof drum sounds, drops on the train windows (`A.rain_glass`, the `rain_amount` shader global), lightning in a STORM (host calls strikes: net event `bolt`). Falling weather stops at roofs (a particle height field over the player) and none falls aboard. `tests/sky_shots.gd`.
- **Facility light** (`facility.gd`): failing tubes struggle/die/buzz; ceiling vents with a lamp in the duct (`_grate`, picked by room hash so layouts don't shift); power failure lights a red lamp per room and turning beacons (`hazards.power_fail`). `tests/light_shots.gd`.
- **Water**: `A.puddle` decals and `A.ripple` rings; puddles and leaks in facility rooms (`facility._puddles`, room hash again), visible drips, wakes round anything wading, rain puddles round the train. `tests/water_shots.gd`.
- **Shift report** (`src/report.gd`): the Bureau form with the stamped grade when the quota is met (net event `report`). `tests/report_shot.gd`.
- **Terminal**: CRT glass, power on/off, camera feed REC dot, clock and tearing. `tests/term_shots.gd`.
- **Crew looks** (`Suit.apply_look`, `src/crew_look.gd`): suit/helmet colour, marking, name patch; in settings (`look_*`), sent with the roster (`net._look`, `look_of`), worn by puppets, your own suit and sleeves, and by a husk as whoever it poses as. `tests/look_sheet.gd`.
- **Creatures**: `tests/creature_sheet.gd` shoots every creature from four sides. Siren and warden feet are grounded (no sinking), wraith rags clear the floor.
- **Checkpoint life** (`src/yard_life.gd`): the clerk at the shop window (stamps when you shop), the gantry crane carrying bales, freight trains on a far line. `tests/yard_shots.gd`.
- **Crew car** (`train.gd`): sage riveted walls over varnished panelling, checker lino with a runner, a perforated headliner on brass ribs, luggage racks, notices; a steel office desk with monitors, a swivel chair; the control stand is a painted console (cream gauges, lamps, labelled switches, radio handset) with the levers on their own quadrant stand. `tests/train_shots.gd`.
- **The checkpoint as a whole works** (`src/checkpoint.gd`; moving parts in `yard_life.gd`): a 350 x 280 m basin ringed by banded cliffs, the main line and a far through line leaving by tunnel portals; the Bureau's office with clock tower and mast, a container terminal under a gantry crane, the scrap works (crusher, conveyor, stacks), a classification yard with repair shed and signal gantries, a fuel depot, a transformer yard, floodlights. Workers, lorries, forklifts, a shunter and the crane all move. The cliffs are `_crag`s: stacked faceted strata stretched along the wall (no collision; invisible walls keep you in). Tunnel mouths (`_portal`): an arched concrete headwall with voussoirs, wing walls, a lined ribbed bore going dark, set into crags. The yard sidings leave the main line by a ladder (`LADDER_A/B`, `_track_seg`) and end at buffer stops (`_buffer`); the core siding joins the main line too. Pavement heights never coincide (ballast 0.03, lots 0.05, core pads 0.06, roads 0.08). Lorries (`truck`) are detailed cab-overs; the fuel line runs from a pump house and filler crane to a valve pit. `P.scrap_heap` is junk over a dark mulch core with an apron of wreckage down its slopes (draws one number from the caller's rng). `Merge`: chunks wider than 70 m are never distance-culled (they were measured from their middle and vanished underfoot). `tests/cp_shots.gd` (aerials, ground views incl. `ground_fuel`, `ground_rim`, the tunnels, the car's interior).
