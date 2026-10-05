# Subterranauts — Deep Dive + Godot Clone Blueprint

Researched 2026-10-05 (two passes). Sources:
- Steam: store page, all patch notes, ~160 reviews, forum threads, and 6 community guides (EN + RU)
- the Fandom wiki (all 27 pages)
- the auto-captions of a 2.5-hour 4-player let's play
- the READMEs of all 18 Thunderstore mods
- the source code of one open-source mod (SubTerminalEX), which reveals real class names inside the game

**(unverified)** = I couldn't confirm it. Treat those as your own design call.

---

## 1. What it is

- **Genre:** "Lethal-like" — 1–6 player co-op horror scavenging with proximity voice. Openly Lethal Company-inspired; its twists are a **train instead of a ship**, **four resource types instead of money-value scrap**, and a **GTFO-style typed terminal**.
- **Dev:** Red Basket Games — effectively one person (Asa Longino; terminal examples use `MINIMAP ASA`). Hobby project, sporadic updates.
- **Tech:** Unity **2022.3**, Mono, C#. Modded via BepInEx/Harmony. Networking is almost certainly **Photon PUN**: the game's `NetworkManager` has an `OnJoinedRoom` callback, and players join via a **room code** shown on the HUD. Proximity voice is probably Photon Voice **(unverified)**. No native Steam lobbies; a mod adds Steam invites.
- **Timeline:**
  - **Demo:** before release.
  - **Early Access:** 21 Oct 2024.
  - **0.3.25 "Say Cheese"** (Nov 2024): Snatcher, Observer, bodycams.
  - **0.3.31:** controller support, Quick Delivery.
  - **0.3.50 "It's Time"** (Dec 2024): Arctic biome, Blizzard.
  - **1.0.09 "The Ward"** (19 Oct 2025): Ward facility, Wraith entity, shorter days, harder AI.
  - **1.0.31** (Feb 2026): rebalance, money dupe fix.
- **Price & reviews:** $4.99. ~190 reviews, 76% positive.
- **Tone:** grim corporate dystopia played as dark comedy. You work for the **Association of Scrap Allocation**, paid in **Bucks**. The starter lore disk is literally `WELCOME_TO_HELL`. "The Association expects losses, and you've already been factored in."

## 2. The core loop (exact structure)

```
CHECKPOINT  (shop building: upgrades/hats terminal, suit rack, SHREDDER + lever, gate)
   │  type LEAVE_CHECKPOINT → assignment begins, quota appears top-left of HUD
   ▼
ROUTE MAP: branching lettered stations; ALWAYS 3 stations, then the next checkpoint
   │  VIEW_STATION X to compare, ROUTE_TO X to go. No going back.
   ▼
STATION (one in-game day)
   ├─ surface map: ~1/3 of scrap, weather, Leviathan late in the day
   └─ elevator → procedural facility: ~2/3 of scrap, most monsters
   │  ~8 PM: "WARNING: return to train before automatic departure"
   │  midnight (12:00): train departs automatically, with or without you
   ▼
 ×3 stations
   ▼
CHECKPOINT: unload the train, carry scrap into the shredder → someone PULLS THE LEVER to submit
   ├─ quota met → Bucks paid, gate opens, buy upgrades, next assignment (quota goes up)
   └─ quota not met → gate stays shut. LEAVE_CHECKPOINT asks "Are you sure?" → YES →
      "ramming speed": the train rams the gate, everyone dies, "ASSIGNMENT FAILED" → game over
```

Key rules:
- **Quota = per-resource targets.** The HUD (top-left) shows `have / need` for each resource; "have" counts what's in the train. A quota needs e.g. 12 steel, 5 rubber, 7 copper, 8 plastic, and players spend whole stations hunting "the copper" or "any rubber". This is the game's best original idea.
- **Overflow carries over.** Don't shred more than you need: unsubmitted scrap rides along and counts toward the next quota. Shredding more earns more Bucks, so there's a cash-vs-banking trade-off.
- **Dark joke:** a teammate's **corpse shreds for 1 of each resource**.
- **Difficulty ramps per assignment:** more stations to pick from, bigger facilities, more enemies, a higher "heat level" (see §5). Players say it gets really hard after ~10 checkpoints.
- **Quota doesn't scale with player count**, which makes solo brutal. Scale it in yours.
- **Day pacing:** in-game clock on the HUD, the train cab and the terminal. In 1.0 the day got shorter and players called it "too aggressive". Make it a tunable.
- **Death:** you drop/lose what you carry (bought gear included, which snowballs: no light, no scanner). Scrap on the **elevator shelves** or in the train is safe. Dead players spectate until the next station. Solo death = the train leaves = run over. No revive.
- **Can't late-join or rejoin mid-run** (a mod fixes this). There's no mid-run save, so a disconnect loses the run.

## 3. Player

- **HP:** 100, with slow passive regen. Two-tier rule: above 51 you regen to 100; at 50 or below you're capped at 50. The Statue deliberately does more than 50 damage "to screw your regen".
- **Stamina:** ~7 s of sprint, ~4 s to refill. Generous next to LC, so kiting works. The Better Boots upgrade doubles it.
- **Movement:** walk, sprint, crouch (silent to hearing-based AI), jump. A crouch toggle was requested. Leaving the map bounds = you get zapped.
- **Noise:** footsteps (not while crouching) **and your actual mic audio** feed monster hearing.
- **Inventory:** 5 slots (6 with Backpack) + 1 **equipment** slot. Scroll to switch.
  - LMB = Use (radio talk, flare, crank)
  - RMB = Use Alternate (light toggle)
  - MMB = Use Equipment (scan)
  - Q = drop item, C = drop equipment
  - Hold E = pick up / interact (players wanted tap-to-pick-up)
- **HUD:**
  - clock (top) and compass under it
  - quota have/need (top-left)
  - HP (white) and stamina (orange) bars (bottom-left)
  - context prompts (bottom-center) and slots under them
  - the **room code**
  - top-right: the held item's description, which for scrap is its **resource breakdown**
  - upgrades add the minimap (bottom-left) and life monitors (bottom-right)
- **Scrap can hide inside boxes**: aim at one to see "hold [E] to pick up".
- **Cosmetics:**
  - **Suits:** free colours on a rack.
  - **Hats:** 5 Bucks each from the shop robot; lost on death, not saved across saves. Wearing them caused multiplayer bugs.
  - **Extras:** a dance emote, and the shopkeeper sometimes wears a random hat.

## 4. The train (your "ship")

- **Locomotive/cab:**
  - the terminal workstation
  - a **battery charger** with 4 slots (hold E to insert; recharges by the next station)
  - the **starter kit**: flashlight + battery, instant camera + battery, `WELCOME_TO_HELL` disk, scanner. Starter items **can't be sold**.
  - a **chalkboard** to pin Instant Camera photos on
  - the horn lever (upgrade)
- **Terminal = 4 screens + a clock + a disk reader**, left to right. Move the mouse left/right to look between them.
  1. life monitor + clock
  2. **main terminal** (commands, cameras, map)
  3. **quota + resource market prices** (and the minimap view)
  4. disk reader slot for lore floppies
- **Cargo car(s):** rows of shelving to store gear and scrap. The **Storage Car** upgrade adds another.
- **Deliveries:** items bought with `BUY` arrive on a **little rail handcar** that rolls up to the rear of the train playing a jingle; your items sit on its shelves. **Quick Delivery** makes it faster.
- Travel between stations is a loading screen (a mod lets you walk the train while it moves; do this natively).
- The train is "too safe" (reviews). Pulsators can get into the cab, but that's about it.
- Atmosphere moment people loved: night falls, and the only light in the world is the train and teammates' flashlights coming back.

## 5. Stations, surface, weather, facilities

**Stations:**
- Each has a letter on `MAP`.
- `VIEW_STATION D` shows its facility **type**, size, and the upcoming weather if you own the **Weathervane**.
- Route choice = risk vs reward vs which resources you need.

**Surface:**
- Hand-made maps: **Desert** (base), **Arctic** (5 maps; seasonal, rarer off-season).
- Features: caves (some lead into the facility), broken shacks (they don't protect from the Leviathan), signposts with arrows to the elevator, a town, a hill, and ziplines.

**Weather / world events:**
- Announced as a "**weather alert**" (an air-raid siren for meteors).
- Events:
  - sandstorm
  - **meteor shower**: hide under something solid
  - **acid rain**: damage, and it leaves you capped at 50 HP
  - solar flare
  - **blizzard** (arctic)

**The elevator:**
- Players call it up and down; a full team ride plays elevator music.
- It can leave without you, and you can fall down the empty shaft.
- It has **shelves** for safe stashing.

**Facilities (procedural):**
- Themes: **Factory** (most common, has security cameras), **Lab**, **Flesh** (lots of bulkheads), **Backrooms** (rarest), **The Ward** (1.0).
- The generator, as revealed by the LooneysBiggerMaps mod's knobs:
  - **room count** = base + per-difficulty amount, × a multiplier
  - a **"heat level"** difficulty number that drives **trap severity/count**
  - a trap pass during generation
  - after generation: **fixed item pickups** (gear lying around) + **floor resource loot**
  - **enemy spawn caps** that ramp up
- Entities follow a **spawn schedule by time of day**; e.g. the Statue only after late night (1.0.31).

**Security bulkheads:**
- Doors stamped with a code (`Q82`) that only the train terminal opens/closes.
- This forces a "terminal operator" role, which is great at 3+ players and miserable solo. Closing one on a monster can save a teammate.

**Lore disks:**
- Floppies found inside. Insert them in the reader → `LIST_LOGS` / `READ`.
- Logs: WELCOME(_TO_HELL), FACILITY, LAB, and one per creature, written as a field diary by previous crews. "Lorekeeper" achievement.
- This doubles as the bestiary: zero UI work, lots of flavour.

## 6. The terminal — design + how it's actually built

**UX:**
- Commands in `UNDERSCORE_CASE` (case-insensitive).
- **Tab** autocomplete, **Up/Down** history, mouse-wheel scrollback.
- Shorthand args (`BUY FLA`, partial player/station names), quantities (`BUY FLASHLIGHT 3`).
- Paged `HELP 1..6` and `SHOP 1..2`.
- A typo gets "**Command not recognized. Did you mean X?**".
- A **boot-up text** sequence when you sit down.
- Lines print with small delays (typewriter feel).

**Train terminal commands:**

| Command | Does |
|---|---|
| `HELP [1-6]` | command pages |
| `BALANCE` | Bucks |
| `SHOP [1-2]`, `BUY <item> [n]` | order items → delivery handcar |
| `MAP`, `VIEW_STATION <X>`, `ROUTE_TO <X>` / `ROUTE_TO CHECKPOINT` | routing |
| `LEAVE_CHECKPOINT` | start the assignment; with an unmet quota → "Are you sure?" → `YES` = ram the gate = game over |
| `SCAN_TRAIN` / `SCAN_FACILITY` / `SCAN_SURFACE` | item count + steel/copper/rubber/plastic totals per area ("…cleared of scrap, good work.") |
| `LIST_CAMS`, `VIEW_CAM <id>`, `NEXT_CAM`, `PREV_CAM`, `TOGGLE_LIGHT`, `EXIT_CAMS` | security cameras; **arrow keys pan the camera**; the light turns off when you switch cams |
| `OPEN_BULKHEAD <id>`, `CLOSE_BULKHEAD <id>` | doors |
| `MINIMAP [player]`, `SWITCH_NEXT`, `SWITCH_PREV`, `EXIT_MINIMAP` | 2nd screen: tracked player's minimap **with scrap markers** (Minimap upgrade) |
| `VIEW_BODYCAM <player>` | live feed (they must wear a Body Camera) |
| `LIST_LOGS`, `READ <log>` | lore disks |

**Shop terminal (checkpoint):** `HELP`, `UPGRADES`, `BUY_UPGRADE <NAME>`, `HATS [1/2]`, `BUY_HAT <name>`.

**Internals (from the mod's source):**
- `TerminalManager` (singleton): holds `commands: TerminalCommand[]`, `QueueTextLine(text, delayVec2)`, `EnableInput()`, `skipBoot`, a `response` buffer.
- `TerminalInterpreter`: holds `Interpret(userInput)`, an `args` list, a `currentPrompt` enum (`Prompts.None` / awaiting YES/NO), `errorClip` / `buyClip` sounds, and per-command coroutines like `OpenHatShopCommand` / `BuyHatCommand`.
- `TerminalCommand` is a **ScriptableObject** (a data asset) with fields: `command`, `numArgs`, `argsOptional`, `description`, `parameterDescription`, `example`, `argTips[]`, `hidden`, `actionMethod` (the *name* of a coroutine on the interpreter, called via `StartCoroutine(name)`).
- **Wrong arg count** → prints "Incorrect use of parameters", then the parameter description and the example.
- **"Did you mean"** = Levenshtein distance against all command names.

→ For Godot, that maps 1:1 to a `TerminalCommand extends Resource` with the same fields, plus a `Callable` instead of a method-name string.

## 7. Economy

**Items** (`BUY`, delivered by handcar):

| Item | Price | Power | Notes | Shreds to |
|---|---|---|---|---|
| Flashlight | 35 | battery, 3:20 | RMB toggle | 1 plastic, 1 copper |
| Handheld Radio | 35 | battery, 3:20 | LMB push-to-talk to all radios | 1 plastic, 1 steel |
| Lantern | 55 | battery, 4:45 | big radius | 1 copper, 1 steel |
| Crank Flashlight | 95 | none, 50 s | dims through 5 × 10 s stages; LMB cranks | 2 plastic, 1 steel |
| Instant Camera | 45 | battery, 6 photos | photos are physical items | 1 plastic, 1 copper |
| Beacon | 70 | — | placed icon visible through walls | 1 copper, 2 steel |
| Flare Gun | 65 | 1 flare | stuns some enemies, repels the Leviathan | 2 plastic |
| Battery | 20 | — | 20 s recharge | 1 copper |
| Flare Ammo | 10 | — | | nothing |

**Equipment slot** (can't be shredded):
- **Backpack 80:** 6 slots.
- **Battery Charger 110:** portable charger.
- **Scanner 90:** ~7 m pulse with a ~5 s cooldown. Lists items/resources/entities with distances, outlines loot, shows stick-figure skeletons on creatures, needs no power.
- **Body Camera 85.**

**Upgrades** (permanent per save, whole crew; typed with underscores):
- `TRAIN_HORN` 100
- `WEATHERVANE` 150
- `LIFE_MONITORS` 175
- `BETTER_BOOTS` 215
- `STORAGE_CAR` 250
- `HELMET_RADIOS` 300
- `MINIMAP` 375: HUD map with walls, stairs, players, some enemies + the Roomba; no Mimic/Stalker; the terminal version shows loot
- `QUICK_DELIVERY` (price unknown)

On game over, all upgrades lock again.

**Scrap → resources** (yields vary slightly):

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
| Scrapper (killed creature) | lots | | | |
| Dead teammate | 1 | 1 | 1 | 1 |

Toys squeak, which is noise.

**Market:**
- A terminal screen shows each resource's current **price per unit**. Prices **change daily** (per station/day).
- Shredding pays Bucks per unit at those prices, so the same scrap is worth more on a good day.
- A mod that sells resources prices them at ~**1.6× the sell price**, a sensible buy/sell spread if you add buying.
- Exact formula **(unverified)**. A good-enough model: `price[r] = base[r] * randf_range(0.7, 1.3)` per day, and the payout = Σ units × price.

## 8. Entities — behaviour → counter → how to build it

The pattern: every monster = **one sense + one rule + one telegraph + one counter**.

| Entity | Where | Sense / rule | Telegraph | Counter | AI sketch |
|---|---|---|---|---|---|
| **Roomba** | facility | drives straight, turns a random amount on bump; 2 forward lasers → big explosion | loud clicking | walk behind/beside, jump over from the side; lasers are forgiving | mover + 2 raycasts. The only trap on the minimap |
| **Pulsator** | both | **blind**; hears walking, running, **voice**; chases the last heard spot; explodes ~5 s after aggro or on contact | small distinctive steps; swelling | crouch, stay quiet; once aggro'd, run/dodge. Gets stuck on doors and in the train cab | hear → chase(last_pos) → fuse timer |
| **Mimic** | facility | barrel with legs + tongue. *Running* = harmless; it parks somewhere (often mid-hallway, badly) and becomes a barrel. Anyone within interact range → one-shot, eats you, relocates | a barrel in a weird spot | spot it; bait the lunge by stepping in and backing out → it relocates | wander → hide → ambush → flee with body + loot → drop. Not on the minimap |
| **Rust Crawler** | both | blind centipede that **steals scrap** and makes a nest (curls in a circle around 1 item); hears noise → dashes, ~40 dmg; its head hurts on touch, body is pass-through | circling | one player distracts, another steals; once robbed, it hunts for a new item | seek scrap → guard → hear → dash |
| **Leviathan** | surface, late day | invincible sandworm; periodic rumble + roar; while rumbling, movement/voice → it launches and swallows you | rumble, roar | freeze/crouch + mute; shelter under a solid roof; a well-timed flare | global listener; roof check by upward raycast |
| **Warden** | both | sees only inside its **spotlight cone**; fast chase; kills in 2 hits | very loud footsteps | stay out of the beam; **climb on furniture**: if it can't reach you, it de-aggros | SpotLight3D cone = vision; nav path to target fails → give up |
| **Marionette (mannequin)** | facility | crouched/dormant; if **anyone sees even a pixel** of it (generous FOV) it stands and sprints; one-shots | none (it's dark!) | look away; trap it in a dead end | "is observed?" check |
| **Statue** | facility | weeping angel: moves very fast **only when nobody looks**; always knows where you are; >50 dmg (wrecks regen) | — | keep eyes on it, stick together; late-night spawn | inverse observed check over all players |
| **Stalker** | facility | sneaks behind you, waits, **plays teammates' voices**, then strikes; alone = death; meeting your gaze for a moment → screech + flee | voice lines from nowhere | glance behind you; never go alone | stalk → wait timer → attack unless observed / buddy nearby. Not on the minimap |
| **Spitter** | facility | non-lethal amphibian; slime blinds you, then it runs | | dodge | approach → projectile → screen overlay |
| **Observer** | facility | camera on legs, follows you; look back at it → flash-blind; it runs and leaves a **photo of you** on the floor | clicking | don't look back | follower + observed check |
| **Snatcher** | ceiling vents | vents with **yellow paint**; one drips blood; step under → dropped on, you **drop your held item**, get teleported to another vent | blood drip | watch the ceiling | Area3D + random vent teleport |
| **Bear Trap** | facility | small damage + stuck | | hold E on it to free yourself | Area3D + root |
| **Scrapper** | facility | bug disguised as a scrap pile; sleeps; flees from noise; kill/pick it up → lots of resources | | crouch up to it | flee-on-hear + reward |
| **Gloe** | facility, rare | friendly light orb (various colours); picks one "best friend", lights the way; invincible | | — | follow nearest in range; OmniLight3D. Named after playtester Zoe |
| **Wraith** | 1.0 | added in 1.0, undocumented | | | — |

What players hated (avoid it): one-shots at 100 HP with no warning, monsters invisible in the dark, two mannequin types that look alike but need opposite responses, no way to fight back at all, and completely random spawns ("one run crazy, next run nothing"). Telegraph everything, make "look" and "don't look" enemies visually distinct, use a spawn **schedule + cap** that ramps, and give *some* counter tool.

## 9. Multiplayer & voice

- **Hosting:** host + room code (Photon-style), public lobby list (the refresh button was broken), 6 max (a mod raises it to 32).
- **Proximity voice with room echo/reverb** is the most praised feature. Radios ignore distance (handheld = battery + slot; helmet radio upgrade = keybind).
- **Known breakages to design against:**
  - enemies invisible to some clients
  - players invisible after dying and respawning
  - upgrades not applying to late joiners
  - hats breaking sync
  - disconnects with no rejoin
  - a memory leak at idle

  → **The host is authoritative for AI, loot, quota, upgrades.** Late joiners get a full state snapshot.

## 10. Godot 4.7 build plan (lazy path)

Project skeleton: `~/Claude Projects/subterra-clone` (Jolt physics on). Each milestone is playable.

**M1 — Solo loop, no network**
- `CharacterBody3D` FPS controller: walk / sprint (7 s stamina, 4 s refill) / crouch (quiet), HP with the 51/50 regen rule.
- One train car, one hand-built facility room set, an elevator `Area3D`, a day clock (warning at 20:00, departure at 24:00).
- Scrap = `RigidBody3D` + a `ScrapData extends Resource` (`name`, `resources: Dictionary`). One `.tres` per scrap type.
- 5-slot inventory `Array`, Q to drop. Shredder `Area3D` + lever at the checkpoint → quota check → Bucks.

**M2 — Terminal**
- `TerminalCommand extends Resource` mirroring the original (`command`, `num_args`, `args_optional`, `description`, `example`, `hidden`) + a `Callable`. A `Dictionary` name→command.
- Tab = prefix match, history = Array, "Did you mean" = `String.similarity()` (built in, no Levenshtein needed).
- Screen: a `SubViewport` with a `RichTextLabel` + `LineEdit` on a quad mesh. Camera feeds = more `SubViewport`s. Bulkheads = doors with a random code on a `Label3D`.

**M3 — Procedural facility**
- Room scenes with `Marker3D` doorway sockets. Grow by aligning sockets, reject on AABB overlap, plug unused doorways.
- `room_count = (base + per_level * level) * mult`, a `heat` value scaling traps.
- Seed with one int, so every client rebuilds the same layout.
- Runtime `NavigationRegion3D.bake_navigation_mesh()` after generation.

**M4 — Monsters**
- One `enum State` + `match` per monster, `NavigationAgent3D`.
- Shared senses in one autoload:
  - `hear(pos, loudness)`: footsteps + mic RMS
  - `is_observed(target)`: dot product against each player's camera forward + an occlusion ray
- Start with the Roomba (trap), Pulsator (hearing), Warden (vision cone) — they cover all three sense types.
- Spawn director: time-of-day schedule + cap that ramps per assignment.

**M5 — Multiplayer**
- `ENetMultiplayerPeer` for LAN/IP first → **GodotSteam** `SteamMultiplayerPeer` later (lobbies = invites + codes for free).
- `MultiplayerSpawner` for scrap/monsters, `MultiplayerSynchronizer` for players. Terminal input is sent to the host as text via RPC; the host runs it.
- **Voice:**
  1. capture the mic with `AudioEffectCapture` and encode it (GodotSteam voice API or an Opus addon)
  2. send it by unreliable RPC
  3. play it through an `AudioStreamGenerator` on an `AudioStreamPlayer3D` at the speaker's head
  4. room reverb comes from `Area3D` zones swapping a bus `AudioEffectReverb`
  5. feed the same RMS into `hear()`

**M6 — Progression**
- Route DAG (3 stops → checkpoint), `VIEW_STATION`, weather events, daily market prices, upgrades as flags in a save `Dictionary` → JSON via `FileAccess`.

**Skipped until the loop is fun:** hats, controller support, achievements, lore disks, photos.

### Making it *yours*
The systems are genre-common (LC's loot-quota-leave-before-dark, GTFO's terminal, SCP-style monster rules). The #1 knock on Subterranauts was copying LC's *look*: character models, the dance, the shop jingle. So keep the systems and invent the fiction, art, creatures and sound. Ideas the research points at:
- **Keep:** the **multi-resource quota** and the "bank vs cash out" overflow choice. That's the gem.
- **Keep:** the forced **terminal operator** role, but give solo players a slow manual override.
- **Add:** some counterplay (players asked repeatedly), and a threat that can reach the base vehicle.
- **Scale** quota/bulkheads with player count. Allow rejoin.
- **Swap the train** for your own route vehicle (mine cart line, subway, airship, river barge…).

---

## Sources
- Steam: [store](https://store.steampowered.com/app/3075800/Subterranauts/) · [news/patch notes](https://steamcommunity.com/app/3075800/allnews/) · [discussions](https://steamcommunity.com/app/3075800/discussions/) · [reviews](https://steamcommunity.com/app/3075800/reviews/)
- Steam guides: [FULL GUIDE](https://steamcommunity.com/sharedfiles/filedetails/?id=3375858884) · [COMMANDS](https://steamcommunity.com/sharedfiles/filedetails/?id=3375723454) · [ENTITIES](https://steamcommunity.com/sharedfiles/filedetails/?id=3376055254) · [How to counter the entities](https://steamcommunity.com/sharedfiles/filedetails/?id=3718017281) · [Equipment scrap value](https://steamcommunity.com/sharedfiles/filedetails/?id=3692975741) · [RU complete guide](https://steamcommunity.com/sharedfiles/filedetails/?id=3391673481)
- [Subterranauts Fandom wiki](https://subterranauts.fandom.com/wiki/Subterranauts_Wiki)
- Mods: [Thunderstore community](https://thunderstore.io/c/subterranauts/) · [SubTerminalEX source](https://github.com/KrayOristine/SubTerrminalEX) · [LooneysBiggerMaps](https://thunderstore.io/c/subterranauts/) (generator knobs) · [UpgradeLib](https://thunderstore.io/c/subterranauts/p/Xaru/UpgradeLib/)
- Video: ["Subterranauts: Lethal Company With A Train?!"](https://www.youtube.com/watch?v=DPE76c9Ohck) (auto-captions, day clock/pacing)
- Aggregators: [VaporLens](https://vaporlens.app/app/3075800/subterranauts.md) · [gg.deals](https://gg.deals/game/subterranauts/)
- Unavailable: SteamDB (bot check), PCGamingWiki (no page), Reddit (no community found), the dev's site (404)
