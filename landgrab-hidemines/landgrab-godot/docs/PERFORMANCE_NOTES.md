# PERFORMANCE NOTES

## Pass 5 - from the 1x recording (fps 61, ~500 trade ships, 41 warships, 220 buildings, 23% territory) - IMPLEMENTED, NOT RUN IN GODOT
Overlay at 1x (avg ms per call): `_draw` 10.7 (mines+boats 4.8 !, buildings 2.5, warships 1.5, trade ships 1.0, rails 0.35, labels 0.3), `tick` 12.4 x2/s (step_ships 6.8, bot_think 2.5, step_trade 0.9),
attacks 2.7, hover info 0.8 per frame. (With the editor speed button at 8x/16x the per-call averages are still right; only frame avg / fps / "per second" columns are wrong.)
- **Mines (4.8 ms)**: with 1 boat on screen the cost is the mines. When zoomed out and more than 16 mines exist, they are drawn as small squares in two batched `draw_multiline_colors` calls (client look only).
- **Hover info (0.8 ms every frame)**: `_hover_unit` computed an exact lerped position for all ~500 trade ships every frame; now a nearest-tile pre-filter (margin = 1 tile, never drops a real hit) runs first.
- **step_ships (6.8 ms)**: new timers `ships: chase search`, `ships: go-home search`, `ships: grid build` show which part is the flood fill (`_water_bfs`) and which is bookkeeping.
  `CHASE_SEARCHES_PER_TICK` = 1 (was 2): at most one warship flood fill per economy tick. **Rule change** -> NET_VER / PROTO_VERSION = 12. Set it back to 2 if warships feel too slow to react.
  Known weakness (unchanged): the first warships in the list win the budget each tick, later ones can wait.
### Not done
- Warship loop order rotation (fair sharing of the search budget), `bot_think` (2.5 ms), buildings LOD batching (2.5 ms), static-layer cache for `_draw`, `step_attack` incremental lists.
### Next
Send another 1x recording at the late stage (the new `ships:` and `draw:` rows). If `ships: chase search` is still large, the next step is a cheaper search (bounded radius / reuse), not more budget cuts.


## Pass 4b hotfix: F3 overlay crashed ("Invalid access to property or key 'draw: warships'") because `_pf1` skipped `perf_peak` for 0 us calls. Fixed in `_pf1` and in `_perf_overlay` (.get).

## Pass 4 (this pass) - status: IMPLEMENTED, NOT RUN IN GODOT (static checks + a Python model of the grid only)
Evidence used: a 34 s screen recording of the F3 overlay (Godot editor, embedded game, **8x editor speed**, debug build, Europe map, ~480 trade ships, 36 warships, 224 buildings).
Late in the clip: `_draw` avg 19 ms per frame, `tick` avg 24.6 ms per call (step_ships 13.7 ms, step_ports 6.1 ms, bot_think 3.5 ms), attacks 2.8 ms per step, map upload 0.5 ms.
At 1x a 60 fps frame has 16.7 ms, so a 19 ms `_draw` alone explains the fps loss, and the 25 ms tick calls (2 per second) explain the hitches.
- **F3 overlay fixed**: it divided by the engine-scaled `delta`, so with the editor's 8x button every number lied. It now uses `delta / Engine.time_scale` (real seconds) and prints a warning
  line when the speed is not 1x. `_draw` is split into timed sections: `draw: rails / buildings / labels / trade ships / warships / mines+boats / attack tags / fx+preview`.
- **step_ships (13.7 ms)**: `_targets_near` scanned every trade ship for every warship (36 x 480 dictionary reads per tick). `step_ships` now builds a 24-tile grid + id index once (`_tn_build`),
  `_targets_near` reads only the 3x3 cells around the warship, in ascending trade index = the identical result and order as the full scan (verified with a Python model, 300 random trials),
  and `_target_by_id` uses the id index. The grid exists only while `step_ships` runs (`_tn_ok`).
- **step_ports (6.1 ms)**: ~3 A* searches per tick (`TRADE_ROUTES_PER_TICK`) because the route cache held only 600 routes and was cleared whenever it filled (about 40 ports = 1,500 ordered pairs).
  `ROUTE_CACHE_MAX` is now 3000 and a lane already searched in one direction is reused (reversed) for the other direction instead of a new A*. **This is a rules change** (trade launch timing) -> `NET_VER` and `PROTO_VERSION` = 11.
- **_draw (19 ms)**: far-away trade ships (the LOD dots) are now batched into 2 `draw_multiline_colors` calls instead of 2 `draw_circle` calls each (~960 fewer draw calls with 480 ships; the dots are small
  squares now) and use the tile position instead of a per-ship lerp. When zoomed out with more than 10 warships, other nations' undamaged warships are drawn as simple discs (was ~20 draw calls each).
  Your own warships, boarding ships and ships that just fired keep the full art.
### Not done (and why)
- `step_attack` tier lists incremental: attacks are only ~2.8 ms per step in the recording; it consumes `sim_rng`, so a rewrite risks desync. Not touched.
- Caching the static layers (buildings / rails / labels) out of `_draw` into a child node: probably the next big win, but it changes draw order and invalidation rules and I cannot run Godot. Use the new `draw:` rows to decide.
- `bot_think` (3.5 ms per call) and the overlay position (it covers the HUD) are unchanged.
### What to do next
Record F3 again at **1.0x** speed (ideally an exported release build or at least the game in its own window), same late stage, and send the top rows. Check `user://perf_log.txt` too.

# Late-game performance pass

Backup of the script before this pass: `main.gd.bak_before_perf` (in the separate backups ZIP). Static checks only - NOT run in Godot.

## What was slow late in a match and what changed (all in main.gd)
1. **Attack stepping** (`step_attack`): every attack shuffled its whole contact front every 0.1 s although only a few tiles are taken per step.
   Now a lazy shuffle: only the tiles really taken are drawn at random (same distribution). The "where is the front" marker (drawing only)
   samples at most ~40 tiles instead of scanning the front twice.
2. **Warships** (`step_ships`): each warship built a dictionary for EVERY enemy boat / trade ship / warship on the map every tick (hundreds of
   short-lived dictionaries per ship per tick = garbage collector stutter). Now `_targets_near` only builds entries for units within sight
   (20 tiles) and `_target_by_id` finds a chosen target anywhere. Same targeting rules.
3. **Mines** (`step_mines`): same problem (a full target list per mine per tick). Now checks enemy boats directly, and does nothing when there are no boats.
4. **Trade ports** (`step_ports` / `launch_trade`): every port scanned ALL buildings (villages included) on every launch and counted trade ships
   itself. Now one pass lists the ports (`trade_ports`) and one pass counts ships per port. The route cache is capped at 600 routes
   (it used to grow with every port pair ever used).
5. **Rails** (`rebuild_rails`): the minimum-spanning-network loop was cubic in stations/cities per nation, and cross-nation links compared
   every station with every other. Now Prim in O(n^2) and a grid so a station only looks at its neighbours.
6. **Drawing** (`_draw`): buildings were looped twice per frame over ALL buildings; now one pass collects the visible ones.

## Not changed on purpose
Texture upload throttling, label amortising, frame budget for simulation steps, off-screen culling: already in place and fine.

## Protocol
`NET_VER` / `PROTO_VERSION` 8 -> 9 (the simulation's random stream and rail layout changed slightly, so old and new builds must not play together).

## If it still lags
Tell me: map, number of nations, zoom level, and whether it lags while idle or only during big wars. Then check Debugger > Monitors > Time (process)
and Debugger > Profiler in Godot: the top few functions say what is next.


## Pass 2 (beta launch): drawing LOD, automatic quality, narrow screens - see the end of docs/AI_PROGRESS.md
Client look only (no rules / no protocol change, `NET_VER` unchanged): simple icons for buildings and dots for trade ships when the map is crowded and zoomed out
(`_draw_bld_lod`, `lod_zoom` 3.0); automatic quality levels 1-3 from the measured frame time (`_perf_adapt`: lite shader + no sparks, slower map upload, simpler icons);
compact bottom bar on windows narrower than 980 UI units (`_compact_ui`). Backup of the previous script: `main.gd.bak_before_perf8`.


## Pass 3 (this round): MEASURE FIRST - built-in profiler (F3) + HUD churn fixes   [client only, no rules / protocol change, NET_VER unchanged]
Status: written and statically checked (tabs, brackets, no duplicate / undefined functions, no variable declared twice in a scope). **NOT run in Godot** (not available to me), so there are
NO measured before/after numbers. Backup of the script before this pass: `main.gd.bak_before_perf9`.

What I found by reading v8 (the two earlier passes already fixed the big algorithmic costs, so I did NOT redo them): lazy shuffle in `step_attack`, cheap warship / mine targeting, trade ports in one pass,
Prim rails + grid, building LOD, trade-ship dots, adaptive quality `_perf_adapt`, throttled map upload, bots capped to 300 border tiles + think every 2-4 ticks, `_resolve_clashes` is O(attacks).
Whole-map loops exist only at match start (`rebuild_image` first call, `_calc_*`, `_naval_init`), not per frame / per tick.
What still scales with the late game (per attack step: O(contact front) in `step_attack`; per frame: `_draw` command generation, two 2 MB texture uploads in `rebuild_image`, the map shader on the GPU) cannot
be ranked without a profiler - guessing would risk breaking lockstep determinism - so this pass adds one.

### Profiler: press F3 during a match
Top-left overlay, refreshed once per second, also saved to `user://perf_log.txt` every 5 s (Godot: Project > Open User Data Folder; web build: take a screenshot of the overlay).
- line 1: fps, average and worst frame time, number of frames slower than 34 ms, current automatic quality level
- line 2: engine counters: process ms, draw calls, node count + ORPHAN nodes (growing = leak), static memory (growing over minutes = leak)
- line 3: the late-game load: attacks, total front tiles, tiles changed per second, trade ships / warships / boats, buildings, rails, effects, running blasts
- then every measured section sorted by cost, as "ms of work per second of play" (so 120 ms/s = 12% of one core), average and worst single call, calls per second:
  `tick (all)` with `bot_build`, `bot_think`, `step_boats`, `step_rails`, `step_ports`, `step_trade`, `step_ships`, `step_mines`; `attacks` (all `step_attack` calls of one 0.1 s step);
  `rails rebuild`; `map upload` (rebuild_image); `name labels`; `ui()`; `_after_tick (HUD)`; `hover info`; `_draw (script)` (GDScript time to build the draw commands; GPU time is NOT included - if
  `_draw (script)` is small but fps is low and `process` is low, the GPU / shader / browser is the limit, not the code).
Cost when F3 is off: one boolean test per measured section. Nothing in the rules reads it.

### Small fixes in this pass (safe, client only)
- Leaderboard: `ui()` destroyed and re-created ~25 nodes every 1.5 s; now it is rebuilt only when the shown names / shares (0.1%) / my rank change (`lb_sig`).
- `ui()` and `_refresh_cards()` used `_counts()` (allocates N+1 dictionaries and scans every building) just to read my own numbers; they now use `_counts_of(my_slot)`.

### Test plan (please do this, it is the whole point of this pass)
1. Play (or Spectate at 8x) a big map (World, many nations) to the late game, press F3, let it run ~30 s in a war-heavy moment. Screenshot the overlay (or send `perf_log.txt`).
2. Read it: the top rows say what to fix next:
   - `attacks` large (front tiles in the thousands) -> make `step_attack` incremental (keep the tier lists between steps) - the biggest remaining rules cost.
   - `_draw (script)` large -> split static layers (rails, buildings, labels) into a node redrawn only on tick, drawn in map coordinates under a camera transform.
   - `map upload` large -> upload only every 0.25 s when crowded, or shrink `time_tex` (R32F) to a cheaper format.
   - `tick (all)` large -> look at its children (`bot_think`, `step_ships`, `step_trade`).
   - everything small but fps low -> GPU / shader / browser: try quality level 1-3 manually, check `draw calls`.
   - nodes / memory rising steadily -> leak: name the node type that grows.
3. Send me the overlay and I will fix the top two rows with numbers, not guesses.
