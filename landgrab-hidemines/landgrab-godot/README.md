# Landgrab (Godot 4)

Phase 7: smooth terrain, wave attacks with stages, cancel/counter list, cross-nation rails, ordered + patrolling warships that steal trade boats.

## Run
1. Install Godot 4.3+ (standard build, no .NET needed).
2. Project Manager -> Import -> select `project.godot`.
3. Press F5.

## Flow
- **Lobby**: map offered with a 2:00 countdown and player cap (Mediterranean 8, Pangaea 16, Archipelago 12,
  Highlands 6). Starts when full, or when the timer runs out. Other players are simulated for now.
- **Build**: cards bottom-left or keys 1/2/3. Hover your land to see the footprint (green ok, red blocked,
  gold upgrade). Click to place. Shift keeps the tool, Esc / right-click cancels.

## Buildings (price = base x 1..5, then stays at 5x; upgrades count as purchases)
| Building | Prices | Effect |
|---|---|---|
| Village | 100 / 200 / 300 / 400 / 500 | +120 max troops. Village tool on a village -> City (300 total), on a city -> Duchy (600 total) |
| Station | 100 ... 500 | Rails connect all your stations, cities and duchies on a landmass. Trains pay gold when they reach a city (6) / duchy (12) / station (2) |
| Port | 150 ... 750 | Must touch water. Troop boats and warships leave from your ports. Port tool on a port = level up (max 5): trade ships earn gold by distance; each level adds +20 HP to new warships |

## Pace
`TICK` (top of main.gd) is the master speed: 0.5 s per tick now. Income per tick is in the `GOLD_*` constants,
troop caps in `CAP_*`.

## Phase 6 additions
- **Map labels**: every nation shows its name and troop count on its biggest landmass (appears once you zoom in far enough).
- **Attacks**: a list under the stats panel shows each running attack (and attacks aimed at you) with the troops in it, plus a
  `Attack 245` tag on the front line and a troop count above your boats.
- **Rails**: stations / cities / duchies link only if they are within `RAIL_REACH` tiles AND the straight line is all land (no more rails
  over water). With the Station tool selected, green lines show exactly which of your rail points a new station would connect to,
  and a faint ring marks the reach. Out of reach = no green lines.
- **Sea units**: the arrow on the Port card opens Warship (key 4) and Water Mine (key 5). They need at least one port and are placed on
  water within `SEA_RANGE` tiles of your ports (the reachable water is tinted while you place). Warships patrol near where you put them
  and sink enemy boats inside `WARSHIP_SIGHT`; a mine sinks the first enemy boat that touches it and is used up.
- **Capturing buildings**: when a village / city / duchy is taken, its old owner immediately loses the share of troops that building
  supported (`CAPTURE_TROOP_LOSS`, 1.0 = exactly its share of their troop cap).

## Phase 7 additions
- **Smooth map**: the terrain is drawn by a shader (`TERRAIN_SHADER` in main.gd) from the owner/land data, so coastlines and borders are
  rounded at any zoom instead of square pixels. The simulation still runs on the tile grid underneath.
- **Wave attacks**: an attack grows outward in rings around the tile you clicked (the nearest contact tiles are taken first) and escalates
  through **Skirmish -> Assault -> Surge** as it gains ground (30 / 150 tiles). Each stage widens the ring and speeds the advance; Surge makes
  captured land cheaper. The map only shows a small floating label (stage + troops) that glides along the front - no rings, no boxes.
- **Attack list (left)**: blue rows are your attacks - the **X** cancels and refunds unspent troops (also recalls a boat). Red rows are attacks
  against you - the **crossed swords** launch a counter-attack at that front using the current slider percentage.
- **International rails**: stations of different nations link when within `RAIL_REACH` and the line is all land. These links are dashed gold and
  every train visit pays BOTH nations `INTL_RAIL_PAY`. The Station preview also shows green lines to enemy stations it would connect to.
- **Warship orders**: click one of your warships (no tool selected) -> a crosshair appears -> click any water on its sea. It sails there
  (`SHIP_SPEED` tiles/tick) and then circles that spot (`ORBIT_R`). Esc / right-click cancels the selection.
- **Boat theft**: warships no longer sink trade boats - they steal them. The boat turns around, sails to the thief's nearest port, pays its cargo
  plus `CAPTURE_BOUNTY` (x port level multiplier) and disappears. Trade boats now carry their loot home (paid on return), so it can be stolen.
  Troop boats are still sunk, and mines still sink everything.

## Smooth growth (phase 7b)
- Land changes hands **per tile with a fade** (`fade` in the shader, 0.5 s). Tiles taken in one game tick are staggered across that tick
  (`_set_own(i, o, delay)`), so the front creeps forward every frame instead of jumping every 0.5 s. The simulation itself is unchanged.
- The map is no longer rebuilt tile by tile: only changed tiles are written, and the textures are uploaded when something changed.
- Warship selection shows only a small crosshair on the cursor (green = water, red = land). No text or circles follow the mouse.

## Blob growth (phase 7c)
- An attack now advances along its **whole front** at once, like OpenFront: each tick it takes a share of the contact tiles
  (25% Skirmish / 37% Assault / 50% Surge), always the tiles most surrounded by your land first. The edge stays smooth, the shape grows evenly
  on all sides, and where you click only decides who you attack.
- `_fill_holes`: any enclosed pocket (<= 14 tiles, never touching water or the map edge) inside your land is absorbed after each conquest,
  so bases never end up with holes.
- Borders are a light edge line, as in the reference video.

## Pixel look again (phase 7d)
- The map is drawn as crisp pixel tiles again (same colours and dark borders as before). The rounded-coast shader is gone.
- Growth is still smooth: tiles taken in one tick are revealed one after another across that tick (`_set_own` delay + `time_tex`), so the
  area grows continuously on screen instead of in one block every 0.5 s.

## Round 3 (100-player maps, OpenFront-speed growth)
- Lobbies are always 99/100, so pressing Join starts the game. Maps are 520x320 .. 640x380 tiles.
- Attacks now step 10x per second (`ATK_TICK`) and advance ~1.3 tiles/s into empty land (`ATK_FRONT_SPEED`),
  measured from the reference OpenFront clip. The economy still ticks every `TICK` (0.5 s).
- Attacks, bots, labels and ownership checks use per-player border sets instead of scanning the whole map,
  so 100 players stay playable. Bots use muted colours and territory borders are light/white like OpenFront.

## Round 4 - OpenFront economy (numbers taken from OpenFront's Config.ts, v0.34.12)
- Troops are stored like OpenFront (internal units) and shown /10: start 25,000 (2.5K), bots 10,000.
- Max troops = 2 x (tiles^0.6 x 1000 + 50,000) + 250,000 per village/city/duchy level; bots get a third.
- Troop growth = (10 + troops^0.73 / 4) x (1 - troops / max) per 0.1 s, bots x0.5.
- Gold: flat +100 per 0.1 s (bots 50) = +1000/s. No gold from territory or buildings.
- Prices: 125K doubling (125K, 250K, 500K, 1M, then 1M) for village / station / port; warship 250K x (n+1) up to 1M; mine 50K x (n+1) up to 250K.
- Attacks use OpenFront's attackLogic (plains values): 16 troops lost per wilderness tile, speed depends on attack size vs defender, and an
  attack takes tiles until their cost fractions add up to 1 each 0.1 s step. Default send slider 20%, bots send 5%.
- Win at 80% of the land. Conquering a bot takes all its gold, a human half.
- Train visits pay 10K, intl links 25K; merchant ships hold up to 12K gold each.

## Round 5 - real maps, terrain, alliances
**Maps** are 5 FIXED images in `maps/` (`world.png`, `europe.png`, `asia.png`, `north_america.png`, `africa.png`). Nothing is
generated at runtime any more: the game loads the PNG and reads land / water / terrain from its colours
(water 20,60,100 - green 80,150,70 - desert 220,190,110 - snow 245,248,252). You can repaint them in any image editor.
`tools/bake_maps.py` is the one-off script that produced them (fixed seeds, so the result is always identical).
World has 100 slots, the continents 65. PNG sizes follow OpenFront's (~2 million tiles, World 2000x1000); `MAP_SCALE`
(top of main.gd) shrinks that so GDScript stays smooth: 0.5 = ~500k tiles per map, 1.0 = full size.

**Terrain** (snow = far north/south + big mountain ranges, desert = the big deserts, the rest green wilderness):

| Terrain | Advance speed | Troops lost per tile |
|---|---|---|
| Green wilderness | 1x | 1.15x |
| Desert | 1/1.20x | 1x |
| Snow mountain | 1/1.35x | 1.35x |

Multipliers live in `TERRAIN_SLOW` / `TERRAIN_LOSS`. Owned land is drawn in the plain owner colour (no biome shows through).
Hovering neutral land shows its terrain and numbers.

**Hover bar**: point at any nation's land and the top bar shows its buildings (counts), troops now / max and gold.

**Right-click a nation** opens a menu: *Make alliance* (green, bots accept ~60%, 25 s cooldown after a refusal), *Cancel alliance*
(red, grey until you are allied), *Attack with boat* (blue, grey unless you own coast and a sea route exists), *Attack* (land).
Allies cannot attack each other. The boat leaves from your coast tile with the shortest sea route and lands on the target's
coast tile closest to where you clicked (also used by plain left-click on land you cannot walk to).

## Round 6 - OpenFront pacing, bots as real players
- **Why you grew too fast**: OpenFront's troop costs are tuned for ~2 million land tiles; our maps have ~150-300k, so the same troops
  covered 7-13x more of the map. Now one of our tiles counts as `of_k = REF_LAND / land_count` OpenFront tiles (top of main.gd).
  Troop cost per tile, max troops, large-nation bonuses and front speed are scaled with it, so land grows at OpenFront's speed
  *as a share of the map*: ~0.15% after 15 s, ~0.4% after 1 min, ~0.7% after 2 min (checked against your video: 0.1% at 15 s) -
  on every map and at any `MAP_SCALE`. Want it slower/faster? Raise/lower `REF_LAND`.
- **Bots = real players**: same start troops (2.5K), same troop growth, max troops, gold and attack costs as you (no more handicaps).
  Every 1-2 s a bot "clicks attack" with 15-30% of its troops into free land first, otherwise at a weaker neighbour, unless half
  its troops are already out fighting. So they all expand next to you instead of sitting still.
- Start patch is ~50 OpenFront tiles (`50 / of_k` of ours), like the first frame of the video.

## Round 7 - performance when the map gets crowded
- **Frame budget**: at most 2 economy ticks and 3 attack steps run per frame. If the PC falls behind, the game runs a hair slower
  for a moment instead of trying to catch up (that catch-up loop is what made crowded games spiral into low FPS).
- **Bot-vs-bot attacks** step every 3rd attack tick with 3x the budget (same speed, a third of the scanning). Attacks involving you
  still step 10x per second so your front stays smooth. Attack fronts are also rebuilt less often.
- **Only visible things are drawn**: buildings, rails, trains, ships, boats, mines, merchants, attack tags and name labels outside the
  screen are skipped (big win when zoomed in on a crowded map).
- **No more per-tile allocations**: ownership changes, border updates, hole filling and the front scans no longer create a temporary
  array for every tile; hole filling uses a stamp array instead of dictionaries.
- **Sea searches** (merchant ships, trade boats, warship orders, boat attacks) reuse shared buffers instead of allocating and clearing
  two whole-map arrays each time - those were the big stutters every half second.
- **Map upload rate adapts** to how long the texture upload takes (0.05 s on a fast PC, up to 0.25 s on a slow one).
- **Rails** are rebuilt at most every 3 s for bot building changes (instantly when YOU build a station), with a cheaper distance test.

## Round 8 - premium visual upgrade (see AI_PROGRESS.md)
Theme + typography, glass panels, button/card states, HUD stat rows with troop bar and growth rate, leaderboard, calmer ocean with
shoreline, relief, cleaner borders, nation hover highlight, capture flash, panel fade-ins. Gameplay untouched.

## Round 9 - Phase 3 polish (see AI_PROGRESS.md)
Calmer ocean and cleaner borders, selected-nation outline, label priority + collision culling, zoom-aware building icons without stacking,
clearer purchase cards (name / price / hotkey / count, dimmed when unaffordable), more compact HUD with primary/secondary text.


## Round 9 - gameplay feedback (Phase 4)
Ring effects for launched/escalating attacks and for buildings built, captured or lost; breathing ring on your attacks and attacks against you; faint wake behind boats;
selected-nation outline fades in; green/red toasts with a short pop; building cards pop on purchase and shake when you cannot pay. Visual only. See `AI_PROGRESS.md`.


## Round 10 - UI polish (Phase 5)
Shared margins/palette/progress-bar style, attacks list capped above the card bar, clearer disabled-state tooltips on cards, one clamped map tooltip, "Lobby full" state, coloured end panel, focus-free zoom buttons. See `AI_PROGRESS.md`.


## Round 11 - map quality (Phase 6)
Smoothed coastline and thin zoom-independent borders (shader only), terrain tooltip with dwell delay, cached/edge-safe map labels, eased zoom. See `AI_PROGRESS.md`.


## Mobile / touch controls (phones and tablets)
Mouse + keyboard code is unchanged. All touch code is the last section of `main.gd` ("touch / mobile") and switches on by itself on a
phone or tablet, or the first time a screen is touched. A finger already arrives as an emulated left mouse button, so tap = click and
drag = pan work as before; this layer adds:
- **Pinch** to zoom and **two-finger drag** to pan (the point between your fingers stays put).
- **Long press** (0.45 s, with a ring and a buzz) = right click: opens the nation menu (alliance / attack / boat) or cancels a build.
- **Confirm step**: tapping to choose your start, or to place a building / warship / mine, drops a marker; the gold **check** button
  places it (tap elsewhere to move the marker). Normal attack taps are still instant.
- **Cancel** button (= Esc / right click), **centre on my land** button, Android **back** button = cancel (it never quits the game).
- **Bigger targets**: zoom buttons, sea-units arrow, attack-% slider handle, nation menu, attack cancel buttons, lobby button.
  On small high-DPI screens the whole UI is scaled up (max `TOUCH_MAX_SCALE`).
- **Notch / safe area** insets keep panels clear of camera cut-outs and the gesture bar. A little finger wobble never turns a tap into a pan (`TOUCH_SLOP`).
- **Performance**: frame cap `TOUCH_MAX_FPS` (60), lighter map shader on touch devices (flat ocean/land tones instead of 4 noise lookups
  per pixel), Compatibility renderer on mobile, ETC2/ASTC texture import, screen stays on while playing, landscape-only.
Tunables are the `TOUCH_*` constants at the top of that section. Android: install Godot's Android export template, Project > Export > Android.
Web on a phone also works (Compatibility renderer). Not tested on a device (no Godot or phone here).


## Round 4 (lobby slots + 25 s spawn countdown)
- **Open slots**: every lobby now keeps `LOBBY_OPEN_SLOTS` (2) slots free, so it shows e.g. `98 / 100  (2 open)`. Pressing Join takes one slot and the lobby
  no longer starts by itself: it starts when it is full or when the lobby timer (`LOBBY_SECS`, 2:00) runs out. (Nothing is networked yet, so the
  second slot stays open until then - lower `LOBBY_SECS` for quick solo tests.)
- **Spawn countdown**: when a lobby starts, the whole map is shown for `SPAWN_SECS` (25 s) and nobody spawns yet. Click any land to choose your start,
  click again to move it (a ring with a shrinking time arc marks it, plus a big "GAME STARTS IN" timer). On a phone, tap a spot and press the gold check.
- **Placeholder players** (the bots) choose too: each picks a random spot at a random moment during the countdown, and about a third change their mind
  once. You see their coloured dots appear.
- **When the timer hits 0**: you appear exactly where you last clicked (a random free spot if you never clicked), then every other slot appears on its pick.
  If someone's pick was taken or is too close to a spot someone else clicked, that slot gets a free spot instead (`_start_ok`, `_random_start`).

## Round 5 (multiplayer prep)
- `my_slot` replaces every hard-coded "player 1"; the match ends when ANY slot owns `WIN_SHARE` of the land.
- All gameplay randomness goes through one seeded generator (`sim_rng`, `match_seed`).
- See `MULTIPLAYER_PROGRESS.md` for what is done, what is next, and where work stopped.


## Online test build
Two or more players over a relay server (works in a browser build on itch.io). See `MULTIPLAYER_PROGRESS.md` (top) and `server/README.md`.


## Naval redesign (see NAVAL_REDESIGN_PROGRESS.md - supersedes the merchant / trade-boat / 16-tile / boat-theft notes above)
- No more neutral merchant ships, port trade boats, boat theft or passive port gold. A port launches troop boats and builds warships.
- Troop boats need a port. Warships can be sent to ANY reachable water (no 16-tile limit, real BFS routes, never through land) and
  intercept / sink enemy transports and fight enemy warships (HP, range, cooldown). Only water mines keep `SEA_RANGE`.

## Spectate + smarter bots
See `SPECTATE_AND_BOTS.md`: lobby "Spectate" button (all-bot offline match, 1x-8x speed, click a nation to follow) and a new bot economy/defence/diplomacy brain.
