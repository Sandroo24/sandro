# Naval redesign (ports, transports, warships) - progress / hand-off

**Status: code written and statically checked, NOT run in Godot** (Godot is not available in my environment).
Backup of the pre-redesign script: `main.gd.bak_before_naval` (the older multiplayer backup is `main.gd.bak_before_online`).
Note: the earlier (interrupted) session had saved NO naval changes - this redesign was done from scratch on the project as uploaded.

## What changed
**Removed (old economy):** neutral merchant ships (`merchants`, `spawn_merchants`, `step_merchants`, `_draw_merchant`), port trade boats
(`trade`, `step_ports`, `launch_trade`, `step_trade`, `_pay_trade`, `_deliver_trade`), boat theft (`_capture_trade`, `_pay_capture`),
and the constants `PORT_BOATS, PORT_MULT, TRADE_*, LOOT_*, MERCHANT_SPEED, CAPTURE_BOUNTY, WARSHIP_KILL`. Ports no longer produce gold.

**Ports:** a port is the naval launch point.
- Troop boats (`_boat_plan`) now sail only from your ports (route search starts at the water tiles touching your ports). No port ->
  "Build a port first - troop boats leave from your ports".
- A new warship appears at your port with the shortest sea route to the water you click, and sails there (`place_sea`, `_fleet_route`).
- Port level (upgrade by using the Port tool on a port, max 5): each level above 1 makes new warships 10% cheaper (`PORT_DISCOUNT`, `price()`).
- Costs, placement rules, ownership checks and art are unchanged.

**Warships** (`step_ships`, section "naval simulation"):
- No 16-tile limit. Click your warship (selects it), then click ANY water on the map: real BFS route (never through land), up to
  `SHIP_MAXD` tiles; no route -> message "No sea route to that spot" / "Pick open water". Speed `SHIP_SPEED` = 3 tiles/tick. No teleporting.
- A new order replaces the old one at any time (redirect while moving). Click the selected ship again / Esc / right-click = deselect.
- Health `SHIP_HP` 100, guns `WARSHIP_RANGE` 8 tiles, cooldown `WARSHIP_CD` 2 ticks. Ships shoot the nearest enemy in range even while sailing.
- Idle ships patrol their station point and automatically intercept enemy transports / warships within `WARSHIP_SIGHT` (20 tiles), then go home.
- Manual attack: with a warship selected click an enemy transport or warship (orange crosshair) -> command `shipatk`. The ship plans an
  **intercept course** (first point of the transport's own route it can reach in time, `_plan_chase`), re-plans every few ticks
  (at most 2 route searches per tick, `chase_budget`), and fires when in range.
- Enemy warships fight each other (10 damage per hit).

**Transports:** `boats[]` entries now have `hp` (`BOAT_HP` 50). A hit does `SHOT_VS_BOAT` 25 -> two hits sink one. A sunk transport is removed
from `boats` (`_sink`), so `step_boats` never lands it: its troops are lost and no territory is captured. Own and allied units are never
targets (`_enemy_targets`). Water mines still sink enemy boats (and are the only thing that still uses `SEA_RANGE`).

**UI:** HP bars (own ships always, any damaged ship/transport), red ring on enemy ships/transports, faint route + destination ring for all your
moving ships, selected ship: bright route, target line, pulsing ring and an info tag (HP, order: Moving / Attacking / Intercepting / On station),
hover tooltips (Move / Attack / Land = invalid), gunfire line. Warship placement preview highlights your ports; messages explain every refusal.

**AI:** AI nations with a port build up to `BOT_FLEET` (2) warships near their ports, send idle warships against enemy transports aimed at
their land (`_bot_fleet`, with a 20-tick per-ship cooldown and a 40-tick ban after "no route" so they never spam impossible orders), and try
a boat landing now and then when they have nothing to attack by land (`_bot_naval`, 30-120 tick cooldown, one route search per attempt).
Bots go through `submit(..., ai=true)` so they cannot command human ships (validate checks owner + bot flag).

**Multiplayer:** all naval logic is deterministic and runs inside every client on the relay turns. No new networking: one new command
`shipatk {ship, tgt}` (added to `INT_FIELDS` in `server/relay.py`). `NET_VER` / `PROTO_VERSION` bumped 2 -> 3 (client and relay must match).
The desync checksum now also covers ships (id, tile, hp, target) and boats (id, position, hp). No randomness in combat; `sim_rng` is only
used for the idle-orbit fallback and AI choices, which every client consumes in the same order.

## Tested
- Python syntax/bracket balance/duplicate-function/leftover-reference checks on `main.gd`: passed (static only).
- A Python model of the intercept planner + combat constants (open sea + a land wall, 5 start positions incl. tail chase and late reaction): the transport was sunk in all 5.
- **NOT tested:** anything in Godot (parser errors are possible!), offline play, two-client multiplayer, browser export, the relay with the new command.

## Manual test plan (do in this order; first F5 and fix any parser error - send me the line)
1. Offline, no port: click enemy land across water -> "Build a port first". Build a port (3) on a coast -> card "Warship"/"Mine" unlock.
2. Wait 60 s: no passive gold from ships; no neutral ships swim around any more.
3. Warship (4): click water > 16 tiles from the port: the ship appears at the port and sails there (route line shown). Click it, click another far spot: redirects.
4. Click land / a lake not connected to the sea: red tooltip + message, nothing happens.
5. Send a boat (right-click enemy -> Attack with boat) from a port; select a warship, click the boat (orange crosshair): it intercepts, 2 hits, "Enemy transport sunk"; troops never land, no land changes owner.
6. Friendly fire: your own boats/ships and allies' are never attacked (also in the hover tooltip they are plain water).
7. Several warships + boats at once; watch FPS on the World map (route searches are capped at 2 per tick).
8. Let bots play 5 minutes: bots with ports should build warships (check the leaderboard/ships on the map) and occasionally land boats.
9. Two clients: `python server/relay.py`, 2 instances, same room: build ports, send boats, sink one with a warship on client A, verify client B sees it vanish
   and no red "out of sync" toast appears. Then the public lobby + browser export (wss URL in `OFFICIAL_SERVER` - not hardcoded to localhost/tunnels).

## Known limitations / ideas
- Warships have no fuel; targets beyond a ~2x straight-line search radius may be reported "no route" (increase the factor in `_plan_chase`).
- A very long manual order on the World map runs one big BFS (up to `NAV_NODE_CAP` tiles) on every client for that turn - could cause a short hitch.
- Mines are still range-limited (`SEA_RANGE`) and only hit boats.
- Damaged transports do not lose troops proportionally; a sunk one loses everything.
- AI naval play is intentionally simple (see above).
- Join-in-progress/reconnect still do not exist (see MULTIPLAYER_PROGRESS.md).


## UPDATE 2 (requested changes)
- **Ports make money again, OpenFront style.** Each port sends trade ships (max `PORT_BOATS` = 2 at a time, one every `TRADE_COOLDOWN` = 60 ticks)
  to another port 12-100 water tiles away (yours, neutral or foreign). On arrival BOTH port owners get `route length x TRADE_GOLD_PER_TILE` (60) gold.
  If the destination port disappears the ship earns nothing. (`step_ports`, `launch_trade`, `step_trade`, `_pay_trade`.)
- **Warships steal trade ships** of any nation they are not allied with: on contact the ship is removed and the thief gets its full route value
  immediately (`_capture_trade`). Idle warships go after trade ships within 20 tiles automatically; you can also click one to intercept it.
  Mines do not hit trade ships.
- **Port level -> warship health:** a warship gets `100 + 20 x (level of the port it is built at - 1)` max HP (`mhp`). Upgrading later does not change existing ships.
- **Warship price:** 250K, 500K, 750K, then always 750K (`WARSHIP_PRICE_CAP`). The old 10% port discount was removed.
- Tune the income with `TRADE_GOLD_PER_TILE`, `PORT_BOATS`, `TRADE_COOLDOWN`. Still NOT run in Godot.
- Replaces the earlier statements in this file that ports earn nothing and that port level makes warships cheaper.

## UPDATE 3 (economy balance)
`TRADE_GOLD_PER_TILE` 60 -> 200. Scale: base income 1000 gold/s, train visit 10K, intl rail 25K, old merchant loot up to 12K.
A 50-tile trip pays 10K to each port owner, the 100-tile maximum 20K; one port (a trip every ~30 s) adds about 350 gold/s, ~35% of base income.
A Lv 1 port pays back its 125K price in roughly 6 minutes. Change the one constant to rebalance.

## UPDATE 4 (port level -> income)
`PORT_INCOME_MULT` = x1 / 1.5 / 2 / 2.5 / 3 for Lv 1-5 (+50% of the Lv 1 income per level). A trade ship pays its source owner by the level of the port it left
from (stored as `lv` at launch), the destination owner by the level of HIS port at arrival; a thief gets the source-level value.
Per port (about 350 gold/s at Lv 1): Lv2 ~525, Lv3 ~700, Lv4 ~875, Lv5 ~1050 gold/s (about your whole base income). Upgrades cost 250K-1M, so a
second port is still the better buy early and upgrading pays off in long matches. Tune `PORT_INCOME_MULT`.

## UPDATE 5 (bug: a lone port sent no ships)
`launch_trade` needed ANOTHER port within 100 tiles; with only one port nothing ever launched. Now, if no other port is in reach, the ship sails 12-30 tiles
out to sea and back to its own port and pays the owner for the round trip (`TRADE_SEA_DIST`). With other ports in reach, behaviour is unchanged.

## UPDATE 6 (trade ships: whole-map routes, random ports, every 4 s, cancel trade)
- **No port to trade with = no ship.** Update 5's "sail out and back" loop is gone. A port launches only when another port exists that it can reach by water.
- **No distance limit.** `TRADE_MAX_DIST / MIN_DIST / SEA_DIST` are removed. A ship goes to a RANDOM other port (any owner, neutral included) that is in the
  same connected body of water (`wcomp`, flood-filled once at match start in `_naval_init`) - any ocean, strait, lake or river that exists as water tiles in the map.
- **One ship per port every 4 s** (`TRADE_COOLDOWN` = 8 ticks x TICK 0.5 s). `PORT_BOATS` raised 2 -> 12 per port (a long trip takes a minute, so 2 would have throttled
  it), `TRADE_SHIPS_MAX` = 500 on the whole map.
- **Routes:** `AStarGrid2D` (`nav`, land solid, 4-neighbour, Manhattan costs = whole numbers so all multiplayer clients find the same route). Each port-to-port route is
  searched once and remembered (`route_cache`); at most `TRADE_ROUTES_PER_TICK` = 3 new searches per tick.
- **Money is unchanged**: route length x `TRADE_GOLD_PER_TILE` x port-level multiplier, paid to both port owners. NOTE: routes are now much longer than the old
  100-tile cap and ships leave 15x as often, so income per port is far higher than before; lower `TRADE_GOLD_PER_TILE` (200) if it is too much.
- **Cancel trade:** right-click a nation -> "Cancel trade" / "Resume trade" (commands `trade_off` / `trade_on`, `no_trade` dictionary). While cancelled by either side no ships
  are launched between the two nations and ships already at sea toward that nation turn back unpaid. `NET_VER` and `PROTO_VERSION` 3 -> 4 (client and relay must match).
- **NOT run in Godot.** Risks: `_naval_init` allocates an AStarGrid2D for every tile (about 0.5M on the big maps: a short pause and some tens of MB at match start);
  a first-time long route search can take tens of ms (capped at 3 per tick); AStarGrid2D API used: region / cell_size / diagonal_mode / default_*_heuristic / update /
  set_point_solid / get_id_path (Godot 4.3).

