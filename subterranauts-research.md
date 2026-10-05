# Subterranauts — Deep Dive + Godot Clone Blueprint

Researched 2026-10-05. Sources: Steam store/news/reviews/discussions, the Fandom wiki (every page), the Steam "FULL GUIDE" by ZeroConditio, Thunderstore mod list. Things marked **(unverified)** I couldn't confirm from a source — treat them as design choices you make yourself.

---

## 1. What it is

- **Genre:** "Lethal-like" — 1–6 player co-op horror scavenging with proximity voice. Openly Lethal Company-inspired; its twists are a **train instead of a ship**, **four resource types instead of money-value scrap**, and a **GTFO-style typed terminal**.
- **Dev:** Red Basket Games — effectively one person (Asa Longino; the terminal examples use `MINIMAP ASA`). Hobby project, sporadic updates.
- **Engine:** Unity (Mono) — modded via BepInEx; the 1.0 patch fixed Unity CVE-2025-59489.
- **Timeline:** Early Access 21 Oct 2024 → 1.0 on 19 Oct 2025 → patch 1.0.31 Feb 2026. $4.99. ~190 reviews, 76% positive.
- **Tone:** Grim corporate dystopia played as dark comedy. You work for the **Association of Scrap Allocation**, paid in **Bucks**. "Your survival is secondary to the mission. The Association expects losses."

## 2. The core loop

```
CHECKPOINT (shop + shredder + upgrades + cosmetics)
   │  LEAVE_CHECKPOINT  (starts the assignment; quota shown)
   ▼
TRAIN on a branching route map (stations A, B, C… )
   │  ROUTE_TO <letter>   (pick the next station from VIEW_STATION info)
   ▼
STATION = outdoor surface map (1/3 of the scrap) + elevator → indoor FACILITY (2/3)
   │  loot, survive, haul scrap back onto the train before the DAY ENDS
   │  day ends → train leaves, with or without you
   ▼
repeat for the next station along the route …
   │  last stop: ROUTE_TO CHECKPOINT
   ▼
CHECKPOINT: shred scrap into steel/copper/rubber/plastic → meet assignment → earn Bucks
   │  short on quota? LEAVE_CHECKPOINT asks "Are you sure?" → "yes" kills everyone = game over
   ▼
next assignment: more stations, bigger maps, more enemies, more scrap
```

Key details:
- **Assignment = quota per resource**, not one number. E.g. "needs X steel, Y copper…". Players' main frustration/fun: "you will always need copper" — having lots of scrap but the *wrong mix* fails you. This is the game's best original idea; keep it.
- **Leftover scrap rides with you** to the next assignment unless you discard, sell or use it. Excess may pay extra Bucks (community unsure) **(unverified)**.
- **Difficulty ramps per assignment**: more stations on the route, larger facilities, more enemy spawns. Players report it gets "really hard" after ~10 checkpoints.
- **Quota doesn't scale with player count** — solo is brutal (a major complaint). Scale it in your version.
- **Day length** was shortened in 1.0 and players called it "too aggressive". Make it tunable.
- **Death:** you lose everything you carry (items too — people complain that losing the flashlight + scanner spirals). Scrap left on the **elevator shelves** or on the train is safe. Dead players spectate until the next day. With 1 player, death = the train leaves = run over.
- **Health:** 100 HP. It regenerates only back to 100 if you're above 51; at ≤50 you're capped at 50 (acid rain leaves you at 50). Simple "two-tier regen".
- **Stamina:** generous compared to LC (you can kite enemies); the Better Boots upgrade doubles it.
- **Inventory:** 5 slots (6 with Backpack) + 1 separate **equipment** slot. Use = LMB, Use Alternate = RMB (flashlight toggle), Use Equipment = MMB (scanner), Drop item = Q, Drop equipment = C. Pickup is "hold E" (players wanted tap).
- **No weapons.** Counterplay is avoidance, stealth (crouch), light, flares, and the terminal. Reviews repeatedly ask for some way to fight back.

## 3. The train (your "ship")

- Mobile base: engine cab (horn lever with upgrade), terminal workstation with **two monitors** (move the mouse left/right to switch), **disk reader**, **battery charger**, **chalkboard** for pinning Instant Camera photos, storage area (+ **Storage Car** upgrade adds a carriage).
- Travel between stations is a loading screen (a mod lets you walk around the train while it moves — do that natively; it's charming).
- Players said the train feels too safe. Some threat that reaches the train would help.
- At night it gets pitch black outside and the only light is the train's — the reviews single out that moment as great.

## 4. Stations, surface & weather

- Every station has a letter on the `MAP`. `VIEW_STATION D` shows the station's info (facility **type**, size, and the upcoming weather if you bought **Weathervane**). Route choice is a real decision.
- Surface biomes: **Desert** (base) and **Arctic** (5 maps, added for the holidays, plus a Blizzard event). The surface is hand-made maps with **caves** (some lead to the facility), broken **shacks**, signs with arrows to the elevator, ziplines.
- **Weather / world events:** sandstorm, meteor shower, **acid rain** (damages you, caps HP at 50), **solar flare**, **blizzard**.
- The **Leviathan** (sandworm) only spawns on the surface late in the day — the surface gets more dangerous as the clock runs.

## 5. Facilities (procedural interiors)

- Reached by elevator. Procedurally generated from tiles. Themes, from most to least common: **Factory**, **Lab**, **Flesh**, **Backrooms**, plus **The Ward** (added in 1.0; was too common at first, rebalanced in 1.0.31).
- **Elevator shelves:** a safe stash for scrap at the bottom (survives death).
- **Security bulkheads:** doors labelled with a code (e.g. `Q82`) that can **only** be opened/closed from the train terminal (`OPEN_BULKHEAD Q82`). This *forces* a terminal operator — great with 3+ players, painful solo. Consider adding a slow in-person override for solo play.
- **Security cameras** in factory maps: viewable, movable, with a toggleable light, from the terminal.
- **Traps:** Bear Trap, Snatcher vents. **Decor clutter** makes scrap hard to spot without a scanner (a complaint — give scrap a subtle glint).
- **Floppy disks** of lore spawn inside; bring them back to the train's disk reader → `LIST_LOGS` / `READ <NAME>`. Logs: WELCOME, FACILITY, LAB, + one per creature. Lore and the bestiary in one system — very cheap to make and players love it ("Lorekeeper" achievement).

## 6. The terminal (signature system)

Typed commands, `UNDERSCORE_CASE`, **Tab autocomplete**, **Up/Down history**, shorthand item names (`BUY FLA` = flashlight), quantities (`BUY FLASHLIGHT 3`), paged `HELP 1..6`, paged `SHOP 2`.

**Train terminal**

| Command | Does |
|---|---|
| `HELP [1-6]` | command pages |
| `BALANCE` | Bucks |
| `SHOP [page]`, `BUY <item> [n]` | order items (delivered to the train; **Quick Delivery** upgrade speeds it up) |
| `MAP`, `VIEW_STATION <X>`, `ROUTE_TO <X>` / `ROUTE_TO CHECKPOINT` | routing |
| `LEAVE_CHECKPOINT` | start the assignment; with an unmet quota → "Are you sure?" → `yes` = everyone dies |
| `SCAN_TRAIN` / `SCAN_FACILITY` / `SCAN_SURFACE` | totals of steel/copper/rubber/plastic in each place ("Facility has been cleared of scrap, good work.") |
| `LIST_CAMS`, `VIEW_CAM <id>`, `NEXT_CAM`, `PREV_CAM`, `TOGGLE_LIGHT`, `EXIT_CAMS` | security cameras |
| `OPEN_BULKHEAD <id>`, `CLOSE_BULKHEAD <id>` | doors (closing one can trap a monster or save a teammate) |
| `MINIMAP <player>`, `SWITCH_NEXT`, `SWITCH_PREV`, `EXIT_MINIMAP` | 2nd monitor: tracked player's minimap, **including scrap markers** (needs the Minimap upgrade) |
| `VIEW_BODYCAM <player>` | live first-person feed (player must wear a Body Camera) |
| `LIST_LOGS`, `READ <log>` | lore disks |

**Shop terminal (checkpoint):** `HELP`, `UPGRADES`, `BUY_UPGRADE <name>`, `HATS [1/2]`, `BUY_HAT <name>`.

## 7. Economy

**Items** (bought with `BUY`, delivered to the train)

| Item | Price | Power | Notes |
|---|---|---|---|
| Flashlight | 35 | battery, 3:20 | RMB toggle |
| Handheld Radio | 35 | battery, 3:20 | LMB push-to-talk to all radios |
| Lantern | 55 | battery, 4:45 | big radius around you |
| Crank Flashlight | 95 | none, 50 s | dims through 5 stages of 10 s; LMB to crank |
| Instant Camera | 45 | battery, 6 photos | photos are physical items, pinnable on the chalkboard |
| Beacon | 70 | — | placeable icon visible through walls (mark the elevator) |
| Flare Gun | 65 | 1 flare | stuns some enemies, repels the Leviathan |
| Battery | 20 | — | recharges in 20 s on the train charger; shreddable |
| Flare Ammo | 10 | — | |

**Equipment slot:** Backpack 80 (→ 6 slots), Battery Charger 110 (portable), Scanner 90 (~7 m pulse: lists items/resources/entities with distances, outlines scrap white, stick-figure skeletons on creatures, no power), Body Camera 85.

**Upgrades** (permanent per save, whole crew): Train Horn 100, Weathervane 150, Life Monitors 175 (heartbeat HUD per player), Better Boots 215 (2× stamina), Storage Car 250, Helmet Radios 300 (radio on a keybind, no slot/battery), Minimap 375 (HUD minimap: walls, stairs, players green, *some* enemies red, no mimics, no loot), Quick Delivery.

**Cosmetics:** hats 5 Bucks each (lost on death), free suit colours on a rack, an emote/dance, and the shopkeeper sometimes wears a random hat.

**Scrap → resources** (shredder at the checkpoint; exact yields vary slightly)

| Scrap | Plastic | Rubber | Copper | Steel |
|---|---|---|---|---|
| Bent Spring | | | | 2 |
| Broken Speaker | 1 | 1 | 1 | 2 |
| Cooking Pan | | | | 2 |
| Copper Ingot | | | 3 | |
| Copper Pipe | | | 2 | |
| Empty Can | | | | 1 |
| Hammer | 1 | | | 2 |
| Hazard Cone | 3 | | | |
| Jingle Bells | | | 2 | |
| Large Screw | | | | 2 |
| Milk Jug | 2 | | | |
| Old Boot | | 2 | | |
| Old Clock / Old Speaker | 2 | | 1 | 1 |
| Penny | | | 1 | |
| Red Copper Square Pan | | | 2 | 1 |
| Rubber Band Ball | | 2 | | |
| Rubber Tire | | 5 | | |
| Scissors | 1 | | | 2 |
| Steel Ingot | | | | 3 |
| Toy Dino | 2 | | | |
| Toy Forklift / Toy Truck | 2 | 1 | | |
| Water Bottle | 2 | | | 1 |
| Water Pouch | | 3 | | |
| Water Pump Gasket | | 2 | | |
| Wire Spool | 1 | | 3 | |

Bought items can be shredded too (e.g. Flashlight → 1 plastic + 1 copper; Beacon → 1 copper + 2 steel). That gives you a desperation lever: shred your gear to hit the quota.

The terminal has a **"Scrap Assignment and Market Tracker"** display, and the patch notes mention "scrap market values", so resource prices fluctuate **(exact formula unverified)**. A simple version: each resource has a price that drifts per assignment; meeting the quota pays a base amount, and the surplus sells at market price.

## 8. Entities — behaviour → how to build it

Almost every monster is **one sensory rule + one counter**. That makes them cheap to build and easy to learn. Copy the pattern, not the monsters.

| Entity | Where | Sense / rule | Counter | AI to build |
|---|---|---|---|---|
| **Roomba** | facility | drives straight, turns randomly on bump; 2 forward laser sensors → huge explosion | walk behind/beside, jump over from the side | bump-and-turn mover + 2 raycasts |
| **Pulsator** | both | **blind**, hears footsteps + **mic audio**; chases the last sound, swells, explodes after a timer or on contact | crouch, shut up, dodge during the swell | hearing → chase(last_pos) → fuse timer |
| **Mimic** | facility | looks like a barrel; opens and kills on proximity, then **runs off dragging your body + loot**, drops it later | distrust barrels, chase it to get loot back | disguised prop → grab → flee → drop |
| **Rust Crawler** | facility | centipede guarding a **loot nest**; reacts to sound/motion, very fast | one player distracts, another grabs | patrol around nest + hearing |
| **Leviathan** | surface, late day | invincible; periodic rumble + roar (bait); while rumbling, any movement/talk → launches and swallows you | freeze/crouch until it calms, stand under a solid roof, flare at the right moment | global listener state machine + roof raycast |
| **Warden** | facility | sees **only inside its spotlight cone**; scythes, fast chase | stay out of the beam | SpotLight3D cone = vision cone |
| **Marionette ("mannequin")** | facility | dormant until **looked at**, then sprints at you | don't look; lure into dead ends | "observed?" check (frustum + raycast) |
| **Statue** | facility | the inverse: once noticed, it moves **only when nobody looks**; strangles | keep eyes on it, stick together | SCP-173 rule: all players' view checks |
| **Stalker** | facility | tall shadow; **mimics teammates' voices**; finds you alone → kill; with a buddy → screams and flees; eye contact while it's stalking → flees | never be alone | count players within radius; replay recorded voice clips |
| **Spitter** | facility | non-lethal amphibian; slime blinds you, then it runs | dodge | approach → projectile → screen overlay |
| **Observer** | facility | camera on legs; follows you; if you **look back** → flash-blind, drops a photo of you | don't look back | follower + look check |
| **Snatcher** (trap) | ceiling vents | vent drips blood; walk under → yanked up and **teleported elsewhere** in the facility (alive) | watch the ceiling | Area3D + random waypoint teleport |
| **Bear Trap** | facility | trap | look down | Area3D |
| **Scrapper** | facility | bug disguised as a scrap pile; flees noise; kill it → valuable scrap | sneak up slowly | flee-on-hearing + reward |
| **Gloe** | facility, rare | friendly light orb; picks one "best friend" and lights the way | — | follow nearest player in range, OmniLight3D |
| **Wraith** | 1.0 | added in 1.0, undocumented | ? | — |

Balance lessons from the reviews (instant deaths at 100 HP with no warning are the #1 complaint):
- Telegraph every lethal attack (swell, rumble, scream, drip). The good monsters already do.
- Two look-at/don't-look-at mannequins that look alike felt unfair. Make "look" and "don't look" monsters visually very different.
- A spawn **schedule** by time of day (the Statue was moved "much later into the night") plus a **spawn cap** that ramps per assignment.
- The darkness was "too dark" without a flashlight. Give a faint personal light radius, and don't let one death wipe all your lights.

## 9. Multiplayer & voice

- Host/client P2P, 1–6 players (a mod raises it to 32), joining by **code**, plus a public lobby list. A mod adds Steam friend invites.
- **Proximity voice** with **reverb/echo in rooms** — praised a lot. The mic feeds AI hearing (Pulsator, Leviathan) — a core hook.
- Radios: Handheld (battery, slot) → Helmet Radio upgrade (keybind). Radio audio ignores distance.
- Known pain points: no late join (a mod adds it), no rejoin/mid-run save, desync (enemies invisible to some clients, invisible players after death). **Make the host authoritative for all AI and loot from day one.**

---

## 10. Godot 4 build plan (lazy path)

Stop at the smallest thing that's fun. Each milestone is playable.

**M1 — Solo loop, no network (1–2 weekends)**
- `CharacterBody3D` FPS controller: walk / sprint (stamina) / crouch (quiet). HP with the 51/50 regen rule.
- A one-room "train" plus one hand-built facility, an elevator `Area3D`, a day timer → train leaves.
- Scrap = `RigidBody3D` with `@export var res := {"steel":2}`; 5-slot inventory array; drop with Q.
- Shredder + quota check at a checkpoint scene. One `Resource` (`.tres`) per scrap type, so data lives in the inspector, not in code.

**M2 — Terminal (the soul)**
- `SubViewport` rendered onto the monitor mesh + a `LineEdit`. Commands = `Dictionary` of `"NAME": Callable`. Tab completion = prefix match over the keys; history = an Array.
- Cameras = `Camera3D` nodes in the facility rendering to a 2nd `SubViewport` on monitor 2. Bulkheads = `AnimatableBody3D` doors with a random 3-char ID on a `Label3D`.

**M3 — Procedural facility**
- Room-snapping: each room scene has `Marker3D` "doorway" sockets. Place rooms by aligning sockets, reject a room if its AABB overlaps an existing one, cap with a wall plug. Seed with `RandomNumberGenerator.seed` so clients rebuild the same layout from one int.
- Bake navigation at runtime: a `NavigationRegion3D` with `bake_navigation_mesh()` after generation (or per-room navmeshes linked with `NavigationLink3D`).
- One theme first. Themes = different room-scene pools.

**M4 — Monsters**
- One `enum State` + `match` per monster, `NavigationAgent3D` for movement. No behaviour-tree plugin until you have 6+ monsters and are suffering.
- Shared senses: `hear(pos, loudness)` emitted by footsteps / voice amplitude through a global `NoiseBus` autoload; `is_looked_at()` = dot product with each player's camera forward + one occlusion raycast.
- Start with the Roomba, Pulsator and Warden — they cover hearing, vision cone and trap behaviour.

**M5 — Multiplayer**
- Godot high-level multiplayer: `ENetMultiplayerPeer` for LAN/IP first. For Steam later, use **GodotSteam** with its `SteamMultiplayerPeer` (lobbies give you join codes and invites).
- Host-authoritative: `MultiplayerSynchronizer` on players, `MultiplayerSpawner` for scrap and monsters, RPCs for terminal commands (the client sends text, the host executes).
- **Proximity voice:** capture with `AudioEffectCapture` on a mic bus → compress (Opus via GodotSteam's voice API is the easy route) → RPC unreliable → play on an `AudioStreamPlayer3D` on the speaker's head with a `AudioStreamGenerator`. Room reverb = `Area3D` volumes that change the bus `AudioEffectReverb`. Feed the same RMS level into `NoiseBus` so monsters hear voice.

**M6 — Content & progression**
- Route map (a small DAG of stations per assignment), `VIEW_STATION`, weather, the shop, upgrades as flags in a save `Dictionary` → `FileAccess` JSON.

Skipped on purpose: a hat shop, controller support, achievements, lore disks. They're nice later, but none of them make the loop fun.

### Where to make it "your stuff"
The mechanics you'd be copying are loot-quota-leave-before-dark (LC), the terminal (GTFO), and the monster rules (SCP/Weeping Angel tropes) — all common genre ground. The reviewers' biggest knock on Subterranauts was copying LC's *look* (character models, dance, shop jingle). So keep the systems and make the fiction, art, creatures and audio yours. Some original twists the research suggests:
- Swap the train for something else that travels a route (a mine cart, a submarine line, a zeppelin).
- Keep the **multi-resource quota**; it's the most original system here.
- Give players *some* counterplay tool (reviewers asked again and again).
- Put a threat on the base/vehicle so the safe zone isn't 100% safe.
- Scale quota and bulkheads with player count so solo works.

---

## Sources
- [Steam store page](https://store.steampowered.com/app/3075800/Subterranauts/) · [Steam news / patch notes](https://steamcommunity.com/app/3075800/allnews/) · [Steam discussions](https://steamcommunity.com/app/3075800/discussions/)
- [Subterranauts Fandom wiki](https://subterranauts.fandom.com/wiki/Subterranauts_Wiki) (Terminal, Items and Equipment, Scrap, Upgrades, Stations, Facilities, Entities + creature pages)
- [Steam guide: FULL GUIDE AND EVERYTHING ABOUT THE GAME](https://steamcommunity.com/sharedfiles/filedetails/?id=3375858884)
- [Thunderstore mods](https://thunderstore.io/c/subterranauts/) · [VaporLens review summary](https://vaporlens.app/app/3075800/subterranauts.md) · [gg.deals](https://gg.deals/game/subterranauts/)
