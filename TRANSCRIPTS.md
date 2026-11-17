# KAGE: Ninja of the Wind · Build session transcripts (reconstructed)

> **Read this first.** These are **not raw logs**. The original Kiro Crew chat
> history was not kept in the project; `.haze/` holds only empty
> blackboard/ledger tables. These transcripts were **reconstructed from the code
> base**: the two `HANDOFF.md` files, `README.md`, the module layout in `src/`
> and `legacy/src/`, the test drivers, the leftover probe/trace files in
> `legacy/build/`, and the bug lists the agents left behind. The user quotes in
> Session 3 are copied from `HANDOFF.md`. Everything else is paraphrased, and
> agent dialogue is condensed. File names, numbers, bugs and fixes match what is
> in the repository.

**Team (Kiro Crew)**
- **team-lead**: owns the goal, splits it into work-ledger items, writes `HANDOFF.md`.
- **worker-art**, **worker-world**, **worker-player**, **worker-ui**, **worker-audio**: dispatched `kirocrew-worker` sessions, one per work item.
- **verifier**: an acceptance check that runs the headless test drivers before an item counts as done.
- **Subagent 1** (named in `HANDOFF.md` §2): a cloud worker that built a Linux TIC-80 + Xvfb window rig for screenshots.

---

## Session 1: Legacy side-scroller, first slice

**User:** Make a 2.5D open-world ninja platformer in TIC-80, fantasy anime Japan. 8 regions, sky islands, an underworld. Run, variable jump, double jump, air dash, wall jump, katana, kunai, bosses, shrines. Verify everything inside TIC-80. Don't assume it works.

**team-lead:** Scope agreed: **KAGE: Ninja of the Wind**, Lua, TIC-80 Pro 1.3.1 (`b1586e2`). Before writing game code I'm probing the emulator so we know what it actually does.
> probe: `tic80 cart.lua --cli --skip --volume=0` runs headless, `trace()` goes to stdout, `exit()` quits.
> probe: 442 fps with 100 sprites, 228 fps with 700. Plenty of headroom.
> finding: `--cli` does not draw. Logic can be tested headless; art needs a window.

Ledger items:
1. `legacy/src/01_core.lua` + `02_palette.lua` → worker-art
2. `03_art.lua`, `04_terrain.lua`, `05_props.lua`, `06_chars.lua` (all art procedural, no asset files) → worker-art
3. `07_world.lua`: 240×136 map, 8 regions, caves, sky islands → worker-world
4. `tools/build.sh`, `tools/test.sh`, `tools/preview.sh` → team-lead

**worker-world:** Adding `07_world.lua` fails at load:
```
too many local variables (limit is 200) in main function
```
A TIC-80 cart is one Lua chunk, so the art modules' locals pile up in one function.

**team-lead:** Wrap modules 02–06 in `local function buildArt()`. Hoist only the handles later modules need: colour names `V,K,B,…`, `T`, `BIOME`, `genTerrain/genProps/genChars`, `blk16`, `palApply`. Painter helpers stay private. I'm writing this into HANDOFF §5 as the most important structural rule.

**worker-art:** Preview shows 16×16 frames bleeding into each other. Frames were placed at stride 4, so frame 4 overwrote frame 0.
**team-lead:** Add `blk16(base, k)` (stride 2, 8 per row pair) and never hand-compute block indices. Regression test: `tests/t_paint.lua`.

**worker-world:** Two more: the player spawns inside the shrine, and no lava or sludge appears anywhere because the flood fill checked the wrong tile.
**team-lead:** `findStart()` for spawning. Replace the flood with pools along carved cave floors. Also remove the stray `rougeOr()` and `T.PINK_FALLBACK` typos that broke the atlas.

**verifier:** `t_smoke`, `t_paint`, `t_world`, `p_atlas`, `p_chars` pass.

---

## Session 2: Legacy playable slice

**team-lead:** Next items: `08_tiles.lua` collision, `09_player.lua` controller, `10_camera.lua` follow camera with region tint, `20_render.lua` parallax renderer + HUD.

**worker-player:** Ledge grab traces don't match. Running `build/trace_ledge2.lua`, `trace_exact.lua`, `trace_spawn_now.lua` (still in `legacy/build/`).
> fix: ledge detection used the foot tile, now the hand tile. `t_player` green.

**worker-art:** I can't screenshot in `--cli`. `screencapture` and synthetic keys are blocked by macOS privacy settings.
**team-lead:** Dispatching Subagent 1 to a cloud box: Linux TIC-80 1.3.1 Pro, Xvfb, xdotool, cropped screenshots (`~/tic/run.sh`). Locally, `p_verify.lua` checks framebuffer output.

**verifier:** `t_tiles`, `t_player`, `t_game`, `p_verify`, `qa_tic_api` pass.

**team-lead (handoff):** Movement, camera, render, HUD and lifecycle are verified. Not done: entity spawner (`World.spawns` has 93 unread records), enemies, combat, pickups, menus, save, audio, water. Written to `legacy/HANDOFF.md` §9–§10.

---

## Session 3: The remake. "Don't Starve meets BotW"

**User:** *"layout like Don't Starve"* … *"ninja Japanese setting, with jumping isometric mechanics, a hybrid of Zelda BotW and Don't Starve, RPG"*. Enemies, quests, cities, NPCs.

**team-lead:** This needs a different renderer, so it's a rewrite rather than an extension. The side-scroller moves untouched to `legacy/`, and nothing new depends on it. New layout is `src/00_head.lua` … `80_main.lua`, concatenated in lexical order by `tools/build.sh`, skipping `_*.lua`. Before choosing the renderer I'm probing `ttri`:
> 1. `texsrc=0` addresses one 128×256 texture: tiles at v 0–127, sprites at v 128–255. Pixel-exact with integer coords.
> 2. Passing z enables a **depth buffer**: strict `<`, chromakey texels write no depth, `cls()` clears it.
> 3. The palette map at `0x3FF0` applies to `ttri` too, so hit flashes and recolours are free.
> 4. `texsrc=1` wraps at 1920×1088.
> 5. 2000 small `ttri` ≈ 4.9 ms. Affordable.

Decision: a real 2.5D scene. Orthographic rotatable iso camera (yaw 45°, Q/E rotate in 45° steps, pitch 0.66 rad), heightfield terrain of 8×8 cells with cliffs, 3D models for buildings, billboards for characters, and everything z-buffered so nothing needs painter's sorting.

Ledger (dispatched in parallel):
| item | worker | files |
|---|---|---|
| palette, gfx, procedural atlas | worker-art | `02_pal` `03_gfx` `04_tiles` `05–08_art_*` |
| continent + towns | worker-world | `10_world` `11_build` `12_objects` `13_towns` |
| renderer | team-lead | `20_render` |
| player physics | worker-player | `40_ent` `41_player` |

**worker-world:** World gen is deterministic at boot: one 240×112 continent plus Onigashima, 8 regions (Sakura Vale, Whispering Bamboo, Kyo Plains, Mount Fuyu, Haunted Wood, Minato Coast, Kappa Marsh, Onigashima), rivers, Great Lake, roads, bridges, 5 towns + Kurodera, 6 pagodas, 8 shrines. About 230 ms.

**worker-player:** BotW kit done: sprint, jump, double jump, kite glide, climb any cliff or wall, swim with stamina, fall damage above 46 units, 3-hit combo, plunge, shuriken. `tests/t_climb.lua` climbs a pagoda headless.

**verifier:** `t_smoke`, `t_world`, `t_climb` pass. `shot_world` renders 7 camera views + world map to `build/shots/`.

---

## Session 4: Survival, RPG and UI

**team-lead:** Dispatching:
- worker-player → `42_enemy` (14 camps), `47_proj`, `48_boss` (Jorogumo, Tengu Lord, Orochi, Shuten-doji)
- worker-world → `35_items` (crafting, recipes, shops), `36_interact`, `43_npc`, `44_quest` (6 main + 9 side quests)
- worker-ui → `45_clock` (DS day clock, darkness, the Yami, cold), `46_fx` (weather), `50_ui`, `51_menu`, `61_save`, `70_game`

**worker-ui:** Bank-1 HUD: colour 0 is transparent there (`0x3FF8` = 0), so black text vanished. Use `C_NIGHT` for black on the HUD bank.

**worker-art:** The sprite atlas is nearly full (skyline at y 249/255). Variants must be palette maps, not new sprites.

**worker-ui:** Text carts without a `-- <PALETTE>` section open all black in the editors. `build.sh` now appends one generated from `Pal.base`. TIC-80 ends code at the first line starting with `-- <`, so that section must stay last.

**worker-ui:** itch.io page assets: `tests/shot_itch.lua` renders cover, banner, background and 9 screenshots to `itch/`, plus a description and tags.

---

## Session 5: Audio and the bug sweep

**team-lead:** Last big item: `src/60_audio.lua`. Nobody can hear the headless runs, so audio has to be checked by measurement.

**worker-audio:** Instruments from poked waveforms (koto, shakuhachi, taiko, shamisen, fue). Code-driven sequencer, 7 looping tracks (title, field, night, snow, town, oni, boss). Main theme in the Yo scale, In scale at night. 40 SFX on channel 3, 3 jingles. `t_audio.lua` captures the sound registers; `tools/audio.py` re-synthesises them to MP3 and piano rolls. Levels balanced by A-weighted measurement.

**User:** There's no sound in the windowed game.

**worker-audio:** Found it. The old runner passed `--volume=0`, and TIC-80 saved that into `options.json` on exit, which muted the user's windowed TIC-80. Volume restored to 15 and the flag removed from `tools/test.sh`. Never pass `--volume`.

**team-lead:** Adding full-play drivers. `t_quests.lua` plays the main story and all side quests; `t_reach.lua` climbs to every kodama and orb; `t_title.lua` covers start-up.

**verifier:** These drivers found:
- Title screen crashed on frame 1 (`P` was nil in `Shrine.drawOrbs` and `Light.collect`).
- `package` quest stepped back to step 0 and crashed the NPC marker.
- Quest parcel vanished with a full bag (`Inv.add` → `Drops.give`).
- Finale music overridden by `Music.region()`.
- Dojo-roof kodama unreachable (`frontObject` compared against the eave height).
- Spire orbs buried inside pillars (`s.top` now uses `spire()`'s return value).

**User (playtest screenshot):** I'm stuck in the water, and I can't cut the bamboo in the first quest.

**worker-player:** Banks one step high can now be swum onto, and X leaps out of the water. Every weapon chops wood now (1.5× hits without a hatchet, 2× for bamboo with the bokken). Tall plants lean, wobble and topple (`World.chop`, `World.fell`).

**worker-ui:** UI polish from the same screenshot: tab hint overlap, stats line crossing the divider, the quest list now scrolls, the cooking list is clipped, dialog paging, shop label overlap, compass label over the ryo counter, toasts over the crafting tabs. `shot_ui` guards them.

**verifier:** `t_smoke t_audio t_climb t_title t_quests t_reach t_world shot_ui` all pass. `kage.lua` rebuilt.

**team-lead (handoff):** Next: a real playtest with sound (needs a human), spire ring spacing, standing on trees, atlas space. Written to `HANDOFF.md` §7.

---

## Session 6: Publish

**User:** Write transcripts of the sessions, then deploy a playable HTML build to GitHub.

**Kiro:** Reconstructed this file from the code base. Exported the cart with TIC-80 Pro (`load kage.lua & export html`), created the repo, and published the HTML build to GitHub Pages.
