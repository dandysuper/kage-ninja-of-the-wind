# KAGE — Ninja of the Wind · Engineering Handoff (2.5D open-world remake)

Read this before touching code. It records what exists, what is verified, what is
not, the conventions the code depends on, and the next tasks in priority order.

---

## 0. TL;DR for the next agent

State after the audio session (all verified headless, see §3):

- **Audio is done** (§8): 40 SFX + 3 jingles, and a code-driven music sequencer
  with 7 looping tracks (title, field, night, snow, town, oni, boss), region /
  time / battle aware, with Music and Sound volume options in the System tab.
  It has **never been heard through a real window**: levels were balanced by
  A-weighted measurement of a faithful re-synthesis (`tools/audio.py`).
- `kage.lua` in the project root is rebuilt and boots to the title screen. The
  title screen used to crash on frame 1 (nobody had run it since the remake);
  fixed, and `tests/t_title.lua` now covers the real start-up flow.
- `tests/t_quests.lua` plays the whole main story (4 bosses, finale) and all 9
  side quests; `tests/t_reach.lua` climbs to every kodama and spire orb. They
  found and fixed 5 bugs (§7).
- Run every driver before handing off:
  `for t in t_smoke t_audio t_climb t_title t_quests t_reach t_world shot_ui; do sh tools/test.sh tests/$t.lua 300; done`

Next, in order: a **real playtest with sound** (needs a human, §7 item 1), then
the design questions in §7.

---

## 1. What this project is

The user asked for a remake of their side-scrolling ninja platformer into a
**2.5D open-world RPG**: *"layout like Don't Starve"*, *"ninja Japanese setting,
with jumping isometric mechanics, a hybrid of Zelda BotW and Don't Starve, RPG"*,
with enemies, quests, cities and NPCs.

What was built (all in `src/`, Lua 5.3, TIC-80 Pro 1.3.1):

- **Renderer**: real 2.5D scene — orthographic, rotatable isometric camera
  (default yaw 45° = diamond iso; Q/E rotate in 45° steps, smoothly), pitch 0.66
  rad. Terrain is a heightfield of 8×8-unit cells with cliffs; buildings, pagodas,
  castle and torii are 3D models; characters/trees/props are billboards. Everything
  is drawn with **z-buffered `ttri`**, so no painter's sorting anywhere.
- **World**: one 240×112-cell continent + the separate Onigashima island, 8 regions
  (Sakura Vale, Whispering Bamboo, Kyo Plains, Mount Fuyu, Haunted Wood, Minato
  Coast, Kappa Marsh, Onigashima), rivers, the Great Lake, roads with bridges,
  5 towns (Hanamura, Kyo with castle and walls, Yukimura, Takemura, Minato) +
  Kurodera temple, 6 climbable pagoda towers, 8 spirit shrines, ~18 kodama,
  ~15 chests, 14 enemy camps, 4 boss arenas. Generated deterministically at boot
  (~230 ms).
- **Player (BotW)**: walk, sprint (SHIFT/C), jump (X), double jump (after the
  Jewel), kite glide (hold X in air, after quest 1), wall climbing on any cliff or
  building (push into it; X = leap), swimming with stamina, fall damage, stamina
  wheel with exhaustion, 3-hit katana combo, plunge attack (Z in air), shuriken (S),
  standing on rocks/stumps/rooftops.
- **Survival (Don't Starve)**: hunger, hearts (quarter hearts), DS day clock, night
  palette tint + **DS darkness** (black outside light, dithered rims; after ~4 s in
  the dark "the Yami" hurts you), torches/lanterns/campfires, cold on Mount Fuyu
  (fur cloak / warm food / fire), rain/snow/petal/firefly weather, harvest and
  regrowth, crafting with DS-style tabs, campfire + cooking-pot recipes, shops,
  inns (sleep to dawn, heal, save), death → respawn losing ¼ ryo.
- **RPG**: 15 quests (6 main: recover the Three Sacred Treasures from Jorogumo,
  the Tengu Lord and Orochi, then defeat Shuten-doji on Onigashima; 9 side),
  NPC dialogue with "!"/"?" markers, objective compass + map pin, pagoda survey =
  map reveal + fast travel, spirit-shrine trials → orbs → Kannon statue upgrades
  (heart / stamina), kodama seeds → Ponta the tanuki enlarges the bag.
- **UI**: HUD on VRAM bank 1 (hearts + tracked quest top-left, DS clock + hunger
  badge + ryo top-right, crafting tabs left, hotbar + W/A/L equipment bottom,
  stamina wheel by the ninja, interaction prompts, toasts, banners, region names,
  boss bar); pause menu tabs Items / Craft / Map / Quests / System; cook and shop
  screens; title screen with orbiting camera; death and finale screens; pmem save.
- **Audio** (§8): koto / shakuhachi / taiko / shamisen / fue instruments built
  from poked waveforms; a main theme in the Yo scale that turns into the In scale
  at night and on the title; a matsuri town tune; an In-scale battle track; 40
  effects on channel 3; quest / tower / victory jingles that pause the music.

The previous side-scroller is preserved untouched in **`legacy/`** (its own
`HANDOFF.md`, `src/`, `tests/`, `tools/`, `kage.lua`). Nothing in the new game
depends on it.

---

## 2. Environment — verified facts

| Thing | Value |
| --- | --- |
| Project root | `/Users/danb/Documents/ninja game` (not a git repo) |
| Emulator | `/Applications/TIC-80 Pro.app/Contents/MacOS/tic80`, **1.3.1 Pro** |
| Lua | 5.3 (integer `//`, bitwise ops available) |
| Python | `python3` 3.13 with PIL (`tools/frames.py`) and numpy (`tools/audio.py`) |
| Audio tools | `lame` and `ffmpeg` in `/opt/homebrew/bin` (MP3 previews) |
| Code size | No practical limit hit: the old cart was 140 KB; the new one is ~330 KB of source |

On this Mac, **synthetic keystrokes and `screencapture` are blocked** by macOS
privacy settings, so everything is verified headless with `--cli`, where drawing
still happens into VRAM and is read back (see §3).

**Never pass `--volume` to tic80** (the old runner used `--volume=0`). TIC-80
writes its options, including an overridden volume, to
`~/Library/Application Support/com.nesbox.tic/TIC-80/.local/b1586e2/options.json`
on exit, so one headless run muted the user's windowed TIC-80 for good. `--cli`
opens no audio device, so the flag is useless there anyway. `legacy/tools/*.sh`
still pass it; don't run them as they are.

Empirically verified TIC-80 behaviour (probes in this session, all on 1.3.1):

1. `ttri` with `texsrc=0` addresses **one 128×256 texture**: tiles 0–255 at
   v 0–127, sprites 256–511 at v 128–255. Pixel-exact 1:1 when screen coords are
   integers (with or without z).
2. Passing `z1..z3` enables a **depth buffer**: test is strict `<` (smaller z =
   nearer; an equal-depth second draw loses), **chromakey-transparent texels do not
   write depth**, `cls()` clears it, precision is fine even at z ≈ 1e6.
3. The **palette map** (`0x3FF0`, nibble address `0x7FE0`) is applied at draw time
   by both `spr` and `ttri` → per-sprite recolours, white hit-flashes and
   silhouettes are just palette maps (`Pal.remap/solid/reset`).
4. `texsrc=1` (map) wraps at 1920×1088 (negative u wraps too).
5. VRAM bank 1 transparent colour = index **0** (`0x3FF8` = 0) → on the HUD
   bank, colour 0 is invisible; use `C_NIGHT` for "black".
6. `key()` works with no `-- input:` line; Z/X/A/S still drive `btn(4..7)`.
7. `trace()` does **not** append a newline in `--cli` logs — add `"\n"`.
8. A text cart without a `-- <PALETTE>` section loads with an all-black palette;
   the game pokes its palette in `BOOT`, so in-game colours are right, but the
   built-in editors will look black (see §7, item 6).
9. Speed (`--cli`, this Mac): 2000 small `ttri` ≈ 4.9 ms, a full-screen map
   quad ≈ 0.35 ms, 100k Lua `sin` loop ≈ 4.4 ms.

A Linux build of TIC-80 1.3.1 Pro with a scripted window rig (`~/tic/run.sh`:
Xvfb + xdotool keys + cropped screenshots) exists on the cloud machine of
Subagent 1 of the thread that wrote this. It is optional; another thread may not
be able to reach it.

---

## 3. Tooling

```sh
cd "/Users/danb/Documents/ninja game"
sh tools/build.sh                          # src/*.lua -> kage.lua (playable cart)
sh tools/test.sh tests/t_smoke.lua 150     # headless run; 150 s watchdog
sh tools/test.sh tests/shot_world.lua      # renders 7 camera views + world map
sh tools/test.sh tests/shot_sheet.lua      # sprite atlas, ninja frames, mobs, icons
sh tools/test.sh tests/t_audio.lua 300     # audio checks + sound register capture
python3 tools/audio.py build/t_audio.log build/audio   # -> mp3 previews + piano rolls
```

- `build.sh` concatenates `src/*.lua` in **lexical order**, skipping files that
  start with `_`. All modules share **one Lua chunk**. The playable cart ends with
  a `-- <PALETTE>` section generated from `Pal.base` (§7). TIC-80 ends the code at
  the **first line starting with `-- <`**, so that section must stay last and no
  source line may start with `-- <`; `--code-only` skips it (`test.sh` uses this
  because it appends the harness after the build).
- `test.sh <driver>` builds `build/<name>.cart.lua` = all modules +
  `tests/_harness.lua` + the driver (appended last, so a driver may redefine
  `TIC`), runs `tic80 --cli --skip`, writes `build/<name>.log`,
  converts framebuffer dumps to `build/shots/<tag>.png` (3× scale), prints the
  log tail, and **exits non-zero** on a Lua error or any `FAIL` line.
- Harness API (`tests/_harness.lua`): `Test.log(s)`, `Test.ok(cond, msg)`,
  `Test.dump(tag)` (composites bank 0 + bank 1 with their own palettes),
  `Test.finish()` (summary + `exit()`).
- Input injection: set `In.fake = { up = true, atk = true, ... }` before
  `Game.tick()`; action names are in `src/01_core.lua` (`ACTIONS`).

Existing drivers:

| File | Purpose | Last result |
| --- | --- | --- |
| `tests/t_smoke.lua` | Boots the real game, new game, scripted walking/jumping/combo/throw, opens every menu tab, crafts a torch through the menu, climbs the pagoda, cycles the Music volume option in the System tab, night with torch, combat vs bandit+wolf+oni, then ~2700 frames of random-input fuzzing with random teleports and times of day | **PASS** 6/6, 3600 frames, avg 3.5–4.5 ms (fuzz is random; audio costs 0.003 ms/frame) |
| `tests/t_title.lua` | The real start-up flow t_smoke skips: title screen + title music, Controls panel, New Game through the menu, intro dialog, a few seconds of play, music fades to the region track | **PASS** 10/10 |
| `tests/t_audio.lua` | Audio data checks (all names defined, song data valid, waveforms in RAM, region → track mapping, priorities, volume levels in pmem), then records the 4 sound registers every frame for every effect, jingle and track (+ jingle-over-music and crossfade cases) | **PASS** 68/68, 30k frames in ~2 s |
| `tests/t_quests.lua` | Scripted playthrough of the main story (mq1 → mq2 → the 3 treasure bosses → mq4 → Shuten → finale) and all 9 side quests with an invulnerable ninja; each boss AI runs 15 s against him, its height is checked against the katana's reach, then it is finished with `Enemy.hurt`. Includes full-bag and empty-handed turn-in regressions | **PASS** 117/117 |
| `tests/t_reach.lua` | For every kodama and spire-trial orb: start 2.5 cells away with full (unrefilled) stamina, hold toward it from up to 4 sides, stand on top and collect | **PASS** 23/23: all 19 kodama and 4 orbs, ≤ 136 frames, ≥ 70 stamina left |
| `tests/t_climb.lua` | Walk into the Hanamura pagoda, climb it, let go, check he stays on top | **PASS** 2/2 (on top at frame 55) |
| `tests/t_world.lua` | Real inputs: swim onto a bank 4 high, X-leap out of the water onto a bank 8 high, chop a tree with the starting bokken (6 hits, lean grows, falls, stump, wood collected), bamboo with the bokken (4), a tree with a hatchet (4) | **PASS** 25/25 |
| `tests/shot_ui.lua` | **UI lint**: renders every screen with worst-case content (16-slot bag, 99999 ryo, 12 hearts, all quests, toasts + banner, long dialog, every menu tab and craft category, cook/pot, every shop, death, finale, title + controls) and records each `print`/`rect`/`rectb`/divider on vbank 1. FAILs on text off screen, text overlapping text, or text crossing a box border or divider (draw order aware: text later covered by an opaque fill is ignored). Screens in `build/shots/ui_*.png` | **PASS**, 0 issues |
| `tests/shot_world.lua` | Camera views of village (3 yaws), paddies, bamboo, Fuyu, coast + 1 px/cell world map | Renders correctly |
| `tests/shot_sheet.lua` | Atlas usage + art contact sheets | Atlas fits (max y 249 of 255) |

Screenshots of the last good runs are in `build/shots/` (`t01_title.png`,
`s01_start.png`, `s06b_system.png`, `s08_night.png`, `icons.png`, `worldmap.png`,
…). Audio previews from the last `tools/audio.py` run are in `build/audio/`
(`music_*.mp3`, `jingle_*.mp3`, `sfx_tour.mp3`, piano-roll PNGs, `report.txt`).

Headless gotcha: a cart without `exit()` (like `kage.lua`) keeps running after
you stop waiting for it, and `tic80 --cli` ignores SIGTERM. Kill it with
`kill -9 <pid>` or stray emulators will skew later timings.

---

## 4. Source layout

```
src/00_head.lua       cart metadata + controls summary
src/01_core.lua       math locals, hash/value noise/fbm, In (input actions), misc
src/02_pal.lua        16-colour palette (C_* names), bank tint, palette-map helpers
src/03_gfx.lua        sset/sget, skyline atlas packer (Gfx.add/addfn -> Gfx.flush),
                      Gfx.icon (8x8 icons into free map-tile slots), blit()
src/04_tiles.lua      T (ground tile ids), BAND (wall texture bands), procedural
                      tile painters, Gfx.fillBands, Gfx.animTiles (liquids)
src/05_art_chars.lua  ninja frames (side/front/back, slash, jump, glide, climb, swim)
src/06_art_world.lua  trees (procedural), rocks, plants, props, FX, wall decals
src/07_art_items.lua  8x8 item + UI icons
src/08_art_mobs.lua   NPCs and enemies
src/10_world.lua      W.gen: regions, heights, rivers, lake, tiles, roads, commit
src/11_build.lua      materials (MAT/TMAT), buildings, gable/hip roofs, pagodas,
                      castle, torii, wall decals, Build_roofH
src/12_objects.lua    OBJ table (static objects), setObj, biome scatter
src/13_towns.lua      all towns, temple, boss arenas, shrines, kodama, chests,
                      enemy camps, signposts, POIs, NPC spawn list
src/20_render.lua     Cam, proj(), chunk meshing + cache, model/billboard/ground
                      decal drawing, Render.world
src/30_boot.lua       Boot.graphics / Audio.init / Boot.world
src/35_items.lua      ITEM, Inv, Craft/RECIPES, POT recipes, SHOPS
src/36_interact.lua   World.hit (harvest with tools), World.interact (A), regrowth,
                      campfire burn-out, placing objects
src/40_ent.lua        entity list, groundAt, Ent.resolve (push-out collision),
                      Ent.physics, Ent.view (screen-relative facing), shadows
src/41_player.lua     Player controller, combat, interaction, x-ray silhouette draw
src/42_enemy.lua      ETYPE, enemy AI, camps + spawn director (wildlife/yokai)
src/43_npc.lua        NPC kinds/recolours, wander, talk, shops/inns, tanuki, cat
src/44_quest.lua      QUESTS data, quest state machine, markers, compass target,
                      pagoda survey
src/45_clock.lua      day/night, tint keys, hunger/cold/dark survival, Light
                      collection + DS darkness overlay
src/46_fx.lua         particles, slash arcs, floating text, shake, hit-stop
src/47_proj.lua       projectiles, item drops (magnet pickup), Drops.give
src/48_boss.lua       4 bosses, sealed bridge, spirit shrines, Kannon statue
src/50_ui.lua         text helpers, toasts, banners, Dialog, HUD
src/51_menu.lua       pause menu, cooking, shop, world map + fog + fast travel
src/60_audio.lua      waveforms, instruments, effects and songs as data; poked
                      into sound RAM by Audio.init; Sfx / Music / jingles (§8)
src/61_save.lua       pmem save/load
src/70_game.lua       game states, frame pipeline, camera, weather, sleep, travel
src/80_main.lua       BOOT / TIC (must stay last)
```

### Rules the code depends on

- **One chunk, chunk-level locals leak forward.** A `local X` at module top level
  is visible to every later module and **shadows globals of the same name**. This
  already bit once: `20_render.lua` had `local P = proj`, which hijacked the global
  player `P`; it is now `PRJ`. Before adding a top-level local, grep for the name.
  Lua's 200-locals-per-function limit applies to the whole chunk — modules expose
  tables (`Render`, `Enemy`, `Quest`, …) instead of many locals.
- Core locals available everywhere: `flr ceil abs sqrt sin cos atan min max PI
  TAU rnd fmt`. Globals: `clamp lerp sgn approach angdiff dist dist2 rndf pick
  chance hash2 vnoise fbm`.
- **Bank 1 (HUD) must never use colour 0** for visible pixels (transparent).
- **UI layout conventions** (`51_menu.lua`): menu panels keep a key-hint footer
  row (`footer(items, x0, x1, y, back)`, `Menu.key` draws the Z/X/A/S sprites or
  a drawn cap for any other key); content ends above its divider. Cut long names
  with `Menu.fit(s, w, small)`, scroll long lists with `Menu.scroll` /
  `Menu.scrollMarks`. While a menu or the finale is open the world is dimmed by
  scaling the bank-0 palette in `drawWorld`, never with scanlines. Dialog text
  is paginated to 4 wrapped lines per page by `Dialog.lines`. Run `shot_ui`
  after any UI change.
- **Never forward explicit `nil`s to TIC-80 API calls** (e.g. in wrappers): an
  explicit nil counts as an argument, so `print(s, x, y, c, nil, nil, nil)`
  prints at scale 0, i.e. invisibly. Wrap with `...`.
- New sprites: `Gfx.add(name, artString)` / `Gfx.addfn(name, w, h, fn)` inside an
  `Art.*` function called from `Boot.graphics`; they are packed by `Gfx.flush()`.
  Access as `SPR[name] = {u, v, w, h}`. Art strings: hex digit = palette index,
  `.` = transparent, rows separated by newlines or `|`.

---

## 5. Engine notes

### Projection (src/20_render.lua)

```
lx = dx*cos a + dy*sin a                 (screen right)
lf = dx*sin a - dy*cos a                 (into the screen along the ground)
sx = SCX + lx
sy = SCY - (lf*sin p + dz*cos p)
depth = 100000 + lf*cos p - dz*sin p     (DOFF keeps ttri's perspective
                                          correction effectively affine)
```

`Cam.a` yaw (target `Cam.ta`), `Cam.setPitch(p)`, `Cam.x/y/z` focus, `Cam.sx/sy`
shake. `proj(x,y,z)` is global; `Render.begin()` caches the trig per frame.

### World data (per cell, index `i = y*240 + x + 1`)

`WH` height (world units, multiples of 4; water = −4, drawn at −3), `WT` ground
tile (mirrors the TIC map), `WO` object id (`OBJ`), `WF` flags (`F_ROAD F_TOWN
F_ROOF F_MODEL F_BRIDGE F_NOSPAWN F_WATER F_SHALLOW F_HAZ`), `WR` region, `WM`
side-material override, `WB` building id. Map rows **112–135 are not world**:
they hold the wall/cliff texture bands (`BAND.*`) sampled by side faces.

### Terrain meshing

Per 8×8-cell chunk, lazily cached in `MESH[k]` (`k = cy*30 + cx`): greedy top
rectangles + side faces merged along edges, back-face culled by direction, tall
faces split into band-height segments (lip row only on the first). Call
`Render.invalidate(x, y)` after changing `WH` at runtime, and keep
`CHMIN/CHMAX` (chunk height bounds, `Render.chunkBounds()`) in sync.

### Buildings / models

`Build_add(kind, x, y, w, d, base, door, opt)`: footprint cells are raised to the
eave and flagged `F_ROOF` (walls = terrain side faces with `WM` material, so
collision and climbing work); the sloped roof, gables and door/noren decal are a
model polygon list (`MODELS`, indexed by chunk in `MCHUNK`). Walking on roofs
uses `Build_roofH`. Pagodas set `F_MODEL` cells (collision only, no terrain
faces). Polygon winding: clockwise on screen = front face.

### Billboards & depth

`Render.bill(rect, x, y, z, flip, pm, scale, bias)` draws a screen-aligned quad
whose top vertices get the true depth of a vertical object (`d - h/cos p *
sin p`), so tall sprites are correctly occluded by cliffs. The player is drawn
twice: a flat silhouette without depth, then the real sprite with depth → x-ray
outline when hidden behind terrain.

### Physics

`groundAt(x, y)` = cell top, sloped roof, or the top of any solid object cylinder
(`OBJ.r/h`). `Ent.resolve(e)` pushes the body circle out of cells taller than
`z + step (4.5)` and out of cylinders — robust sliding, no ledge sticking.
`Ent.physics(e)` = velocity + resolve + gravity (0.22) + ground snap. Jump
velocity 2.62 → ~15.4 units peak; double jump 2.45.

---

## 6. Content map (for quests and testing)

POIs (`POI.<name>`, world units): `start`, `hanamura`, `dojo`, `paddies`, `kyo`,
`castle`, `yukimura`, `onsen`, `takemura`, `minato`, `docks`, `temple`, `lair`
(Jorogumo), `summit` (Tengu Lord), `lake` (Orochi; stepping stones from the west
shore at cells 163–172, 72–73), `onigashima` (Shuten-doji), `bridge` (sealed
until `mq4` step 2), `cat` (Tama, quest "cat").

Quest ids: main `mq1 mq2 jewel mirror sword mq4`; side `rice cat bounty tea pelts
kappa package silk spirits`. NPC ids used by quests: `sensei farmer mei captain
teamaster tailor fisher merchant inn_yuki woodcutter abbot lady`.

Save format (`src/61_save.lua`, `pmem`): 0 magic `0x4B470002`; 1–19 player stats,
clock, equipment, spawn; 20–35 inventory (`itemIndex*1000 + count`, items sorted
by id); 36–51 quests (`state + step*4 + count*256`); 56 towers, 57 shrines,
58 bosses, 59 kodama, 61 chests (bitmasks); 62 tracked quest; 70–122 map fog
bits. Harvested objects are not saved (they regrow on load).

---

## 7. Known issues / TODO (priority order)

1. **Real playtest in a window, with sound** (needs a human: synthetic keys and
   screen capture are blocked on this Mac). Feel of jump/climb/glide, combat
   timing, camera rotation; tune `WALK RUN JUMP_V GRAV`, enemy `windup/cd/dmg`,
   hunger rate (`Clock.survival`), day length (`Clock.len` = 6 min), fall damage
   threshold (46 units). **Listen** to the mix in game: music vs effects levels,
   how often enemy "growl" telegraphs fire, the dialog "blip" rate. Every value
   is in the data tables at the top of `src/60_audio.lua`.
2. **Spire trials are a climb, not a jump course.** Consecutive pillars of a
   shrine ring are ~42 units apart, more than a running jump (~38) and gliding
   can't gain height, so the intended route is just "climb the tallest pillar"
   (always possible, `t_reach`). Shrink the ring radius in `shrine()`
   (`13_towns.lua`, `* 6` / `* 5`) if pillar-hopping is wanted.
3. Objects with collision cylinders can be stood on, including tree trunks
   (h = 60): the ninja can end up perched on a tree after a fall. Either keep it
   as a ninja feature or exclude trees from `groundAt` tops.
4. **Sprite atlas is nearly full** (skyline max y 249/255, all free tile slots used
   by icons). Before adding art, reclaim space (fewer frames, palette-map variants
   instead of new sprites, smaller sprites).
5. Nice-to-haves: minimap, more NPC dialogue variety, weapon visuals in the ninja's
   hand, more enemy attack frames, interiors,
   weather ambience (rain/wind) on a spare channel, per-region field variants
   beyond snow/oni.

Fixed and verified in the audio session (kept here so nobody re-investigates):

- **No sound in the windowed game**: the old test runner's `--volume=0` had been
  saved into TIC-80's `options.json` (see §2). Volume restored to 15, flag removed.
- **Stuck in water**: swimming only exited onto banks at most 1.5 above the water.
  Now banks one step high (4) can be swum onto, and **X leaps out of the water**
  (1.1x jump, enough for banks 8 high; leaping at a taller cliff grabs it).
- **Trees could not be cut** without a hatchet, and bamboo not with the starting
  bokken, which made the opening quest's "cut bamboo with Z" impossible. Every
  weapon now chops wood: without a hatchet trees take 1.5x hits (6 instead of 4)
  and the bokken needs 2x for bamboo; rocks still need a pickaxe. Tall plants
  (h >= 40) lean further with each hit and wobble (`World.chop`, drawn with
  `Render.billRot`), then topple away from the player (`World.fell`, a 27-frame
  `kind = "fx"` entity) and drop their loot when they land.
- Bank-1 colour fix: the Map tab fog is opaque (`build/shots/s05_map.png`).
- **Title screen crashed on frame 1** (`P` nil in `Shrine.drawOrbs` and
  `Light.collect`); the orb cull now uses the camera focus and the player light
  is skipped without a player. Covered by `t_title`.
- **Quest crash**: talking to a turn-in NPC without the items stepped the quest
  back unconditionally; for `package` (turn-in is step 1) that made step 0 and the
  NPC marker indexed a nil step every frame. Now it only steps back onto a `have`
  step.
- **Lost quest item**: a quest's starting item (`give`, the parcel) went through
  `Inv.add` and vanished with a full bag. It now uses `Drops.give`, which drops
  the overflow at your feet.
- **Finale music**: `Boss.onDeath` called `Music.region()` after the finale had
  started; `Music.region()` now keeps the title theme during the finale.
- **Dojo-roof kodama could not be collected**: `frontObject` compared the
  player's z with the cell's eave height instead of the roof surface the
  kodama is drawn on.
- **Spire-trial orbs sat at the plaza base + pillar height** instead of on the
  pillar (8-20 units inside three of the pillars, 4 above the Tide one); `s.top`
  now uses `spire()`'s return value.
- **UI polish** (from a playtest screenshot): the "Q/E tabs  X back" hint was
  printed over the System tab and spilled onto the world; the Items stats line
  crossed the divider; the quest list never scrolled (quests 14-16 unreachable
  on screen); the cooking list grew out of its panel; long dialog text was cut
  after 4 lines; long shop names hit the Buy/Sell label; the quest arrow's
  distance label landed on the ryo counter; toasts covered the crafting tabs;
  menus dimmed the world with scanlines. All fixed; `shot_ui` guards them.
- `t_climb` lets go at the top; the 9 icons with malformed rows (`cmeat fish gfish
  sushi tea axe cloak magatama pin`) are 8x8 again; the cart has a `<PALETTE>`.

---

## 8. Audio (src/60_audio.lua)

Everything is generated in code at boot; the cart has no binary sound sections.
`Audio.init()` (called by `Boot.all`) pokes 16 waveforms and the SFX slots, then
compiles the songs. The module wraps its internals in `;(function() ... end)()`
so it adds **no chunk-level locals** (the chunk is near Lua's 200-local limit).

### API (unchanged signatures)

- `Sfx.play(name)`: names in `Sfx.NAMES`. `complete`, `tower` and `victory` are
  **jingles**: multi-voice phrases on channels 0-2 that pause the music, then it
  resumes where it stopped; a jingle requested while one plays is queued (max 2).
  All other effects play on **channel 3** with a priority (1 UI ticks, 2 normal, 3
  important, 4 death): a lower priority effect does not cut a higher one that is
  still sounding, and the same effect is not restarted within 3 frames.
- `Music.play(track)`: `title field night snow town oni boss`, nil = stop. Same
  track = no-op; `boss` and nil switch at once; otherwise the old track fades for
  40 frames (held flute notes get their release) and the new one starts.
- `Music.region()`: finale → title; boss alive or shrine trial → boss; night or
  Haunted Wood → night; town → town; Onigashima → oni; Mount Fuyu → snow; else
  field (`REG[r].music` picks the region flavour).
- `Music.update()`: once per frame from `Game.tick` (sequencers + effect timers).
- `Audio.setLevels(music, sfx)`: 0-3 (Off / Low / Mid / High), stored in
  **pmem slot 255** (`0xA0D << 8 | m | s << 2`), separate from the save game.
  Exposed as "Music volume" / "Sound volume" in the System tab (Z cycles).

### Data formats

- **Waveforms** (`WAVES`): built from harmonic recipes (`harm({1, .5, ...})`).
  Slot 0 = all 0 = white noise, slot 1 = all F = metallic short-LFSR noise.
- **Instruments** (`INST`, SFX slots 0-14) and **effects** (`SFXD`, slots 16-55)
  share one format: per-tick strings `v` loudness 0-f, `w` waveform, `a`
  arpeggio semitones, `p` pitch (0-7 up, A-H = -1..-8; steps of 1 Hz, or 16 Hz
  with `x`), plus `s` speed (-n = n+1 frames per tick), `r` reverse arpeggio,
  `loop = { v = { start, size } }`. Effects add `note` (57 = A4), `vol`, `pri`,
  `jit` (random +-semitones per play). An effect's length is derived from its
  volume envelope. Spare slots: 1, 15, 56-63.
- **Songs**: one string per voice and part, one token per step, one bar per line:
  `D4` note (`!` louder, `?` softer), `-` hold, `.` rest (a sustained instrument
  plays its release instrument), a single letter = hit from the track's kit.
  A track (`TRACKS`) picks parts, an order, frames per step, a kit, voices
  (channel, instrument, volume, octave shift, speed override, velocity jitter)
  and an optional **mode** remap: `IN = { E -> Eb, B -> Bb }` turns the Yo-scale
  theme into the In scale (night, title). Songs are checked at init: wrong part
  lengths, unknown kit letters and out-of-scale notes land in `Audio.errors`,
  which `t_audio` fails on.

### Music

| Track | Material | Frames/step | Notes |
| --- | --- | --- | --- |
| field | main theme, D Yo (D E G A B) | 16 (8ths, ~112 bpm) | A B A2 B2, 32 bars, 68 s; koto + shakuhachi + bass/taiko; A2 is a koto solo |
| night | theme in D In | 20 | koto with longer decay, sparse flute, furin chimes instead of taiko |
| snow | theme, Yo | 18 | koto part on bells an octave up, wind gusts and chimes |
| title | theme in D In | 18 | A B, loud taiko + kane |
| town | matsuri tune, G Yo | 13 | shamisen + fue + taiko/shime/kane; A2 = shamisen plays the tune |
| boss | battle tune, E In (E F A B C) | 7 (16ths) | shamisen ostinato + fue + driving taiko |
| oni | battle material without lead | 10 | Onigashima ambience, temple bell |

Channel plan: music 0-2 (melodic accompaniment, lead, bass + drums), effects 3.

### Verifying audio without ears

`tests/t_audio.lua` logs the 4 sound registers (frequency, volume, waveform,
stereo) every frame exactly as the emulator computed them. `tools/audio.py`
re-synthesizes them with TIC-80's own algorithm (32-step waves, the two LFSR
noises, volume x stereo / 15 / 5 per channel) into MP3 previews (boosted 3.5x;
raw TIC-80 output is quiet), piano rolls with a spectrogram, and a report.
Mix levels were set from A-weighted loudness per channel of these renders:
lead about -33 dB(A), koto 3-6 dB under, bass/drums lower; effects peak
between -20 (hits, roar) and -38 dB(A) (text blip). Verified facts (1.3.1): SFX RAM `0x100E4 + id*66`, waveforms
`0x0FFE4`, registers `0x0FF9C` (18 bytes/channel) are readable in `TIC()` one
frame after `sfx()`; note 57 = 440 Hz; `sfx()` with a **float note raises
"invalid note"** (use integers); `sfx(id, note, d)` plays d-1 frames.

---

## 9. Controls (as implemented)

| Key | Action |
| --- | --- |
| Arrows | move (camera-relative) |
| SHIFT or C | sprint (stamina) |
| X | jump · hold in air = glide (kite) · while climbing = leap · in water = leap out · menus: back |
| Z | katana combo · chop/mine/cut facing object (any weapon chops wood; a hatchet is faster, rocks need a pickaxe) · in air = plunge · menus: confirm |
| A | talk / pick up / open / cook / pray · Items tab: drop |
| S | throw shuriken · Craft tab: next category |
| Q / E | rotate camera 45° · menus: switch tab |
| TAB or I | bag + crafting menu · M map · J quests |
| 1–0 | use hotbar slot (eat, equip, light, place) |
| Enter / Space | confirm |
