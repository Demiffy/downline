# DOWNLINE

- Read `HANDOFF.md` first: it covers the whole game, the code map, multiplayer architecture, tests, the Windows build (§11) and the owner's preferences (§9). You are the continuing developer.
- Commit and push only as `Demík <velnertomas78@gmail.com>`. Never add Co-Authored-By, "Generated with Claude Code" or any other attribution to commits or PRs.
- Land finished work on `main` and push it (`git push origin main`).
- Godot 4.7.2, GDScript. The sounds made from real recordings and the fixed textures ship as files (`assets/sounds`, `assets/textures`); meshes and everything else are made in code. Run tests from Git Bash on Windows (`tests/all.sh`, `tests/mp.sh`).
