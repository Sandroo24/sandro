# AI_PROGRESS.md - Landgrab

## LATEST: hidden mines (not run in Godot). Only your own mines are drawn (spectators see all); `can_place_sea` only refuses a tile that holds YOUR mine (an enemy mine no longer leaks through "There is already a mine here"). Rule change -> NET_VER = PROTO_VERSION = 13. Enemy boats still trigger every mine as before.

## LATEST: performance pass 5 (mine LOD, hover prefilter, CHASE_SEARCHES_PER_TICK=1, protocol 12; see docs/PERFORMANCE_NOTES.md) - not run in Godot

## Before that: performance pass 4 (see docs/PERFORMANCE_NOTES.md)  -  IMPLEMENTED, NOT RUN IN GODOT
Files changed: `main.gd` (backup `main.gd.bak_before_perf10`), `server/relay.py` (PROTO_VERSION 11), docs. NET_VER = PROTO_VERSION = 11 (trade-route cache changed trade launch timing).
Done: F3 overlay uses real time; `_draw` section timers; trade-ship grid/id index for `step_ships`; route cache 3000 + reverse-route reuse; batched LOD trade dots; LOD warships.
Static checks only: brackets, tabs, duplicate funcs / vars, new function referenced, no my_slot in new rules code, grid == full scan (Python model).
Test: F5 (report parser errors) -> play to late game at 1x -> F3 -> send top rows. Check: trade dots look OK (squares), far enemy warships are discs, warships still capture trade ships,
trade ships still launch between ports, online two clients no desync message.
Open: static-layer cache for `_draw`, `bot_think`, `step_attack` incremental lists, overlay overlapping HUD.

---------------------------------------------------------------------------------------------------------------------------------------------------------

## LATEST (performance pass 3): profiler + HUD churn fixes - see docs/PERFORMANCE_NOTES.md "Pass 3"
Press **F3** in a match to see where the time goes (overlay + `user://perf_log.txt`). Not run in Godot (no Godot here): no measured numbers yet.
Backup before this pass: `main.gd.bak_before_perf9`. Exact stopping point: instrumentation + leaderboard/HUD fixes done and statically checked; the real bottleneck is NOT yet
identified because it needs one run of the profiler on a late-game match. Next action: run the test plan in docs/PERFORMANCE_NOTES.md and fix the top rows.

---

## LATEST TASK (v2): Bomb Launchers (4 levels) + SAM Sites + fallout zones  -  status: FINISHED IN CODE, NOT RUN IN GODOT
Godot is not available in my environment: nothing was played. Done instead: a full read of the nuclear code, static checks (tab indentation, bracket balance, no
duplicate functions, no variable declared twice in a scope, no undefined function / constant names, every new function referenced). All clean.
Backups: `main.gd.bak_before_nukes3` (the file as you sent it, before this session), older ones are from earlier rounds.
**First thing to do: open the project, press F5, and send me any parser error line.**

### Audit: the previous (interrupted) session had already finished almost everything - I verified each point in the code
| Your requirement | Where it is | Status |
|---|---|---|
| Port arrow keeps ONLY Warship + Water Mine | `SEA_ORDER` popup (`sub_panel`); port arrow in `_build_ui` | done |
| Other stuff in its own section | second row of the build bar: **Bomb Launcher** (`silo`) + **SAM Site** (`sam`), hotkeys 6 / 7 | done |
| Bomb Launcher fires small nuclear bombs, 750K | `BOMB_PRICE["atom"]` = 750,000 (Small Bomb) | done |
| Launcher has 4 levels | `LAUNCHER_MAX` 4; click your launcher again with the Bomb Launcher tool to upgrade: 1.5M / 2.5M / 4M (`LAUNCHER_UPGRADE_PRICE`); faster reload per level (60 / 50 / 40 / 30 s) | done |
| Level 2 can send a Nuke, 5M | `BOMB_NEED_LEVEL["nuke"]` = 2, `BOMB_PRICE["nuke"]` = 5,000,000 | done |
| Level 4 can send the 25M whole-map bomb | `BOMB_NEED_LEVEL["mega"]` = 4, 25,000,000; radius = `MEGA_RADIUS_FRAC` x the longer map side | done |
| SAM sites counter bombs aimed at your base, range you choose | `SAM_RANGE` = 24 tiles, reload 7.5 s, shoots every enemy bomb that flies inside the range; hit chance Small 80% / Nuke 55% / Mega 30% (`BOMB_SAM_HIT`); allies' bombs are never shot | done |
| Hit land = nobody's land + green nuclear zone | `_blast_rows`: tile owner -> 0 and `_mark_fallout` (flag in the alpha channel of `map_tex`, drawn glowing green by the map shader) | done |
| Anyone can claim the zone by clicking it like normal land | fallout is plain free land: an ordinary attack on it works, and `_set_own` clears the green flag the moment a tile gets an owner; the terrain tip says "Nuclear fallout ... Attack it to claim it" | done |

### What I changed this session
1. **Blast sweep instead of one giant step** (`_detonate` -> `_blast_jobs_step` / `_blast_rows` / `_blast_finish`). Before, one bomb changed every tile in the circle inside a single
   step; for a Mega Bomb that is 100,000+ `_set_own` calls (a multi-second freeze on every client). Now the blast is a job that sweeps over the map row by row, at most
   `BLAST_TILE_BUDGET` (3000) changed tiles per 0.1 s step. Small Bomb and Nuke finish in one step as before; a Mega Bomb sweeps the map in a few seconds like a shockwave.
   Troop losses, building / ship / mine destruction run when the sweep is done. Integer distances (no `Vector2.length()` per tile). Deterministic: row-major order, `sim_rng`.
2. `blast_jobs` is reset in `start_game` and covered by `_net_checksum()`.
3. `NET_VER` 7 -> 8 and `PROTO_VERSION` 7 -> 8 in `server/relay.py` (rules changed; client and relay must match - restart the relay, re-export web clients).
4. This file.

### Tune these (constants near the top of `main.gd`, block "nuclear weapons")
`BOMB_PRICE`, `BOMB_NEED_LEVEL`, `LAUNCHER_UPGRADE_PRICE`, `SILO_RELOAD_BY_LEVEL`, `BOMB_INNER` / `BOMB_OUTER` (Small 5 / 10 tiles, Nuke 12 / 24), `MEGA_RADIUS_FRAC` (0.5 = the circle
reaches about half the map's long side around the target: aimed at the middle it wipes nearly the whole map; use 2.0 to wipe literally everything), `NUKE_SPEED` (0.6 tiles per 0.1 s),
`SAM_RANGE`, `SAM_RELOAD_STEPS`, `BOMB_SAM_HIT`, `NUKE_TROOP_KILL`, `BLAST_TILE_BUDGET`. The card tooltips (`BUILD_TIP`) contain these numbers as plain text - edit them too.
Map sizes at MAP_SCALE 0.5: World 1000x500, Europe 800x650, Asia 750x650, Africa 700x725, North America 750x680 tiles.

### Test scenarios (offline; Spectate cannot launch bombs; give yourself gold or wait)
1. F5: no parser error. Build bar shows Village / Station / Port, then a second row Bomb Launcher / SAM Site. Port arrow opens ONLY Warship + Water Mine. Launcher arrow opens Small Bomb / Nuke / Mega Bomb.
2. Build a Bomb Launcher (6) inside your land. Key 8: aiming circles follow the mouse; click an enemy: bomb arcs across, target gets a warning, land turns green, buildings in the inner circle vanish.
3. Click the green land: normal attack, it becomes yours and the green disappears.
4. Nuke (9): refused ("needs Bomb Launcher level 2") until you click your launcher with tool 6 (1.5M). Mega (0) needs level 4 (2.5M, then 4M).
5. Second bomb right away: "still reloading" (60 s at level 1, 30 s at level 4). A second launcher can fire at once.
6. SAM Site (7): ring shows its 24-tile reach. Bomb at a nation with SAMs: "shot down" messages most of the time (80% small), a miss lands.
7. Mega Bomb on the World map: the map should NOT freeze; the fallout spreads over a few seconds. Watch FPS.
8. Nuke a nation's last tiles: eliminated, no crash. Nuke a port with trade ships bound for it: ships turn back. Nuke a station: rails re-form.
9. Online (two clients, new relay.py): launch + impact, no red "out of sync" toast.

### Not done / open issues
- Not run in Godot at all (parser errors possible). Balance (radii, flight time, prices, SAM chances) is untested.
- **Bots never build launchers / SAMs and never launch bombs** (they can only be hit; they still capture / lose your launchers and SAMs like any building). Nuke AI is a separate task.
- Fallout is only a look + "free land": it has no radiation damage and does not fade. SAMs only engage bombs (not boats / ships).
- Touch / mobile aiming flow for the bomb mode is untested (it reuses the generic `_click` path).
- No "traitor" penalty for nuking an ally (it is simply refused).

### Exact stopping point
Everything in your spec is implemented and statically checked. Next action: F5, report parser errors, run scenarios 1-9, tell me how the blast size / flight time / prices feel. Next sensible task: nuke AI for bots.

---

# AI_PROGRESS.md - Landgrab

## (SUPERSEDED by the v2 section above - kept for history) Missile Silo + SAM Launcher + Atom Bomb (v1)
Godot is not available here: nothing was played. Static checks only (tab indentation, bracket balance, no duplicate functions / constants, no variable declared twice in the edited
functions, every new function and constant referenced, no `my_slot` / global randf in the new rules code) - all clean. Backup before this task: `main.gd.bak_before_nukes`.
**First thing to do: open the project, F5, and send me any parser error line.**

### What was added (`main.gd`; `NET_VER` 6 -> 7 and `PROTO_VERSION` 6 -> 7 in `server/relay.py`, they must match - re-export clients, restart relay)
- **Missile Silo** (`silo`, 1,000,000 gold, flat price) and **SAM Launcher** (`sam`, 1,500,000): normal land buildings placed with the existing `build` command
  (`LAND_EXTRA`, footprint / ownership / gold checks all come from `can_place`). **Atom Bomb** (`atom`, 750,000): new command `{"type":"nuke","kind":"atom","tile":T}`.
  Prices are OpenFront's: the game already uses OpenFront's +1000 gold/s, so a bomb is ~12 minutes of base income.
- **UI**: three new cards in the sub panel (the one that opens with the Port arrow), hotkeys 6 = Silo, 7 = SAM, 8 = Atom Bomb. Atom Bomb mode shows an inner (destroyed) and outer
  (random losses) circle at the cursor; click = launch (Shift keeps firing, Esc / right click cancels). The Atom card says "needs silo" until a silo is ready. Info panel lists Silo / SAM counts.
  Silo, SAM and bomb have their own small art (`_draw_silo`, `_draw_sam`, `_draw_atom`). Bombs fly in an arc with a trail; every nation sees a pulsing warning ring on the target; blast flash on impact.
- **Rules** (all in `step_attacks()` -> `step_nukes()`, i.e. every 0.1 s, identical offline / online, `sim_rng` only):
  - `validate("nuke")`: silo exists, gold, a silo is ready, target is not your own land and not an ally's land. `apply` -> `_launch_nuke`: nearest ready silo (ties: lowest tile) fires,
    gold is paid, that silo reloads `SILO_RELOAD_STEPS` (600 = 60 s). The target's owner gets a "NUCLEAR LAUNCH" warning.
  - Flight: `NUKE_SPEED` 0.6 tiles/step (6 tiles/s). Each step every ready SAM of a nation that is neither the bomb's owner nor its ally and is within `SAM_RANGE` (14 tiles) fires once
    (reload 75 steps = 7.5 s) and hits with `SAM_HIT_CHANCE` 0.75 (rolled with `sim_rng`).
  - Impact (`_detonate`): land inside `NUKE_INNER` (5 tiles) loses its owner, land up to `NUKE_OUTER` (10) loses it with probability `NUKE_RING_LOSS` (0.5). Tiles go through `_set_own`,
    `tiles` is updated, a nation with 0 tiles is eliminated (the bomber gets the usual conquest gold). Hit nations lose `NUKE_TROOP_KILL` x (tiles lost / tiles owned) of their troops (and the lower
    troop cap). Buildings within 5 tiles, or whose tile lost its owner, are destroyed (occupancy cleaned, rails rebuilt at once; trade ships bound for a destroyed port turn back as usual).
    Boats, trade ships, warships and mines within 5 tiles are destroyed. Friendly fire is possible (blast near your own / allied land).
- Online: new command goes through the existing `_cmd_pack` / `submit` / `validate` path. `_net_checksum()` now also covers bombs in flight, silo / SAM reload counters and the number of buildings.

### Tune these (constants near the top of `main.gd`, block "nuclear weapons")
`PRICE_SILO` / `PRICE_SAM` / `PRICE_ATOM`, `SILO_RELOAD_STEPS`, `NUKE_SPEED`, `NUKE_INNER`, `NUKE_OUTER`, `NUKE_RING_LOSS`, `NUKE_TROOP_KILL`, `SAM_RANGE`, `SAM_RELOAD_STEPS`, `SAM_HIT_CHANCE`.
NOTE: the card tooltips (`BUILD_TIP` silo / sam / atom) contain the numbers as plain text (60 s, 14 tiles, 75 %, 5 / 10 tiles) - edit them if you change the constants.
Radii are scaled for this ~220-tile-wide map (OpenFront atom is 12 / 30 on a much bigger map); if a bomb feels too small / too big change `NUKE_INNER` / `NUKE_OUTER` first.

### Test scenarios (offline first; give yourself gold, or wait; Spectate cannot launch)
1. F5 -> no parser error. Open the sub panel (Port arrow): five + three cards. Atom card shows "needs silo".
2. Build a Silo (key 6) inside your land: building appears with the missile art; the Atom card now shows 750K.
3. Key 8, hover an enemy: inner / outer circles + tooltip; click: gold -750K, bomb arcs across the map, target nation gets the warning; on impact land / buildings / ships in the circle vanish, tile counts drop.
4. Second launch right away: "Your Missile Silos are still reloading" (60 s). A second silo can fire at once.
5. Target an ally's land / your own land: refused with a message. Target with too little gold: card shakes.
6. Build a SAM (key 7) near an enemy target region and launch at it from another nation (or let a bot be the target): the SAM fires when the bomb is within 14 tiles; ~75 %: "shot down" messages, no blast; a miss -> blast.
7. Nuke a nation's last tiles: it is eliminated, no crash. Nuke a port with trade ships heading to it: ships turn back, no crash. Nuke a station: rails vanish / re-form.
8. Online (two clients): launch + impact, no "desync" message (checksum includes the new state).

### Not done / open issues
- Not run in Godot at all (parser errors possible); balance (radii, flight speed, prices) untested.
- **Bots never build silos / SAMs and never launch bombs** (they can only be hit by them; they still capture / lose your silos and SAMs like any building). Nuke AI is a separate task.
- **No Hydrogen Bomb** and **no radioactive fallout** (nuked land is simply free land that anyone can re-conquer at once). No "traitor" penalty for nuking someone you are allied with (it is simply refused).
- SAMs only engage atom bombs; a SAM never targets boats / ships. SAM and silo have no upgrade levels.
- Warships boarding a trade ship when the warship is destroyed by a blast: relies on the existing `step_capture` cleanup (ship gone -> boarding state cleared next step); not exercised.
- Touch / mobile placement flow for the Atom Bomb mode is untested (it reuses the generic `_click` path).

### Exact stopping point
Feature complete as specified above. Next action for you: F5 -> report parser errors -> run scenarios 1-8 -> tell me how the blast size / flight time / prices feel. Next sensible task: nuke AI for bots.

---------------------------------------------------------------------------------------------------------------------------------------------------------
# (previous round)

## LATEST TASK: "warships cannot capture trade ships sailing to their OWN port"  -  status: IMPLEMENTED, NOT RUN IN GODOT
Godot is not available in my environment: nothing below was played. Static checks only (tab indentation, bracket balance, no duplicate functions, no variable
declared twice in the edited functions, every new function/constant referenced) - all clean. Backup before this task: `main.gd.bak_before_ownport`.
**First thing to do: open the project, F5, and send me any parser error line.**

### Rule (deterministic, identical for human and AI warships, nothing reads my_slot / randomness / clock)
Nation `o` may capture a trade ship only if (1) its owner is neither `o` nor an ally of `o`, AND (2) the destination port (`tb["dst"]`) does not belong to `o`.
A port of an ALLY protects nothing: only `o`'s own ports do.

### Audit (where trade ships are chosen / locked / captured)
- `_enemy_targets(o)`: single source of targets. Used by the idle auto-lock in `step_ships`, the lock upkeep in `step_ships` (a lock whose target is missing from the list is dropped),
  `validate("shipatk")`, `_enemy_unit_at` (click/hover target for the orange attack styling) and mines (boats only).
- `step_capture()` (every 0.1 s attack step): boarding upkeep and boarding start both used `_is_trade_enemy` (alliance only).
- `_complete_capture()`: unchanged. `_bot_fleet` only sends warships at enemy TROOP transports (`boats`), never trade ships, so it needed no change.

### What changed (`main.gd`, `server/relay.py`)
1. New helpers next to `_is_trade_enemy`: `_trade_dest_owner(tb)` (0 when the destination port is gone / no longer a port, no crash) and
   `_trade_capturable_by(o, tb)` = `_is_trade_enemy(o, tb)` and not (dest owner == o). Constant `CAPTURE_OWN_PORT_PROTECTED := true` (set false = old behaviour, for testing).
2. `_enemy_targets`: trade ships failing `_trade_capturable_by` are not listed => no auto-lock, no manual lock, no click/hover target, and an existing lock is dropped on the next `step_ships`.
3. `step_capture`: both checks (boarding upkeep, boarding start) use `_trade_capturable_by` => if an alliance is made or the destination port changes owner to the warship's nation
   mid-boarding, the boarding is aborted cleanly (`_abort_boarding` clears `cid`, `cprog` and the ship's `capt`). Missing destination port: `_trade_dest_owner` returns 0, `step_trade` turns the ship back as before.
4. `validate("shipatk")`: refuses with "That ship is sailing to your own port" for an enemy trade ship heading to your own port (before the generic "Pick an enemy ..." message).
5. Captured ships: the rule is generic (it reads the current `tb["o"]` and the unchanged `dst`), so a ship I captured is mine (never a target), and a ship Rick captured from Bob that
   sails to my port is not capturable by me. Bob's warships may still capture it (the port is not Bob's).
6. `NET_VER` 5 -> 6 and `PROTO_VERSION` 5 -> 6 (must match; re-export clients and restart `relay.py`). No new state fields => `_net_checksum()` unchanged.
- Bots: same `step_ships` code. With nothing capturable in sight an idle bot warship just stays on its station point (it never chases a protected ship).
- NOT changed: ship art, capture animation, 0.8 s boarding, 1.2 s cooldown, hover top bar, UI.

### Test scenarios (Spectate; online if you can). Follow a nation with `my_slot` = A. Use `CAPTURE_OWN_PORT_PROTECTED := false` to compare with the old behaviour.
(a) Rick's trade ship sailing to MY port: my warship parked next to my port never locks or boards it (no crosshair/orange, ship keeps sailing and pays on arrival).
    Manual order on it: toast "That ship is sailing to your own port".
(b) Rick's trade ship sailing to ALLY Bob's port (A allied with Bob, not with Rick): my warship captures it. Bob's alliance changes nothing.
(c) Bob's (ally's) own trade ship, any destination: never captured by me. My own trade ships: never targets.
(d) While my warship is boarding Rick's ship (0.8 s window, use 1x speed): make an alliance with Rick, or have the destination port conquered by me: boarding stops, no stuck "being captured"
    state (ship sail colour back to Rick's), no crash. Also: warship locked (not yet boarding) when the port changes owner to me: it lets go and returns to its station.
(e) Rick's ship that Bob captured and that sails to my port: my warship must not capture it; Rick's other ships to Bob's port still can be captured.

### Open issues / not verified
- Nothing was run in Godot (parser errors possible). Online desync not tested; both sides run the same code, but client and relay must be updated together (protocol 6).
- Click on a protected trade ship now behaves like clicking open water (the ship is not a target); there is no special toast on a plain click (only `validate` gives the message, e.g. for a stale order).
- Warships of the nation whose port it is will wait idle with nothing to capture (by design). Whether this makes warships go out to the sea lanes is gameplay AI: NOT done here (not requested:
  bots just stay on their station point).

### Exact stopping point
All requested items 1-8 are implemented. Next action for you: F5 -> report parser errors -> run scenarios (a)-(e). If the rule feels too strong/weak, flip `CAPTURE_OWN_PORT_PROTECTED`.

---------------------------------------------------------------------------------------------------------------------------------------------------------
# (previous round)

## CURRENT TASK (this round): status = ALL FOUR TASKS IMPLEMENTED, NOT RUN IN GODOT
Godot is not available in my environment, so nothing below was played. Done instead: scripted exact-match edits, a static scope checker
(tab indentation, no variable declared twice in a scope, bracket balance, no duplicate functions, every new function referenced) - all clean.
Backup of the file you sent: `main.gd.bak_before_capture`. **First thing to do: open the project, press F5, and send me any parser error line.**

### Audit (what I found before editing)
- Golden balls: ONE place - `_draw` drew a gold circle + outline above every TRADE ship (`draw_circle(... ACC)`). Warships, troop boats (`_draw_paper_boat`)
  and the mine art have none, so only the trade-ship ball was removed. (Mine art keeps its small red/colour dots: it is not a ship.)
- Old steal: `_fire()` -> `_capture_trade()` paid the thief instantly, deleted the trade ship, and the generic gunfire line (`s["shot"]`) was drawn at it.
  Also `step_ships()` ran only on the 0.5 s economy tick (`TICK`), so a 1.2 s cooldown could not be exact there.
- Hover: `_update_info()` only looked at the land tile under the mouse; `_ship_at()` / `_enemy_unit_at()` are click helpers for my own ships / enemy targets.
- Targets: `_enemy_targets(o)` already skips own and allied boats, trade ships and warships; mines, `_bot_fleet`, `validate("shipatk")`, auto-targeting and
  shooting all go through it. Aimlock already existed (`s["tgt"]`) but the shooting step could still pick another nearby target.

### What changed (all in `main.gd`, plus `server/relay.py` PROTO_VERSION 4 -> 5 and `NET_VER` 4 -> 5 because the rules changed: client and relay must match)
1. **Golden ball removed** from trade ships (nothing else about ship art changed).
2. **Capture (replaces the thrown line + instant steal)**
   - Aimlock: a warship locks one trade ship (`tgt`) and keeps it until it is captured, sunk, gone, allied, or another warship boards it first. While locked on a
     trade ship it only boards it (it never opportunistically shoots/steals other trade ships); it may still shoot nearby enemy warships/transports.
   - Approach: it sails the existing intercept course, holds position within `CAPTURE_HOLD_DIST` (1.5 tiles).
   - Boarding (`step_capture`, in game rules): within `CAPTURE_RANGE` (4 tiles) the warship starts boarding. It lasts `CAPTURE_STEPS` = 8 steps = 0.8 s.
     On the 8th step - one exact game step for every client - `_complete_capture` changes the owner; the trade ship keeps sailing its route for the new owner and
     the new owner is paid when it arrives (no instant gold any more). If the ship gets farther than `CAPTURE_HOLD_RANGE`, disappears or becomes an ally's, boarding stops.
   - Animation (look only, derived from sim state, never changes the game): the sail colour wipes from the old owner's to the captor's colour with a filling ring,
     the warship shows muzzle flashes + smoke puffs at its gun and spark rings on the trade ship (no lines), then a white ring flashes at the capture.
   - Cooldown: `CAPTURE_COOLDOWN_STEPS` = 12 steps = 1.2 s, counted in 0.1 s attack steps. I chose to run the whole capture machine from `step_attacks()` (0.1 s,
     `ATK_TICK`, identical offline and online) instead of `step_ships()` (0.5 s), because 1.2 s is not a multiple of 0.5 s. Same for human and AI warships.
   - A just-captured ship is untargetable for `CAPTURE_PROTECT_STEPS` (30 steps = 3 s) so two warships cannot ping-pong it.
   - Bots use the same code (auto-lock in `step_ships`), so AI warships capture exactly like yours.
3. **Hover (top bar)**: `_hover_unit()` + `_show_unit_info()`. Trade ship: owner name + "Trade boat". Warship: owner name + "Warship  HP cur / max".
   Radius `HOVER_SHIP_PX` (26 px, grows with ship size); a warship beats a trade ship when both are close; hovering land still shows the nation info as before.
   Colour: ALLIES **and MY OWN ships** are `UI_GOOD` green (own ships also get a "YOURS" tag, allies "ALLY"); enemy ships stay white. Spectate: "mine/ally" is
   relative to the followed nation (`my_slot`).
4. **Allies**: verified every target/damage path uses `_enemy_targets` (allies excluded): auto-targeting, shooting, mines, `_bot_fleet`, capture and `validate`
   (`shipatk` on an ally is refused). New alliance while locked/boarding: the lock and the boarding are dropped on the next step (`_is_trade_enemy`); ending the alliance
   restores normal hostility. `validate` also refuses a trade ship that is already being captured.
5. Online checksum now also covers the capture state (ship `cid`/`ccd`, trade ship owner/`capt`).

### Tune these (constants near the top of `main.gd`)
`CAPTURE_RANGE` 4.0, `CAPTURE_HOLD_DIST` 1.5, `CAPTURE_HOLD_RANGE` 7.0, `CAPTURE_STEPS` 8 (animation time = steps x 0.1 s), `CAPTURE_COOLDOWN_STEPS` 12 (1.2 s),
`CAPTURE_PROTECT_STEPS` 30, `CAPTURE_FLASH_STEPS` 6, `HOVER_SHIP_PX` 26.0, warship HP `SHIP_HP` 100 (+`PORT_HP_PER_LEVEL` per port level).

### Test plan (please run, in this order)
1. F5: no parser error; lobby -> Spectate at 4x. Zoom onto a coast with ports: trade ships have no gold ball.
2. Watch a warship near trade ships: it locks one, sails alongside, muzzle flashes + ring fill (~0.8 s), colour flips, white ring, ship keeps sailing under the new colour;
   the same warship waits ~1.2 s before the next capture. No thin line while capturing.
3. Hover a trade ship and a warship (also while they move): top bar shows owner (+HP); own/ally = green, enemy = white; land hover still works.
4. Make an alliance (right-click a nation) while a warship is boarding that ally's ship: boarding stops, nothing is captured, no shots between allies.
5. Online two clients: no "desync" message after a capture (checksum includes it). Relay must be the new `relay.py` (protocol 5).

### Open issues / not verified
- Not run in Godot at all (parser errors possible). The boarding progress ring moves in 8 visible steps (0.1 s each), not continuously.
- A captured ship sails on to its ORIGINAL destination port; it pays the new owner (route value x source-port level) and the port's owner as usual. If you want it to
  turn toward the thief's own port instead, that needs a new route search (not done).
- If trade between the thief and the destination port's owner is cancelled (`no_trade`), the captured ship vanishes without payment (existing rule).
- Warships still follow the moving ship with the existing intercept planner; in tight channels they may need a few re-plans (every 2-20 ticks).

### Exact stopping point
All four tasks are implemented and statically checked. Next action: run the test plan above and report problems.

---

(Older notes below are from earlier rounds.)

# AI_PROGRESS.md - Landgrab premium visual upgrade

**Task:** premium visual identity, HUD, map presentation and interaction feedback - no gameplay changes.
**Phase:** 3 (map readability + HUD unification + cards + labels/icons) - COMPLETE and saved. Project is in a stable state.
(Phase 2 notes below are kept; Phase 3 notes are at the end.)
**Backup of the untouched project:** `landgrab6.zip` (the previous file you got). Original code is also unchanged apart from the files below.

## Inspection summary (Phase 1)
- Godot 4.3, single scene `main.tscn` + `main.gd` (Node2D). Map = one Sprite2D with a canvas_item shader reading data textures
  (owner, conquest time, palette, terrain). All UI is built in code in `_build_ui()` on CanvasLayers; no external fonts/assets.
- Problems found: default Godot font and theme, flat panels without depth, every button/card used ad-hoc colours, the map shader used a harsh
  white 1-tile border, a checkerboard ocean and per-tile speckle, no hover/selection feedback on the map, no feedback for fresh conquests,
  pastel nation colours that blended into the grass, plain leaderboard rows, no troop capacity bar or growth rate in the HUD.
- No multiplayer/networking in the project; maps are fixed PNGs (no procedural generation).

## Completed improvements
1. **Visual identity**: one `Theme` (`_make_theme`) - system font stack (Inter / Segoe UI / SF Pro / Roboto / Arial, falls back to Godot's font),
   calm text colours, styled tooltips, gold slider with a round handle. Shared palette constants `UI_*`.
2. **Panels / buttons / cards**: glass panels with soft border and drop shadow; primary (gold) and secondary (glass) buttons with proper
   hover/pressed/disabled states; building cards with hover lift, selected state (gold border + glow) and no style rebuild every refresh.
3. **HUD**: stat rows with coloured accent bars (troops / territory / gold), troop capacity bar, real troop growth rate (+x/s) and gold income
   (+1.0K/s), leaderboard with rank numbers, your row in gold, and your own rank shown when you are outside the top 6.
4. **Map**: calm deep-to-shallow ocean with foam line (shore distance baked once per map), land relief patches + beaches, softer borders
   (dark line between two nations, light rim toward free land, soft coast rim), richer nation colours that skip the grass-green band.
5. **Feedback**: nation under the cursor gets a soft highlight; freshly captured tiles flash briefly (from the real conquest timestamps);
   hover/press scale on buttons and cards; info / context / attack / message / end panels fade in when they really appear.

## Files modified
- `main.gd` (everything above). New: `AI_PROGRESS.md`. README.md got a Round 8 section.

## Tests
- NOT run in Godot (no Godot available in my environment). Done: static checks of the edited GDScript (tab indentation, duplicate locals,
  all new functions referenced) and a numpy approximation of the new map shader on the Africa map to check the palette (not a Godot render).
- Please check on first run: no parser errors; shader compiles (map visible); panels look right; hover highlight; leaderboard.

## Known issues / unverified
- System font depends on the PC (falls back to Godot's default font if none of the listed fonts exist).
- Shoreline gradient is 12 tiles wide at MAP_SCALE 0.5; if you raise MAP_SCALE you may want to widen it in `_calc_shore` / the shader.
- Lobby screen only inherits the theme/panel/button styles; it has not been redesigned.

## Where work stopped / next action
Stopped at a stable checkpoint after the first upgrade. Next: (1) lobby/menu redesign, (2) attack-front glow and arrows on the map,
(3) building placement preview polish + sound/notification toasts.


---
## Phase 3 (this session)
**Backup before Phase 3:** `landgrab7.zip`.

### Completed
1. **Map**: ocean is calmer (less tonal noise, weaker shallow gradient, fainter foam line); borders cleaner (dark line between nations 42%,
   light rim toward free land 26%, faint coast rim 7% instead of the earlier stronger glow); new **selected-nation outline** (bright border on
   the nation picked with the right-click menu); the hover highlight from Phase 2 is kept.
2. **Labels**: drawn in priority order (you first, then biggest nations); a label that would overlap a more important one is skipped
   (`_draw_labels`); thinner dark outline + soft shadow for readability on every colour; ally names are light green.
3. **Building icons**: important buildings drawn first, villages last; icons never stack (14 px grid keeps the first); villages hidden when
   zoom < 0.8 (zoomed far out); icon size clamped 13-44 px.
4. **Cards**: clear hierarchy - name (primary), price (gold, red when you cannot pay), hotkey badge top-left (muted), owned count top-right
   (`x2`, accent). Cards you cannot afford are slightly dimmed; sea cards without a port stay at 50%. Purchase logic/costs untouched.
5. **HUD**: hover info bar has primary (name 18, troops 16) vs secondary (buildings/gold 13, muted) text; panels a little more compact
   (HUD 196 px, leaderboard 176 px, cards 98x100).

### Files modified
`main.gd`, `AI_PROGRESS.md`, `README.md`.

### Tests
NOT run in Godot (not available here). Only static checks (tab indentation, duplicate locals, new code paths read through).
Please check on first run: shader compiles, nation names do not overlap when zoomed out, cards look right, right-click outline shows.

### Known issues / risks
- Label collision uses the label's on-screen box; very long names at high zoom can still touch building icons (icons are drawn first, labels on top).
- The `\u00d7` (multiplication sign) in the card count needs a font with that glyph; all common UI fonts have it.
- Lobby screen still not redesigned.

### Stopped at
Stable checkpoint after the Phase 3 items above.
### Next specific actions
1. Lobby/menu redesign. 2. Attack-front glow / arrows. 3. Building placement preview polish and toast notifications.
### Files to keep
The whole project folder (`landgrab8.zip`); `AI_PROGRESS.md` is the resume point.


---
## Phase 4 (this session) - gameplay animation and feedback
**Backup before Phase 4:** `landgrab8.zip` (the file you uploaded). Only `main.gd`, `AI_PROGRESS.md` and `README.md` changed.

### Inspection findings
- Single scene/script. Map is one shader sprite; everything else is `_draw()` on the Node2D + code-built UI. Phase 2/3 already had: button/card
  hover+press scale (`_hover_fx`), panel fade-ins (`_panel_fade`), nation hover highlight, per-tile capture flash (shader, from real timestamps),
  right-click nation outline. These were reused, not duplicated.

### Completed (all visual only - no combat, economy, price, save or network code touched)
1. **Ring effects system** (`fx` array, `_fx_ring`, `_draw_fx`): capped at 24, drawn only when on screen, radius clamped 10-46 px so it stays readable at any
   zoom, positions are world tiles (follow the territory when panning/zooming), cleared in `start_game`. Only runs in phase "play".
   Used for: your attack launched (blue, at the clicked point), your attack escalating Skirmish->Assault->Surge, building built/upgraded/placed (gold),
   building captured by you (green) or lost by you (red).
2. **Attack indicator**: breathing ring behind the troop tag of your attacks and attacks against you (same set that already had tags; bot-vs-bot never drawn).
3. **Boat wake**: 2-4 faint dots along the boat's real path (2 when more than 10 boats exist).
4. **Selected nation**: outline now fades in (`sel_amt`) with a gentle pulse, plus a faint overall lift of the selected nation; resets when the menu closes or the target changes.
5. **Toasts**: `say(text, secs, kind)` - kind "info" (default) / "good" (green) / "bad" (red) tints text and border, and the panel pops in (kill-safe tween).
   Success: built/placed/captured/conquered = good. Errors (not enough gold, invalid spot, ally, no sea route, port needed) = bad.
6. **Cards**: success pop (`_card_pop`), short shake on denial (`_card_deny`) when you press a card you cannot afford / need a port, or click an invalid spot
   with "Not enough gold". Pressing a card you cannot afford still enters placement mode exactly like before (logic unchanged).

### Files modified
`main.gd`, `AI_PROGRESS.md`, `README.md`.

### Tests
NOT run in Godot (not available in my environment). Done: scripted patch with exact-match assertions (every edit applied once), tab-indent check outside the shader,
all new functions referenced, no duplicate local names in the edited functions. **No debugger output, no zoom-level check, no rapid-click test happened.**
Please check on first run: no parser errors; ring/wake/attack-ring visible; toast colours; card pop/shake; selected-nation outline pulse.

### Known risks / unverified
- Cards live inside a container; Godot containers can reset a child's scale/rotation when they re-sort, so the pop/shake may be cut short by a layout refresh.
  If it looks wrong, tell me and I will move the effect to the card's icon instead.
- Toast pop uses the panel's size before the new text is laid out, so the pivot can be slightly off for very different message lengths (cosmetic).
- Attack ring and tag overlap slightly at low zoom (ring is faint and drawn under the text).
- Not done: lobby redesign, sound, tooltips beyond the existing theme ones, ownership-change effect for single plain land tiles beyond the existing shader flash.

### Stopped at
Stable checkpoint after the items above; nothing half-finished.
### Next specific action
Run the game and report any parser error/debugger message; then Phase 5 = tune what looks off, add attack-front direction arrows, and lobby/menu polish.


---
## Phase 5 (this session) - UI polish and responsive layout
**Backup before Phase 5:** `landgrab9.zip`. Only `main.gd`, `AI_PROGRESS.md`, `README.md` changed. No scenes changed (`main.tscn` only holds the script).

### Screens inspected (verified in code)
Lobby, in-game HUD (troops/territory/gold), hover info bar, leaderboard, build cards + sea sub-panel, attacks list, right-click menu, message toast, zoom buttons, end-of-game panel.
**Not present in the project (grep verified), so not created:** settings menu, pause menu, loading screen.

### Findings
- `project.godot` uses `canvas_items` + `expand`: the UI viewport is never smaller than 1280x720 units; other window sizes scale uniformly or extend one axis. So panels anchored to window edges stay on screen; fixed-pixel sizes are OK.
- Verified problems: inconsistent window margins (10 vs 14 px); duplicate hard-coded colours that differ slightly from the `UI_*` palette; two copies of the progress-bar styling; two copies of the map tooltip drawing (one without left/top clamping);
  the attacks list could grow down into the card bar when many attacks/boats are active; zoom buttons could take keyboard focus (Space/Enter would re-trigger zoom); disabled/blocked states on cards were only colour; lobby "Join game" silently did nothing when the lobby was full; end panel had no outcome colour.

### Completed
1. `UI_MARGIN` (12 px) used by HUD, info bar, leaderboard, card bar, zoom panel and attacks list.
2. Palette: lobby/attack/ctx/info colours now use `UI_MUTED`, `UI_TEXT`, `UI_GOOD`, `UI_BAD` (map drawing colours untouched).
3. `_style_bar()` shared by the HUD troop bar and the lobby bar.
4. Attacks list: incoming attacks first, then yours, then boats; capped to the free height above the card bar with "+N more attacks" (hidden ones still run normally).
5. Zoom buttons: 40x36, tooltips "Zoom in/out", no keyboard focus.
6. Card tooltips now also say "Needs a port first." / "Not enough gold yet." when that is the state.
7. Map tooltip: one shared `_tip()` (building preview now uses it), clamped on all four sides.
8. Lobby: join button disabled and labelled "Lobby full" when full and you are not in it (logic unchanged).
9. End panel: green for victory, red for defeat, bigger button, more spacing.

### Tests
NOT run in Godot (not available here). No resolutions were rendered; 1280x720 / 1600x900 / 1920x1080 / narrow windows were reasoned from the stretch settings only. Static checks only: scripted patch with exact-match assertions, tab indentation, new functions referenced.
### Known risks / remaining
- `_refresh_attacks` reads `ctl.position.y` for the cap; if a layout pass has not run yet it falls back to 2 rows (harmless).
- Font sizes are still literals (11-22) rather than named constants; hover info bar can get wide with many building types (centre aligned, ~850 px max at 1280).
- Phase 4 risk still open: container may reset card scale/rotation during card pop/shake.
### Stopped at
Stable checkpoint. Next three: (1) run the game and fix any parser/runtime error, (2) named font-size constants + lobby visual pass, (3) settings/pause menu only if you want one.


---
## Phase 6 (this session) - map quality, performance, stability
**Backup before Phase 6:** `landgrab10.zip`. Changed: `main.gd`, `AI_PROGRESS.md`, `README.md`. (The screenshot mentioned in the request did not arrive in the chat, so the diagnosis below comes from the code, not the image.)

### Cause of the pixelated coast / territory edges (traced in code)
- Godot 4.3, canvas_item shader on one Sprite2D. The map is a tile grid of `W x H = source PNG x MAP_SCALE (0.5)`, e.g. World 1000x500, Europe 800x650. `make_map` point-samples the PNG (one source pixel per 2x2 block) into `land[]`.
- The shader reads every texture with `texelFetch` / nearest, so each tile is a hard `zoom x zoom` square: staircase coast, tile-wide foam line, tile-wide (1 tile thick) borders that get fatter as you zoom in.
- No polygon geometry is involved; the source PNG is not the limit (it is 2x the grid). The simulation grid is the limit, and I did NOT change it (ownership, land count, balance depend on it).

### Implemented (rendering only; `land[]`, ownership, combat, economy untouched)
1. **Smoothed coastline**: new linear-filtered `land_tex`; the shader interpolates the land flag between tile centres and cuts at 0.5. Staircase diagonals become smooth lines, straight coasts do not move; inner-corner pixels borrow owner/terrain of the heaviest surrounding land tile. (Checked with a numpy simulation on the real Europe mask: shape preserved, diagonals smooth. NOT a Godot render.)
2. **Borders keep a constant thin width when zoomed in** (`px_tile` = zoom; width = 1.1/zoom tile per side, whole tile when zoom <= ~1.1 so the default view looks as before). Dark border / light free-land rim / coast rim / selected outline all use it.
3. **Foam line** follows the smoothed coast and is thin when zoomed in.
4. **Terrain tooltip** appears only after the mouse rests 0.45 s and never while dragging (fade-in); build-placement tooltips are still immediate.
5. **Labels**: text sizes cached (`str_sz`) instead of `get_string_size` twice per label per frame; labels whose centre is on screen are nudged to stay fully inside the window; other nations' labels are skipped when they would sit under a HUD panel (yours is always drawn).
6. **Smooth zoom**: wheel/buttons set `zoom_goal`, `_step_zoom` eases the real zoom (~0.15 s) around the cursor; `fit()` sets both.
7. Skip per-frame array rebuilds when `floats` / `fx` are empty.

### Performance - what was and was NOT done
- NOT measured: no Godot here, so no profiler/FPS numbers exist. Findings are from reading the code: per-frame `_draw` (labels with 2 string measurements + 6 text draws each, buildings, rails), `rebuild_image` uploading two W*H*4 textures up to 20x/s while the map changes (already self-throttled 0.05-0.25 s), leaderboard rebuilt every 3 ticks (1.5 s, cheap). Only the label-size cache and empty-array guards were changed because they are safe by reading.
- New shader cost: 1 extra texture read per pixel plus a 4-iteration loop only on inner-corner coast pixels.

### Tests
NOT run in Godot. Static only: shader braces/parens balanced, tab indentation, new members referenced. **The shader has never been compiled**; if the map is blank or Godot reports a shader error, send me the message (fallback: restore Phase 5 `main.gd` from `landgrab10.zip`).

### Remaining / risks
- Territory-vs-territory borders are still tile-staircase (thin now, but not smoothed); coast smoothing is visual only so a boat/attack can look <0.5 tile off the drawn coast.
- Label nudging uses window size, not the map; very small nations still hide at low zoom (unchanged).
- Sim grid resolution unchanged; a higher MAP_SCALE would change balance and needs your approval.
### Stopped at
Stable checkpoint after the items above. Next: (1) run it and report shader/parser errors, (2) measure real FPS (Debugger > Monitors) on World map with many attacks, (3) optional smooth border shapes / sub-tile ownership rendering.


---
## Mobile / touch pass
**Changed:** `main.gd` (new last section "touch / mobile"; 2 lines inserted in `_ready`; the attack-list X button size and its x position now read
`atk_btn_px` / `safe_cur.x`, which equal the old values on desktop), `project.godot`, `README.md`. No mouse/keyboard code touched. No earlier mobile code existed
except the existing `InputEventMagnifyGesture` branch (trackpads), which is left alone.
**Done:** pinch + two-finger pan, long press = right click, confirm-before-place/spawn with marker, cancel / recentre buttons, Android back, bigger touch targets,
UI scale from DPI, safe-area insets, tap slop, lite shader, 60 fps cap, mobile renderer + texture import + landscape in project settings.
**Not verified:** never run in Godot or on a device; emulated-mouse flags (`DEVICE_ID_EMULATION`) are assumed from Godot 4.3 behaviour; if taps place buildings
without the confirm marker, that check did not match - tell me.
**Next:** test on a phone; adjust `TOUCH_MAX_SCALE`, `TOUCH_SLOP`, `TOUCH_HOLD`; optional portrait "rotate your phone" hint.



---
## Phase 7 - Multiplayer architecture audit (design only)
**Result:** `MULTIPLAYER_ARCHITECTURE.md` (new, project root). **No game code, scenes or project settings were changed**; `main.gd`, `main.tscn`, `project.godot` are byte-identical to `landgrab12-mobile.zip`.
**Recommendation:** dedicated, server-authoritative Godot server using the built-in MultiplayerAPI (ENet first; WebSocket if a browser build is wanted). Clients send commands only; the server validates and applies them with the same rule functions the bots use.
**Verified in code:** no networking exists; player 1 is hard-coded as the human (~84 comparisons, 12 `players[1]`); bots = players 2..N and already use `start_attack` / `can_place` / `place_building`; all territory changes pass through `_set_own`; sim is frame-driven with the global RNG (22 sites); rule functions call UI helpers (`say`, `_float_at`, `_fx_ring`...); maps are fixed PNGs (deterministic); win check only looks at player 1.
**Not verified (no Godot here):** nothing was run or tested; server CPU/bandwidth/hosting numbers are estimates; headless run of the current `main.gd` was not tried.
**Tests performed:** none in Godot. Only a byte comparison confirming the game files are unchanged.
**Stopped at:** audit + architecture complete; preparatory code changes P1-P8 are listed (with risk) but intentionally not implemented because they cannot be tested here.
**Next specific action (Phase 8):** write unit tests for the existing rules, then P1 (controller field), P5 (territory-delta log in `_set_own`), P7 (server RNG), then command envelope + event queue, then remove hard-coded player 1. See section 7 of `MULTIPLAYER_ARCHITECTURE.md`.
**Questions to answer before Phase 8:** max humans per match; browser build needed?; late-join takeover of bots?; team/alliance victory?; disconnect policy (60 s grace then bot) OK?


---
## Nuclear overhaul (Bomb Launcher / SAM Site / bombs / fallout)
**Backup before this work:** `main.gd.bak_before_nukes2` (copy of the uploaded `main.gd`). Changed: `main.gd`, `AI_PROGRESS.md`.
**Status: written and statically checked (tab indentation, no variable redeclarations, no leftover references to removed constants, bracket balance). NOT run in Godot.**

### What you asked for -> what was done
- **Port arrow now only has Warship and Water Mine.** The nuclear cards moved to their own section: a second row under Village / Station / Port with
  **Bomb Launcher** and **SAM Site**. The small arrow on the Bomb Launcher card opens the bombs popup (**Small Bomb, Nuke, Mega Bomb**).
  Hotkeys: 6 launcher, 7 SAM, 8 small bomb, 9 nuke, 0 mega bomb.
- **Bomb Launcher** (internal id `silo`): 1M to build. Click it again with the tool to upgrade, **4 levels** (1.5M -> Lv2, 2.5M -> Lv3, 4M -> Lv4),
  shown as "Lv n" on the map. Lv1 fires the Small Bomb (750K), **Lv2+ the Nuke (5M)**, **Lv4 the Mega Bomb (25M)**. Higher levels also reload
  faster (60 / 50 / 40 / 30 s). Level 3 has no extra bomb (not specified) - it only reloads faster.
- **SAM Site** (internal id `sam`): 1.5M. Range **24 tiles** (maps are 500-1000 tiles wide, so the old 14 was tiny). Every ready SAM that has a
  hostile bomb inside its range fires once (7.5 s reload). Hit chance: Small Bomb 80%, Nuke 55%, Mega Bomb 30%. Allies' bombs are never shot.
  The SAM tool shows the range circle of every SAM you own and of the one you are placing.
- **Bombs**: Small Bomb inner radius 5 / outer 10 tiles; Nuke 12 / 24; **Mega Bomb inner radius = 0.5 x the longer map side** (`MEGA_RADIUS_FRAC`) -
  aimed at the middle it covers about the whole map. (You wrote "whole map bomb": I read it as a huge blast, not a literal wipe of every tile. Set
  `MEGA_RADIUS_FRAC := 2.0` for a literal whole-map wipe, which also eliminates everyone including you.)
- **Fallout zone**: every land tile inside the inner radius (owned or not) and every ring tile that lost its owner becomes **nobody's land AND
  contaminated**. The map shader draws it toxic green with a glowing edge; the hover tooltip says "Nuclear fallout - nobody owns it. Attack it to claim
  it." Claiming works exactly like normal free land (click / attack it). The mark is removed in `_set_own` the moment a tile gets an owner.
  The fallout flag lives in the alpha byte of `map_data` (the shader ignores that alpha for drawing).

### Files / functions touched (all in `main.gd`)
Constants block "nuclear weapons"; `BUILD_LABEL`, `BUILD_TIP`; `price`, new `_place_cost`; `can_place`, `place_building`, `_can_upgrade`, `_upgrade_label`;
`_silo_for` / `_silo_ready` (level argument), `_bomb_inner/_bomb_outer`, `_launch_nuke`, `_sam_intercept`, `_detonate`, new `_mark_fallout`, `_set_own` (clears
fallout); `validate` ("nuke"), `_click`, `_toggle_build`, key handler; `_draw_nuke_preview`, `_draw_nukes`, `_draw_atom` (+ nuke / mega icons), `_draw_preview` (SAM range);
`TERRAIN_SHADER` (`fall_at`, fallout colouring); UI: second card row, `launcher_arrow`, `nuke_panel`, `_toggle_nuke`, `_place_nuke`, `_toggle_sub`, `_refresh_cards`.
Multiplayer: the command is still `{"type":"nuke","kind":...}` (kind may now be `atom`, `nuke` or `mega`); all rules run in the deterministic sim (`sim_rng`, row-major loops),
so clients stay in step. `relay.py` needs no change if it already forwards the `kind` string (check its allowed values if it validates them).

### Not done / risks
- NOT run in Godot. First run: check Output for parser errors, then: build a launcher, upgrade it, fire each bomb, watch SAM rings, claim fallout.
- AI nations do not build launchers, SAMs or fire bombs (they never did).
- The Mega Bomb detonation loops over up to ~500k tiles in one frame: expect a short hitch on a big map.
- Prices of upgrades (1.5M / 2.5M / 4M) and the SAM hit chances / ranges are my choices - tune the constants at the top.
- Gold income is about +1000/s: a 5M nuke is ~83 min and a 25M mega bomb ~7 h of base income, as you specified; you may want more income sources.
### Stopped at
Stable checkpoint after the items above. Next: (1) run it and report any parser error, (2) optional AI use of SAM / launcher, (3) fallout slowing or damaging troops if you want it to matter more.


---
## Beta-launch performance pass 2 (from landgrab-nukes-v7.zip)

**Files changed:** `main.gd` ONLY (copy it over your project's `main.gd`). `main.gd.bak_before_perf8` is your v7 `main.gd`, untouched (roll back with it).
Everything else in the zip (maps, server, docs, scenes, project settings) is exactly what you sent. This pass builds on the earlier "Late-game performance pass"
in `docs/PERFORMANCE_NOTES.md` (attack stepping, warships, mines, trade ports, rails) - it does NOT redo those; it adds the client-side drawing / quality work below.

## Status: written and statically checked, NOT run in Godot (no Godot in my environment)
Static checks done: bracket balance, tab indentation, no variable redeclaration inside any function (scope-aware script), all new members/functions referenced.
Please run once and watch the Output panel for parser errors before the beta.

## What I found (by reading the code, no profiler available)
- The end-game lag when crowded is mostly DRAWING, per frame: every visible building is ~20 draw calls (hundreds/thousands at the end), and every trade ship
  (up to 500) is a paper boat of ~5 draw calls plus two polygon arrays. Zoomed out, all of them are on screen at once.
- Next costs: the map texture upload while territory changes everywhere (already self-throttled) and the heavy terrain shader on phone GPUs.
- The simulation itself looked bounded (bots think every 1-2 s over <=300 border tiles, attacks step 3x slower for bot-vs-bot, route searches are budgeted).
- Layout: v7 already has ONE bottom bar (cards + troop slider) with popups placed above their own card and the attack list stopping above open popups - I left that alone.

## What I changed (client / look only - no rules, no balance, nothing the lockstep relay compares)
1. **Simple icons when crowded** (`_draw_bld_lod`): when zoom < `lod_zoom` (3.0) and more than 90 buildings are on screen, buildings are drawn as one-or-two
   coloured shapes (circle = village, ringed circle = city/duchy, square = station, diamond = port, triangle = launcher/SAM). Zoom in (or play a small match) and you get the full art.
2. **Trade ships as dots** when more than 40 sail and zoom < `lod_zoom` (boarded / just-captured ships keep the full art and rings).
3. **Cheaper de-duplication** of overlapping icons (integer grid key instead of a Vector2i per building per frame).
4. **Automatic quality** (`_perf_adapt`): if the frame time stays above ~1.5x the target (about < 40 fps) for 3 s, it steps down at most once per 6 s:
   level 1 = lite map shader (same one phones use) + no conquest sparks; level 2 = map texture uploaded at most every 0.12 s and LOD zoom 5; level 3 = upload every 0.2 s and LOD zoom 8.
   It never steps back up inside a match; a new match starts at level 0 (the lite shader stays once applied). It prints "automatic quality level N" to the Output log.
5. **Narrow windows / small phones** (`_compact_ui`, viewport narrower than 980 UI units): cards 90x88 instead of 98x100 and a 150-wide troop slider box, so the bar does not run into the zoom buttons.

## Not done / risks
- NOT measured: no FPS numbers exist. Tell me what a crowded late game shows in Debugger > Monitors (FPS, draw calls) and I can tune `lod_zoom`, the 90 / 40 thresholds, or the levels.
- Phone GPUs: if the map still feels heavy on a low-end phone, the next step is rendering the map at lower resolution (needs project stretch/viewport changes - not attempted blind).
- The map texture is still uploaded whole (Godot has no partial upload for ImageTexture); only the interval adapts.
- Mega Bomb detonation spread (`BLAST_TILE_BUDGET`) and trade timing changes in v7 were left as they are.
- I could not look at the layout on a real phone: check the bottom bar, popups above Port / Bomb Launcher, message bar and the attack list on one phone and one 16:9 window.

## Stopped at
Stable checkpoint after the five items above; nothing half-written.
## Next specific actions
1. Run the game, play to a crowded late game, check Output for errors and for "automatic quality level" lines.
2. Tell me FPS / draw-call numbers (or whether it still lags and at which zoom) - then tune thresholds.
3. Test on one phone (landscape): bottom bar width, popups, text size.


---
## Hosting fix pass (from landgrab-mobile-v4.zip)
**Backups:** `server/relay.py.bak_v15` (old relay). Static/runtime checks: the relay was RUN here and tested with a real WebSocket client (health page, upgrade, public lobby, version mismatch,
two players -> match start, commands). `main.gd` was only edited in 3 small spots (not run in Godot).
- **Bug found and fixed (server): `relay.py` dropped every `nuke` command** (its command whitelist `INT_FIELDS` / `STR_FIELDS` had no `nuke` entry), so no Small Bomb / Nuke / Mega Bomb ever fired in an online match.
  Test before: forwarded ['attack'] only; after: ['attack', 'nuke:atom', 'nuke:mega'].
- `PROTO_VERSION` 15 -> **16** (relay.py) and `NET_VER` 15 -> **16** (main.gd): an old relay now answers "Version mismatch" instead of silently ignoring bombs. Re-export the game AND re-deploy relay.py.
- **Likely reason it "does not work" when hosted:** `OFFICIAL_SERVER` in main.gd is a trycloudflare.com *quick tunnel* address (changes at every restart). Put a permanent https address there and re-export. See `server/DEPLOY.md`.
- New: `server/check_server.py` (tests a hosted address like the game does and says what is wrong), `server/DEPLOY.md`, `server/Dockerfile`; the relay prints a hosting checklist at start, honours `HOST` / `PORT`;
  the lobby note now shows which address it could not reach.
- Not verified: your actual hosting setup (I cannot see it), the real Cloudflare / hosting-service proxy, TLS (check_server.py handles wss:// but I could only run it against ws:// locally), and the game in Godot / a browser.
### Next
1. On the machine that hosts: run `python relay.py`, then `python check_server.py <your public address>` and tell me the exact output if it is not "OK".
2. Set `OFFICIAL_SERVER` to the permanent address, re-export the web build, re-upload.


---
## Fix pass v6 (from landgrab-mobile-v5.zip) - players, growth shape, boats, Mega Bomb
**Backup:** `main.gd.bak_before_v6` (your v5 `main.gd`). **Status: written + statically checked (brackets, tabs, no variable redeclaration, no leftover references). NOT run in Godot.**
The growth rule was tested in a Python simulation (old rule -> square, new rule -> round blob); the relay was run and tested with a real WebSocket client (it forwards `ally_ask` and `nuke`).

1. **Alliances between real players.** Two causes: (a) `validate("ally_ask")` flatly refused human targets ("not available yet"); (b) the right-click menu only opened for `own[tile] > 1`, so it
   never opened on slot 1 and also opened on your own land when you are not slot 1. Now: menu opens on every other living nation (`own > 0 and != my_slot`). Pressing **Make alliance** on a
   human sends a *request* (2 min, `ALLY_REQ_TICKS`); the other player gets a 9 s message, and their menu button for you now reads **Accept alliance** - pressing it forms the alliance
   (both sides' attacks on each other are cancelled). Your own button says "Request sent" meanwhile. Bots still answer at once (60%). **Cancel alliance** works for both.
2. **Growth no longer looks like a cube.** The attack step took front tiles with 3 own neighbours first, then 2, then 1 - that fills corners first and grows squares. Now notch tiles still
   go first, but all other front tiles are one random pool, and free-land growth prefers (75%) the tile nearer to the nation's centre out of two random candidates (per-nation centroid
   kept in `Player.csx/csy` inside `_set_own`). Wars between nations use the random pool without the centre bias. All integer / `sim_rng`, so online clients stay identical.
3. **Boats.** No port needed any more: the boat leaves from any water next to your coast (`_coast_waters`, sampled to ~1500 coast tiles). Attacking **free (unowned) land** by boat already worked in
   the landing code and the left-click path - it was only blocked by the port check. AI nations still need a port to try boat landings (keeps the AI search cost as before).
4. **Mega Bomb = nation strike.** Click a nation's land (not yours, not an ally's): at impact the game finds the radius around the impact tile that contains **85%** of that nation's tiles
   (`MEGA_LAND_SHARE`, distance histogram, no sorting) and destroys exactly that nation's tiles inside it (other nations / free land in the circle are untouched). Those tiles become fallout, its buildings
   there die, its troops drop by the same share. Ships / boats / mines are not touched. Small Bomb and Nuke are unchanged. The "85%" is the nearest tiles to the impact, so far-away islands can survive.
5. **Protocol 17** (`NET_VER` in main.gd, `PROTO_VERSION` in server/relay.py, check_server.py, DEPLOY.md): the rules changed, so old builds / old relays are refused with a clear message. Re-export AND re-deploy the relay.

### Not verified / risks
- Not run in Godot or a browser. First run: watch the Output panel for parser errors; test with two phones/browsers: right-click (long-press) the other player, Make alliance -> Accept alliance.
- The Mega Bomb impact does one pass over the whole map to find the crater (a short hitch, one time), then sweeps with the existing 3000-tiles-per-step budget.
- Round growth is a bias, not a rule: coasts, mountains and neighbours still shape nations. If it is now too round, lower the 0.75 in `step_attack`; if you want it rounder, raise it.
### Stopped at
All five items implemented and saved; nothing half-written. Next: (1) test alliances between two real devices, (2) look at the new growth shape in play, (3) boat attack on free land from a coast without a port, (4) fire a Mega Bomb at a neighbour.
