# Multiplayer - ONLINE TEST BUILD (read this first)

## NEW (landgrab19): official public lobby
The big "Join game" button is now the ONLINE public lobby (server-driven), not the offline simulation:
- `relay.py` `PublicLobby`: map rotation + countdown + 2 player slots (`watch`, `pjoin`, `pleave` -> `pub` broadcasts every second; at 0 it
  starts a room `!pubN` with `n = map cap` nations, humans in slots 1..H, bots fill the rest). `PROTO_VERSION` / `NET_VER` are now 2.
- `main.gd`: `OFFICIAL_SERVER` constant (SET IT before export). `enter_lobby()` -> `_pub_connect()`; `_pub_*` functions; `net_pub` flag.
  If the server cannot be reached the old offline practice lobby is shown and it retries every 15 s.
- Private rooms = the "Private room" button (room code box; empty = a random code is made). Unchanged lockstep code.
- Relay side TESTED with a script (watch, 2-slot limit, full message, start with 65 nations, commands, rollover, drops, private rooms).
  The Godot side was NOT run (no Godot here): first run F5 with `python server/relay.py` running, then 2 instances, both press "Join game".

**Status: written, NOT run in Godot** (Godot is not available to me). The relay server (`server/relay.py`) IS tested (script in the chat: rooms, host,
start, turns, command cleaning, desync check, drops). `main.gd` was edited by exact-match scripts + static checks only. Backup of the
version before this work: `main.gd.bak_before_online`.

## What was built (and why it is NOT the "server owns the simulation" design of steps 5+)
A browser build cannot host or use ENet/UDP, and a server-side simulation needs the 5000-line script split first. So this is **lockstep through a dumb relay**:
- `server/relay.py` (Python 3.8+, no packages): rooms, lobby, host, a shared random seed, and one numbered **turn every 0.1 s** that carries the
  commands players sent. It does not know the game rules.
- Every client runs the same deterministic simulation on the same turns (turn = one `step_attacks()`, every 5th turn also `tick()`). Bots are NOT sent
  over the network: they run inside each client from the shared seed. A player who disconnects becomes a bot on every client.
- Each client sends a **state checksum** every 5 s; the relay broadcasts "desync" (red toast) if two differ.

## Changes in main.gd (search for `online`, `_net_`, `_exec`)
- Determinism fixes (these were real divergences between "me" and "others"): `step_attacks` and `place_building`'s rail rebuild used `my_slot` -> now "is a human"; rail
  start offsets used the global `randf()` -> `sim_rng`; `match_seed` is consumed once (offline games used to repeat the same seed).
- `submit()` for humans -> `_exec()` -> `_net_send` (online) or `apply` (offline). Bots still `apply` locally. Executing a turn = `_net_exec_turn`: dropped slots -> bot, commands ->
  `validate` + `apply` for the slot the RELAY stamped on them, then the step/tick.
- Spawn phase online: clicks send a `pick`; `begin_play()` places every human (slot order) at their pick (crowded/bad pick -> free spot), then bots.
- Lobby: name / room / server address fields + "Play online". The first person in a room is the host (Change map, Start match). Nations in a match: `ONLINE_NATIONS` (24) capped by the map.
- Online you can fall without ending the match (it keeps running, you spectate); a lost connection shows "Connection to the server lost".

## Known limits
- No alliances with human players, no late join, no reconnect (leaving = your country becomes a bot for good).
- The relay cannot judge commands, so a modified client could cheat. Fine for friends, not for strangers.
- Everyone must run the SAME build. Bump `NET_VER` (main.gd) and `PROTO_VERSION` (relay.py) together after any gameplay change, otherwise a stale cached itch page desyncs.
- Mixing desktop and browser clients may desync over time (different math library for `pow`). Test with browsers only.
- Slow machines fall behind the others (they catch up by running several turns per frame) but stay consistent.

## First-run checklist (in this order)
1. F5 offline: fix any parser error (report the line), play a short offline match: lobby -> spawn -> attack/build -> end. Offline must behave as before.
2. `python server/relay.py`, then Debug > Customize Run Instances > 2 instances, F5. Both: Play online (ws://localhost:8765, same room), host: Start match. Pick starts, play 2 minutes.
3. Watch for the red "out of sync" toast. If it shows, note the turn number and what you did just before.
4. Then web export + wss (see server/README.md).

# Multiplayer prep - progress (resume point)

Nothing here has been run in Godot (not available to me). Every change is a scripted, exact-match edit plus static checks
(bracket balance, no duplicate functions, no leftover literal `1` ownership checks). **First thing to do: open the project, press F5, and fix any
parser error; then play one quick match (lobby -> 25 s spawn -> a few attacks/buildings -> win/lose).**

## Done

### Step 1 - "my slot" instead of "player 1"  (DONE)
- New `var my_slot := 1` (near `phase`). Every "this is mine" check now uses it: all `players[1]`, `owner == 1`, `own[i] == 1`, `_float_at(.., 1)`,
  `can_place(1, ..)`, `start_attack(1, ..)`, `place_building(1, ..)`, `_boat_plan(1, ..)`, `owns_comp(1, ..)`, `price(1, ..)`, `_has_port(1)`, `cnt[1]`, `border[1]`,
  `allies[1]`, `spawn(1, ..)` (about 100 sites).
- Bots are now "every slot whose `Player.bot` is true" (`p.bot = i != my_slot`); the three bot loops (`_plan_bot_starts`, `spawn_bots`, `bot_think`)
  skip any non-bot slot instead of assuming `2..N`. A human slot is never driven by the AI.
- **Match end** now checks every slot: the first slot (human or bot) with `WIN_SHARE` of the land wins for everybody; you lose only when your own slot dies.
  (Before, a bot reaching 80% did not end the game.)
- Still true: only one slot is a human and it is slot 1. To test two humans locally later, set `my_slot` per client and mark the other slot `bot = false`.

### Step 3 - one seeded random generator for gameplay  (DONE)
- `var sim_rng` + `var match_seed` (0 = pick a new seed at `start_game`). All gameplay randomness (bot decisions and builds, start picks, trade routes,
  merchants, warship wander, alliance acceptance, attack-tier shuffles, bot spawn picks) uses `sim_rng.*`; `Array.shuffle()` became `_shuffle()`.
- Deliberately left on the global RNG: lobby/map choice, purely visual jitter (`_set_own` reveal delay, train start offset).
- Result: a server can seed a match, and the same seed + same commands gives the same bot behaviour (float order/dictionary order is not guaranteed
  identical across machines, so this is for server-side testing and replays, not for lockstep).

### Step 2 - game rules separated from the UI  (DONE, untested in Godot)
- New hooks `_ev_say(slot, text, secs, kind)`, `_ev_float(slot, tile, text, col)`, `_ev_ring(slot, pos, col, life, r_tiles)`. Offline/client: they show the
  message only if `slot == my_slot` and not `headless` (so the game looks exactly as before). On the server (step 5) they will queue an event for that peer.
- All 11 functions of the list now use them: `_capture_trade`, `_deliver_trade`, `_flip_building`, `_kill_target`, `_pay_capture`, `_rail_pay`, `eliminate`,
  `order_ship`, `start_attack`, `step_attack`, `tick`. A script confirmed no direct `say/_float_at/_fx_ring/ui/calc_labels/_refresh_attacks/finish` call is left inside them.
  Both sides of "you did X / X was done to you" are now two independent hook calls (one per slot); an `!= by_owner` / `!= o` guard keeps the old "elif" behaviour.
- New `var headless` (set at the top of `_ready` from `DisplayServer.get_name() == "headless"` or the `dedicated_server` feature) and `var winner_slot`.
- `tick()` is rules only now: when a slot reaches `WIN_SHARE` it sets `winner_slot` and `phase = "over"`. New `_after_tick()` (client only, returns at once when
  headless) does `calc_labels` / `_refresh_attacks` / `ui` and shows the end screen via `finish()`. `_process` calls `tick()` then `_after_tick()`.
- "Your nation has fallen" is now decided in `_after_tick` (per client), not in the rules: on a server one human dying must not end the match for everybody.
- Found and fixed 4 leftover literal `1` meaning "me" that step 1 missed: `_kill_target`, `_capture_trade` (both `owner == 1`), `_ship_at` (`!= 1`), `_rail_links_for` (`!= 1`).
- Still UI-entangled on purpose (they are command handlers, step 4): `_click`, `_toggle_build`, `_ally_make`, `_ally_cancel`, `_ctx_do_boat`, `_cancel_attack`,
  `_counter_attack`, and `start_game` / `begin_play` (they call `ui`, `say`, `calc_labels`). Step 5 will also have to stop `_ready()` from building UI on the server.

### Step 4 - commands that validate themselves  (DONE, untested in Godot)
- New command layer (section "commands" just above `bot_think`). A command is a dict `{"slot", "type", ...}`; types: `attack` (target, frac, focus?), `boat` (tile, frac),
  `build` (kind, tile), `sea` (kind, tile), `ship` (ship id, tile), `cancel` (attack/boat id), `ally_ask` (target), `ally_cancel` (target).
- `validate(slot, cmd, ai=false) -> String` ("" = ok, else the player-facing reason). `slot` is who SENT it (a server will pass the peer's slot, never a field of the
  message); `cmd.slot` must match. `ai=false` => the slot must NOT be a bot, `ai=true` => it must be a bot, so the AI and a human can never drive the same country.
  Checks: phase is play, slot in range and alive, field types, `0 < frac <= 1` (NaN fails), tile ranges, focus inside the map, enough troops (>= 100) and gold,
  target alive / not an ally / actually touching your border (`_has_contact`, early exit), `can_place` / `can_place_sea`, `_boat_plan` (always recomputed, a client path is never
  used), ship belongs to the sender and `_ship_order_why`, attack/boat id belongs to the sender, alliance rules.
- `apply(cmd)` performs it (the only caller of `start_attack`, `place_building`, `place_sea`, `order_ship`, `launch_boat_plan`); `submit(slot, cmd, ai)` = validate + apply.
- Everything produces the same dicts now: `_click` (attack / boat / build / sea / ship), the ctx menu (`_ctx_do_attack`, `_ctx_do_boat`, `_ally_make`, `_ally_cancel`),
  `_counter_attack`, `_cancel_attack`, and the bots (`bot_think` attacks, `bot_build` buildings, both with `ai=true`).
- Defence in depth: `place_building` / `place_sea` now re-check `can_place*` themselves and return bool (no gold is taken for a refused placement);
  `start_attack` clamps `frac` and range-checks `o`/`t`. `order_ship` is now silent (returns bool); its reasons live in `_ship_order_why`.
- Alliances: `ally_ask` is answered at once by a bot (60 % yes, same as before); the "turned you down" cooldown is now per asker (`"asker_target"` key) and counted in
  ticks (50 = 25 s) instead of the local `clock`. Asking a HUMAN slot is rejected with a message until step 5 adds request/accept. Fixed another leftover literal `1`
  in `_ally_cancel` (`allies.erase(1)` -> the sender's slot) - cancelling now also tells the other side.
- Small visible differences (on purpose): a refused order now shows a red toast with the reason instead of doing nothing / burning troops (not enough troops, "Your land does not
  touch theirs - use the boat", "No free land next to your border"); the counter-attack toast only says "launched" when it really was.
- Known leftovers for step 5: `place_building` still sets `rails_force` only when `p == my_slot` (rail rebuild is immediate for you, up to 6 ticks later for others - harmless but
  a server has no `my_slot`); `launch_boat()` is an unused wrapper; spawn start picks (`my_start`, `bot_picks`) are still lobby code, not commands.

### Earlier this session
- Lobby keeps `LOBBY_OPEN_SLOTS` (2) slots free; 25 s spawn countdown where everyone (bots as placeholders) picks and can change their start.

## NOT done - next steps in order

### Step 5 - network layer and server-owned lobby / spawn countdown
Thin `NetBridge` (ENet first): client sends commands, server validates + applies + sends results (territory deltas from `_set_own`, building/attack/boat
events). Server owns `LOBBY_SECS`, `SPAWN_SECS`/`spawn_left`, each human's chosen start tile (`my_start`) and the bot picks (`bot_picks`).
Needs the simulation split into a UI-free class so a headless server can run it (see `MULTIPLAYER_ARCHITECTURE.md`, section 2.3).

## Where I stopped
Step 4 is finished (edits + static checks only; **nothing has been run in Godot**; Step 2 is also still untested). Backups: `main.gd.bak_step4` (before this step) - not in the zip.
Next: Step 5 (network layer). Before I start it I need your answers on the big design choices: ENet only, or also WebSocket for a browser build? Where will the dedicated server run?
How many humans per match? Test list for step 4 (offline, one player):
1. F5, report any parser error. 2. Click enemy land you border: attack starts as before (blue ring). Click enemy land you do NOT touch on the same island: red toast "Your land does not touch theirs - use the boat".
3. Click land across the sea: boat launches; click land with no sea route: red toast with the reason. 4. Build a village, upgrade it to city/duchy, build station and port, upgrade a port to max and click it again:
red "Port is already level ..." toast, no crash. 5. Try to build with too little gold: card shakes + red toast, gold unchanged. 6. Place a warship and a mine near a port; select a warship and click open water / land:
it sails / "Pick open water". 7. X on one of your attacks gives the troops back; sword counter-attacks. 8. Right-click a bot: Ask alliance (accepted or declined), try again at once: "just turned you down",
Cancel alliance; attack/boat buttons of the ctx menu. 9. Bots still attack and build (watch the map for 2-3 minutes) and the match can still end.
