# Landgrab - Multiplayer architecture (Phase 7: audit + recommendation)

Status: **audit and design only. No gameplay code was changed in this phase.**
Tags: **[VERIFIED]** = read in the code of `landgrab12-mobile.zip`. **[ASSUMPTION]** = my estimate or Godot behaviour I could not test here
(Godot is not available in my environment, so nothing in this project has ever been run by me).

---------------------------------------------------------------------------------------------------------------------------------

## 1. Audit of the current game

### 1.1 Project shape
- [VERIFIED] Godot **4.3** (`config/features=("4.3")`), one scene `main.tscn`, one script `main.gd` (**5,000 lines**, one `Node2D`).
  Maps are fixed PNGs in `maps/` (`world, europe, asia, africa, north_america`), baked with `tools/bake_maps.py`. No procedural generation, so every
  machine that loads the same PNG gets the same land/water grid. This is good news for networking.
- [VERIFIED] **No networking code at all**: no `multiplayer`, `ENet`, `rpc`, `WebSocket` or peer references anywhere.
- [VERIFIED] Mobile/touch layer exists (last section of `main.gd`), project is landscape-only, mobile renderer = Compatibility.

### 1.2 How a match starts, runs, ends
- `phase` is one of `lobby / spawn / play / over`.
- Lobby (`new_lobby`, `lobby_step`): the lobby is **simulated locally**: `joined = cap - 1`, pressing Join fills it, `start_game()` runs. There is no real lobby.
- `start_game()`: `N = lobby.joined`, builds `players[0..N]` (index 0 unused, **player 1 is always "you"**, players `2..N` are bots: `p.bot = i > 1`).
- `spawn` phase: the local human clicks a tile -> `spawn(1,x,y)` + `spawn_bots()` -> `phase = "play"` (all bots spawn at that same instant, using `randi()`).
- Simulation is driven from `_process(delta)` by two **frame accumulators**: economy `tick()` every `TICK = 0.5 s` (max 2 per frame) and
  `step_attacks()` every `ATK_TICK = 0.1 s` (max 3 per frame). If the machine is slow it deliberately runs slower (frame budget).
- End: `tick()` ends the match when player 1 owns `>= WIN_SHARE (80%)` of land, or player 1 is dead (`finish()`). **Only player 1's result is checked.**

### 1.3 Who controls what today
| System | Where | Controlled by |
|---|---|---|
| Human actions | `_click`, `_ctx_do_*`, `_counter_attack`, `_toggle_build` ... | call sim functions with a **hard-coded player id `1`** |
| Bot attacks | `bot_think()` (loops `p in 2..N`) | calls `start_attack(p, target, ratio)` - the same function the human uses |
| Bot buildings | `bot_build(p, c)` (called in `tick()` when `pl.bot`) | calls `can_place` + `place_building(p, ...)` - same functions as the human |
| Bot boats / ships / alliances | none | bots never launch boats, never use warships/mines, and only *answer* alliance requests (random 60% yes) |

Good: **bots already go through the same rule functions as the human** (`start_attack`, `can_place`, `place_building`), so combat/economy logic is not duplicated. [VERIFIED]

### 1.4 Authoritative state (what the server would have to own)
All of this lives as plain variables on the one node. [VERIFIED]
- Map: `land`, `terr`, `comp` (static, from PNG); **`own`** (tile owner, the single most important mutable array); `border[p]`, `coast[p]` (derived).
- Players (`class Player`): `nm, col, troops, gold, tiles, peak, alive, bot, think_at, grow, bought{}, comps{}, allies{}`.
- Combat: `attacks[]` (`id,o,t,troops,focus,stage,gained,...`), `boats[]` (troop boats).
- Economy/buildings: `bld{centre -> {t,o,cd,lv}}`, `occ{}` (footprints), `rails[]`, `ships[]` (warships, with hp/cd/target), `boats[]` (transports, with hp), `mines[]`.
- Time/match: `tick_n`, `atk_n`, `phase`, `N`, `next_atk_id`, `ally_ask`.
- Client-only (must stay local): everything visual - `fx`, `floats`, `labels`, `lab_cache`, `time_data` (uses local `clock`), shaders, `view_pos/zoom`, all UI nodes, touch state.

### 1.5 The single choke points that already exist
- **`_set_own(i, o, delay)`** - every territory change in the game goes through it [VERIFIED: attacks, `grab`, `spawn`, boat landings, hole filling]. It is also where
  `border[]`, `comps{}` and the shader textures are updated. This is the natural place to record **territory deltas** for the network.
- `start_attack`, `launch_boat_plan`, `place_building`, `place_sea`, `order_ship`, `_ally_make`, `_ally_cancel`, `_cancel_attack` are the effective "commands". [VERIFIED]

### 1.6 What blocks real human players (verified problems)
1. **Player 1 is hard-coded as "the human"**: ~84 comparisons / 12 `players[1]` references (`tick()` win check, `_ally_*`, `eliminate` bounty, UI, fx, `_click`...). [VERIFIED count by grep; some `== 1` are tile flags, so the true number is lower]
2. **Simulation is frame-driven and uses the global RNG**: 22 `randf/randi` sites inside the sim (bot decisions, spawn picks, alliance acceptance, trade routes).
   Two machines would diverge, so **deterministic lockstep is not viable without a big refactor** -> use a server that owns the simulation and sends results.
3. **Rules and UI are entangled**: sim functions call `say()`, `_float_at()`, `_fx_ring()`, `_card_pop()`, `ui()` (e.g. `start_attack`, `eliminate`, `_flip_building`,
   `_rail_pay`, `_pay_capture`, `_capture_trade`, `step_attack`). On a server these need to become **events**, not UI calls.
4. **Commands are not self-validating**: `place_building` charges gold without re-checking (the caller must have run `can_place`); `start_attack` does not clamp `frac`,
   check that the target tile is reachable, or that the sender owns that country; `order_ship` shows `say()` messages. The *validation functions exist*
   (`can_place`, `can_place_sea`, `_boat_plan`) but are only called by the UI/bot, not enforced inside the command.
5. **Alliances are player-1-only**: `_ally_make/_ally_cancel` assume `me = players[1]`, and acceptance is `randf() < 0.6`. Human-vs-human alliances need request/accept messages.
6. **Bots hard-coded as `2..N`** in `bot_think` and `spawn_bots`; `Player.bot` is a plain bool (no "unoccupied", no peer id, no session).
7. **One 5,000-line script** mixes rendering, input, touch, UI and simulation; a headless server cannot reuse it cleanly (see 2.3).
8. Lobby, spawn selection and match end all assume exactly one human.

### 1.7 What already helps
- Gameplay state is plain data (arrays/dicts/PackedArrays) - easy to serialise.
- Fixed PNG maps -> clients and server share identical terrain (send a map id + hash, not the map).
- `_set_own` choke point; bots already use the shared rule functions; `Player.alive` exists; ids for attacks (`next_atk_id`) already exist.
- Border/frontier sets make attacks cheap, so one server process can realistically run a 100-player match [ASSUMPTION - never measured].

---------------------------------------------------------------------------------------------------------------------------------

## 2. Networking options compared

| | A. Godot high-level multiplayer, **ENet, host = a player (listen server)** | B. **Dedicated authoritative Godot server** (headless) | C. Hosted backend (Nakama / PlayFab / Photon / Steam lobbies ...) |
|---|---|---|---|
| Dev complexity | Lowest to prototype | Medium (needs sim/UI separation) | Medium-high (new SDK + still need authoritative sim somewhere) |
| Hosting cost | none | a VPS (see 4) | monthly fee + usually still a VPS for the sim |
| Sync/reliability | host's connection and CPU decide a 100-nation match; host quits = match dies | stable | good for lobbies/matchmaking; does not run your game rules |
| Anti-cheat | **weak**: the host can cheat and sees everything | **strong**: server validates every command | depends - most services are not authoritative for custom rules |
| 100 nations | host's phone/PC runs GDScript sim for everyone: poor | one process per match on a server | n/a |
| Future scale | poor | good (many match processes, add a matchmaker later) | good, but lock-in |
| Fit with project | quick demo only | **best, needs a refactor first** | later add-on, not a replacement |
| Maintenance | simple | one codebase for client + server | extra service to maintain |

### Recommendation: **B - dedicated, server-authoritative Godot server, using Godot's built-in `MultiplayerAPI`**
- Same engine and same GDScript rules on client and server -> the validated rules are written **once**.
- Transport: **`ENetMultiplayerPeer`** first (UDP, works on Android/iOS/desktop). If you want a **browser build** (your README mentions web export), plan a
  `WebSocketMultiplayerPeer` (TCP/wss) transport behind the same message layer, because browsers cannot use ENet/UDP [ASSUMPTION: from Godot's documented web limits].
- Use **your own compact command/snapshot messages through a thin `NetBridge`** rather than scattering `@rpc` functions over the 5,000-line script: easy to validate, rate-limit and version.
- **No database, accounts system or third-party service is needed for Phase 8.** A random per-match session token (to allow reconnecting) is enough. Accounts become useful
  only later (persistent names, bans, stats, ranked); a lobby service (Option C) becomes useful only when you have more than one server and want global matchmaking.

### 2.3 Can this project run as a headless server?
- Godot supports dedicated-server exports (`--headless`, the "dedicated server" export mode, `OS.has_feature("dedicated_server")`).
- **Today: not cleanly.** `_ready()` builds the whole UI, theme, shader material, textures and touch layer, and the sim calls UI helpers. Running the unchanged `main.gd`
  headless would be fragile [ASSUMPTION - untested]. The safe path is to **extract the simulation into a UI-free `GameSim` class** (state + `tick()` + `step_attacks()` + command
  functions) that both the client (for display) and the server use. See Phase 8.

---------------------------------------------------------------------------------------------------------------------------------

## 3. Slots, controllers, bots, disconnects

### 3.1 Data model
Each country (slot) gets:
`controller` (`HUMAN | BOT | UNOCCUPIED`), `peer_id`, `session_token`, `display_name`, `connected`, `disconnected_at`, `last_command_tick`.
Slot ids stay `1..N` (today's player ids), so `own[]`, `bld`, `allies{}` do not change. `Player.bot` becomes derived from `controller == BOT`.
**Exactly one controller per slot, enforced by the server**: commands are accepted only if `slot.controller == HUMAN and slot.peer_id == sender`, and
`bot_think/bot_build` skip any slot whose controller is not `BOT`. A human and the AI can never act on the same country at the same time.

### 3.2 One rule path for humans and bots
`Command` (plain dict) -> `validate(slot, cmd)` -> `apply(slot, cmd)` (the existing `start_attack` / `place_building` / ... bodies) .
Humans produce commands from clicks (sent over the network), bots produce the same commands from `bot_think/bot_build`. Combat and economy code is **not duplicated**:
only the *source* of the command differs. Move the "should I?" checks (`can_place`, ownership, alive, frac clamp) from the callers **into** `validate`.

### 3.3 Match start / filling slots
1. Lobby (server-side): humans join up to `slots`. Start when full, or when the countdown (`LOBBY_SECS`) ends - remaining slots get `BOT`.
2. Spawn phase (timer, e.g. 20-30 s): every human picks a start tile (server validates land + free + not too close). Humans who do not pick get a random valid start.
   Then bots spawn (server RNG). Then `phase = play` at a server tick number all clients are told.
3. Late join (recommended): during the first ~2 minutes, a new player may **take over a bot slot** (smallest bot nation) - they inherit its land/troops/gold.
   After that window, the match is closed to newcomers (keeps matches fair).

### 3.4 Disconnect policy (recommended, with consequences)
- **0-60 s grace**: slot stays `HUMAN`, flagged `disconnected`. The nation keeps its economy and defends; it does **not** start new attacks. (Prevents someone being wiped by a Wi-Fi blip.)
- **After 60 s**: handoff to `BOT` ("caretaker": uses the same bot code), slot remains **reclaimable**.
- **Reconnect** with the same `session_token` at any time while the slot is alive: server sets `controller = HUMAN`, sends a **full snapshot**, bot stops immediately.
- **Eliminated**: slot is `alive = false`; every command from it is rejected (server-side check), the client becomes a spectator.
- Consequence to accept: a rage-quitter's nation becomes a bot that others can eat; a reconnecting player may find the situation changed. Not auto-replacing instantly avoids
  punishing short disconnects; not leaving the nation idle forever avoids a "free target" that stalls the match.
- Explicit **Leave** button: hand off to bot immediately (no grace).

### 3.5 Match end
Server decides, once: winner = first slot (or alliance, if you add team wins later) reaching `WIN_SHARE`; **or** all humans eliminated/left; **or** optional time limit.
Server broadcasts `MATCH_END{winner, ranking, stats}` exactly once, sets `phase = over`, stops accepting commands, then closes the match process. Today only player 1's result is checked; this must become per-slot.

---------------------------------------------------------------------------------------------------------------------------------

## 4. Networked game state plan

### 4.1 Rule: clients send *intentions*, the server computes *results*
| Client -> server command | Server validation (examples) |
|---|---|
| `SPAWN(tile)` | phase == spawn, land, free, spacing, not already spawned |
| `ATTACK(target_owner, frac, focus_tile)` | slot is HUMAN+owned by sender+alive, `0.01<=frac<=1`, target alive & not ally, `troops >= min`, target actually adjacent or reachable, rate limit |
| `BOAT(target_tile, frac)` | same + the server recomputes `_boat_plan` itself (never trusts the path from the client) |
| `BUILD(type, tile)` / `SEA_BUILD(type, tile)` | `can_place` / `can_place_sea` on the server (gold, ownership, footprint, port rule) |
| `SHIP_ORDER(ship_id, tile)` | ship belongs to sender; server recomputes route |
| `CANCEL_ATTACK(attack_id)` | attack belongs to sender |
| `ALLY_REQUEST/ACCEPT/CANCEL(target)` | both slots alive; human-human needs accept; bots answer with server RNG |
The client **never** sends "attack succeeded", "I have enough gold", "tile X is mine", prices, troop counts or a path.

### 4.2 Server -> clients
- **Join / reconnect snapshot**: map id + hash, `own[]` as run-length encoding (large uniform runs, small), players table, buildings, attacks, ships/mines/merchants, `tick_n`, phase.
- **Every attack step (0.1 s)**: a list of territory deltas `(tile, new_owner)` recorded in `_set_own`. Clients apply them with the existing `_set_own`/shader code
  (the conquest-time texture already uses local `clock`, so the "tile by tile" animation keeps working).
- **Every economy tick (0.5 s)**: per-slot stats `(troops, gold, tiles, alive, controller, connected)` - small.
- **Events** (reliable): building placed/upgraded/lost, attack started/ended, alliance changes, elimination, match end, kill/capture messages (replace today's `say()` calls).
- Moving things (boats, warships, trade boats, merchants): send **path + start tick + speed once**; clients interpolate. No per-frame positions.
- Rough bandwidth [ASSUMPTION - estimate]: a few hundred territory deltas per second at ~4 bytes each is well under 10-50 KB/s per client even in a busy 100-nation match.
  Use unreliable-ordered for stats, reliable for commands and events.

### 4.3 Reliability, errors, abuse
- Every message has `type`, `proto_version`, and (commands) a client `seq`; the server acks the last applied `seq`; duplicates/old seq ignored.
- Validate types and ranges of every field (ints within `0..W*H`, enums known, strings length-capped). Unknown/oversized message -> drop; repeated invalid -> kick.
- **Rate limit** per slot (token bucket, e.g. ~10 commands/s, burst 20) and a hard cap on pending attacks per slot.
- Sender identity comes from the transport (`get_remote_sender_id()`), **never** from a field inside the message.
- Version handshake on connect; map hash must match; server rejects mismatched clients with a readable error.
- Connection errors: client shows a reconnect screen, retries with the session token; server keeps the slot (3.4).
- Server timing: run the sim on a **fixed-step server clock** (not the client's frame budget), so 100-nation matches are consistent for everyone.
- Randomness: server owns the RNG; clients never call `randf/randi` for anything that affects state (the 22 sites must move behind the server).

---------------------------------------------------------------------------------------------------------------------------------

## 5. Preparatory changes (identified; deliberately NOT implemented in Phase 7)
No Godot is available here, so any edit to the 5,000-line script would be untestable. The following are the safe first steps for Phase 8, ordered by risk:

| # | Change | Risk | Testable? |
|---|---|---|---|
| P1 | Add `controller` field to `Player` (`HUMAN/BOT/UNOCCUPIED`), keep `bot` as derived; make `bot_think/bot_build/spawn_bots` filter by controller instead of `range(2,N+1)` | low | yes (offline game must behave identically) |
| P2 | Replace literal `1` with a `local_slot` variable (default 1) in `tick()` win check, `_click`, `_ally_*`, `eliminate`, fx | medium (84 sites) | yes (offline) |
| P3 | Command envelope: `submit_command(slot, cmd)` that calls `validate` then the existing functions; make the UI/bot call it | medium | yes |
| P4 | Sim event queue instead of `say()/_float_at()/_fx_ring()` inside rule functions (UI consumes events) | medium | yes |
| P5 | Record territory deltas in `_set_own` (array of `(tile, owner)` flushed per step) | low | yes |
| P6 | Extract `GameSim` (state + rules) from `main.gd` into a UI-free class | **high** | needs Godot + unit tests first |
| P7 | Server-owned RNG (`RandomNumberGenerator` instance in sim) instead of global `randf/randi` | low-medium | yes |
| P8 | GDScript unit tests (GUT or plain scene) for: `price`, `max_troops`, `can_place`, `_set_own` bookkeeping, `step_attack` loss/speed, `eliminate`, win check | low | yes - do this **before** P2/P6 |
Why none were done now: they are only valuable if tested; I cannot run the game, and a broken offline game is worse than a documented plan.

---------------------------------------------------------------------------------------------------------------------------------

## 6. Hosting and risks (all [ASSUMPTION] until measured)
- One server process per match. A 100-nation GDScript sim is CPU-bound on one core: plan **~1 core per concurrent match**; a small 2-4 vCPU Linux VPS is a sensible start
  (cost in the low tens of USD/month range). Measure real tick time with the headless build before choosing a size.
- Open one UDP port (ENet) or a TLS WebSocket port (browser). A tiny launcher/matchmaker script that starts a server process per match can come later.
- Risks: large untested refactor (P6), sim speed with 100 nations on a server, mobile players on bad connections (grace/reconnect policy matters), fairness of late-join, cheating via a modified client (mitigated by server authority), no accounts so names are not unique.
- Open questions for you: max humans per match? browser build required? is late-join takeover of bots wanted? team/alliance victory? should a disconnected player's nation really become a bot after 60 s?

## 7. Recommended Phase 8 plan
1. Write unit tests for the existing rules (P8). 2. P1 + P5 + P7 (low risk). 3. P3/P4: command envelope + event queue, offline game still identical.
4. P2: remove hard-coded player 1. 5. Extract `GameSim` (P6) and run it from a headless entry scene (`server_main.tscn`) offline-first (server + one local client in one process).
6. Add `NetBridge` (ENet), snapshots + territory deltas, command validation, rate limits. 7. Lobby/match flow, reconnect and disconnect policy. 8. Two-machine and mobile tests, then hosting.
