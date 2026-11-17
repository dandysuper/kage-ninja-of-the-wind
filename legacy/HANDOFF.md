# KAGE — Ninja of the Wind · Engineering Handoff

Handoff for the next agent. Read this fully before touching code. It records what
exists, what is verified, what is broken, and the exact conventions the codebase
depends on. Everything here was verified on the machine this was built on; where
something is *assumed* rather than *verified* it is marked **[unverified]**.

---

## 1. What this project is

A **2.5D open-world ninja platformer** for **TIC-80**, written in Lua, themed on a
fantasy anime Japan. Working title: **KAGE — Ninja of the Wind**.

Scope agreed with the user:

- Open world: **8 regions** on a 240×136 tile map, plus **sky islands** and a
  **deep underworld**.
- A **2.5D look**: parallax background layers, pseudo-3D ("extruded cube") terrain
  blocks, depth-sorted entities with drop shadows.
- Mechanics: run, variable-height jump, double jump, air dash, wall slide/cling,
  wall jump, katana slash, kunai throw, slide/crouch, ledge grab, hearts +
  stamina, ryo coins, scrolls, spirit orbs, health upgrades, 6 enemy types with
  distinct behaviour, mini-boss + bosses, NPC dialogue, shrine save/heal, torii
  fast travel.
- Controls (documented in `src/00_meta.lua`):
  arrows = move/crouch, `Z`/`A` = jump (hold higher, tap again = double jump),
  `X`/`S` = katana (air slash while airborne), `Up+X` = throw kunai,
  `Down+Z` in air = air dash, `Up` at a shrine = rest/save/fast travel.

**Standing process requirement from the user:** verify work *inside TIC-80*, using
the headless test harness for logic and screenshot previews for art — never assume
correctness.

---

## 2. Environment — verified facts

| Thing | Value |
| --- | --- |
| OS | macOS |
| Project root | `/Users/danb/Documents/ninja game` |
| Emulator | `/Applications/TIC-80 Pro.app/Contents/MacOS/tic80` |
| Version | `1.3.1-dev Pro (b1586e2)` |
| Emulator source (for API questions) | `/Users/danb/Documents/TICPRO/src/src/tic.h` |

Verified CLI behaviour:

- `tic80 <cart.lua> --cli --skip --volume=0` runs headless and exits.
- `trace("...")` writes to stdout — this is how the headless tests report.
- `exit()` quits immediately.
- `--cli` ignores drawing, so **only logic can be tested headless**; art must be
  verified with a real window + screenshot (see the tooling scripts).
- Performance headroom is large: **442 fps with 100 sprites + rects**, **228 fps
  with 700** in `--cli`. Target is ≤8 ms of Lua per frame at 60 fps. Extensive
  per-frame drawing, particles and parallax are affordable.

**TIC-80 API facts that the codebase depends on** (each verified by experiment, not
from docs):

1. **Sprite pixel addressing.** Sprite `n` pixel `(x,y)` is nibble
   `base + n*64 + y*8 + x`, two pixels per byte, low nibble first.
   - bank 0 (sprites 0–255): nibble base **0x8000**
   - bank 1 (sprites 256–511): nibble base **0xC000**
   - `spr()` reads bank A by default; `spr(256+n)` reaches bank 1.
2. **16×16 blocks.** The sheet is 16 sprites wide, so a 16×16 block at index `n`
   covers sprites `n, n+1, n+16, n+17` — exactly what
   `spr(n, x, y, key, 1, 0, 0, 2, 2)` draws. Therefore blocks tile with a
   **stride of 2**, and only **8 blocks fit per row-pair**; block 8 must skip two
   sprite rows. `blk16(base, k)` in `src/03_art.lua` is the single source of truth
   for this. **Never compute a 16×16 block index by hand.**
3. **Palette.** This build has **no `pal()`/`palt()` helper**. The 16 RGB triplets
   live at RAM `0x3FC0` (3 bytes each) and are poked directly. Two palette banks
   exist; `vbank(1)` switches the view and read-back confirmed both banks must be
   written for bank-1 art to match. `palApply()` writes both.
4. **Map.** 240×136 tiles. `mget(240, 0)` and `mget(0, 136)` return 0 without
   error. `map()` must be called with colorkey 0 so index-0 (air) shows through.
5. **Tile flags.** `fset(id, flag, bool)` / `fget(id, flag)` work for both tile and
   sprite ids. This is the tile property store (collision, one-way, water, hazard,
   climb). Flags are declared in `src/01_core.lua` as `F_SOLID`, `F_ONEWAY`,
   `F_WATER`, `F_HAZARD`, `F_CLIMB`, `F_BREAK`, `F_DECO`, `F_SLOPE`.

---

## 3. Tooling — how to run things

All three scripts are executable and live in `tools/`.

```sh
cd "/Users/danb/Documents/ninja game"

sh tools/build.sh                    # concatenates src/*.lua -> kage.lua (playable cart)
sh tools/test.sh tests/t_world.lua   # headless run of a test driver, prints build/test.log
sh tools/preview.sh tests/p_world.lua 6   # 6s real window + screenshot
```

- **`build.sh`** concatenates `src/*.lua` in **lexical filename order**, skipping
  any basename starting with `_`. Output defaults to **`kage.lua` in the project
  root** (`/Users/danb/Documents/ninja game/kage.lua`), i.e. inside the project, not
  the parent directory. Last verified build: **9 modules, 2807 lines, 99 142 bytes**.
  Run the built cart with
  `"/Applications/TIC-80 Pro.app/Contents/MacOS/tic80" kage.lua`.
- **`test.sh`** builds `build/test_cart.lua` = all of `src` + the test driver, runs
  it headless with a 60 s watchdog, and prints the log.
- **`preview.sh`** builds `build/preview.lua` = all of `src` + the preview driver,
  runs it fullscreen, `screencapture -x /tmp/shot.png`, downscales to
  `/tmp/shot_s.png`, then kills TIC-80.

To *look* at a preview: a static file server is normally already running on port
8765 rooted at `/tmp` (`python3 -m http.server 8765 --directory /tmp`); fetch
`http://localhost:8765/shot_s.png`. If it is not running, start it.

**Framebuffer verification without a screen capture** (the reliable path on this
machine, where `screencapture` and synthetic keystrokes are blocked by macOS
privacy permissions):

```sh
sh tools/test.sh tests/p_verify.lua   # asserts pixels + dumps the framebuffer
sh tools/ppm.sh                        # build/test.log -> build/frame.png (3x)
```

`tests/p_verify.lua` runs the production `BOOT`/`Game` path in `--cli`, then reads
the rendered framebuffer back from VRAM — the screen at nibble `0x0000`
(`peek4(y*240+x)`, 240×136, 4bpp) and the palette at `0x3FC0` — and asserts sky,
terrain, the ninja sprite, and the HUD. It also emits the frame as hex between
`PPM-BEGIN`/`PPM-END` markers; `tools/ppm.sh` reassembles that into a PNG. This
is how visuals are verified when no window can be captured.

### Existing tests / previews

| File | Purpose |
| --- | --- |
| `tests/t_smoke.lua` | Foundation smoke test. **18/18 pass** (palette in both banks, map bounds, `fset`/`fget`, `spr16` for both banks, `key` is a function). |
| `tests/t_paint.lua` | Controlled 16×16 canvas experiment that *proved* the block packing. Keep it; if you suspect the atlas is wrong, run this first. |
| `tests/t_dump.lua` | Dumps a sprite block as hex text rows — the fastest way to inspect art exactly, without a screenshot. |
| `tests/t_world.lua` | Structural checks on the generated world. |
| `tests/p_atlas.lua` | Draws all 512 atlas slots 30 per row on a checkerboard. |
| `tests/p_chars.lua` | Character sheet, 7 per row at scale 2. |
| `tests/p_world.lua` | Whole world as one screen pixel per tile. |
| `tests/p_gameplay.lua` | Delegates every frame to the production `TIC` (the live game). |
| `tests/p_verify.lua` | Headless framebuffer pixel assertions + PPM dump of the live frame. |

`src/_probe*.lua`, `src/_clitest.lua` are throwaway probes, excluded from builds by
the `_` rule. They can be deleted.

---

## 4. Source layout and the module-ordering contract

Modules are numbered because `build.sh` concatenates in lexical order, and **every
module shares one Lua chunk** — so a `local` declared in an earlier module is
visible to every later one.

```
src/00_meta.lua      cart header, control scheme, source-layout doc
src/01_core.lua      screen/map/world sizes, physics constants, tile flags,
                     math helpers, deterministic RNG, buffered input, Frame
src/02_palette.lua   16 colour names, PAL_RGB, palApply/palSetTint/palUpdateTint,
                     AND the buildArt() wrapper opening (see §5)
src/03_art.lua       procedural pixel painter (8×8 and 16×16 canvases) + blk16()
src/04_terrain.lua   tile registry T, biome ids BIOME, genTerrain()
src/05_props.lua     buildings/props/nature art, genProps()
src/06_chars.lua     player, 6 enemies, boss, items/HUD art, genChars(),
                     PF/EF frame constants, AND the buildArt() closing
src/07_world.lua     World table, REGIONS, worldGen()
src/08_tiles.lua     flag-driven collision queries + swept-AABB moveBody
src/09_player.lua    fixed-step character controller (the Player table)
src/10_camera.lua    follow camera, look-ahead, region tracking + tint
src/18_game.lua      Game.boot()/Game.frame() lifecycle + damage recovery
src/20_render.lua    renderFrame(player): parallax, map, ninja, HUD
src/80_main.lua      BOOT()/TIC() dispatch
```

Rules to keep:

- Keep the numeric prefixes. `80_main.lua` stays last (it only defines `BOOT`/`TIC`).
- Only `01_core.lua` locals are expected to be visible to *gameplay* modules.
  Atlas internals are deliberately **not** exported (see §5).
- `01_core.lua` currently declares roughly 60 chunk-level locals. Budget is 200
  (see §5) — account for that before adding new module-level locals.

### `01_core.lua` contents worth knowing

- Sizes: `SCREEN_W/H` = 240×136, `TS` = 8, `MAP_W/H` = 240×136, `WORLD_W/H` =
  1920×1088. The camera and HUD use `SCREEN_W/H` directly; there is still no
  separate `CAM_W/H` or `HUD_H` constant.
- Physics tuning (fixed step, no dt, 60 fps): `GRAVITY` 0.30, `GRAVITY_APEX` 0.16,
  `MAX_FALL` 4.4, `RUN_ACCEL` 0.34, `RUN_MAX` 1.55, `RUN_FRICTION` 0.42,
  `AIR_ACCEL` 0.22, `JUMP_VEL` −4.05, `DOUBLE_JUMP_VEL` −3.55, `DASH_SPEED` 4.0,
  `COYOTE_TICKS` 7, `JUMP_BUFFER_TICKS` 7.
- Math: `flr ceil abs sqrt sin cos atan min max fmod sgn sign2 clamp lerp mid
  approach dist dist2 ease wrap` and `PI TAU INV60`.
- RNG: `rngSeed`, `rngF`, `rngI`, `rngR`, `rngPick`, `rngChance` — deterministic
  (an LCG that never touches `math.randomseed`).
- Misc: `spr16(idx,x,y,key)` draws a 2×2 block; `rep(s,n)` is a string-repeat
  helper; `blit16Index` is an unused readability placeholder you may delete.
- **Input** (`Input` table) is the gameplay-facing interface: fields
  `x, y, left, right, up, down, jumpHeld, atkHeld, jump, atk, jumpBuf, atkBuf, any`.
  `inputUpdate()` refreshes it each frame, and `inputConsumeJump()` /
  `inputConsumeAtk()` clear the buffer when a jump/attack is spent. Jump accepts
  `btn(4)` or `btn(6)`; attack accepts `btn(5)` or `btn(7)` (both key sets), because
  the gamepad enum could not be found in the emulator headers. Keep that aliasing.
- `Frame` is the chunk-level tick counter; `ticks()` and `secs()` read it.
  `80_main.lua` increments it before dispatching.

---

## 5. ⚠️ The 200-local limit and the `buildArt()` pattern

**This is the single most important structural fact in the repo.**

Lua allows **200 local variables per function**, and a TIC-80 cart's main chunk
*is* one function. The atlas modules (palette + art + terrain + props + characters)
need far more than that; the first attempt to add the world module failed with:

```
too many local variables (limit is 200) in main function
```

The fix, already in place: modules `02`–`06` are wrapped in one function:

- `src/02_palette.lua` declares the hoisted handles and opens `local function buildArt()`
- `src/06_chars.lua` closes it and calls `buildArt()` once at load time

Hoisted handles (the only things later modules may rely on):

```lua
local V,K,B,S,N,W,G,O,R,C,J,F,PK,VI,BR,DK = 0..15   -- colour index names
local T, BIOME = {}, {}                             -- tile registry, biome ids
local genTerrain, genProps, genChars, blk16          -- atlas entry points
local isTerrain                                      -- tile id 1..80 predicate
local palApply, palSetTint, palUpdateTint            -- palette control
local PF, EF                                         -- player / enemy frame constants
```

**Consequences for you:**

- Inside `buildArt()`, all the painter helpers (`artP`, `artBox`, `artDisc`, …) and
  the short colour names are in scope and work by their bare names.
- `artP` / `artBegin8` / `artBegin16` etc. are **NOT** visible outside
  `buildArt()`. Gameplay and renderer modules must not call them. If you need
  runtime pixel art, add a new exported function inside `buildArt()`.
- If you add a gameplay module with many helpers, either keep them few, put them in
  a table, or give the module its own wrapper function the same way.

---

## 6. The art pipeline

All cartridge art is **generated procedurally at boot** — there are no asset files.

- `artBegin8(id)` / `artBegin16(id)` select the canvas. `artP(x,y,c)` plots,
  clipped to the canvas. Helpers: `artClear artH artV artBox artRect artOutline
  artLine artDisc artRing artNoise artDither artSwap artG`.
- Terrain uses **parametric textures** (per-biome spec table + noise), signature
  objects (trees, houses, torii) are hand-authored generators.
- Characters use **"silhouette then fill"**: a part is drawn 1 px larger in the
  outline colour, then filled. This gives clean outlines automatically.
- **Lighting convention: light comes from the upper left.** Every terrain block
  gets a 3-tone bevel plus a 1 px ink line on exposed edges. That is what creates
  the 2.5D "extruded cube" read. Keep it consistent for anything new.

### Atlas map (bank 1, sprites 256–511)

| Range | Contents |
| --- | --- |
| 256–319 | player, 16 frames (idle, run1–4, jump, fall, slash1, slash2, dash, wallslide, crouch, hurt, throw, land, power) |
| 320–383 | 6 enemies × 4 frames: oni, tengu, yurei, rogue ninja, kappa, kitsune |
| 384–415 | boss (Oni Warlord), 8 frames, drawn at scale 2 by the renderer |
| 416–447 | free |
| 448–511 | items, projectiles, FX, HUD icons (8×8) |

Bank 0 (sprites 0–255) holds terrain tiles and platforms/liquids.

Tile id map (see `src/04_terrain.lua` for the authoritative list):

- `1..80` biome blocks: 10 biomes × 8 variants at base `1+(b-1)*8`;
  variant order `V_SOLO, V_TOP, V_TOPL, V_TOPR, V_MID, V_MIDL, V_MIDR, V_BOT`.
- `81..88` one-way platforms (wood/stone/bamboo/ice, L+R).
- `89..100` liquids: water, waterfall, lava, sludge.
- `101..152` buildings: two roof styles × (ridge/slope/eave × L/M/R), walls,
  shoji, pillars, beams, torii, lanterns, fences, banners, well, stairs, sign.
- `153..192` nature: trunks, canopies, pine, bamboo, bushes, tufts, flowers, rocks,
  boulders, vines, ladders (flagged `F_CLIMB`), jizo, tomb, maple, snow tree.
- `193..210` misc: chests, pottery, spikes (flagged `F_HAZARD`), clouds, island
  edge, bridges (flagged `F_SOLID`), floors (flagged `F_SOLID`).

The 16-colour palette is indigo / vermilion / gold / sakura — index meanings are
documented at the top of `src/02_palette.lua`.

---

## 7. World generation — what it does

`worldGen()` in `src/07_world.lua`, in order:

1. `genSurface()` — per-column surface height from three sine terms per region,
   clamped to y 40..78, then smoothed twice so there are no 1-tile spikes.
2. `layMass()` — fills from the surface down, leaving two void rows at the bottom.
3. `genSky()` — floating islands per region (biome-coloured, 2–3 tiles thick) with
   optional one-way perches and a coin-row spawn.
4. `genCaves()` — carves worm tunnels (circle sweeps) below the surface; in the
   volcano and the marsh it also drops **lava / sludge pools** along cave floors
   and fills surface dips, so those regions have visible lethal terrain.
5. `placeLandmarks()` — hand-placed villages, shrines, torii, pagodas, houses,
   bridges, plank runs, chests, coins, NPCs, enemies and bosses.
6. `placeSurfaceDecor()` — procedural trees, bamboo, bushes, flowers, rocks,
   lanterns per biome.
7. `placeClimbHelpers()` — adds plank platforms where the surface step is ≥4 tiles
   (i.e. unjumpable).
8. `refineTerrain()` — **autotiling**: every tile in `1..80` is rewritten with the
   variant matching which of its 4 neighbours is exposed. This is what produces the
   bevel. Decor tiles are skipped.
9. `findStart()` — drops the player spawn on the first solid thing under x=8, so the
   spawn can never end up inside a building.

`World` is the hand-off table to gameplay:

```lua
World.surfY[c]   -- surface height per column (1-based)
World.regOf[c]   -- region index per column
World.decor      -- background decor instances (currently EMPTY, see §9)
World.spawns     -- entity spawn records (see below)
World.startX/Y   -- player spawn in tiles
World.w/h        -- 240, 136
```

Spawn record kinds currently emitted: `coin`, `coinRow`, `chest` (with `item`),
`enemy` (`oni`/`tengu`/`yurei`/`rogue`/`kappa`/`kitsune`), `npc` (with `text`),
`shrine` (with `id`), `boss`, `lantern`. **Nothing consumes them yet** — writing the
spawner is a next step (§10).

### Regions (left to right, in intended progress order)

| # | Name | Biome | Tint | Notable content |
| --- | --- | --- | --- | --- |
| 1 | Bamboo Village | GRASS | none | village houses, shrine 1, torii, 2 NPCs, 1 oni |
| 2 | Whispering Bamboo | BAMBOO | none | shrine 2, **double jump** chest, bamboo climb |
| 3 | Sakura Hills | SAKURA | dusk | shrine 3, 2 torii, **wall cling** chest |
| 4 | Stone Pass | STONE | none | shrine 4, pagoda, stone planks, bridge |
| 5 | Yuki Mountain | SNOW | cold | shrine 5, ice planks, **air dash** chest |
| 6 | Oni Caldera | VOLCANO | ash | shrine 6, **boss**, lava pools, spiritFlame scroll |
| 7 | Spirit Marsh | SWAMP | night | shrine 7, **water walk** chest, yurei |
| 8 | Temple Ruins | STONE | dusk | shrine 8, 2 pagodas, **boss**, torii |

The `tint` field names a palette shift implemented in `palUpdateTint()`
(`dusk`, `cold`, `ash`, `night`), but **nothing calls `palSetTint` per region yet** —
wiring that to the camera's current region is a next step.

---

## 8. Current verified state

**Playable slice verified.** The game boots, generates the world, accepts input,
moves the ninja with full tile collision, follows with a parallax camera, renders
the 2.5D scene, and runs the HUD. All suites pass headless:

| Suite | Checks | Status |
| --- | --- | --- |
| `tests/t_smoke.lua` | 18 | pass |
| `tests/t_tiles.lua` | 24 | pass |
| `tests/t_world.lua` | structural | pass |
| `tests/t_player.lua` | 95 | pass |
| `tests/t_game.lua` | 49 | pass |
| `tests/p_verify.lua` | 12 | pass (framebuffer) |

Last run of `tests/t_world.lua`:

```
tiles solid=14580 decor=659 liquid=391 hazard=251 maxTile=210
spawns=93 start=8,65
start tile=0 start+1=0 ground=2
ground within 8 below start: true
surface gaps=17   maxTile ok: true   badSpawns=0
surface relief y=47..78
```

- The whole atlas paints without error and the world generates in a headless run.
- Art confirmed visually: terrain/props atlas (`p_atlas`), the full character sheet
  (`p_chars` — player, oni, tengu, yurei, rogue ninja, kappa, kitsune, boss, items),
  and the whole world as a pixel map (`p_world` — 8 distinct regions, surface
  relief, cave mouths, sky islands, lava pools in the caldera, shrine/boss markers).
- **The playable frame is confirmed visually** via `tests/p_verify.lua` +
  `tools/ppm.sh` → `build/frame.png`: village houses, bevelled terrain, parallax
  sky with sun, the ninja sprite at the spawn, hearts/stamina/ryo HUD, and the
  "Bamboo Village" region banner.
- `surface gaps=17` is **expected, not a bug**: those are columns where a cave mouth
  opened the surface. Review them so none is an inescapable pit; adding
  ladders/ropes there is a nice-to-have.

### What exists now (new since the last handoff)

- `src/08_tiles.lua` — flag-driven collision: `Tiles.at/atPx/tileFlag/flagAtPx/
  solidAtPx/rectHitsFlag/rectHitsSolid/rectHitsOneWay/wallSideForRect` and the
  axis-separated swept-AABB `Tiles.moveBody(body, dx, dy, opts)` (aliases
  `sweepMove/sweepAABB/moveAABB`). One-way platforms land descending-only and
  honour `opts.dropThrough`. Collision flags are registered once at load:
  `1..80` solid, `81..88` one-way, `SPIKE_BASE`/`BRIDGE_A..FLOOR_WOOD_R` solid.
- `src/09_player.lua` — the fixed-step controller. Run, variable-height jump,
  coyote time, jump buffer, double jump (gated `canDoubleJump`), air dash
  (`canDash`, down+jump in air, stamina cost, re-arms on landing), wall
  slide/cling + wall jump (`canWallCling`), crouch with headroom check, ledge
  grab (`findLedge`/`ledge` state), ladder climb (`F_CLIMB`), hazard/fell flags.
  `Player.reset(x,y)` is the deterministic spawn. Input is read from the shared
  `Input` snapshot without mutating it (replay-safe).
- `src/10_camera.lua` — `Camera.reset/update(player, snap)`: lerped follow with
  velocity look-ahead, clamped to the world, tracks `Camera.region/regionName/
  tint/changed` from `World.regOf` and calls `palSetTint` per region.
- `src/18_game.lua` — `Game.boot()` (art → world → player → camera → palette,
  guarded so re-boots are non-destructive) and `Game.frame()` (player → camera →
  tint → hazard/fell damage & deterministic respawn → render). Progression
  baseline: all three upgrades locked, 3 hearts, 100 stamina.
- `src/20_render.lua` — `renderFrame(player)`: region woodblock sky, far
  mountains, mid silhouettes, near wind streaks (all parallax off `Camera.x/y`),
  the `map()` plane (colorkey 0), the ninja via `blk16(256, frame)` with a drop
  shadow and i-frame flicker, then the HUD (hearts 451/452, stamina bar, ryo 450,
  region name + change banner).
- `src/80_main.lua` — `BOOT()` = `palApply()` + `Game.boot()`; `TIC()` =
  `Frame+1`, `inputUpdate()`, `Game.frame()`.

### Bugs found and fixed during this session (do not regress)

1. **16×16 blocks overlapped.** Frames were placed at a stride of 4 sprites, so
   frame 4's block overwrote frame 0's. Fixed by introducing `blk16(base, k)`
   (stride 2, 8 per row-pair). `tests/t_paint.lua` is the regression test.
2. **Lua 200-local ceiling.** Fixed with the `buildArt()` wrapper (§5).
3. **Player spawned inside the shrine.** Fixed by `findStart()`.
4. **No lava/sludge anywhere.** The flood logic tested the wrong tile; replaced with
   pools along carved cave floors plus surface-dip filling.
5. Typos that broke the atlas: a stray `rougeOr()` helper and a
   `T.PINK_FALLBACK` placeholder that did not exist. Both removed.

---

## 9. What is NOT done — read this before planning

**The playable slice (movement, camera, render, HUD, lifecycle) exists and is
verified.** What remains is everything that makes it a game:

- **No entity spawner.** `World.spawns` has 93 records; nothing reads it.
- **No enemies, no combat, no boss logic.** Sprites exist; behaviour does not.
  No slash hitboxes, no kunai, no damage/i-frames/knockback beyond the simple
  environmental hazard/fell recovery in `Game.frame()`.
- **No pickups.** Coins, chests, scrolls, spirit orbs, and the three upgrade
  chests (double jump / wall cling / air dash) are spawn records only. The
  `canDoubleJump`/`canDash`/`canWallCling` gates exist on the player but nothing
  unlocks them.
- **No game states, menus, dialogue, save, or fast travel.** Shrines and torii
  are map/spawn records only; `Up` at a shrine does nothing yet.
- **No audio.**
- **No water in the world.** The water/waterfall tiles are painted and flagged, but
  generation only places lava and sludge. Waterfalls, ponds and the water-walking
  upgrade area are unbuilt.
- **`World.decor` is empty** and unused. It was reserved for parallax background
  props (distant mountains, pagodas, bird flocks). The renderer currently draws
  all parallax procedurally from `Camera.x/y`.
- **Sky islands are sparse** (0–3 per region) and have no content beyond coins.
- **Underworld has no identity.** y≈106–136 is generic rock with caves; there is no
  UNDER-biome content, no underworld entrance, no descent.
- Dead code to clean: the `HAZARDS` table in `07_world.lua`, the unused `fill`
  field in `REGIONS`, and the `_probe*` files.

---

## 10. Recommended next steps, in order

Each step should end with a headless test or a framebuffer verification.

~~1. `src/08_tiles.lua` collision~~ — **done** (`tests/t_tiles.lua`).
~~2. `src/09_player.lua` controller~~ — **done** (`tests/t_player.lua`).
~~3. `src/10_camera.lua` follow camera + region tint~~ — **done** (`tests/t_game.lua`).
~~7. `src/20_render.lua` 2.5D renderer + HUD~~ — **done** (`tests/p_verify.lua`).

1. **`src/11_entities.lua`** — the spawner that consumes `World.spawns`, plus the
   entity list, depth sorting and drop shadows. Coins/chests first (they unlock
   the three movement upgrades the player already gates on).

2. **`src/12_enemies.lua`** — 6 behaviours + projectiles (shuriken, fireball) +
   the boss state machine.

3. **`src/13_combat.lua`** — slash hitboxes, kunai, damage, i-frames, knockback,
   hit FX, death/respawn at shrines. Replace the placeholder hazard/fell policy
   in `Game.frame()` with real combat damage.

4. **`src/30_states.lua`** — pause, dialogue, shrine save menu with torii fast
   travel. Hearts/stamina/coins/scroll HUD already exist in `20_render.lua`;
   the scroll counter and upgrade icons still need drawing.

5. **`src/40_audio.lua`** — sfx and per-region music, using the TIC-80 sound
   registers.

6. **Content pass.** Water/waterfalls, denser sky islands, a real underworld with
   an entrance and descent, more landmark variety, NPC dialogue text, and
   gameplay tuning.

---

## 11. Gotchas that will bite you

- **Never hand-compute a 16×16 block index.** Use `blk16`.
- **Never add a chunk-level local casually** — you will hit the 200 limit. Put it in
  a table, or inside a module wrapper function like `buildArt()`.
- **`buildArt()` internals are not exported.** `artP` and friends are unreachable
  from gameplay code by design.
- **`map()` needs colorkey 0**, otherwise index-0 air pixels will be drawn opaque
  and thin one-way platforms will look wrong.
- **Two key sets are accepted for jump/attack.** Keep the aliasing.
- **Decor tiles carry no collision flags.** Buildings, trees and torii are
  deliberately walk-through; solidity comes only from `1..80`, the platforms,
  `BRIDGE_A/B`, `FLOOR_*`, and `SPIKE_BASE`.
- **`fset`/`fget` are the tile property store** — add a flag rather than
  hard-coding id ranges in gameplay code.
- **Tooling quirk:** several `write_to_file` calls in this session were dropped
  because the tool XML was malformed (missing `<path>`). If a file you just "wrote"
  is missing, re-emit the call with all tags present.
- **`tools/preview.sh` needs a real window** — do not run it in a headless context.
  On this machine `screencapture` fails with "could not create image from display"
  and `osascript` keystrokes fail with "not allowed to send keystrokes (1002)"
  (macOS Screen Recording / Accessibility permissions are not granted to the
  agent's host). Use `tests/p_verify.lua` + `tools/ppm.sh` instead — reading the
  framebuffer from VRAM needs no permission.
- **VRAM layout for read-back** (verified against the emulator source): the
  framebuffer is at nibble `0x0000` (`peek4(y*240+x)`), the 16-colour palette at
  `0x3FC0` (RGB triplets). `trace()` in `--cli` concatenates lines without
  newlines, so parse PPM dumps with a regex over the whole log, not line-by-line.
- **The colour short-names** (`V K B S N W G O R C J F PK VI BR DK` = 0..15) are
  hoisted out of `buildArt()`, so gameplay/render/test code can use them — but
  remember `B`=2 is BLUE (sky) and `G`=6 is GOLD, not "background"/"green". Grass
  is `J` (jade, 10), earth is `BR` (brown, 14).
