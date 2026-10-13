# DOWNLINE: Handoff

Everything someone needs to pick this project up cold: what the game is, how to run it, how the code is put together, every system, the tools, the conventions, and what is still open.

- **Engine:** Godot 4.7.2 (Forward+ renderer, Jolt physics), GDScript only.
- **Assets:** none. Every mesh, texture, sound and font render is generated at runtime from code.
- **Size:** about 38,500 lines in `src/` (70 scripts) and about 10,700 in `tests/` (85 scripts and 7 shell runners).
- **Last brought up to date:** 2026-10-12.
- **Git:** https://github.com/Demiffy/downline (private), branch `main`. Everything is pushed, this file included. Clone it and carry on.
- **Platform:** developed on macOS (Apple M5, Metal) until 2026-10-08. Development continues on the owner's Windows PC (see §2 for Windows setup, §11 for the Windows build).
- **Name:** DOWNLINE (renamed from "Subterra Clone"; the folder on the Mac was `subterra-clone`).
- **Players' guide:** `README.md` (with screenshots in `docs/images/`) and `docs/HOW TO PLAY.txt` (shipped in the zips). This file is for whoever works on the code.

## Contents

1. [What the game is](#1-what-the-game-is)
2. [Running it](#2-running-it): setup on Windows, controls, the playground
3. [The game loop](#3-the-game-loop): stations, death and fees, the checkpoint, the quota, the shredder's diverter, shop and upgrades, terminal commands
4. [Code map](#4-code-map-src): every script, and the monsters
5. [Systems in detail](#5-systems-in-detail): saving, the shredder, the line, facilities, hazards, surface, train, rendering, sound, held items
6. [Content highlights](#6-content-highlights-visual)
7. [Conventions and gotchas](#7-conventions-and-gotchas)
8. [Tests and visual tools](#8-tests-and-visual-tools)
9. [Owner preferences](#9-owner-preferences-important) (read this)
10. [Multiplayer architecture](#10-multiplayer-architecture)
11. [Windows and macOS builds, auto-update, releasing](#11-windows-and-macos-builds-portable-to-send-to-friends)
12. [Recent changes](#12-recent-changes)
13. [Status, rough edges and ideas](#13-status-rough-edges-and-ideas)
14. [Working from a cloud session](#14-working-from-a-cloud-session-linux-container)

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

**Playground** (`-- playground [THEME]`; from PowerShell `& "C:\Users\velne\bin\godot.exe" --path . -- playground LAB`). Styled like the pause menu (it borrows `menu._theme()`). A slim status strip under the quota shows the place, creature count, clock and which toggles are on (H hides it). TAB opens the tool panel on the right, five tabs, every hotkey also a button (F-keys need Fn on a Mac):
- **CREATURES:** spawn any of the 15 at the crosshair (siren and husk included), a body that gets up as a husk in 3 s, a body that stays down, freeze (F2: held every frame, so whatever spawns later, or lives outside the level node, freezes too), state labels (F3), clear (F4), a noise at the crosshair (F8; N stays night vision).
- **ITEMS:** every piece of gear (wedge and walkie included), random / valuable / heavy scrap (J for random; G is the emote wheel), a photograph.
- **PLAYER:** god mode (F1: sets `player.god`, and `hurt()`/`die()` ignore everything while it's on; topping your health up alone let a 200-damage hit through), noclip (F7), heal, take 25 (turns god mode off, to see the visor crack), recharge everything, +500 credits, headlamp + night vision, back to the lift.
- **WORLD:** fullbright (B), path gizmos (P), slow motion (F6), day/night (F5), up/down (F9), to the breaker, **checkpoint** (builds it with scrap in the shredder's hopper and you at the lever) and back to the station, the events (power failure, reset breaker, tremor, airdrop, airdrop with the plane crashing), rebuild as any theme (F10 cycles).
- **SITES:** rebuild the surface as any biome, with any landmark, or as the dam stop; jump to the landmark, the dam's basin, stairs, crest and windings; open the sluices; the records room door and its chalked code, the twin-key door and a lever; the site's day (burst a main, lockdown on/off, the lift fault, a director scare, the clock to 12/18/20/23:00); and a trip to the next stop with any line event forced (`_ride`). PLAYER has every emote as a button. `tests/playground_sites.gd -- playground` presses them all.
- Screenshots: `tests/run.sh 300 --path . -s tests/playground_shots.gd -- <dir> playground LAB`.

---

## 3. The game loop

1. **Checkpoint.** The terminal is at the front of the crew car. `LEAVE_CHECKPOINT` issues an assignment with a quota and opens the gate.
2. **Route.** `MAP` shows 3 stages of 2–3 station choices each. `VIEW_STATION <letter>` lists facility, size, surface biome, weather (needs WEATHERVANE), hazards and the monsters you'll likely meet. `ROUTE_TO <letter>` departs and the train runs the line to it (§5 "The line"): about 40 seconds, out of the valley, through a tunnel, into the next station.
3. **Station.**
   - Day runs 08:00 → 24:00 over 720 real seconds, with one warning two hours before departure (`main.depart_hour()`: 24:00, or 01:00 with OVERTIME_PERMIT). There is no clock on the HUD or in the pause menu (the owner's call): the train's clocks and the terminal tell the time.
   - **Minimap** (MINIMAP upgrade, `main.draw_minimap`): underground only. The plan of both floors is built once per site (`_mm_build`) and drawn with one transform, at 20 Hz. It shows scrap and creatures only where the scanner found them (`main.scanned`, filled in `scan()`; creature marks fade over 20 s), crewmates as a ping every 5 s, and no remains marker. The terminal site map follows the same rule.
   - **Spawning:** no creature spawns within 25 m of the train or 20 m of a player (`level._spawn` moves it out of sight or drops it); surface pulsators only ≥40 m from everyone, out of sight (`_surface_hidden`). Host-only spot picking uses its own RNG (`_spot_rng`) so a crewmate's build stays in step.
   - Follow the ELEVATOR signposts from the station house to the lift headframe and ride down 60 m into the facility.
   - Scrap goes **inside the train** to count.
   - The train leaves at 24:00. Stepping off while it's moving leaves you standing on whatever's there (the stop, or the line's ground, which carries you off as it goes); get back aboard before the train is 40 m away or you're "LEFT BEHIND" (`main._left_behind`). Missing the departure works the same way: you can still run for it. Hopping off as it runs into the platform (`_arriving`) is harmless.
   - **Death doesn't end the run** (`main._on_died`): a replacement wakes aboard at the same stop, +1 h. **The Bureau charges for it** (`main.died_world`, host): `replacement_fee()` is 40 cr, +20 for each death already this assignment, capped at 140, docked from the crew's credits even into debt (credits go negative: the visor and readout say IN DEBT, BUY refuses, the shredder's takings pay it off). `fees` totals them for the shift report. **A whole crew lost** (2+ players, every one dead within 12 s, `_down`): `_recall()` sets the clock to 30 minutes before departure. Cargo aboard is never touched (the owner asked: no impound). A REMAINS ragdoll (heavy, scan target) lies where you fell with what you held scattered round it; bringing it aboard pays `RECOVERY_PAY` (20 cr, `_check_remains`). The dead player's puppet is hidden (`puppet.set_pose`): the ragdoll is the only body. **LEFT BEHIND** (`main._write_off`) sends you to the next stop and writes off only the scrap you were carrying. Game over only comes from ramming the gate.
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
   - **The quota** (`main.quota_units(n, crew, roll)`): `(3 + 3n + 0.6n²) × (1 + 0.35 per extra crewmate) × 0.6–1.4` per resource (7 / 17 / 33 units at assignments 1 / 3 / 5 solo). `crew_size` is taken when the assignment is issued.
   - Throw scrap into the **shredder** hopper and throw the MAIN DRIVE lever. Credits are paid at the day's prices, item by item as it chews (`shredder.gd`, see §5).
   - **The diverter and the bonded stock:** a two-way rotary switch (yellow handle, SELL green / BANK amber lamps) on the pedestal's hopper side (`shredder._diverter`, `set_divert`; host `main.toggle_divert`, synced as `divert`). On BANK, `shred_item` fills what the quota still needs (paid as usual) and puts every unit past it into `main.bank` unpaid. The stock is kept between assignments and saved; terminal `STOCK` lists it, `STOCK SELL <res|ALL>` sells at today's price, `STOCK SUBMIT <res|ALL>` puts it toward this checkpoint's quota (unpaid; only what's still short) and goes through `_after_submit` (rank, gate). Payload rank counts everything at today's prices, banked or sold (`_cycle_value`). In the hall the **bonded store** (`level._bonded_store`, the west wall by the door): a mesh cage of four bays under enamel plates, one per resource, `show_stock` stacking a bale per 4 units (up to 6 a bay, `_stock_bale`: pressed layers, junk of its kind, steel bands, a tag; own RNG so it never touches the build's). The readout shows the diverter and the stock (`_board_text`).
   - **Payload rank** compares what you shredded against the quota's value: B ≥ 1.0×, A ≥ 1.5×, S ≥ 2.0×, each with a one-off bonus (30 / 80 / 150 cr).
   - Quota met: the gate opens. Leaving without it: the train rams the gate, game over.
5. **Game over** shows run stats. The best run is saved to `user://best_run.json`.

**Shop and upgrades:**
- **Shop:** the shop container at the checkpoint, or the terminal (`SHOP`, `BUY <item> [n]` with prefix completion).
  - Items: FLASHLIGHT 35, LANTERN 55, SCANNER 90, BACKPACK 80, CROWBAR 45, FIRE_AXE 85, SHOTGUN 240, MEDKIT 40, FLARE 15, NOISEMAKER 25, ADRENALINE 35, DOOR_WEDGE 20, WALKIE 50.
  - **Door wedge:** click a shut swing door to jam it (`main.wedge_door`, request/event "wedge"). Creatures can't shove it; they bash at it and the host breaks the wedge after about 10 s (`door._bash`). E pulls it out and gives it back. The stuck failsafe never skips a creature past a wedged door (`monster._wedged_between`).
  - **Walkie-talkie:** while held and charged, your voice frames carry flag 1 (radio, `voice.packet` header is [seq u16][flags u8]) and drain its battery. Anyone carrying a charged walkie hears it at any range on the "Radio" bus: band-limited, overdriven, hissing, with a squelch on key-up and release (`voice._radio_push`). HUD shows RADIO / ON AIR.
  - **Helmet damage:** `player.crack_tier` (hp below 75/45/20 → 1/2/3) holds until you're back to full. `cracks.gd` draws each tier once (on a worker thread at start, `Cracks.warm`, which takes several seconds: `hud._exit_tree` waits for it with `Cracks.finish`, since quitting with that thread still drawing crashed the game) as a 1024 px mask: R holds the cracks (anti-aliased, nearly straight radial cracks thinning outward, rings of web round each strike, a star of short cracks and chips at it), G the frosted crushed glass round each strike. Your own view (`hud.visor_cracks`, `Cracks.overlay()`) is a screen shader: the view bends where the glass is broken, frosted glass blurs and whitens, colour fringes at the cracks, and a crack catches the light only in places (more where the scene behind is bright). It fades in over 0.12 s and stays square at any aspect ratio. A crewmate's visor (`Suit.set_cracks`, `Cracks.visor_material`, pose[13]) uses the same mask projected onto the visor window, glinting. A glass-crack sound plays per new tier. Shots: `tests/crack_shots.gd -- <dir> playground`.
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

Line counts as of 2026-10-12. The scene files are `main.tscn` (the game) and `updater.tscn` (the launcher, `run/main_scene`).

**The game and its state**

| File | Lines | What it does |
|---|---|---|
| `main.gd` | 2245 | The game: state, day clock, travel and stepping off, the shredder's payouts, payload rank and the economy (fees, quota, diverter, bonded stock), every terminal command, environment, fog and sky per biome and weather, ambience and reverb space, noise propagation, scanning, site map and minimap, game over, settings, net state. |
| `data.gd` | 345 | **All content:** scrap items (resources, size, heavy/rare), tools and their prices, upgrades, creature drops, lore logs, the shop, facility themes, `HABITAT`, the field guide, `SITE_HAZARDS`, weathers, `pace()` (test speed-up). |
| `save.gd` | 253 | Saving and continuing a run (§5). |
| `settings.gd` | 182 | Player settings in `user://settings.cfg` (static: anything can read them). |
| `mark.gd` | 45 | The game's mark (two amber chevrons going down over the hazard stripe, `docs/images/mark.svg`) as SVG text; `apply()` makes it the window's and dock's icon (called by `updater.gd` and `main.gd`). The glow is wide faint strokes under a crisp one: Godot's SVG renderer blurs a filtered line away. |
| `version.gd` | 12 | The build stamp (`BUILD`, `SEQ`, `BASE`) that `tools/export.sh` writes for an export. |

**Places**

| File | Lines | What it does |
|---|---|---|
| `level.gd` | 1280 | One stop: a station's surface (terrain, houses, sheds, signposts, scenery, arctic dressing), the lift and the facility, spawns and the spawn director, hazards; or the checkpoint's core (the reclamation hall, the shredder, the bonded store). Built in slices ahead of the train. |
| `station.gd` | 654 | A station's platform, canopy, booking office, forecourt, signal box and water crane. |
| `checkpoint.gd` | 1062 | The checkpoint as a whole works: the basin and its cliffs, tunnel portals, the Bureau's office, container terminal, scrap works, classification yard, fuel depot, engines and wagons. |
| `yard_life.gd` | 651 | The checkpoint going about its business: the clerk, workers, lorries, forklifts, the shunter, the gantry crane, freights on the far line. |
| `line.gd` | 1317 | The line between stops and the trip along it (§5 "The line"). |
| `line_events.gd` | 587 | What happens on a trip: the other train, the halt, a power failure in the tunnel, the thing at the window, weather fronts. |
| `facility.gd` | 2265 | The procedural facility (§5): layout, room kinds and dressing, both floors, the vault, doors and bulkheads, lights, cameras, navmesh and the room graph. |
| `halls.gd` | 1006 | Big rooms (2x1, L, 2x2) and their set pieces per theme. |
| `hazards.gd` | 1390 | Flooded and gassed rooms, steam lines, live cables, the main breaker; power failure, tremor and airdrop events. |
| `footprints.gd` | 105 | Boot prints in sand, snow and mud, fading; pooled decals. |
| `grass.gd` | 239 | Grass you walk through: instanced clumps of blades carpeting the forest and swamp, swaying in the wind and pushed aside by whoever walks through. |
| `airdrop.gd` | 845 | An airdrop start to finish: the cargo plane, the crate out of the door under its canopy, landing, collapse, flare, prying it open; now and then the plane burning and crashing far off. |
| `elevator.gd` | 503 | The mine-shaft lift: headframe, cab, landings, panel; carries riders and cargo. |
| `shredder.gd` | 1091 | The checkpoint shredder, its control desk and CRT, and its cycle (§5). |
| `weather.gd` | 235 | The sky shader, rain and snow, the roof drum, lightning. |

**The train**

| File | Lines | What it does |
|---|---|---|
| `train.gd` | 1839 | The locomotive, crew car, flatcar and storage car; the control stand and gauges, clocks, CRT screens, charger, doors, the delivery handcar; engine, horn, compressor and rail sounds. |
| `winch_truck.gd` | 194 | The LIFT_MOTOR upgrade's winch truck by the headframe. |

**The player and the crew**

| File | Lines | What it does |
|---|---|---|
| `player.gd` | 1041 | First-person controller: stamina, crouch, heavy carry, wading, footsteps, the lights, inventory, attacks, fear audio. |
| `viewmodel.gd` | 523 | The first-person sleeve, glove and held items. |
| `suit.gd` | 1108 | The employee's body (11 jointed parts) in smooth surfaces, its eleven look options, armour, goggles and visor cracks. |
| `suit_mesh.gd` | 306 | Smooth surfaces for the suit: grids, lofted trunks and limbs, lathes, tubes, slabs that lie on another surface, rounded boxes; cached. |
| `body_anim.gd` | How a crew body moves, for crewmates (`puppet.anim`) and your own suit (`player.anim`): a gait cycle run on distance (no skating), knees folding through the swing, a dip at each strike, hip sway and twist, lean into speed and acceleration, backwards and sideways stepping, breathing and weight shifts standing, shuffles when turning on the spot, a tuck in the air and a landing dip. Emotes: `SOCIAL` (the wheel's inner ring: WAVE, POINT, BECKON, THUMBS UP, SALUTE, SHRUG, CLAP with a sound, CHEER, BOW, FACEPALM) and `FUN` (the outer ring: DANCE, ROBOT, CHICKEN, AIR GUITAR, HEADBANG, FLEX, LAUGH, JUMPING JACKS, PUSH-UPS, SPIN, SIT, LIE DOWN); `WHOLE` ones end when it moves off; `body_rot` tips the whole body (push-ups, lying, spinning). `_on_ground` keeps every part out of the floor (soles, knees, seat, hands, helmet) and sets whole-body emotes down onto it. `tests/anim_shots.gd -- <dir> [move ...]` makes a contact sheet of each. |
| `emote_wheel.gd` | Hold G (action `emote`, rebindable), push the mouse to one, let go. `player.emote(name)` plays it and sends `net.act("emote", name)`; the view swings out in front of you (`player.emote_cam`, mouse orbits it, never through walls) and back when it ends. |
| `puppet.gd` | 567 | A crewmate as you see them, played back from their poses. |
| `ragdoll.gd` | 127 | Your remains as a ragdoll that still acts like a pickup. |
| `crew_look.gd` | 256 | The crew-look editor on the title screen. |
| `hud.gd` | 547 | The helmet-visor HUD: quota, HP ring, battery, feed, alerts, scan list, visor fog, minimap, night vision. |
| `cracks.gd` | 85 | Procedural visor-crack textures. |
| `blood.gd` | 69 | Blood splats and drip trails. |
| `scanfx.gd` | 259 | The scanner pulse, through-wall glow, lock-on rings and tags. |

**Things in the world**

| File | Lines | What it does |
|---|---|---|
| `pickup.gd` | 218 | A physical item: impact sounds, noise, charge, `extra`, the fall guard. |
| `items.gd` | 1019 | A hand-built model for every item. |
| `interact.gd` | 66 | Anything you press E on; shared through the host in a crew. |
| `door.gd` | 181 | Double swing doors with wired-glass windows; wedges. |
| `genset.gd` | 182 | The generator's moving engine. |
| `pumpjack.gd` | 99 | The pumpjack's moving linkage. |
| `blast.gd` | 254 | Explosions as everyone sees them. |

**Building blocks**

| File | Lines | What it does |
|---|---|---|
| `art.gd` | 1322 | Procedural textures and the material cache, primitives (box, cyl, sphere, seg, ring, prism), lamps, houses, trees, CRTs and more. |
| `props.gd` | 1810 | The prop kit: furniture, machines, sheds, rocks, fences, containers, vehicles, floodlight towers and more. |
| `build.gd` | 134 | Basic boxes, interactables, labels, displays, omni lights with distance fade. |
| `paint.gd` | 157 | Weathered world text from system fonts (stencil, plate, type, chalk). |
| `merge.gd` | 214 | Bakes static geometry into one surface per chunk (§5 "Rendering"). |
| `sfx.gd` | 1485 | Every sound, synthesized; buses, reverb, footsteps, creature voices. |

**Creatures**

| File | Lines | What it does |
|---|---|---|
| `monster.gd` | 507 | The shared base: pathing (`walk_to`), sight, being looked at, the stuck failsafe, presence sounds, hits and deaths, syncing. |
| `roomba.gd`, `pulsator.gd`, `statue.gd`, `marionette.gd`, `mimic.gd`, `warden.gd`, `leviathan.gd`, `snatcher.gd`, `bear_trap.gd`, `scrapper.gd`, `gloe.gd`, `observer.gd`, `wraith.gd`, `siren.gd`, `husk.gd` | 3705 in all | One file each (table below). |

**Screens, network and launch**

| File | Lines | What it does |
|---|---|---|
| `terminal.gd` | 633 | The amber CRT terminal UI, command parsing and completion, camera and map feeds. |
| `menu.gd` | 538 | The Esc pause menu (Bureau console style), the photo album. |
| `settings_ui.gd` | 561 | The settings screen (game, controls with rebinding, video, audio with a live mic meter, accessibility). |
| `report.gd` | 307 | The shift report form, typed and stamped. |
| `lobby.gd` | 513 | The title screen and crew lobby. |
| `title_cam.gd` | 112 | The title screen's dolly shots round the checkpoint. |
| `intro.gd` | 495 | The CRT boot and the DOWNLINE logo played while the launcher checks for updates. |
| `updater.gd` | 263 | The launcher: loads or downloads the newest pack, then starts the game (§11). |
| `net.gd` | 1065 | Multiplayer (§10). |
| `voice.gd` | 669 | Proximity voice and the walkie-talkie (§10). |
| `playground.gd` | 634 | The debug playground (§2). |
| `pathdebug.gd` | 128 | Path gizmos for the playground. |

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
- Rebuilt 2026-10-12 in Bureau green (`GREEN`) over riveted plate. A heavy cutting chamber on a concrete plinth with a feed step along the front (grating, yellow nosing); stiffener ribs, a foot flange and a top flange bolted round; bearing housings out of both flanks (a round cap per shaft with its bolt ring, grease lines up to a brass manifold). The hopper rises off it: a raked front plate up to the lip (`LIP_Y` 1.88, you feed over it from the step), cheek plates (`_plate`, drawn as quads; `_block` adds invisible walls) climbing to a tall back plate (`BACK_Y` 3.05) under a dust hood with the SHREDDER enamel sign on its brow, a caged lamp under it, the beacon and the klaxon on its roof, and a flanged duct with a damper out through the roof lantern. Inside: wear liners raked down onto two shafts of hooked cutter discs (6 teeth each, spacer collars) turning into each other at different speeds (0.78x), stripper combs between the discs, a rubber flap curtain behind the lip; what's thrown in rests in the teeth on an unseen floor at the shafts' middle (`SHAFT_Y`). Behind: the gearbox (ribs, couplings into the chamber, inspection cover, oil sight glass, the B.R.M. plate), the motor lying on its stool on top (finned, fan cowl and grille, terminal box and conduit), the V-belt down the side from its small pulley to the big spoked one, in a yellow mesh guard. A discharge conveyor (channel frame, skirt boards, head and tail drums, idlers, moving cleats, trestle legs) from a chute in the flank up into a tapered roll-off skip (`_skip`: skids, ribs, lifting lugs, heaped with shred).
- The control desk (`_controls`, `DESK`): a riveted steel cabinet with louvred doors; a sloped desk with the ammeter (chrome bezel, needle on the load), POWER/RUN/OVERLOAD pilot lamps, the emergency stop (decor), the DIVERTER (`_diverter`: a brass escutcheon, a yellow cam-switch handle turning about the desk's normal between SELL and BANK, a lamp each); the MAIN DRIVE lever on its ratchet quadrant at the end nearest the machine (ratchets down, clunks, springs back up when the cycle ends); a low instrument back with the brass plate, and the readout on a big industrial CRT (`_crt(parent, at, size)`, built at 1.6x: a steel case with its tube tapering back, on a tilting yoke, turned down to the desk; `board` is a fat-pixel mono Label3D anchored top left on dark amber phosphor with scanlines and a rolling bar `_roll`). No glass over the tube: `A.glass()` read as a milky oval with light spots. Shots: `tests/shredder_shots.gd -- <dir> [view ...]`.
- A cycle (`run`, host): klaxon, beacon, motor spools up (`shred_motor` loop pitched by speed); each item in the hopper (light first, heavy last) is frozen, dragged down to the nip, then shudders and sinks into the teeth while it's chewed (`shred_metal` with sparks for metal-heavy items, `shred_soft` otherwise, dust, a camera shake nearby, shafts slow under load). Heavy items jam it first: the drive stalls, OVERLOAD lights, it reverses, then goes at it again. `main.shred_item` pays each item as it goes (the readout shows SHREDDING +N CR), `main.shred_done` sums up, ranks the payload and opens the gate. The shreds ride the belt and pile up in the skip (just for show, local, capped at 70). Anyone in the throat while it turns takes 30 and is thrown clear.
- Everyone sees it through `net.event("shredder", [...])` (start / jam / chew / paid / stop); only the host moves items and pays. An empty hopper runs it up and down again (`dry_run`).
- Static parts are built straight into the level (so they merge); `shredder.gd` keeps only the moving parts.

### The line (`line.gd`)
- The train never moves: the line, the stop it's leaving and the stop it's making for slide past along -x. `line.s` is how far the train has come; everything is built in 48 m chunks (`AHEAD` 700 m in front, freed `BEHIND` 520 m back), one chunk a frame, each from its own dice (seeded by its stop's level seed and the run's odometer, so a crew sees the same line). After arriving, everything moves back so the stop is at x = 0 (`_rebase`).
- Every station sits in the same kind of valley: `tunnel ] approach [ station ±100 m ] departure [ tunnel`. Segments (`_segs`): "open" (track, telegraph poles carrying on from the station's at 36 m, signals, W boards, a station board, kilometre posts, maybe a level crossing with flashing lamps and a bell or a passing loop with a freight standing in it, scenery thinning out to the skyline), "tunnel" (portals from `checkpoint._portal` set in a cutting into a mountain, crags up its sides, a lined bore with ribs, white refuge niches, cables and caged lamps), "station" (the wings beside a station's own ground). `height()` is dunes, far hills, now-and-then banks and cuttings, mountains over the tunnels, blended into each station's own `ground_y` round it. The ground uses its own shader (`GROUND`): sand or snow on the flat, rock where it steepens.
- A trip (`ride`): brakes off, the slack clanks down the train, it pulls away (`ACCEL`), cruises at `SPEED` (30 m/s), horns at the whistle boards, into the tunnel. The smoke in a bore hides both ends (`line.dark` thickens the fog, kills the sky light and turns the headlight up in `_update_env`); `SWAP_IN` (15 m in) `main._journey_build` frees the old stop and makes the prebuilt next one current (see "No loading hitch" below: nothing stalls). Out into the early morning (the clock runs from 06:51 to 08:00 along the approach), past the distant and home signals (they drop to red behind the train), brakes (`BRAKE`), a squeal, a stand and a blow-down. The checkpoint's own bores lead straight into the line's tunnels (their dark plugs are in group `bore_plug`).
- Each stop's invisible end walls (group `across_line`) cross the track: they're off while the train runs through them (`_gates`), or they'd sweep everyone off it.
- **No loading hitch:** the next stop is built *ahead*, hidden and far down the line, from the moment the train pulls out (`main._prebuild` -> `level.build_geometry(..., sliced)`): a few milliseconds a frame (`level._slice`, 5 ms budget), the mesh merging on a worker thread (`Merge.bake(..., mark)`: the vertex arithmetic runs in `WorkerThreadPool`, the originals are freed in batches). It's named "LevelNext" (interactables key it as "L") and nothing is spawned. In the tunnel (`SWAP_IN`, 15 m in) `main._journey_build` makes it the current stop and `level.populate(sliced)` adds the loot, creatures and hazards (those go to the crew), a slice a frame. The line's chunks are built the same way (`line._build_chunk(k, _mark)`, 4 ms). Determinism: every slice point reseeds the global dice from the seed and the point's name (`seed(hash([seed, tag]))`), so a stop built in one go (a save, a crewmate joining: `_load_level` sync) is the same one. Builds share `A.snow_cover`: each builder puts its own value back after every pause. If a slow machine isn't done 110 m before the tunnel's end it finishes in one go there (`_hurry`, `level._sliced = false`); the train never slows for it. A trip doesn't end before the stop's built.
- **Timings:** `SPEED` 30 m/s, `ACCEL` 2.2, `BRAKE` 2.1, `LEG` 180 m, `TUNNEL` 210 m: about 40 s a trip.
- **The ground's edges:** the line's ground is kept to `KEEP` (720 m) behind the train, and once the far side of the first tunnel is no longer the checkpoint yard (`_first_x`, `MARGIN` 200 m) it's built that far past the far portal, so the mountain over a tunnel comes down on the far side too (it used to stop at full height there and hang in the sky as a sheet: the "floating ribbons"). Every chunk's ground also drops rock skirts from its edges to below the valley floor (`_terrain`). The two end skirts are meshes of their own (meta `ends`), shown only while no chunk is built on past them (`_skirts`, every frame): between chunks they stood under the ground as a wall per chunk, there for anyone who got below it.
- `settle(level)` lays the whole valley at once for a stop built any other way (start of a run, a saved run, a crewmate joining, the playground).
- Shots: `tests/journey_shots.gd -- <dir> [DESERT|ARCTIC] [DESERT|ARCTIC] [hour]` rides two trips in real time and photographs them.
- **Two lines.** A second, wholly separate track runs beside ours at `OTHER_Z` (-21 m, `level.OTHER_Z` too): along every open segment, through every station (`level._rails`, not at the checkpoint), into its own twin portal (`checkpoint._portal(..., twin)` leaves off the wing walls and crags between the pair). `height()` levels the ground along both lines; scenery, houses and big rocks keep off it. A freight sometimes stands on it on the approach (`_standing`, engine ticking over).
- **Line events (`line_events.gd`, `line.events`):** planned per trip from the stop's seed in `ride()` (`events.plan`), ticked each frame, cleared at the end. Force them with Engine meta `force_events` (`halt`, `freight`, `power`, `thing`, `squall`). None are dangerous; they're things that happen on the way.
  - *The other train* (35%, leaving a station): a road switcher and 7-10 wagons come out of the other line's portal in the first leg at 13 m/s, horn twice (ditch lights flashing), clatter past with a swish and a shake, smoke off the stack (unshaded puffs tinted by the haze and the hour).
  - *A halt we don't stop at* (40%): a dead platform (`line._halt`) with a crooked name board, drifts, a flickering lamp and a figure in a suit who turns his head after the train and is gone when you look back.
  - *Power fails in the tunnel* (22%): `train.set_power(false/true)`. Lamps flicker out, the screens, clock and charger lamps die, red emergency lamps glow; back on near the far end.
  - *The thing in the tunnel* (14%): early in the bore something near black comes up from behind on the side the local camera is on, takes the window nearest it (`_twin`, train.gd's side windows) and paces the train there for 3 s, head raised to the glass (the car floor is 1 m up, so the windows are 2-3 m off the rails) and turned in: all you really see is two red eyes. Then it drops back. Each client places it by its own camera. It's a follower: `main.followers` spawns that many Sirens at the next stop.
  - *Weather moving through*: running out of a storm in the first leg, into one in the second, or a squall after the tunnel. `main.line_weather`/`line_mix` blend the environment (`main.weather_now()`); the front itself is 14 ellipsoid `FogVolume`s with a billowing `NoiseTexture3D` density, glowing like the storm's own haze (0.4x its colour times daylight: dimmer and a front this dense reads as a black wall), and `volumetric_fog_length` goes out to 240 m while one is near.

### Ride stutters (2026-10-13)
- A stop built on the way is sliced (`level._slice` 5 ms, `line._slice` 4 ms). The pieces that ran unsliced and caused the 80–280 ms freezes while cruising:
  - `Merge.bake` generating every primitive on the main thread before its worker thread (now 150 a slice);
  - the old stop freed in one frame at the swap (`line._free_slowly`: hidden, then 250 nodes a frame, deepest first);
  - the terrain working out every height four times (once now, sliced);
  - `Station.build` (takes `mark`);
  - a big hall dressed whole (`Halls.dress` awaits `fac._m` a cell at a time);
  - the navmesh bake (`bake_from_source_geometry_data_async` when `_sliced`; a stop built at once still finishes inside `build`, which `tests/levels.gd` relies on);
  - forest dressing and item spawns (sliced more often).
- New pauses use tagged slices (they reseed), so every machine still builds the same stop.
- Worst cruising frames went from 80–280 ms to 50–80 ms. The smaller 40 ms ones (about 8 a trip) remain: heavy scenes of around 1,800 draw calls plus the line's own work.
- `tests/trip_hitches.gd` measures it; the run-to-run noise is large, so compare several runs.

### Particles: two traps (fixed 2026-10-13)
- A material with `billboard_mode = BILLBOARD_PARTICLES` ignores each particle's scale unless `billboard_keep_scale = true`: every puff drew at its mesh's size. Every particle material in the game sets it now; set it on any new one.
- A `Curve` clamps its points to 0..1 unless `max_value` is raised first, so a scale curve growing 0.4 to 2.5 stopped at 1. Every scale curve sets `max_value` now.
- The dam's mist and spray draw over the falling sheet (`render_priority` 2): transparent things are sorted by the centre of their bounds, and the sheet's huge bounds put it in front.
- With both fixed, explosions swell into a fireball and spread as smoke, steam bursts fill a corridor, the dam's spray is fine droplets (it was 1 m blobs) and its mist rolls in big faint clouds, and exhaust and smoke grow as they rise.

### Surface biomes (`data.gd` BIOMES, `biomes.gd`)
- Five: DESERT 38, ARCTIC 20, FOREST 15, SWAMP 14, CITY 13 (the `chance` weights; `main._pick_biome`). Each entry gives the ground and rock texture kinds, rock tint, haze, sky and sun colours, extra fog, the footstep off open ground (`main.surface_at`), what a STORM/SANDSTORM roll becomes there, whether rain falls, and a description (`VIEW_STATION` shows it). `main._update_env` reads haze/sky/sun/fog from it; `line_events` squalls follow it.
- `level._surface_build` lays the shared stop (terrain, track, station, houses, the lift pad, signposts), then DESERT/ARCTIC dress as before and the rest go to `level._dress(bio)` (scenery points from `_dress_point`, off the way to the lift: `_off_trail`). `ground_y` shapes each: the swamp sits low (hollows below `Biomes.WATER` fill from one big water sheet; the way to the lift is held just above it for the boardwalk), the town is near flat and level under its streets (`STREETS_Z`, `_city_cx`, `_on_street`, decided before the houses), the forest a little hillier.
- **Forest:** oaks (`Biomes.oak`: tapering bark trunk, root flare, limbs, a crown of `foliage` clumps; some dead), birches, spruce, ferns, bushes, fallen logs with root plates and fungus, stumps, mossy boulders; wooded ridges on the skyline (`tree_ridge`). New textures `moss`, `bark`, `foliage`; footstep `step_grass`.
- **Swamp:** `water_y` = `Biomes.WATER` (footsteps splash below it); buttressed cypress with knees and hanging moss, reeds and cattails at the water's edge, a boardwalk on posts from the station to the lift (`_boards`, `on_boards` makes footsteps wood), shacks on stilts, a sunk rowboat, lily pads and scum. Texture `mud`, footstep `step_mud`.
- **City:** cracked streets with kerbs, pavements and worn centre lines; ruined blocks (`ruin_block`: storeys of brick or concrete with the windows out, boards, sills and floor bands, slabs fallen in, a broken top with rebar, rubble, a faded shop sign), streetlamps, traffic lights, a bus, rubble heaps, billboards, wrecks; tower blocks on the skyline (`tower`). Texture `rubble`.
- **Grass** (`grass.gd`): forest meadow grass (short, 6 blades a clump), swamp sedge (taller, darker), desert `dry` tufts (stiff, bleached, splayed; 0.7/m²), arctic `frost` stalks (dead straw through the snow; 1.1/m²) and city `weeds` (dark broad blades, off the streets: `_on_street` 4.2 m; 0.7/m²), on the stops and beside the line (the line's grass jobs carry their density). `Grass.carpet` scatters clumps over a stretch of ground given as its own mesh grid, so every clump stands on the ground as drawn (level: `_terrain`'s 2 m grid; line: each chunk's grid, kept as meta `hgrid`), at `per_m2` (8 forest, 2.5 swamp, 6 beside the line), thinner between the drifts (`lush`). It keeps off the track, the platforms, the lift's pad, the way to it, the houses, water, bores and mountains. `plant` cuts a field into 8 m tiles, each a MultiMesh written straight to its buffer, drawn in full within `NEAR` (35 m) and a sixth of it out to `FAR` (75 m). About 280k clumps on a forest stop: 145 fps on an M5, about 0.3 s of the build. The line plants its grass at the end of each chunk, a slice at a time (`_grass`, via `_m`), and adds no hitches on a ride. One shader for all of it: wind (gusts rolling over the field plus flutter, stronger in a storm or rain, from `main.weather_now`), and up to 8 pushers (players and creatures nearest the camera, `_pushers`, fed once a frame) leaning the blades away and pressing them down. Their own dice: planting moves no other scenery. Shots: `tests/grass_shots.gd -- <dir> playground`.
- **The line** follows the biome too: segments carry `bio`/`next_bio` (`line._bio_at`), the ground shader takes the biome's textures (`_ground_mat(bio)`), and `_scenery_bio` dresses forest, swamp (with water) and town outskirts.
- Shots: `tests/biome_shots.gd -- <dir> FOREST|SWAMP|CITY|DESERT|ARCTIC [LANDMARK|-] [hour]`.

### Landmarks (`landmarks.gd`)
- Most stops (80%) get one landmark that suits the biome (`Landmarks.FOR`): CHAPEL (nave of stone or boards, steep slate roof, buttresses, coloured panes, a rose window, the bell tower with louvres, the bell and a spire; pews, the altar, a lectern; a graveyard behind a low wall), LOOKOUT (a steel fire tower with a square stair climbing inside it round a well, walkable, to a glazed cab with a catwalk; fire finder, radio), FARM (red gambrel barn with its doors run open, hay, a loft, a tractor; a silo with its ladder; a stock tank), FUEL (canopy over two pump islands with globe pumps, the kiosk with counter, till and shelves, the price sign).
- `level._choose_landmark` places it before the terrain (flattened, `_houses` points over its footprint so houses and trees keep off), facing the station; `Engine.set_meta("force_landmark", KIND)` forces one (shot scripts, tests). Its loot spots go into `_houses` (surface scrap lands there).
- **Safes** (`Landmarks.safe`, one per landmark): hold E 3 s to pry open, loud (noise 22); 2-3 valuables drop out (host). They join `facility.supplies` (deposit-box style: `deposit` meta, `lid` hinge), so saves remember them.

### Landmark stops (`Data.LANDMARK_STOPS`; the first: the dam, `dam.gd`, `dam_halls.gd`)
- Once an assignment `main._landmark_stop` swaps one route choice for a landmark stop: its own facility theme and a name, in a biome that suits it (`MAP` tags it `[DAM]`, `VIEW_STATION` describes it). Engine meta `force_dam` puts it first (tests).
- **The dam** (`level.dam`): the valley behind the station is dammed. An arch (`R` 400 m, centre downstream) 44 m high from ridge to ridge, one mesh (`_body`) with the downstream face battered back, in the `formwork` texture (pour lifts, tie holes bleeding rust, streaks). The crest road between parapets with lamp standards, a road bridge over the spillway. The spillway: piers, four radial gates in red lead, winch houses; the water is ONE sheet (`_spill_water`, a column per 0.6 m from `_spill_path`) from under the reservoir's surface, drawn down to the gates, out under their lips, over the ogee, down the chute and round the bucket onto the stilling basin; shader `FLOW` (glassy ropes over the crest, white lower down, faster as it falls, UV2.x how far down). The basin: walls, baffles, `CHURN` water (boil at the foot, rafts of lace foam carried off, a swirl over the drain, fine ripples from smooth coordinates: stepped ones lit up as a checkerboard), the `FOAM` roller where the sheet lands, droplets and mist, a drain lip into the culvert, the `waterfall` loop. The reservoir behind it, two intake towers with gatehouses and bridges, the powerhouse at the foot (brick, steel windows, the penstocks into its back), the transformer yard, pylons over the western ridge, a climbable stair tower (6.4 m bays: 33 degrees) up the face to the crest and a hut with a safe, floodlights. `keep_out` keeps houses, scenery and scrap off the works; `flats` levels them; `basin_floor` sinks the basin's ground; `line.height` adds `Dam.ridge` round the reservoir.
- **Under it** (theme `DAM`): sweating concrete, a green dado, cold tubes. Big rooms are `turbine_hall` (units standing out of their pits in railings, governor cabinets, the crane, one unit open with its windings out on a cradle: `fac.jackpot`, where `level.populate` puts the WINDINGS, 22 copper) and `control_room` (the mimic board, desks facing it). At 18:00 the sluices open (`site_clock._sluices`: klaxon, notice, the spillway louder), then rooms flood one after another from the far end (`_inflow`: a culvert grating gushing, the water rising over 55 s).
- Tests: `tests/dam.gd`; shots `tests/dam_shots.gd -- <dir> [biome] [hour] [view ...]`.

### The facility through the day (`site_clock.gd`)
- Built in `level.populate` after the hazards (every machine), ticked by `level.tick` on the host; its events go to everyone as net event `site`.
- **Fire shutters:** 2-4 ordinary doorways (no swing door, no bulkhead, rooms of their own) get a roll-down shutter in a hood with guide channels, a hazard bottom bar and an amber beacon on each face. They're registered as facility doors (`FS1`..): `set_door`, the door net event and the room graph treat them as bulkheads. Start open.
- **Burst main** (14:00-20:00, likelier where a room's already flooded): a pipe on a dry room's wall splits and sprays (particles, sound, a noise), and `hazards._flood` floods the room, everything it lays rising from below the floor over ~28 s.
- **Lockdowns** (from 20:00, one or two): klaxon, beacons turning, every shutter and every open bulkhead shut for `LOCKDOWN_SECS` (90), then back as they were.
- **23:00:** `elevator.set_fault()`: sparks and smoke at the headframe, the readout says LIFT FAULT / EMRG DRV, the lift crawls (`crawl` ≥ 3.5) for the rest of the day; the PA alert calls everyone to the lift.
- Test: `tests/site_clock.gd` (shutters, a burst, a lockdown and its release, the lift fault, a landmark's safe).

### The horror director (`director.gd`)
- Built in `level.populate` on every machine, ticked once a second by `level.tick` on the host. Each player underground gets a stress (recent damage decaying, the nearest hunting creature within 16 m, being alone); the crew's intensity is their highest, smoothed.
- Moods: RELAX (the first minute below, and 40-70 s after any peak: no scares, and `quiet` holds `level.tick`'s extra pulsators back), CALM (nothing on purpose; after 35-70 s of low intensity, BUILD), BUILD (a scare every 9-16 s at whoever's alone and least frightened, worse each time: steps or a knock behind you; a whisper or an open swing door two rooms over slamming; every lamp round you dying, stuttering and coming back with a screech far off; then a noise at you that draws whatever hunts by ear), PEAK (intensity over 0.7: it leaves you to it).
- Scares go out as net event `director` and play on every machine where they happen (`net_event`: sound, slam, lights).
- Checked in `tests/site_clock.gd`.

### Crew puzzles (`facility.gd`, `twin_lever.gd`)
- **The records room** (`_pick_secure`): the next dead end out after the vault, behind a keypad door (`secure_code`, four digits; dark green riveted door marked SECURED, a keypad with a lamp beside it, RECORDS over the door). No manual override; the site map shows `????`. The code is chalked on a wall in a room at least three cells away (`_secure_clue`: RECORDS, the digits ringed, DON'T FORGET). Whoever finds it reads it out to whoever's at the train terminal: `OPEN_BULKHEAD ####`. Inside: 2-3 valuables and a data disk (`level.populate`).
- **The twin-key blast door** (`_pick_twin`, `twin_code` T##): another dead end; TWO-MAN RULE over a steel frame. Two levers (`twin_lever.gd`: a riveted backplate, two quadrant plates over the handle's swing with a notched rail, a T grip with its latch, a caged lamp to one side; the handle pulls down and out toward you, `UP` 0.12 to `DOWN` 2.3 rad, never into the wall) on the furthest-apart walls of the room in front, on a bare stretch of wall (`_clear_spot`, see below): a pulled lever holds down for `HOLD` (2.5 s) on its spring, lamp amber; pull the other while it's down and the door opens (host), lamps green. Alone: a DOOR_WEDGE clicked on a lever jams it down for good (the wedge code path treats levers like swing doors: `set_wedged`, `net_key`). The terminal refuses it. Inside: a heavy valuable and another.

### Facility generation (`facility.gd`)
**Layout:**
- The main floor is a grid of 12 m cells (`facility.gen_layout`): a core of 3-5 rooms round the lift, then **wings**: a straight corridor run of 2-6 cells out from a non-corridor room, a cluster of 2-5 rooms at its end (`_grow_cluster`), repeated until the room count (`main._gen_stop`: 14 + 4 per assignment + 0-8; VIEW reads LARGE / SPRAWLING / VAST). Corridor cells (`layout.corridor`) never join big rooms or take loop links, and turn into tunnels 95% of the time, so the far ends of a site are 100-200 m apart and a crew that splits up is properly alone. Loot scales with rooms minus corridor cells; creature counts (`level._n`) with sqrt(rooms / 16). Extra loop links, bulkheads (coded, opened from the terminal or with a loud manual override) and crawl vents (1.1 m) between unlinked neighbours.
- The **vault** is the furthest dead end, behind its own bulkhead, with the best loot. It opens only with the **VAULT KEYCARD**: no terminal, no manual override. `level._place_keycard()` leaves one per site well away from the vault (14 m+), preferring mezzanine loot spots and the lower floor, furthest from the lift, with a bear trap beside it when it's on the floor (same draws on every machine; the host spawns). The card glows faintly red and is a scan target. Hold it and press E at the reader outside the door (`facility._vault_swipe`, host-side; `Interact.who_now`'s held item; a crewmate's card is taken back with `to_owner "take"`) and the door opens (`open_vault`: the reader lamp goes green). Saves keep `vault_open`.
- **The strongroom** (`facility._vault`): brushed-steel walls with rails, banks of deposit boxes on three walls (two big ones per wall to pry open, `_deposit_box` / `_open_deposit`, hold E 1.6 s: 1-2 of GOLD_BAR, CASH_BOX, BEARER_BONDS; they're in `supplies` so saves remember them), a steel table under a green-shaded lamp with gold bars and a cash box or bonds on it, a mesh cage at the back round the heavy prize with shelving, yellow floor lines and a STRONGROOM 7 stencil, cold strip lights and two red lamps. Outside: a riveted steel surround with hazard chevrons, a locking wheel and bolts on both faces of the door, AUTHORISED PERSONNEL ONLY, an amber caged lamp. GOLD_BAR / CASH_BOX / BEARER_BONDS are `no_spawn` (vault only).

**Room kinds:**
- storage, machine (generators), pit, collapsed, break, office, lab, server, empty, atrium (mezzanine deck + stairs), tunnel (ribbed corridor on straights; every wing corridor), vault, stairwell.
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
- **Wall clearance** (`facility._clear_spot` / `_reserve`): once the rooms are dressed, the AABBs of everything smaller than a whole wall or floor are gathered (`_see_walls`, before merge.gd bakes them away). The twin levers, the chalked code and the main breaker each take a stretch of wall with nothing in it (no shelf, sign, cabinet, pipe or crate) and reserve it (also into `crates`). The chalked code sits higher (1.75 m), clear of the wall band, its lines spaced so they don't run into each other; `clue_n` is the way its wall faces.
- **The main breaker** (`hazards._build_breaker`): a deep green isolator cabinet on two wall rails. A panelled door hinged down the left with a lock handle; on it the MAIN BREAKER plate, a yellow DANGER 440 V plate, a voltmeter, the pilot lamp (green, red when tripped) and an amber one, and a glazed window onto two rows of breakers. The operating handle is on its right side over an ON/OFF quadrant, up `LEVER_ON`, dropping to `LEVER_OFF` when it trips (swinging out through the front). Conduits with couplings climb to the ceiling from a junction box. `tests/wall_shots.gd -- <dir> playground` photographs the levers, the breaker (on and tripped) and the code.
- **Power failure:** lights and emissive surfaces dark, red emergency lights, lift at 1/3 speed, cameras and bulkheads offline, cables dead, generators stall. Fixed by the MAIN BREAKER, which is shown on the scanner and map.
- **Tremor:** dust and falling debris, sometimes scrap; can trigger a power failure.
- **Airdrop** (`airdrop.gd`, played on every machine from the same spot and heading): a twin-engine Bureau plane comes in low, the crate goes out of the cargo door, free-falls, the canopy blossoms open, and it swings down onto the spot. It lands in dust, the canopy sags, tips over downwind and lies on the sand, and a red flare smokes for 4 minutes. Prying it open is loud: the straps snap, the lid flips off, the sides fall flat, and the host lays 2-3 valuables (sometimes a tool or medkit) in the shredded paper. About 1 in 8 (`CRASH_CHANCE`), the plane arrives already burning: left engine on fire, a black trail, wallowing, the engines coughing and backfiring. A while after the drop it rolls over and goes down far off, out of reach. The crash: a flash, a fireball swallowed by black smoke, a dust ring, burning wreckage on arcs, a mushroom column, ground fires with secondary fireballs, and a column that stands for minutes. The boom arrives at distance/343 s, and if you're underground the facility shakes and dust falls (`hazards.tremor(true)`: no alarm, no noise, no power cut). Sounds are synthesized in sfx.gd: `plane_loop`, `drop_fall`, `chute_pop`, `drop_land`, `crate_pry`, `backfire`, `explosion_far` (a dull far thud, sub drop and rolling rumble, no echo copies, which came out as bongs). Shots: `tests/airdrop_shots.gd -- <dir> [hour] [crash]`. The puffs set `billboard_keep_scale`. Their colours are written as they should look and converted to linear.

### Surface (`level.gd`)
- **Terrain:** rolling dunes, flattened along the track, around the lift and under houses.
- **Buildings:** a walk-through station house and other houses (§6), signposts to the lift with distances, tin sheds.
- **Scenery:** car wrecks, ruin walls, scrap heaps, fences that follow the ground, a water tower, windmills, a pumpjack, an arch frame, telephone poles with sagging wires.
- **Distant landmarks:** banded rock spires and arches past the edge, stepped mesas on the horizon.
- **Biomes:** five (§5 "Surface biomes"). Arctic gets:
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
- **Power:** `powered`, `set_power(on)`: lamps registered with `_lamp`, CRT screens, the clock and charger lamps follow it; `_emergency_lamp`s glow red when it's off.

### Rendering and performance
- **Merging and culling:** static geometry is merged per chunk. Lights use distance fade: shadows within 12 m, lights off past 45 m, dual-paraboloid omni shadows. That took facility frames from 25 ms to about 9–10 ms (`tests/perf.gd`).
- **Occlusion culling** (on in `project.godot`): `facility._occluders()` puts a BoxOccluder3D in every thin, big (≥ 2.4 m) wall, floor and ceiling box. Facility floor/ceiling slabs don't cast lamp shadows (`Merge.bake(..., indoors = true)`), and merged chunks stop drawing at 140 m (`Merge.FAR`). Fixed site (`perf.gd` seeds its RNG): 14.5 → 12.2 ms average, 17.5 → 14.8 ms worst. Splitting small detail into its own LOD chunks was tried and reverted (it doubled draw calls). FPS counter: VIDEO settings.
- **Draw calls (2026-10-11):** every non-emissive `A.mat` carries meta `arr` (texture layer, 1/tile, grating) and `vc_tint`; `Merge` folds all of them into one surface per chunk drawn with `A.array_material()` (a Texture2DArray of every texture kind + a shader doing the StandardMaterial's triplanar/tint/roughness; layer and tiling in UV2, tint in COLOR). Emissive, glass and custom materials stay their own surfaces. The facility merges per room (12 m chunks); swing-door leaves and each moving genset part are merged too (moving parts marked live, then each baked). Only `facility.SHADOW_LAMPS` (3) room lamps nearest the camera cast shadows, lamps past `LAMP_REACH` (32 m) are hidden in the renderer (`instance_set_visible`, only ever re-shown if the node is lit, so flicker and power failures keep control). Sounds: synthesis has its own RNG (`Sfx._r`, seeded by name, behind `_lock`) and `Sfx.warm()` makes every sound (`Sfx.ALL` + takes) on a worker thread at start; add new sound names to `ALL`. Measured with `tests/perf_tour.gd` (vsync off; `-- breakdown` toggles each cost): facility 23-25 ms -> 7-9 ms, checkpoint 6-11 -> 3.4-6, worst-frame hitches from first-played sounds gone. What's left in a facility: ~2.5 ms of engine setup (culling, light pairing for ~100 lamps), ~2.3 ms GPU.
- **Lighting rules:** explosion and electric-arc lights cast shadows so they stop at walls. Flickering lamps dim their bulb materials too.
- **Quality setting:** LOW / MEDIUM / HIGH changes render scale, shadow atlas size, SSAO and glow.
- **Environment:** ACES tonemap, volumetric fog (dense per weather), glow, SSAO. SSR is off (it made blocky reflections).

---

### Sounds measured off real recordings
Freely licensed recordings (Wikimedia Commons, CC0 / CC BY / CC BY-SA: footsteps, metal hits, doors, drops, glass, drips, train horns, a diesel railcar, a gunshot, thunder, a siren, a heartbeat, a tiger, a scream, wind) were measured with `tools/sound_analyze.py` (envelope, attack/decay, octave bands, centroid, the strongest modes and their decay rates, pitch track, onsets, slow modulation), then our synthesized sounds were rebuilt to match (`tests/sfx_dump.gd` writes ours to WAV for the same analysis). No recording is in the game or the repo.
- Footsteps (`Sfx._step`): heel strike, then toe/scuff 70-110 ms later; concrete grit, tile click, metal plate ring and grate rattle, hollow wood knock (sometimes a creak), sand and snow crunch. Four takes per sound (`TAKES`, `_has_takes`: steps, thunk, clank, door_shut, drip), used in turn, each seeded by its name (the same on every machine).
- thunk (dropped things: 200/700/1800 Hz knocks + click), clank (a free bar's partials 1 : 2.76 : 5.40 : 8.93 + structure hum), door_shut (`_slam`: the 128-360 Hz woody cluster + thump + latch), door_open (latch + hinge), drip (rising bubble plink), crack_glass (crack + tinkle tail), heartbeat/heart (lub ~105 Hz, dub ~138 Hz), diesel (39 Hz firing, 78 Hz strongest, below 900 Hz), horn (reedier, brighter, swells in faster).
- The locomotive (`train._engine_sound`): a four-stroke V12 like GE's (`Sfx._prime_mover`: each cylinder firing every second turn, so ~40 Hz at idle and ~105 Hz at run 8; uneven cylinders and paired banks give the chug; each pulse booms a long exhaust stack round 40-50 Hz with a chuff and the block's thump). Three takes (`prime_lo/mid/hi` at 400/720/1050 rpm) crossfaded by rpm, each pitched only to its neighbours; the throttle goes a notch at a time toward what the line asks (`train.notch`: 8 pulling away, 5 at line speed, 0 braking), the rpm winds up and down slowly. A soft turbo rush under load, the traction motors' whine with speed. (Forum descriptions: GE four-strokes "chug", EMD two-strokes have a tonal whine; the owner wanted the deep one.) Rail joints: one knock per axle per joint, front to back (`train._axles`, `JOINT` 18.3 m), and a rolling rumble (`rail_roll`).
- **Clicks and pops (fixed 2026-10-12, keep it that way):** a loop must run on into its own start. `_make` bends every loop's last 0.1 s onto its first sample (`_seamless`) and copies the head again past `loop_end`, because Godot's WAV playback interpolates across the loop point into whatever follows (zeros: a click every time round). Filters on a loop start cold, so the engine's use `_lp/_hp/_bp(..., wrap = true)`. One-shot grains in a loop need an attack and a fade (the prime mover's pulses had a step at each firing). Loops are never stopped or started while audible: `train._loop` / `line._sound` glide the volume. The World reverb has `predelay_feedback` 0 (at 0.4 the 30 ms predelay rang at ~33 Hz on the engine's chug and ran away: the tunnel clipped solid) and `hipass` 0.15; Master has a hard limiter at -0.5 dB. `tests/trip_audio.gd -- <out.wav>` records a whole trip off Master and prints each second's peak, loudness and clipped samples (needs a window and an audio device). On macOS, Godot outputs silence for a buffer if the audio lock is held (`AudioStreamWAV.set_data`, bus edits), so never make sounds or edit buses mid-trip.
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
- **Stations** (`station.gd`, built by `level._surface_build`): a brick-faced platform under a stone coping (white edge, yellow line, patched asphalt, ramps and lamps at both ends) running x -30..21 so the storage car fits; a cast-iron canopy (fluted columns, brackets, a lattice beam, a tin roof with sheets missing, a valance of pointed boards, hanging lamps, hanging name boards and a stopped double-faced clock); the booking office on the platform's back edge with its floor at platform level: booking hall walked straight through to the forecourt (green tiled dado; benches on the bare walls, a brass queue rail at the ticket window with its grille, the B.R.M. medallion in the floor, a map of the line, Bureau notices, the departures board, a weighing machine, TO TRAINS hung inside the platform door and WAY OUT over the back one), ticket office (the clerk's counter under the ticket window with a stool, a ticket case of pigeonholes, the desk under the front window, parcels on a bench under the end window, a platform scale and weights, a sack truck, ledger shelves, the safe, a coat and cap on a hook, a calendar) and waiting room (a chimney breast with the fire still glowing, a mirror and a clock on the mantel, an armchair by it on a rug, benches, a table laid for tea, a coat stand, a dead palm, pictures). The furniture is laid out round the ways through (`_interior`, its comment lists the openings): nothing in a doorway or the clear patch inside it, nothing tall in front of a window; the dado rail breaks at every opening (`_lining`); `_yaw(n)` turns a piece's front (local -z) to face a wall's normal. Shots: `tests/station_rooms.gd -- <dir> playground` (each room from under its ceiling and walking in, the platform benches); brick with stone quoins, lintels and sills, a slate roof with two chimneys, sash windows (some boarded, panes out); steps down to a gravel forecourt (lamp, bench, B.R.M. notice board, a van that never left) where the signposts to the lift start; a signal box past the west end (brick locking room, glazed cabin with a lever frame, stair up its end) and a water crane past the east end. Name boards at both ends face the track. `level._station_clear` keeps houses, rocks and trees off all of it; the loot spot inside is added to `_houses` after the snow's laid. Shots: `tests/station_shots.gd -- <dir> [DESERT|ARCTIC] [hour]`.
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
tests/all.sh          # 18 headless suites, as many at once as there are cores (JOBS=n), longest first, a failure retried once alone (~80 s on an M5): check smoke stranded monsters loop hazards levels lift voice_play kit creatures2 save photo_drop thin_items husk_follow settings_logic economy
tests/all.sh full     # with the 3-station smoke
tests/mp.sh           # multiplayer: two headless processes over ENet on localhost (lobby, travel, mirroring, pick/drop/kill/doors, same build, voice, blood, death)
tests/mp_late.sh      # joining a shift already at a station
tests/mp_save.sh      # play and save with a crew, then continue it
tests/run.sh 120 --headless --path . -s tests/voice.gd   # voice codec, the capture filter, voice occlusion
tests/mp_photo.sh     # an observer photo across a crew: lands where the host has it, picture and all
tests/mp_save.sh      # two rounds: play and save with a crew, then continue it (pockets, album, station)
tests/mp_shots.sh <dir> [quick]   # two WINDOWS: the client photographs the host's body and every creature copy (look at the PNGs)
```
State: everything above passed on the Mac and on the Windows PC (2026-10-08, Git Bash). On 2026-10-12, after the economy and shredder work, `check`, `smoke quick`, `loop`, `save`, `stranded`, `economy` and `mp.sh` were run and pass (in a Linux cloud session, §14). The mp tests pick a random UDP port in 24600–24990 on localhost.

| Suite | Covers |
|---|---|
| `check.gd` | terminal parsing, generator, data |
| `smoke.gd -- quick` | one station end to end (~4 s; drop `quick` for 3 stations) |
| `stranded.gd` | stepping off mid-trip (open line, tunnel) leaves you behind, never in the void; climbing straight back on or hopping off as it runs in is fine (real time: a few minutes) |
| `monsters.gd` | every monster's behaviour in a real room |
| `loop.gd` | heavy items, supply crates, vault (one keycard far from it, the terminal refused, the reader refusing an empty hand and opening with the card, deposit boxes paying out), mezzanines, payload rank |
| `hazards.gd` | habitats, flood, cables, gas, steam, power failure + breaker + generator stall, tremor, airdrop, lift doors, wall-muffled hearing, scanner highlight, pause menu, settings |
| `levels.gd` | two-level rooms and B-2: monsters through pits, mezzanines, lift ↔ farthest basement room; the unstuck failsafe must fire ≤ 6 times |
| `lift.gd` | the lift carries you, scrap and a body; cab contents sync from the cab ("E"); creatures stop outside the cab and the train |
| `voice_play.gd` | a crewmate's voice frames reach their player at full level from the very first game (voice.main used to stay null) |
| `kit.gd` | medkit, adrenaline, flare, noisemaker, charging rack, headlamp, upgrades, creature drops, weapon hit boxes, door wedge |
| `save.gd` | a run saved mid-station comes back the same in a fresh game: stop, site, credits, clock, upgrades, items left and aboard, a pinned photo, pockets, the album, an open crate, past events; the pause menu album; game over deletes it |
| `dam.gd` | the dam landmark stop: offered once an assignment, built with its lift, facility, windings and ridges, walkable crest and stairs, nothing random on it, the sluices flooding rooms at 18:00 |
| `economy.gd` | the quota by assignment and crew, replacement fees and debt, the crew-wipe recall, the diverter banking surplus, the bonded store's bales, STOCK SELL / SUBMIT, the save keeping it |
| `thin_items.gd` | small, thin things land on top of snow, sand and facility floors (and can be picked up) instead of sinking in |
| `husk_follow.gd` | a husk tagging along keeps a crewmate's distance without twitching to and fro |
| `settings_logic.gd` | rebinding (and swapping a key that's taken), quality presets turning CUSTOM and back, an old settings file read the new way, the settings screen built and reset |
| `photo_drop.gd` | observer photos land on the floor (30 drops and 4 real flashes); an item that falls out of the world comes back |
| `creatures2.gd` | the siren (calls in a stolen voice from behind a wall, backs off when seen, lunges unseen, fakes a sound with no voices) and the husk (a body left lying gets up, comes close, stares, attacks, dies back into a body). Same site every run (seeded); creatures are placed on clear floor in line of sight (`clear_spot`). |

`tests/run.sh` runs every test silent (`--audio-driver Dummy`). A windowed one (a shot script) is put behind whatever you were in: Godot pulls itself to the front as it starts, so the script puts the previous app back in front (osascript, on a Mac). Test speed (2026-10-13): `Engine` meta `fast_test` may be a float (`Data.pace()` uses it exactly): `stranded` rides at 0.2 (220 s down to 74 s). `monsters` and `playground_sites` ride fast too (78 to 52 s, 61 to 21 s). Engine meta `test_seed` fixes `main.rng`, so a test gets the same route and sites every run: `site_clock`, `kit`, `creatures2` and `thin_items` use 11 (env `SEED=n` tries another); random sites made them fail now and then. A forced landmark keeps looking up to 4000 tries. `monsters` falls back to any ordinary room if no plain one is free. The `hazards` suite is a little flaky under the parallel load of `all.sh` (a different tremor/gas check now and then); rerun it alone before chasing it.

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
| `tests/run.sh 400 --path . -s tests/event_shots.gd -- <dir> [hour or -] [halt,freight,power,thing,squall]` | the line events forced on and photographed as they happen |
| `tests/run.sh 200 --path . -s tests/trip_audio.gd -- <out.wav> [inside\|outside]` | a trip's sound recorded off Master: per-second peak, loudness, clipping |
| `tests/run.sh 400 --path . -s tests/shredder_shots.gd -- <dir> [view ...]` | the shredder and its desk from all round (front, three_quarter, hopper, controls, readout, desk_side, side, drive, back, conveyor; name some to take only those) |
| `tests/run.sh 500 --path . -s tests/economy_shots.gd -- <dir>` | the diverter (SELL, BANK), the bonded store empty and full, the readout, the visor in debt, the shift report with fees |
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
- **Run only the tests a change needs** (the owner asked, 2026-10-12): the suites that exercise the code you touched, not `all.sh` by reflex. Purely visual changes need screenshots, not suites.
- **Docs:** the README is the players' and friends' page (what the game is, screenshots, how to play, hosting); HANDOFF is the developer's. Keep both current when you change something they describe.
- **Releases:** publish (`tools/export.sh release`) only when the owner asks; pushing to `main` does not reach players (§11).
- **Runs the game itself**, now on Windows (`godot --path . -- playground FACTORY` and so on) and plays it with a friend over the internet.
- **Disliked, and fixed:**
  - billboard text, modern-looking fonts, pixel fonts for world text
  - floating or untextured viewmodels
  - flat boxy props, z-fighting, gaps in water and doors
  - gamey sounds
  - lights whose bulbs stay lit while the light flickers
  - parts of animations coming apart

---

## 10. Multiplayer architecture

Player-facing hosting and joining are in the README. The hub is `src/net.gd` at `/root/Net` (it survives scene reloads).

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
- New shared state goes into `main.net_state()` / `net_apply_state()` (read new keys with `st.get(key, default)` so older saves load) and, if a save should keep it, `save.gd _apply_state`. Example: the economy's `fees`, `bank`, `divert`, `banked_now`, `crew`, `lost_from`.

---

## 11. Windows and macOS builds (portable, to send to friends)

> **How players get a new version:** pushing to `main` does nothing for them. Their games update from the **latest GitHub Release**, so a change reaches players only when the owner runs `tools/export.sh release` from a clean, pushed `main` (it needs `gh` logged in and the export templates, so it's run on the owner's PC: a cloud session can't publish, §14). Publish only when the owner asks.

`export_presets.cfg` has two presets. **"macOS"**: universal (Intel + Apple Silicon) `Downline.app` in a zip, ad-hoc signed by Godot's built-in signer (works from Windows too), microphone usage text and audio-input entitlement set, not notarised (players right-click > Open, or `xattr -dr com.apple.quarantine`; `docs/HOW TO PLAY.txt` says so). **"Windows"**: Windows Desktop, x86_64, **`binary_format/embed_pck=false`**: `Downline.exe` (the engine, 110 MB, only changes with Godot) plus `Downline.pck` (the game, about 1 MB). Portable, nothing to install. `tests/`, `docs/`, `build/` and `*.md` are excluded. Output goes to `build/windows/` (`build/` is git-ignored).

**One command:** `tools/export.sh` (Git Bash on Windows or Terminal on the Mac; builds both platforms either way) stamps the commit into `src/version.gd` (`BUILD` = short hash, `SEQ` = commit count; put back afterwards), exports both, boots the pack once headless with the local godot (`--main-pack`) to catch script errors, and zips `build/Downline-<commit>-windows.zip` (exe + pck + `docs/HOW TO PLAY.txt`) and `build/Downline-<commit>-mac.zip` (the .app + HOW TO PLAY). **One pck updates both platforms:** nothing is imported (no textures to compress per platform), so the Windows export's `Downline.pck` is the update pack for Mac players too; the lobby and the intro show the build and the platform (`BUILD abc1234 · MACOS`), and Mac and Windows crews play together on the same build. It also writes `build/version.json` (version, seq, base, Godot version, pck URL, sha256, size). `debug` also builds `Downline_debug.exe`. **`tools/export.sh release`** (from a clean, pushed main; needs `gh` logged in) publishes the build as the latest GitHub Release of the public repo `Demiffy/downline`: the pck, version.json and both zips. Never publish without the owner asking.

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
   - **Icons:** `tools/export.sh` renders the mark (`src/mark.gd`) to `build/icon.png` (1024 px, `tools/icon.gd`; `build/.gdignore` keeps it from being imported) and both presets point `application/icon` at it: the Windows export turns it into the .exe's .ico (`application/modify_resources=true`; Godot 4.7 writes the exe's resources itself, no rcedit), the macOS preset points at `build/icon_mac.png` instead (the same tile inside Apple's 824-of-1024 margin, `mark.mac_image`; full-bleed it stood bigger than every other app in the dock), made into the .app's .icns. A game run straight on a Mac (the playground, tests) sets the dock icon to the padded one too (`mark.apply`); the dock still calls it "Godot" then, being Godot's own app, and only the export is called DOWNLINE. Exporting by hand needs those files first: `godot --headless --path . -s tools/icon.gd -- build/icon.png`.
   - The exe is unsigned, so SmartScreen will say "Windows protected your PC". Friends click **More info → Run anyway**.
   - Both players must run the **same build**. The level is rebuilt from a shared seed, so different code versions will desync.
   - Audio input is enabled in `project.godot` (`audio/driver/enable_input=true`). Proximity voice needs it.
   - Debug build for testing: `--export-debug "Windows" build/windows/Downline_debug.exe`. Set `debug/export_console_wrapper=1` in the preset if you want a console window with logs.

---

## 12. Recent changes

### 2026-10-12: stakes, the bonded stock, the shredder rebuilt
- **Economy** (§3): replacement fees and debt (`main.replacement_fee`, `died_world`), the crew-wipe recall (`_recall`), the quota by assignment and crew (`quota_units`), the shredder's diverter and the bonded stock (`shred_item`, `toggle_divert`, `_c_stock`, `level._bonded_store` / `show_stock`), the shift report's REPLACEMENT FEES and SURPLUS TO STOCK rows (`report.gd`, report array items 8 and 9). `tests/economy.gd`, `tests/economy_shots.gd`.
- **The bonded store** stands on the hall's west wall by the door (`level.STORE_AT`); one of the two pallet racks moved back to z 16.1 and the other went, as did the east corner's static bales.
- **The shredder** (§5) rebuilt from the ground up in Bureau green, and its controls are one desk with a big CRT for the readout. Gameplay positions kept: the hopper box (`level.hopper`), `CZ`, the throat's hurt zone; `NIP` moved up to 1.0 and `SHAFT_Y` to 0.72 (what's thrown in rests in the teeth). `tests/shredder_shots.gd`.

### 2026-10-11: look and feel

- **Sky and weather** (`src/weather.gd`): a sky shader (drifting cloud by weather, stars at night, the sun disc, dawn gold), weathers OVERCAST/RAIN/STORM besides the old ones; rain and roof drum sounds, drops on the train windows (`A.rain_glass`, the `rain_amount` shader global), lightning in a STORM (host calls strikes: net event `bolt`). Falling weather stops at roofs (a particle height field over the player) and none falls aboard. `tests/sky_shots.gd`.
- **Facility light** (`facility.gd`): failing tubes struggle/die/buzz; ceiling vents with a lamp in the duct (`_grate`, picked by room hash so layouts don't shift); power failure lights a red lamp per room and turning beacons (`hazards.power_fail`). `tests/light_shots.gd`.
- **Water**: `A.puddle` decals and `A.ripple` rings; puddles and leaks in facility rooms (`facility._puddles`, room hash again), visible drips, wakes round anything wading, rain puddles round the train. `tests/water_shots.gd`.
- **Shift report** (`src/report.gd`): the Bureau form with the stamped grade when the quota is met (net event `report`). `tests/report_shot.gd`.
- **Terminal**: CRT glass, power on/off, camera feed REC dot, clock and tearing. `tests/term_shots.gd`.
- **The suit** (`suit.gd`, rebuilt 2026-10-13): every piece is a smooth surface from `suit_mesh.gd`, so nothing is a box or cylinder stuck on, nothing floats or cuts in, and no ends show. The trunks (`PEL`, `TOR`) are lofted through superellipse sections; each limb (`ARM`, `FORE`, `LEG`, `SHANK`) is a tapered bar rounded at both ends, so a joint stays round whichever way it bends. The upper arm is built along the shoulder-to-elbow line (the elbow is 2 cm further out: hung straight, the forearm stood beside the sleeve). Things lying on the body are `slab`s on its own surface: pockets, flaps, the storm flap, the name tape, knee pads, armour plates and helmet paint. Bands (tape, belt) are the trunk's own sections a few mm bigger.
  - Helmet: an ellipsoid shell (`HELM_C`/`HELM_R`, `helm_pt`) with a real window cut in it (`WIN`). Inside: an inner skin, a rubber gasket round the window, the visor set behind it, a rolled rim, a neck bellows, ear cups, a lamp, and a cable over the crown to a battery at the nape.
  - Boots are lofted feet (`_foot_mesh`: heel to toe) with a padded collar, toe cap, lugged sole, laces up the instep and shaft, and a pull tab; the trouser hem hangs over them.
  - Gloves have a gauntlet over the sleeve's end (the sleeve, `FORE`, stops under it), a shaped palm, three-jointed fingers and a thumb, curling toward the thigh.
  - Every mesh carries its look slot (meta `lk`: suit, webbing, trim, helmet, visor, glove, boot) and is recoloured by `look_mat`. The pieces that change shape (`Style`, `Marking`, `Pack`, `ChestKit`, `BackName`) are rebuilt by `_variant`, onto the body's render layer. Meshes are cached by key and arguments (`M.cached`): the first figure takes about 0.1 s, later ones about 2 ms, about 235 MeshInstances each.
- **Grime** (`Suit.set_grime`, `player.grime` = mud, snow, wet, blood 0..1; `player._grime_step`): an overlay shader on every suit mesh (`GRIME`, `material_overlay`, one material per figure). Each mesh carries a `row` instance uniform, its standing-pose height from the feet, set once, so mud climbs from the boots and stays on the cloth in any pose. Effects:
  - mud: from walking mud or water (a little from sand and grass);
  - snow: settles on whatever faces up out in the arctic or a blizzard, melts indoors into wet;
  - wet: from rain or wading; darkens the suit and makes it glossy;
  - blood: from every hit (`hurt`).
  It all wears off, three times faster aboard the train, and blood faster at full health. Crewmates get it as pose[14] (pose[15..16] is now the once-a-second hp and pockets). Shader colours are linear (dark brown mud is a few hundredths). Shots: `tests/grime_shots.gd -- <dir>`.
- **The cold**: out on an arctic stop or in a blizzard, each breath mists the visor (`hud.breathe`, a soft patch low on the glass; every 3.4 s at rest, down to 1.3 s blown or scared). With each breath a puff of vapour comes out in front of the visor, low, where the mouth is (`Suit.breath`, on the head; crewmates run their own breath timer). The cold check uses the stop's own biome (`level.biome`), not the route's. Shots: `tests/cold_shots.gd -- <dir> playground`.
- **Footprints** (`footprints.gd`): a boot-sole decal at every foot plant (`STRIDE` 0.72 m, left and right mirrored) on sand, snow and mud (`main.surface_at`), for you (`player._prints`) and each crewmate (`puppet._prints`). Each is darker in sand, a blue-grey hollow in snow, near black in mud, fading over `LIFE` 90 s. Each foot plant also kicks something up (`_kick`, `KICK`): dust off sand, powder off snow, a splash in water, mud flecks, a little off grass, from 6 emitters a kind used in turn. They live on the stop's level, from one shared pool of 180 (the oldest reused), and project onto layer 1 only (not the grass, not people). Shots: `tests/footprint_shots.gd -- <dir> playground`.
- **Light in the haze**: every hanging lamp (`A.hanging_lamp`) has a `Cone`, a SpotLight3D under the shade with a strong volumetric fog energy (40), so a shaft of light falls through the facility's haze. It sways with the lamp and dims with flicker, haunting and power cuts (`facility._dim_bulb` scales its `base`). Your dust motes are denser (420, 7 m round you): unseen in the dark, drifting in every beam. The facility hides lamps more than 32 m from the camera, checked every 0.25 s (`_shadow_budget`), so a shot test that jumps the camera must wait before shooting. Shots: `tests/shaft_shots.gd -- <dir> playground`.
- **Snow on the train** (`weather._cold`, the `snow_amount` shader global, 0..1). It builds while you're out in arctic air (slowly) or a blizzard (fast), from the stop's or the line's biome, never in a tunnel, and melts slowly elsewhere. The barrel roofs (`train._roof_snow`) gather it in patches along the crown that spread into a blanket, deeper on top. Window glass (`A.rain_glass`) frosts over in feathery patches, never the whole pane. Rain on the windows already streaks back along the glass at speed (`rain_wind`). Shots: `tests/train_snow_shots.gd -- <dir> playground`.
- **Hit marks** (`marks.gd`, `main.mark`, `net.mark`): a shotgun pellet that hits the world leaves a dark pit with chipped paint and hairline cracks; a crowbar or axe that clangs off a wall leaves a gouge along the swing (`player.cb_right`). Each gives a puff of grit and sparks. Pooled decals (160) on the train or the stop, fading after 4 minutes; the crew see them. Explosions already leave a scorch (`blast.gd`). Shots: `tests/marks_shots.gd -- <dir> playground`.
- **The night sky** (`weather.SKY`): with the stars, a faint galaxy band across them, and the moon (a pale disc with dark seas and a halo) high on the side away from the sun. When the sun is low, a warm band lies along the horizon on its side (dawn coming out of the night's tunnel, dusk). Shots: `tests/sky_night_shots.gd -- <dir> playground`.
- **The flashlight in the air** (`player._process`): the beam's volumetric fog energy is 0.15 / the fog density (clamped 1.2 to 9). It shows about as much in thin night air as underground, and a blizzard's white-out doesn't blind you. Rain, sand and snow are lit where the beam crosses them. Shots: `tests/beam_shots.gd -- <dir> playground`.
- **Crew looks** (`Suit.apply_look`, `src/crew_look.gd`): eleven options, `Suit.LOOK` in order (a look is an array of indices, short ones padded with 0):
  - colours and finishes: suit colour (14), helmet colour (12), visor (6, from smoke to gold and silver mirror), gloves (6), boots (5), reflective tape (6, NONE hides it), wear (clean, worn, filthy);
  - marking (9: stripe, twin stripes, medic cross, checker, crew number, chevron, band, hazard band);
  - what's on your back (rucksack with a bedroll, air tanks with a hose, tool pack, radio pack with a whip aerial, or nothing);
  - helmet style (RESCUE crest, MINER brim with a big cap lamp, PILOT sun-visor housing);
  - what's on your chest (radio, chest lamp, ID badge, knife, nothing).
  Your name goes on the chest's name tape and on a patch on the pack. In settings as `look_<slot>`, sent with the roster (`net._look` takes 3 to 16, so an older build's three still work), worn by puppets, your own suit, your sleeves and gloves (`viewmodel.look`, reapplied after every rebuild, never on what you hold: `_held`), and by a husk as whoever it poses as. The editor has the options in two columns with swatches, and WHOLE, HELMET and BACK views. Shots: `tests/suit_closeups.gd -- <dir> [look...]` (every side and joint up close, in poses that open the joints) and `tests/look_sheet.gd -- <dir> [mixed|slot...]` (each option list in a row).
- **Creatures**: `tests/creature_sheet.gd` shoots every creature from four sides. Siren and warden feet are grounded (no sinking), wraith rags clear the floor.
- **Checkpoint draw distance:** the checkpoint merges in 24 m chunks drawn to `level.CP_FAR` (800 m) (`Merge.bake(..., far)`), so the far side of the basin and the skyline show; yard_life's moving rigs too.
- **Reclamation hall** (`level._reclamation_hall`): pitched roof (`HALL_EAVE/RIDGE`) on pitched trusses, a glazed lantern on the ridge, gable ends with vents, high windows, skylights, a bridge crane on runway beams, plinth, gutters and downpipes, a caged ladder, the brick hall office annex; the shredder's dust stack goes out through the lantern.
- **Engines** (`checkpoint.loco(parent, length, colour, number, end_cab)`): a road switcher for the freights on the far line and an end-cab yard switcher for the shunter; wagons now stand on the rail heads (`RAIL_TOP`). Floodlight towers (`P.floodlight_tower`) have a braced railed platform, a bank of six lamps in yokes, a ladder and conduit. The gate guard sits at his desk (`yard_life` round wait `SITS`), the clerk's arms reach forward (+x is forward on suit joints).
- **Checkpoint life** (`src/yard_life.gd`): the clerk at the shop window (stamps when you shop), the gantry crane carrying bales, freight trains on a far line. `tests/yard_shots.gd`.
- **Crew car** (`train.gd`): sage riveted walls over varnished panelling, checker lino with a runner, a perforated headliner on brass ribs, luggage racks, notices; a steel office desk with monitors, a swivel chair; the control stand is a painted console (cream gauges, lamps, labelled switches, radio handset) with the levers on their own quadrant stand. `tests/train_shots.gd`.
- **The checkpoint as a whole works** (`src/checkpoint.gd`; moving parts in `yard_life.gd`): a 350 x 280 m basin ringed by banded cliffs, the main line and a far through line leaving by tunnel portals; the Bureau's office with clock tower and mast, a container terminal under a gantry crane, the scrap works (crusher, conveyor, stacks), a classification yard with repair shed and signal gantries, a fuel depot, a transformer yard, floodlights. Workers, lorries, forklifts, a shunter and the crane all move. The cliffs are `_crag`s: stacked faceted strata stretched along the wall (no collision; invisible walls keep you in). Tunnel mouths (`_portal`): an arched concrete headwall with voussoirs, wing walls, a lined ribbed bore going dark, set into crags. The yard sidings leave the main line by a ladder (`LADDER_A/B`, `_track_seg`) and end at buffer stops (`_buffer`); the core siding joins the main line too. Pavement heights never coincide (ballast 0.03, lots 0.05, core pads 0.06, roads 0.08). Lorries (`truck`) are detailed cab-overs; the fuel line runs from a pump house and filler crane to a valve pit. `P.scrap_heap` is junk over a dark mulch core with an apron of wreckage down its slopes (draws one number from the caller's rng). `Merge`: chunks wider than 70 m are never distance-culled (they were measured from their middle and vanished underfoot). `tests/cp_shots.gd` (aerials, ground views incl. `ground_fuel`, `ground_rim`, the tunnels, the car's interior).

---

## 13. Status, rough edges and ideas
**Working and tested:** the full loop, all 15 creatures, two-floor facilities with cross-floor pathing, all hazards and events, upgrades, terminal, cameras, maps, scanner, pause menu and settings, fullscreen scaling, biomes and weathers.

**Known rough edges and ideas not done yet:**
- The cross-floor pathing has a failsafe: a monster stuck for 3 s while unseen skips ahead to its next waypoint. It fires 0–6 times per test run (`levels.gd` prints where). Places it has shown up: lift-room corners, mezzanine tops, near basement doorways. Worth tightening further.
- Arctic in clear weather is quite hazy, because of the fog density and white fog albedo. Could be lighter.
- Crafting uses for scrap were discussed but not built.
- Players only get new builds from a GitHub Release (§11). As of 2026-10-12 the latest release is `v920d96e` (2026-10-11): everything after it (the line's events and sound fixes, the macOS build, the economy, the rebuilt shredder) reaches players with the next `tools/export.sh release`.
- The playtest bot gets stuck in pits; it was deliberately left as is.
- The player has a third-person suit (`player._suit`, render layer `BODY_LAYER`) that only other cameras see: observer photos and the security-camera feeds.
- `docs/subterranauts-research.md` has notes on the original game for any further features.

**Ideas agreed with the owner (2026-10-12), in the order suggested; 1 and 2 are done:**
1. ~~Stakes: replacement fees and debt, the crew-wipe recall, a quota that grows with the run and the crew.~~ Done.
2. ~~Bank or sell the surplus: the diverter and the bonded stock.~~ Done.
3. **The train isn't safe:** a scrap thief (the original's Rust Crawler: steals scrap, nests round it; one player distracts while another steals it back) that can raid the flatcar, and late-night boarders (after 22:00 a husk or siren can climb aboard the flatcar or storage car).
4. **Bureau contracts and danger pay:** some stops carry a bonus job ("recover a TRANSFORMER: +150", "photograph a warden: +80"); flooded, gassed or late sites pay more per unit.
5. **A run with an arc:** five assignments, the last an audit (a huge quota, every creature allowed), a run-end grade and memento; Bureau notices that change a rule each assignment; lore logs that tell a story across the run.
Smaller: a first-shift prompt that tells new players the next terminal command; a check that one player can do everything (bulkheads, the vault, heavy items); rejoin after a disconnect is worth a test.

---

## 14. Working from a cloud session (Linux container)

Sessions in claude.ai's cloud run in a fresh Linux container with this repo cloned and no Godot. What has worked:

- **Godot:** download the Linux build (`https://github.com/godotengine/godot/releases/download/4.7.2-stable/Godot_v4.7.2-stable_linux.x86_64.zip`), unzip it, `ln -s .../Godot_v4.7.2-stable_linux.x86_64 /usr/local/bin/godot`, then `godot --headless --path . --import` once. The headless suites run as they do on Windows (`tests/run.sh` needs perl, which is there).
- **Screenshots:** there's no GPU. Install the software Vulkan driver (`apt-get install -y mesa-vulkan-drivers libvulkan1`) and run shot scripts under a virtual display: `xvfb-run -a -s "-screen 0 1280x720x24" tests/run.sh 400 --path . --resolution 1280x720 -s tests/<x>_shots.gd -- <dir>`. It renders Forward+ correctly but slowly (20-40 s a shot, several minutes a script) and darker than a real GPU does; judge colours with that in mind.
- **One Godot at a time.** Renders share the CPU: two at once take more than twice as long, and a render that seems to have died may just be crawling. The processes show as `godot --path ...` (the symlink's name, not the binary's): check with `ps aux | grep "[g]odot --path"`. Never `pkill -f <pattern>` from a shell whose own command line contains the pattern (it kills itself); the `[g]` trick avoids that.
- **Shoot only what you need.** A shot script that builds one stop and puts the camera straight where each picture should be (one frame each, 1280x720) is minutes; the big review scripts (`station_shots`, `cp_shots`, `creature_sheet`) build a lot and take many views, and can time out here. `tests/readme_shots.gd` is the pattern.
- **Git:** set `user.name "Demík"` and `user.email "velnertomas78@gmail.com"` in the clone (§9). Pushing works. Publishing a release does not: `gh` there has no valid token, and the GitHub tools can't upload release assets. Push to `main`; the owner runs `tools/export.sh release` on their PC.
- Files for the owner to look at (screenshots) go in the session's scratchpad and are sent from there.

> **After the bigger-facility change (fixed 2026-10-12):** the floating ribbons (above, "The ground's edges"). Of the suites that failed in the cloud, `hazards` was load only (it passes alone). The rest assumed the old small layouts or had a bug of their own: `creatures2` looked for two walled-off rooms that aren't part of a big room or a corridor and found none (now a corridor will do); `monsters` counted the fire shutters, which stand open, as shut bulkheads; `husk_follow` stood the player in the lift room's shaft and moved it twice a frame (the player's own physics as well as the test's). In the game: the husk errored every frame on `get_meta("rummage", null)` (Godot treats a null default as none: use `has_meta`; `facility.gd` had one too), took a player right on top of it for one with their back turned (`_looked_at_by` is level now), and stood pinned when walked into a corner (after half a second pinned it squeezes past you to the open side: `_pinned`, `_squeeze`).
