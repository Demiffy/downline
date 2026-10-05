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

## Controls
| | |
|---|---|
| WASD / Shift / Ctrl / Space | move / sprint (7 s stamina) / crouch (silent) / jump |
| E (hold for some) | pick up, use, manual bulkhead override (loud) |
| LMB / RMB | use held item (toggle light; held equipment → equip it) |
| F or MMB | scan (needs Scanner equipped) |
| 1–6, wheel | select slot |
| Q / C | drop item / drop equipment |
| Esc | release mouse / leave terminal |
| R | restart after game over |

## Code map (`src/`)
- `data.gd`: **all content** (scrap, items, prices, facility themes, weather). Make it yours here.
- `main.gd`: game state, day clock, travel, shredder, terminal commands, lighting.
- `level.gd`: a station (surface, elevator, facility, spawns) or the checkpoint.
- `facility.gd`: procedural room-grid generator plus monster pathing.
- `player.gd`, `hud.gd`, `terminal.gd`, `pickup.gd`, `roomba.gd`, `pulsator.gd`, `build.gd` (box helpers), `sfx.gd` (synthesized sounds).

## Tests
```
tests/run.sh 60 --headless --path . -s tests/check.gd     # logic: terminal, generator, data
tests/run.sh 240 --headless --path . -s tests/smoke.gd    # plays a full assignment headless
tests/run.sh 120 --path . -s tests/shots.gd -- /tmp/shots # screenshots (opens a window)
```
`run.sh` adds a hard timeout, because macOS has no `timeout` command.
