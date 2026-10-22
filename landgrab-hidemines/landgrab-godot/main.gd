extends Node2D
# Landgrab - Godot 4 (phase 4: lobby + buildings: village / station / port).

const TICK := 0.5                 # seconds per game tick - THE master speed knob (bigger = slower game)
const ATK_TICK := 0.1              # attacks / expansion step: 10 per second, like OpenFront
# PLAYER-vs-PLAYER fights only (taking free land is unchanged). Both are plain multipliers on the OpenFront-style numbers below:
const ATK_LOSS_MULT := 0.65   # the attacker's troop loss for every tile it conquers (1.0 = before). Lower = attackers lose fewer troops for the same land.
const ATK_SPEED_MULT := 1.6   # how fast an attack takes tiles (1.0 = before). Higher = the front advances faster for the same troop count.
# Troop advantage = faster conquest. Without this an attacker with MORE than ~1.2x the defender's troops was no faster at all (500K against 10K
# moved like 15K against 10K). Above ATK_ADV_START (attacker troops / defender troops) the speed grows with the logarithm of the advantage:
# 1.5x troops about +14 %, 5x about +80 %, 10x about +120 %, and it never exceeds ATK_ADV_MAX (so: clearly faster, never instant).
const ATK_ADV_START := 1.2
const ATK_ADV_SLOPE := 0.4    # speed bonus per doubling of the advantage
const ATK_ADV_MAX := 2.5      # the most the bonus can ever give (2.5 = two and a half times as fast)
const ATK_FRONT_SPEED := 1.3       # tiles per second the front advances (measured from the reference video)
const LOBBY_SECS := 120.0         # a lobby starts after this long, or as soon as it is full
const LOBBY_OPEN_SLOTS := 2       # slots left free in every lobby (for the two testers); everyone else is a placeholder player
const SPAWN_SECS := 25.0          # once a lobby starts the map is shown this long: everybody picks (and may change) their start
const ACC := Color("d9ac4f")      # antique gold: the single accent of the whole UI
const OUT := Color("2b1d10")
# Historical palette (atlas / campaign map): dark navy "ink" panels framed in brass, parchment text, forest green and burgundy for good / bad
const UI_LINE := Color(0.85, 0.67, 0.31, 0.30)   # gilt hairline
const UI_TEXT := Color("f0e4c4")                  # parchment
const UI_MUTED := Color("a89873")                 # aged vellum
const UI_GOOD := Color("86c382")                  # forest
const UI_BAD := Color("e0705f")                   # burgundy, lifted so it reads on navy
const UI_NAVY := Color(0.043, 0.075, 0.125, 0.93) # panel fill
const UI_INK := Color("22160a")                   # dark brown ink (text on brass / parchment)
const UI_BRASS := Color("a8843a")                 # frame lines
const UI_BURGUNDY := Color(0.23, 0.09, 0.11, 0.97) # selected card fill
const UI_MARGIN := 6              # distance of every HUD panel from the window edge
const NAMES := ["You", "Aurelia", "Borea", "Calden", "Dorne", "Esker", "Fenmark", "Galt",
	"Hollin", "Ister", "Juno", "Kessa", "Lorne", "Mirev", "Norra", "Ostel"]

# ---- maps: each lobby picks one. "max" = player slots ----
# The 5 maps are FIXED images in res://maps/ (baked once by tools/bake_maps.py - nothing is generated at runtime).
# "w"/"h" are the OpenFront-style sizes (~2 million tiles each) = the PNG size; MAP_SCALE shrinks them so GDScript stays
# smooth: 0.5 = about 500k tiles per map, 1.0 = full size (heavier).
# PNG colours: water (20,60,100), green (80,150,70), desert (220,190,110), snow (245,248,252).
const MAP_SCALE := 0.5
# PACING: OpenFront's economy (troop costs, max troops) is tuned for ~2 million land tiles. Our maps are smaller, so one
# of our tiles stands for `of_k` OpenFront tiles (= REF_LAND / land_count). Troop cost per tile, max troops and the
# front speed are scaled with it, so land GROWS AT THE SAME SPEED AS A SHARE OF THE MAP as in OpenFront
# (about 0.15% of the land after 15 s), whatever the map size or MAP_SCALE. Raise REF_LAND = slower expansion.
const REF_LAND := 2000000.0
const MAPS := [
	{"name": "World", "img": "res://maps/world.png", "w": 2000, "h": 1000, "max": 100},
	{"name": "Europe", "img": "res://maps/europe.png", "w": 1600, "h": 1300, "max": 65},
	{"name": "Asia", "img": "res://maps/asia.png", "w": 1500, "h": 1300, "max": 65},
	{"name": "North America", "img": "res://maps/north_america.png", "w": 1500, "h": 1360, "max": 65},
	{"name": "Africa", "img": "res://maps/africa.png", "w": 1400, "h": 1450, "max": 65},
]
const BOAT_STEP := 3              # tiles a troop boat sails per game tick
const BOAT_MAX_PATH := 500        # longest sea route a boat will take (tiles)
const BOAT_NODE_CAP := 400000     # route search gives up after this many water tiles

# ---- buildings ----
const BUILD_ORDER := ["village", "station", "port"]
const BASE_PRICE := {"village": 125000, "station": 125000, "port": 125000, "warship": 250000, "mine": 50000}
const PRICE_CAP := 1000000        # OpenFront: city / port / factory cost 125K x 2^owned, capped at 1M
const OF_TICKS_PER_ECON := 5.0    # OpenFront ticks every 0.1 s; our economy ticks every TICK (0.5 s)
const GOLD_PER_OF_TICK := 100.0   # OpenFront: every player earns 100 gold per tick (bots 50) = +1000/s
const WIN_SHARE := 0.8            # OpenFront: own 80% of the land to win
# short names for the small cards (BUILD_LABEL stays the full name used in messages)
const CARD_SHORT := {"silo": "Launcher", "mine": "Water Mine"}
const BUILD_LABEL := {"village": "Village", "station": "Station", "port": "Port", "warship": "Warship", "mine": "Water Mine", "silo": "Bomb Launcher", "sam": "SAM Site", "atom": "Small Bomb", "nuke": "Nuke", "mega": "Mega Bomb"}
const BUILD_TIP := {
	"village": "Village: raises max troops. Click it again with this tool: Village -> City -> Duchy.",
	"station": "Train station: links your cities by rail. Trains pay gold when they pass through a city.",
	"port": "Port: must touch the water. Sends a trade ship to a random port anywhere on the map (every 15 s at Lv 1, 1.5 s faster for every level) that it can reach by water (gold for the distance sailed; nothing sails while there is no other port), launches troop boats and builds warships. Click a port again to upgrade it (max Lv 5): trade income x1 / 1.5 / 2 / 2.5 / 3 and +20 HP on new warships per level.",
	"warship": "Warship: click any water - it launches from your nearest port and sails there. Click it to give orders: it sinks enemy transports, fights warships and boards and captures enemy trade ships (not allies'), which then sail for you. Needs a port.",
	"mine": "Water mine: sits at sea and blows up the first enemy boat that touches it. Needs a port.",
	"silo": "Bomb Launcher (1M): fires bombs at any spot on the map. Click it again with this tool to upgrade it (max Lv 4; 1.5M / 2.5M / 4M): Lv 1 = Small Bomb, Lv 2 = Nuke, Lv 4 = Mega Bomb, and it reloads faster with every level (60 / 50 / 40 / 30 s). Build it inside your territory. The arrow opens the bombs.",
	"sam": "SAM Site (1.5M): shoots at enemy bombs that fly within 24 tiles of it (Small Bomb 80% hit chance, Nuke 55%, Mega Bomb 30%; 7.5 s reload). Build several to protect your base. Allies' bombs are never shot.",
	"atom": "Small Bomb (750K): click a target. Everything within 5 tiles is destroyed; land up to 10 tiles away is hit at random. The land becomes nobody's and turns into a green fallout zone until somebody claims it. Needs a ready Bomb Launcher.",
	"nuke": "Nuke (5M): click a target. Everything within 12 tiles is destroyed, land up to 24 tiles away is hit at random, and the land turns into a fallout zone. Needs a ready Bomb Launcher of level 2 or higher.",
	"mega": "Mega Bomb (25M): click a NATION's land. About 85% of that nation's land (the part nearest to the impact point) and the buildings on it are destroyed and turn into fallout; its troops drop by the same share. Cannot target yourself or an ally. Needs a ready Bomb Launcher of level 4.",
}
const PRICE_STEPS := 5            # price tiers: 1x, 2x, 3x, 4x, 5x the base price, then it stays at 5x

# ---- troop capacity (tune these) ----
const CAP_BASE := 150.0
const CAP_TILE := 6.0
const CAP_VILLAGE := 250000.0   # OpenFront: +250,000 max troops per city level (village = lv1, city = lv2, duchy = lv3)
const CAP_CITY := 500000.0           # a city replaces its village, so this is the total, not extra
const CAP_DUCHY := 750000.0          # same: total for a duchy

# ---- income per tick (slow on purpose) ----
const GOLD_BASE := 0.12
const GOLD_TILE := 0.006
const GOLD_VILLAGE := 0.03
const GOLD_CITY := 0.1
const GOLD_DUCHY := 0.25
const GOLD_STATION := 0.03
const RAIL_PAY := {"station": 10000.0, "village": 0.0, "city": 10000.0, "duchy": 10000.0}   # gold per train visit
const RAIL_SPEED := 0.5           # tiles per tick

# ---- ports ----
const PORT_MAX := 5               # max port level
const PORT_HP_PER_LEVEL := 20     # a warship built at a port gets +20 max HP for every port level above 1
const PORT_INCOME_MULT: Array[float] = [0.0, 1.0, 1.5, 2.0, 2.5, 3.0]   # trade income by port level: a Lv 5 port earns about as much as your whole base income
const PORT_BOATS := 12            # max trade ships afloat per port at a time (a trip can take a minute)
const TRADE_COOLDOWN := 30        # ticks between two trade ships from a LEVEL 1 port: 30 ticks x TICK (0.5 s) = 15 seconds
const TRADE_COOLDOWN_PER_LEVEL := 3   # every port level makes it 3 ticks = 1.5 seconds faster (Lv 5: 9 seconds)
const TRADE_SHIPS_MAX := 500      # safety cap: trade ships afloat on the whole map
const TRADE_ROUTES_PER_TICK := 3  # new sea routes (not yet remembered) that may be searched per tick
const TRADE_STEP := 2             # tiles a trade ship sails per tick
const TRADE_GOLD_PER_TILE := 200.0 # gold per tile of the route: a 50-tile trip = 10K (one train visit), the 100-tile maximum = 20K. A port averages ~350 gold/s on top of the 1000/s base income
const WARSHIP_STEP_PRICE := 250000
const WARSHIP_PRICE_CAP := 750000 # a warship never costs more than this

# ---- rails ----
const RAIL_REACH := 34.0          # two rail points link only if closer than this AND the straight line is all land

# ---- sea units (unlocked by owning a port) ----
const SEA_ORDER := ["warship", "mine"]
const SEA_RANGE := 16             # WATER MINES only: dropped at most this many water tiles from one of your ports. Warships have NO range limit.
const SHIP_HP := 100              # warship health at a level 1 port (+PORT_HP_PER_LEVEL per extra port level)
const BOAT_HP := 50               # troop transport health
const WARSHIP_RANGE := 8.0        # tiles: guns reach this far
const WARSHIP_CD := 2             # ticks between two shots of one warship
const SHOT_VS_BOAT := 25          # damage to a transport (two hits sink it)
const SHOT_VS_SHIP := 10          # damage to an enemy warship
const WARSHIP_SIGHT := 20.0       # tiles: an idle warship goes after enemy ships / transports it sees this close, then returns to its station
const MINE_TRIGGER := 1.6         # tiles: an enemy boat this close sets the mine off
const SHIP_SPEED := 3             # tiles per tick (a transport sails BOAT_STEP = 3)
const ORBIT_R := 6.0              # tiles: radius of the circle an idle warship patrols around its station point
# ---- capturing trade ships (all timers count 0.1 s attack steps = ATK_TICK, so they are exact and identical on every client) ----
const CAPTURE_RANGE := 4.0        # tiles: a warship this close to its locked trade ship starts boarding it
const CAPTURE_HOLD_DIST := 1.5    # tiles: alongside the trade ship the warship stops sailing and holds position
const CAPTURE_HOLD_RANGE := 7.0   # tiles: boarding is broken off if the trade ship gets farther away than this
const CAPTURE_STEPS := 8          # boarding lasts 8 steps = 0.8 s; the ship changes owner on the last one
const CAPTURE_COOLDOWN_STEPS := 12  # 12 steps = 1.2 s before the same warship may start another capture
const CAPTURE_PROTECT_STEPS := 30   # a ship that was just captured cannot be targeted again for 3 s
const CAPTURE_FLASH_STEPS := 6    # client look only: how long the white ring after a capture lasts
# ---- nuclear weapons (OpenFront prices: Missile Silo 1M, SAM Launcher 1.5M, Atom Bomb 750K - they fit this game's +1000 gold/s economy) ----
# Distances are in map tiles. This map is ~9x smaller than OpenFront's, so the blast is scaled up (OpenFront atom: 12 / 30) to stay meaningful.
const LAND_EXTRA := ["silo", "sam"]          # land buildings placed with the normal build command (silo = Bomb Launcher, has levels)
const DEFENSE_ORDER := ["silo", "sam"]       # second row of the build bar: Bomb Launcher, SAM Site
const NUKE_ORDER := ["atom", "nuke", "mega"] # the bombs (popup of the Bomb Launcher arrow, hotkeys 8 9 0)
const PRICE_SILO := 1000000
const PRICE_SAM := 1500000
const BOMB_PRICE := {"atom": 750000, "nuke": 5000000, "mega": 25000000}    # paid per bomb launched
const BOMB_NEED_LEVEL := {"atom": 1, "nuke": 2, "mega": 4}                 # Bomb Launcher level needed for each bomb
const BOMB_INNER := {"atom": 5.0, "nuke": 12.0}    # tiles: every tile inside loses its owner and becomes fallout; buildings / units die
const BOMB_OUTER := {"atom": 10.0, "nuke": 24.0}   # tiles: land between INNER and OUTER is hit at random (NUKE_RING_LOSS)
const MEGA_LAND_SHARE := 0.85      # Mega Bomb: you pick a NATION; about this share of ITS land (the part nearest to the impact point) is destroyed
const BOMB_SAM_HIT := {"atom": 0.80, "nuke": 0.55, "mega": 0.30}   # chance that one SAM shot stops the bomb
const LAUNCHER_MAX := 4
const LAUNCHER_UPGRADE_PRICE := [0, 0, 1500000, 2500000, 4000000]  # price to REACH that level (index = new level)
const SILO_RELOAD_BY_LEVEL := [0, 600, 500, 400, 300]              # attack steps (0.1 s) between two launches, by launcher level
const NUKE_SPEED := 0.6            # tiles per attack step (0.1 s) = 6 tiles/s: a 150-tile shot takes ~25 s
const ALLY_REQ_TICKS := 240      # a human alliance request stands for 2 minutes (240 economy ticks of 0.5 s)
const BLAST_TILE_BUDGET := 3000    # a blast changes at most this many tiles per attack step (0.1 s): a Mega Bomb then sweeps over the map in a few seconds instead of freezing the game
const NUKE_RING_LOSS := 0.5
const NUKE_TROOP_KILL := 1.0       # a hit nation loses this x (tiles lost / tiles owned) of its troops, on top of the lower troop cap
const SAM_RANGE := 24.0            # tiles: a SAM Site shoots at enemy bombs that come this close (maps are 500-1000 tiles wide)
const SAM_RELOAD_STEPS := 75       # 7.5 s between SAM shots
const CAPTURE_OWN_PORT_PROTECTED := true   # RULE: a warship can never capture a trade ship that is sailing to a port of its OWN nation (false = old behaviour, for testing)
const HOVER_SHIP_PX := 26.0       # client only: how close (pixels) the mouse must be to a ship to show its owner in the top bar
const SHIP_MAXD := 2500           # longest sea route a warship order may have (tiles)
const NAV_NODE_CAP := 1200000     # a warship route search gives up after visiting this many water tiles
const BOT_FLEET := 2              # warships an AI nation keeps
const SPEC_NATIONS := 32          # how many nations a spectator match has (all of them AI)
const INTL_RAIL_PAY := 25000.0        # gold EACH nation gets per train visit on a link between two nations' stations
const BLUE := Color("5aa9ff")     # your attacks
const RED := Color("ff6b5b")      # attacks against you
const STAGE_NAMES := ["Skirmish", "Assault", "Surge"]
# Backdrop behind the map: a quiet deep-navy gradient with a barely visible slow haze and fine grain, darker toward the corners, with a soft
# shadow and a thin pale rim around the map so the board lifts off the table. Drawn on its own layer behind everything (look only).
const BG_SHADER := """
shader_type canvas_item;

uniform vec2 vp_size = vec2(1280.0, 720.0);
uniform vec4 map_rect = vec4(-9999.0, -9999.0, 1.0, 1.0);   // map position and size in canvas pixels
uniform float now = 0.0;

float hash(vec2 p) {
    return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

float vnoise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

float box_dist(vec2 p, vec2 centre, vec2 half_size) {
    vec2 d = abs(p - centre) - half_size;
    return length(max(d, vec2(0.0))) + min(max(d.x, d.y), 0.0);
}

void fragment() {
    vec2 p = UV * vp_size;
    vec2 q = UV - vec2(0.5);
    vec3 c_mid = vec3(0.052, 0.112, 0.178);
    vec3 c_edge = vec3(0.022, 0.044, 0.080);
    float r = length(q * vec2(1.0, 0.85));
    vec3 col = mix(c_mid, c_edge, smoothstep(0.10, 0.85, r));
    float hz = vnoise(p * 0.004 + vec2(now * 0.004, 0.0)) * 0.6 + vnoise(p * 0.012 - vec2(0.0, now * 0.006)) * 0.4;
    col += vec3(0.012, 0.025, 0.030) * (hz - 0.5);
    col += (hash(floor(p)) - 0.5) * 0.012;
    vec2 mc = map_rect.xy + map_rect.zw * 0.5;
    vec2 hs = map_rect.zw * 0.5;
    float d_sh = box_dist(p - vec2(4.0, 9.0), mc, hs);
    col *= 1.0 - 0.45 * (1.0 - smoothstep(0.0, 42.0, d_sh));
    float d0 = box_dist(p, mc, hs);
    col = mix(col, vec3(0.72, 0.56, 0.26), 0.55 * (1.0 - smoothstep(0.0, 1.6, abs(d0))));   // brass frame line around the chart
    COLOR = vec4(col, 1.0);
}
"""

# ---- conquest sparks: a fixed pool (no allocation while playing), look only ----
const SPARK_MAX := 160            # sparks alive at once (ring buffer: the oldest is reused)
const SPARK_LIFE := 0.55          # seconds
const SPARK_PER_FRAME := 6        # new capture bursts per rendered frame at most, however fast the simulation runs

const TERRAIN_SHADER := """
shader_type canvas_item;

uniform sampler2D map_tex : filter_nearest, repeat_disable;
uniform sampler2D time_tex : filter_nearest, repeat_disable;
uniform sampler2D pal_tex : filter_nearest, repeat_disable;
uniform sampler2D ter_tex : filter_nearest, repeat_disable;
uniform sampler2D shore_tex : filter_nearest, repeat_disable;
uniform vec2 map_size = vec2(220.0, 130.0);
uniform float now = 0.0;
uniform float hl_owner = 0.0;   // nation under the cursor (0 = none)
uniform float hl_amt = 0.0;     // 0..1 fade of that highlight
uniform float sel_owner = 0.0;  // nation picked with the right-click menu (0 = none): bright outline
uniform float sel_amt = 1.0;    // 0..1 fade-in / gentle pulse of that selection
uniform sampler2D land_tex : filter_linear, repeat_disable;   // land flag per tile, LINEAR filtered: rounds the staircase coast
uniform float px_tile = 1.0;    // on-screen size of one map tile (the zoom): keeps borders and foam a fixed thin width when zoomed in

// Plain pixel tiles. A tile that was just taken keeps showing its old owner until its own moment (time_tex),
// so a conquest appears tile after tile, continuously, instead of in one block every game tick.
// x = owner shown right now, y = land flag
vec2 cell(ivec2 c) {
    ivec2 mx = ivec2(map_size) - ivec2(1);
    c = clamp(c, ivec2(0), mx);
    vec4 m = texelFetch(map_tex, c, 0);
    float ct = texelFetch(time_tex, c, 0).r;
    float o = (now >= ct) ? m.r : m.b;
    return vec2(floor(o * 255.0 + 0.5), m.g);
}

float hash(vec2 p) {
    return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

// nuclear fallout flag of a tile (kept in the alpha channel of map_tex)
float fall_at(ivec2 c) {
    ivec2 mx = ivec2(map_size) - ivec2(1);
    return texelFetch(map_tex, clamp(c, ivec2(0), mx), 0).a;
}

float vnoise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

// Width of a border line inside a tile, from the tile edge. bw >= 1 (zoomed out) = the whole tile, as before.
float edge_amt(float d, float bw) {
    if (bw >= 0.999) {
        return 1.0;
    }
    return 1.0 - smoothstep(bw * 0.5, bw, d);
}

bool is_foe(vec2 n, float ow) {
    return n.y > 0.5 && n.x > 0.5 && abs(n.x - ow) > 0.5;
}

vec3 pal_col(float id) {
    return texelFetch(pal_tex, ivec2(int(id + 0.5), 0), 0).rgb;
}

// How recently the tile at c changed hands: 1 = just now, 0 = more than 8 seconds ago (from the same timestamps as the animation).
float recent(ivec2 c) {
    ivec2 mx = ivec2(map_size) - ivec2(1);
    c = clamp(c, ivec2(0), mx);
    float a = max(now - texelFetch(time_tex, c, 0).r, 0.0);
    return 1.0 - smoothstep(1.0, 8.0, a);
}

float terr_at(ivec2 c) {
    ivec2 mx = ivec2(map_size) - ivec2(1);
    c = clamp(c, ivec2(0), mx);
    return floor(texelFetch(ter_tex, c, 0).r * 255.0 + 0.5);
}

void fragment() {
    vec2 uvt = UV * map_size;
    ivec2 mxc = ivec2(map_size) - ivec2(1);
    ivec2 c = clamp(ivec2(floor(uvt)), ivec2(0), mxc);
    // Coastline: the tile grid only decides ownership. Where a pixel sits on the coast, the land flag is interpolated between
    // tile centres and cut at 0.5, so staircase coasts become smooth diagonals without moving any straight coast.
    float lsm = texture(land_tex, UV).r;
    vec2 me = cell(c);
    bool as_land = lsm >= 0.5;
    if (as_land && me.y < 0.5) {
        // inner corner: a water tile whose pixel counts as land. It takes the owner and terrain of the heaviest land tile around it.
        vec2 q = uvt - vec2(0.5);
        ivec2 b0 = ivec2(floor(q));
        vec2 w = q - floor(q);
        float best = -1.0;
        for (int k = 0; k < 4; k++) {
            ivec2 o = ivec2(k % 2, k / 2);
            ivec2 t = clamp(b0 + o, ivec2(0), mxc);
            vec2 ct = cell(t);
            float wt = ((o.x == 1) ? w.x : 1.0 - w.x) * ((o.y == 1) ? w.y : 1.0 - w.y);
            if (ct.y > 0.5 && wt > best) {
                best = wt;
                c = t;
                me = ct;
            }
        }
        if (best < 0.0) {
            as_land = false;
        }
    }
    vec2 fc = vec2(c);
    float sh = floor(texelFetch(shore_tex, c, 0).r * 255.0 + 0.5);
    if (!as_land) {
        if (me.y > 0.5) {
            sh = 1.0;   // outer corner: a land tile whose pixel the smoothed coast gives to the sea
        }
        // ocean: deep navy that turns to soft teal toward the coast, with a very slow drifting tone
        vec3 deep = vec3(0.055, 0.157, 0.263);
        vec3 mid = vec3(0.086, 0.231, 0.357);
        vec3 shallow = vec3(0.176, 0.447, 0.557);
        float n = vnoise(fc * 0.07 + vec2(now * 0.02, now * 0.012));
        vec3 col = mix(deep, mid, 0.30 + 0.30 * n);
        if (sh > 0.5 && sh < 13.0) {
            float s = 1.0 - (sh - 1.0) / 11.0;
            col = mix(col, shallow, s * s * 0.62);
        }
        // soft drifting light on the water (restrained: fades when zoomed far out, where it would only look like noise)
        float wa = clamp(px_tile / 7.0, 0.25, 1.0);
        float w1 = vnoise(fc * 0.30 + vec2(now * 0.10, -now * 0.06));
        float w2 = vnoise(fc * 0.85 - vec2(now * 0.07, now * 0.12));
        float caus = smoothstep(0.60, 0.88, w1 * 0.6 + w2 * 0.5);
        col += vec3(0.05, 0.10, 0.12) * caus * 0.55 * wa;
        // land casts a soft shadow onto the water below and to the right of it (light comes from the upper left)
        float cs1 = texture(land_tex, UV - vec2(0.9, 0.9) / map_size).r;
        float cs2 = texture(land_tex, UV - vec2(2.0, 2.0) / map_size).r;
        col *= 1.0 - 0.20 * smoothstep(0.35, 0.95, cs1) - 0.08 * smoothstep(0.35, 0.95, cs2);
        // thin foam line on the shore: a fixed thin width when zoomed in, up to the whole tile row when zoomed out
        float fw = clamp(1.6 / px_tile, 0.12, 0.5);
        col = mix(col, vec3(0.78, 0.90, 0.94), 0.16 * smoothstep(0.5 - fw, 0.5, lsm));
        COLOR = vec4(col, 1.0);
    } else {
        // terrain colour of this tile: 0 green wilderness, 1 desert, 2 snow mountain
        float tv = floor(texelFetch(ter_tex, c, 0).r * 255.0 + 0.5);
        vec3 tcol = vec3(0.42, 0.58, 0.30);
        if (tv > 1.5) {
            tcol = vec3(0.92, 0.94, 0.97);
        } else if (tv > 0.5) {
            tcol = vec3(0.86, 0.74, 0.47);
        }
        // broad light/dark patches give the land relief instead of flat speckle
        float lf = vnoise(fc * 0.045) * 0.55 + vnoise(fc * 0.17) * 0.45;
        tcol *= 0.90 + 0.16 * lf;
        tcol *= 0.985 + 0.03 * hash(fc);
        // surface character per terrain: ridged snow mountains, dune ripples, darker forest clumps on the green land
        float rel = 0.0;          // brightness change, about -0.6 .. +0.6
        vec3 rtint = vec3(1.0);   // colour multiplier
        if (tv > 1.5) {
            float h0 = vnoise(fc * 0.55);
            float h1 = vnoise(fc * 0.55 + vec2(0.45, 0.45));
            float ridge = 1.0 - abs(vnoise(fc * 0.22) * 2.0 - 1.0);
            rel = clamp((h0 - h1) * 3.2, -0.6, 0.6) + (ridge - 0.5) * 0.35;
            rtint = mix(vec3(1.0), vec3(0.80, 0.87, 1.0), 0.5 - 0.5 * clamp(rel * 2.0, -1.0, 1.0));   // shaded slopes turn bluish
        } else if (tv > 0.5) {
            rel = sin(fc.x * 0.55 + fc.y * 0.32 + vnoise(fc * 0.12) * 7.0) * 0.07;
        } else {
            float tr = smoothstep(0.55, 0.78, vnoise(fc * 0.50 + vec2(11.0, 11.0)));
            rel = -0.20 * tr;
            rtint = mix(vec3(1.0), vec3(0.80, 0.95, 0.80), tr);
        }
        // mountains throw a short shadow on the land below them
        if (tv < 1.5 && terr_at(c - ivec2(2, 2)) > 1.5) {
            rel -= 0.16;
        }
        tcol *= (1.0 + rel * 0.55) * rtint;
        if (sh > 249.5) {
            tcol = mix(tcol, vec3(0.88, 0.82, 0.60), 0.22);   // beach
        }
        vec3 col = tcol;
        if (me.x < 0.5 && fall_at(c) > 0.5) {
            // nuclear fallout: nobody's land, glowing toxic green until somebody claims it
            float fpl = 0.5 + 0.5 * sin(now * 1.5 + fc.x * 0.23 + fc.y * 0.19);
            float fsp = hash(fc + floor(now * 1.5));
            col = mix(col * 0.62, vec3(0.32, 0.92, 0.20), 0.60 + 0.10 * fpl);
            col += vec3(0.05, 0.16, 0.0) * fsp;
            float fne = min(min(fall_at(c + ivec2(-1, 0)), fall_at(c + ivec2(1, 0))), min(fall_at(c + ivec2(0, -1)), fall_at(c + ivec2(0, 1))));
            if (fne < 0.5) {
                col = mix(col, vec3(0.78, 1.0, 0.35), 0.45);   // glowing edge of the zone
            }
        }
        if (me.x > 0.5) {
            // owned land: plain, opaque owner colour with a hint of the same relief so big nations are not flat
            col = pal_col(me.x);
            // smooth hand-over: for 0.4 s after the switch the old owner's colour (or the bare land) melts into the new owner's
            float swa = now - texelFetch(time_tex, c, 0).r;
            if (swa >= 0.0 && swa < 0.4) {
                float oid = floor(texelFetch(map_tex, c, 0).b * 255.0 + 0.5);
                vec3 prev = (oid > 0.5) ? pal_col(oid) : tcol;
                col = mix(prev, col, smoothstep(0.0, 0.4, swa));
            }
            col *= 0.95 + 0.08 * lf;
            if (hl_owner > 0.5 && abs(me.x - hl_owner) < 0.5) {
                col = mix(col, vec3(1.0, 0.95, 0.80), hl_amt * 0.18);   // the nation under the cursor: warm lift
            }
            float ow = me.x;
            if (sel_owner > 0.5 && abs(ow - sel_owner) < 0.5) {
                col = mix(col, vec3(1.0), sel_amt * 0.07);       // selected nation: faint overall lift
            }
            vec2 nl = cell(c + ivec2(-1, 0));
            vec2 nr = cell(c + ivec2(1, 0));
            vec2 nu = cell(c + ivec2(0, -1));
            vec2 nd = cell(c + ivec2(0, 1));
            // Borders are drawn from the tile edge inward. Zoomed out they fill the whole tile (as before); zoomed in they
            // keep a constant thin width instead of growing into fat blocks.
            vec2 fp = clamp(uvt - vec2(c), vec2(0.0), vec2(1.0));
            float bwd = min(1.0, 1.1 / px_tile);
            float el = edge_amt(fp.x, bwd);
            float er = edge_amt(1.0 - fp.x, bwd);
            float eu = edge_amt(fp.y, bwd);
            float ed = edge_amt(1.0 - fp.y, bwd);
            float foe_a = 0.0;
            float free_a = 0.0;
            float sea_a = 0.0;
            if (is_foe(nl, ow)) { foe_a = max(foe_a, el); }
            if (is_foe(nr, ow)) { foe_a = max(foe_a, er); }
            if (is_foe(nu, ow)) { foe_a = max(foe_a, eu); }
            if (is_foe(nd, ow)) { foe_a = max(foe_a, ed); }
            if (nl.y > 0.5 && nl.x < 0.5) { free_a = max(free_a, el); }
            if (nr.y > 0.5 && nr.x < 0.5) { free_a = max(free_a, er); }
            if (nu.y > 0.5 && nu.x < 0.5) { free_a = max(free_a, eu); }
            if (nd.y > 0.5 && nd.x < 0.5) { free_a = max(free_a, ed); }
            if (nl.y < 0.5) { sea_a = max(sea_a, el); }
            if (nr.y < 0.5) { sea_a = max(sea_a, er); }
            if (nu.y < 0.5) { sea_a = max(sea_a, eu); }
            if (nd.y < 0.5) { sea_a = max(sea_a, ed); }
            float free_x = free_a * (1.0 - foe_a);
            float sea_x = sea_a * (1.0 - max(foe_a, free_a));
            col = mix(col, vec3(0.97, 0.93, 0.80), 0.09 * sea_x);    // coast: just a faint warm rim
            col = mix(col, vec3(0.98, 0.93, 0.76), 0.30 * free_x);    // border toward free land: light parchment rim
            col = mix(col, vec3(0.09, 0.06, 0.04), 0.58 * foe_a);     // border between two nations: crisp dark-ink engraved line
            if (foe_a > 0.0) {
                // active front: a border next to land that changed hands in the last few seconds glows warmly and pulses
                float cf = max(recent(c), max(max(recent(c + ivec2(-1, 0)), recent(c + ivec2(1, 0))), max(recent(c + ivec2(0, -1)), recent(c + ivec2(0, 1)))));
                col = mix(col, vec3(1.0, 0.70, 0.32), foe_a * cf * (0.40 + 0.16 * sin(now * 6.0 + fc.x * 0.35 + fc.y * 0.25)));
            }
            if (sel_owner > 0.5 && abs(ow - sel_owner) < 0.5) {
                col = mix(col, vec3(1.0, 0.86, 0.45), 0.78 * sel_amt * max(foe_a, max(free_a, sea_a)));   // selected nation: antique-gold outline
            }
            // freshly conquered tiles flash for a moment (real capture, from the same timestamps as the animation)
            float age = now - texelFetch(time_tex, c, 0).r;
            if (age >= 0.0 && age < 1.2) {
                float fk = 1.0 - age / 1.2;
                col = mix(col, vec3(1.0), fk * fk * 0.50);     // eased: bright on impact, long soft tail
            }
        }
        // raised-land look: the coast facing the light (upper left) catches light, the opposite coast falls into shade
        float bev = texture(land_tex, UV + vec2(1.1, 1.1) / map_size).r - texture(land_tex, UV - vec2(1.1, 1.1) / map_size).r;
        col *= 1.0 + 0.20 * bev;
        COLOR = vec4(col, 1.0);
    }
    // one soft light gradient over the whole map (upper left a little brighter)
    COLOR.rgb *= 1.04 - 0.07 * (UV.x * 0.5 + UV.y * 0.5);
    // faint antique warmth over the whole chart
    COLOR.rgb = mix(COLOR.rgb, COLOR.rgb * vec3(1.035, 1.0, 0.945), 0.55);
}
"""

# ---- terrain types ----
# 0 = green wilderness, 1 = desert, 2 = snow mountain.
# TERRAIN_SLOW: how many times slower an attack advances (size-wise) over that terrain.
# TERRAIN_LOSS: how many times more troops the attacker loses per tile taken on that terrain.
const T_GREEN := 0
const T_DESERT := 1
const T_SNOW := 2
const TERRAIN_NAME := ["Green wilderness", "Desert", "Snow mountain"]
const TERRAIN_SLOW: Array[float] = [1.0, 1.20, 1.35]
const TERRAIN_LOSS: Array[float] = [1.15, 1.0, 1.35]
const TERRAIN_COL := [Color("73994f"), Color("e0c27a"), Color("eef3f7")]   # preview / minimap colours
const TERRAIN_CELL := 3           # terrain is decided per 3x3 block of tiles

# ---- losing a city ----
const CAPTURE_TROOP_LOSS := 1.0   # 1.0 = the old owner loses exactly the share of troops that building supported


class Player:
	var nm: String
	var col: Color
	var troops := 0.0
	var gold := 0.0
	var tiles := 0
	var peak := 0
	var alive := false
	var bot := false
	var cd := 0
	var think_at := 0   # bots: next game tick on which they look around
	var naval_at := 0   # bots: next game tick on which they may try a boat landing
	var counter_at := 0   # bots: next game tick on which they may counter-attack someone who attacks them
	var ally_at := 0      # bots: next game tick on which they may ask for an alliance
	var ally_until := {}  # bots: ally slot -> game tick after which they may end that alliance
	var grow := 0.0     # real troop growth per second (internal units), shown in the HUD
	var bought := {"village": 0, "station": 0, "port": 0, "warship": 0, "mine": 0, "silo": 0, "sam": 0, "atom": 0, "nuke": 0, "mega": 0}
	var comps := {}     # landmass id -> number of tiles owned on it
	var allies := {}    # player id -> true while an alliance with that player stands
	var csx := 0        # sum of the x / y of every tile this nation owns (centroid = csx / tiles): used to grow round
	var csy := 0


# Small up/down arrow button (opens the sea-units menu above the Port card).
# Engraved panel frame: navy ink fill, brass outer line, fine inner line, cut corners, two small gems. Drawn straight onto the canvas item.
class HistBox extends StyleBox:
	var fill := Color(0.043, 0.075, 0.125, 0.93)
	var edge := Color("a8843a")
	var inner := Color(0.85, 0.67, 0.31, 0.30)
	var gem := Color("d9ac4f")
	var cut := 4.0

	func set_edge(c: Color) -> void:
		if edge != c:
			edge = c
			emit_changed()

	func _oct(r: Rect2, k: float) -> PackedVector2Array:
		var x0 := r.position.x
		var y0 := r.position.y
		var x1 := r.end.x
		var y1 := r.end.y
		return PackedVector2Array([Vector2(x0 + k, y0), Vector2(x1 - k, y0), Vector2(x1, y0 + k), Vector2(x1, y1 - k), Vector2(x1 - k, y1), Vector2(x0 + k, y1), Vector2(x0, y1 - k), Vector2(x0, y0 + k)])

	func _cols(c: Color, n: int) -> PackedColorArray:
		var a := PackedColorArray()
		a.resize(n)
		a.fill(c)
		return a

	func _draw(ci: RID, rect: Rect2) -> void:
		var o := _oct(rect, cut)
		var sh := PackedVector2Array()
		for q in o:
			sh.append(q + Vector2(0.0, 2.0))
		RenderingServer.canvas_item_add_polygon(ci, sh, _cols(Color(0, 0, 0, 0.26), sh.size()))
		RenderingServer.canvas_item_add_polygon(ci, o, _cols(fill, o.size()))
		var closed := o.duplicate()
		closed.append(o[0])
		RenderingServer.canvas_item_add_polyline(ci, closed, _cols(edge, closed.size()), 1.5, true)
		var i2 := _oct(rect.grow(-3.5), maxf(cut - 2.0, 1.0))
		i2.append(i2[0])
		RenderingServer.canvas_item_add_polyline(ci, i2, _cols(inner, i2.size()), 1.0, true)
		if rect.size.x > 60.0 and rect.size.y > 24.0:
			for gy in [rect.position.y + 1.0, rect.end.y - 1.0]:
				var c := Vector2(rect.position.x + rect.size.x * 0.5, gy)
				var d := PackedVector2Array([c + Vector2(0.0, -2.6), c + Vector2(3.6, 0.0), c + Vector2(0.0, 2.6), c + Vector2(-3.6, 0.0)])
				RenderingServer.canvas_item_add_polygon(ci, d, _cols(gem, 4))


# A thin gilt rule with a small diamond in the middle (title underline).
class HistRule extends Control:
	var col := Color(0.85, 0.67, 0.31, 0.80)

	func _init() -> void:
		custom_minimum_size = Vector2(0, 10)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var c := size * 0.5
		draw_line(Vector2(size.x * 0.12, c.y), Vector2(c.x - 9.0, c.y), col, 1.0, true)
		draw_line(Vector2(c.x + 9.0, c.y), Vector2(size.x * 0.88, c.y), col, 1.0, true)
		draw_colored_polygon(PackedVector2Array([c + Vector2(0.0, -4.0), c + Vector2(5.0, 0.0), c + Vector2(0.0, 4.0), c + Vector2(-5.0, 0.0)]), col)
		draw_colored_polygon(PackedVector2Array([c + Vector2(0.0, -2.0), c + Vector2(2.5, 0.0), c + Vector2(0.0, 2.0), c + Vector2(-2.5, 0.0)]), Color("22160a"))


# Fallback cursor: the same image, drawn by the game on a top layer, used when the OS / browser cursor is unreliable (F7 toggles).
class SoftCursor extends Control:
	var main: Node
	var tex_arrow: Texture2D
	var tex_cross: Texture2D

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		size = Vector2(32, 32)

	func _process(_d: float) -> void:
		if not visible:
			return
		var cross := main != null and int(main.get("sel_ship")) != 0
		position = get_viewport().get_mouse_position() - (Vector2(16, 16) if cross else Vector2(2, 2))
		queue_redraw()

	func _draw() -> void:
		var cross := main != null and int(main.get("sel_ship")) != 0
		var t: Texture2D = tex_cross if cross else tex_arrow
		if t != null:
			draw_texture(t, Vector2.ZERO)


class ArrowBtn extends Button:
	var open := false
	func _draw() -> void:
		var c := size * 0.5
		var s := 5.0
		var ay := 1.0 if open else -1.0
		draw_colored_polygon(PackedVector2Array([
			c + Vector2(-s * 1.4, -ay * s * 0.5), c + Vector2(s * 1.4, -ay * s * 0.5), c + Vector2(0, ay * s * 0.7)]), Color("d9ac4f"))


# Flat button that draws an X (cancel) or crossed swords (counter-attack).
class IconBtn extends Button:
	var kind := "x"
	var col := Color("ffffff")
	func _draw() -> void:
		var c := size * 0.5
		var s := minf(size.x, size.y) * 0.26
		var cc := col.lightened(0.3) if is_hovered() else col
		if is_hovered():
			draw_circle(c, minf(size.x, size.y) * 0.5, Color(col, 0.18))
		if kind == "x":
			draw_line(c + Vector2(-s, -s), c + Vector2(s, s), cc, 2.4, true)
			draw_line(c + Vector2(-s, s), c + Vector2(s, -s), cc, 2.4, true)
		else:
			draw_line(c + Vector2(-s, s), c + Vector2(s, -s), cc, 2.4, true)
			draw_line(c + Vector2(s, s), c + Vector2(-s, -s), cc, 2.4, true)
			draw_line(c + Vector2(-s * 0.75, s * 0.1), c + Vector2(-s * 0.1, s * 0.75), cc, 2.0, true)
			draw_line(c + Vector2(s * 0.75, s * 0.1), c + Vector2(s * 0.1, s * 0.75), cc, 2.0, true)


# Small control that draws a building icon (used on the build cards).
class BldIcon extends Control:
	var main
	var kind := "village"
	func _draw() -> void:
		if main == null:
			return
		var s := minf(size.x, size.y) * 0.95
		main.draw_building(self, kind, Vector2(size.x * 0.5, size.y * 0.6), s, Color("f2b84b"), 1.0)


# --- map / game state ---
var W := 220
var H := 130
var N := 12
var land := PackedByteArray()
var coast: Array = []              # per player: {tile: true} for owned land tiles that touch water
var is_coast := PackedByteArray() # 1 = land tile that touches water
var img_interval := 0.05
var ally_req := {}                # human alliance requests: "asker_target" -> tick_n until which the request stands (they answer by asking back)
var ally_ask := {}                # "asker_target" -> tick_n before which that nation will not answer the asker again
var info_panel: PanelContainer
var info_sw: ColorRect
var info_name: Label
var info_ally: Label
var info_bld: Label
var info_troops: Label
var info_gold: Label
var info_o := -1
var info_t := 0.0
var ctx_panel: PanelContainer
var ctx_title: Label
var ctx_make: Button
var ctx_cancel: Button
var ctx_trade: Button
var ctx_boat: Button
var ctx_atk: Button
var ctx_target := 0
var ctx_tile := -1
var terr := PackedByteArray()     # terrain per tile: 0 green wilderness, 1 desert, 2 snow mountain
var ter_tex: ImageTexture
var own := PackedByteArray()      # tile owner (0 = neutral)
var comp := PackedInt32Array()    # landmass id per tile
var land_count := 0
var of_k := 1.0                   # OpenFront tiles per one of our tiles (see REF_LAND)
var players: Array = []
var attacks: Array = []
var boats: Array = []
var bld := {}                     # centre tile -> {"t": type, "o": owner, "cd": int}
var occ := {}                     # footprint tile -> centre tile of the building on it
var rails: Array = []
var rails_dirty := true
var floats: Array = []
var tip_mp := Vector2.ZERO          # mouse position when the terrain tooltip timer last restarted
var tip_still := 0.0               # seconds the mouse has been still (terrain tooltip waits for 0.45 s)
var fx: Array = []                # short ring effects tied to real events: {"p" tile centre, "col", "age", "life", "r" tiles}
var sel_cur := 0                  # nation currently outlined (right-click menu)
var sel_amt := 0.0                # fade-in of that outline
var ships: Array = []             # warships: {"id","o","t" tile,"pt" previous tile,"home" station tile,"hp","cd","tgt" target id (0 none),"auto","path","pi","rp","ban","shot"}
var mines: Array = []             # water mines: {"o", "t"}
var nukes: Array = []             # bombs in flight: {"id","o","kind","a" silo tile,"b" target tile,"k" steps flown,"n" steps to impact}
var blast_jobs: Array = []         # blasts still sweeping over the map (rules state): {"o","cx","cy","rin","rout","y" next row,"y1","tb","hit"}
var blasts: Array = []            # CLIENT LOOK ONLY (never read by the rules): {"p" tile pos,"t0" clock,"big"}
var labels: Array = []            # land labels: {"o", "t" tile, "w" width in tiles}
var sel_ship := 0                 # id of the warship waiting for a destination (crosshair mode), 0 = none
var next_atk_id := 1
var atk_sig := ""
var atk_lbls := {}
var terrain: Sprite2D
var bg_mat: ShaderMaterial            # backdrop shader (own layer behind the map)
var sp_pos := PackedVector2Array()    # spark pool: origin in map tiles ...
var sp_vel := PackedVector2Array()    # ... velocity in screen pixels per second
var sp_age := PackedFloat32Array()    # seconds alive (>= SPARK_LIFE = free slot)
var sp_col := PackedColorArray()
var sp_head := 0
var sp_budget := 0
var map_data := PackedByteArray()   # RGBA8 per tile: owner, land, previous owner
var time_data := PackedByteArray()  # float32 per tile: clock time the tile changed hands (may be in the near future)
var time_tex: ImageTexture
var map_dirty := false
var clock := 0.0
var pal_tex: ImageTexture
var reach_stamp := ""
var reach_dist := PackedInt32Array()
var reach_list: Array[int] = []
var adj: Array = []
var border: Array = []            # per player: {tile: true} for owned tiles that touch someone else's land
var lab_cache := {}
var str_sz := {}                   # cached text sizes for map labels: "text|size" -> Vector2 (get_string_size every frame was the label cost)
var atk_acc := 0.0
var ui_font: Font                  # body face: bundled Lora (res://fonts), falls back to a system serif
var ui_bold_font: Font             # Lora at a heavier weight: numbers
var ui_title_font: Font            # bundled GFS Baskerville: headings, nation names on the map
var cur_arrow: Texture2D           # historical cursor images (res://ui)
var cur_cross: Texture2D
var cur_hand: Texture2D
var cur_soft := false              # true = the cursor is drawn by the game (fallback when the browser ignores custom cursors), toggle with F7
var cur_node: Control
var troops_bar: ProgressBar
var troops_rate: Label
var gold_rate: Label
var _last_rate_lbl: Label
var shore := PackedByteArray()     # per tile: water distance to the coast (1..12), 250 = land that touches water
var shore_tex: ImageTexture
var land_tex: ImageTexture         # land flag per tile (linear filtered in the shader: smooth coastline)
var hl_owner := 0                  # nation under the cursor (map highlight)
var hl_amt := 0.0
var perf_level := 0                # automatic quality: 0 full, 1 lite shader + no sparks, 2 slower map upload, 3 simplest drawing (client look only)
var perf_on := false               # F3: profiler overlay (client only, costs nothing when off)
var perf_label: Label
var perf_us := {}                  # key -> microseconds spent this second
var perf_calls := {}               # key -> calls this second
var perf_peak := {}                # key -> slowest single call this second (microseconds)
var perf_win := 0.0
var perf_frames := 0
var perf_slow := 0                 # frames slower than 34 ms this second
var perf_maxdt := 0.0
var perf_setown := 0               # tiles that changed owner this second
var perf_log: Array = []
var perf_log_t := 0.0
var lb_sig := ""                   # what the leaderboard currently shows (so it is only rebuilt when it changes)
var perf_acc := 0.0
var perf_n := 0
var perf_since := 0.0
var img_floor := 0.05              # shortest time between two map texture uploads (grows with perf_level)
var lod_zoom := 3.0                # below this zoom (px per tile) crowded maps draw simple icons instead of the full art
var lite_on := false
var bar_sbox: VBoxContainer
var compact_cur := false
var compact_init := false
var view_r := Rect2()              # on-screen rectangle (+margin) used to skip drawing things nobody can see
var atk_n := 0                    # attack step counter (bot-vs-bot attacks only step every 3rd one)
var rails_force := false           # a player-made change: rebuild the rails right now
var rails_t := -100                # tick of the last rail rebuild
var _bfs_par := PackedInt32Array()  # shared sea-search buffers (see _water_bfs)
var _bfs_dist := PackedInt32Array()
var _bfs_q: Array[int] = []
var _seen := PackedInt32Array()     # flood-fill stamps for _fill_holes
var _seen_n := 0
var img_t := 0.0
var trade: Array = []             # trade ships: {"id","o" owner,"pi" source port,"dst" destination port,"path","k","pk"}
var no_trade := {}                # "a*1000+b" -> true: nation a cancelled trade with nation b (no ships between them, either way)
var wcomp := PackedInt32Array()   # water body id per tile (0 = land): ports trade only inside one connected body of water
var wsize := PackedInt32Array()   # tiles per water body
var nav: AStarGrid2D              # sea-route finder, land = solid (built by _naval_init at match start)
var port_sea := {}                # port tile -> its water tile in the biggest water body (-1 = none)
var trade_ports: Array[int] = []    # every port, refreshed once per tick by step_ports (launch_trade used to scan ALL buildings per launch)
var route_cache := {}             # src_port * (W*H) + dst_port -> PackedInt32Array water path (the sea never changes: routes are reused)
var trade_budget := 1             # trade-ship route searches left this tick
const CHASE_SEARCHES_PER_TICK := 1 # warship route searches (a flood fill each) per economy tick; was 2. RULE: warships may react a tick later when many chase at once
const TN_CELL := 24                # tiles: cell size of the per-step trade-ship grid (a warship's sight, 20, always fits in 3x3 cells)
const ROUTE_CACHE_MAX := 3000      # remembered trade routes (was 600: with ~40 ports the cache was cleared again and again and every launch searched anew)
var _tn_ok := false                # the grid below is valid ONLY while step_ships runs (trade ships do not move or change inside it)
var _tn_pos := PackedInt32Array()  # trade index -> tile
var _tn_ids := {}                  # trade id -> trade ship dictionary
var _tn_cells := {}                # cell key -> PackedInt32Array of trade indices (ascending)
var _tn_cols := 1
var chase_budget := 1               # warship route searches left this tick (they are the costly part on big maps)
var pstart: Array = []
var spawn_left := 0.0
var my_start := Vector2i(-1, -1)  # where you will spawn = the last land tile you clicked during the countdown
var bot_picks := {}               # placeholder players: slot -> {"tile", "at", "redo_at", "redo_tile"}
var spawn_sb: StyleBoxFlat
var phase := "lobby"              # lobby / spawn / play / over
var my_slot := 1                  # the country (slot) THIS client controls. Everything "mine" uses this, never a literal 1
var sim_rng := RandomNumberGenerator.new()   # ALL gameplay randomness (bots, spawns, naval routes, alliances) uses this, seeded per match
var match_seed := 0               # 0 = pick a new seed when the match starts; a server will send the real one
var headless := false             # true on a dedicated server: no UI exists, so the _ev_* hooks and _after_tick do nothing
var winner_slot := 0              # set by tick() when a slot reaches WIN_SHARE (0 = nobody yet); the client turns it into text

# ---- online play (see the "online" section): lockstep through a relay server ----
const NET_VER := 17                                    # must match PROTO_VERSION in server/relay.py
# THE OFFICIAL SERVER (where the big "Join game" button goes). Put your hosted relay here BEFORE exporting.
# A browser build (itch.io) needs wss://your-domain  (plain ws:// is blocked on https pages). "" = no official server, offline practice lobby only.
# !! This is a *quick tunnel* address: it dies whenever cloudflared / relay.py restarts and is different every time. For a release use a permanent https address (see server/DEPLOY.md), then re-export.
const OFFICIAL_SERVER := "https://fighting-turn-century-agreement.trycloudflare.com"
const DEFAULT_SERVER := OFFICIAL_SERVER               # what the private-room address box shows at first (type another relay's address to use it)
const ONLINE_NATIONS := 24                            # nations in an online match (humans + bots), capped by the map's size
const TURN_SECS := 0.1                                # one network turn = one attack step; every 5th turn is also an economy tick
const NET_SPAWN_TURNS := 250                          # SPAWN_SECS / TURN_SECS
const NET_SUM_EVERY := 50                             # every 5 s each client sends a state checksum so a desync is noticed
const HUMAN_COLS := [Color("d9ac4f"), Color("4a97d0"), Color("c04a6a"), Color("dc7a32"), Color("e6dcc0"), Color("8fba68"), Color("8e72c8"), Color("d4533f")]   # antique gold, azure, rose, ochre, ivory, sage, violet, vermilion
var online := false               # true while connected to a relay (lobby or match)
var net_ws: WebSocketPeer
var net_state := ""               # "" / connecting / lobby / playing / lost
var net_host := false
var net_players: Array = []       # lobby: [{slot, name}]
var net_slots := {}               # running match: slot -> name of every human
var net_turn_q: Array = []        # turns received but not executed yet
var net_turn := 0                 # number of the last executed turn
var net_desync_shown := false
# official public lobby (server-driven): the server owns map, countdown and the open player slots
var net_pub := false              # the current connection is the public lobby (not a private room)
var pub_seq := -1                 # lobby number from the server (-1 = nothing received yet)
var pub_left := 0.0               # seconds until the public match starts (server value, counted down locally)
var pub_shown := -1
var pub_cap := 65                 # nations of the public match
var pub_open := 2                 # real-player slots (all other nations are bots)
var pub_in := false               # I took a player slot
var pub_me := -1
var pub_next := 0
var pub_next_cap := 65
var pub_retry := 0.0              # offline practice lobby: seconds until the next try to reach the official server
var pub_conn_t := 0.0
var pub_srv := ""                   # id of the relay process we are connected to (players on the same id are in the same lobby)
var pub_online := 0
var probe_ws: WebSocketPeer = null   # silent background try at the official server while the practice lobby is on screen
var probe_t := 0.0
var probe_sent := false
var human_picks := {}             # spawn phase: slot -> Vector2i chosen start of every human
var fallen_shown := false
var net_name_edit: LineEdit
var net_server_edit: LineEdit
var mob_cache := -1                   # -1 unknown, 0 desktop, 1 phone / tablet browser
var paste_target: LineEdit = null
var paste_ok_cb: Variant = null     # JavaScript callbacks (kept in variables so they are not freed)
var paste_err_cb: Variant = null
var net_room_edit: LineEdit
var net_btn: Button
var net_map_btn: Button
var mode := "attack"              # attack or a building type
var tick_n := 0
var acc := 0.0

# --- lobby state ---
var lobby := {}
var next_idx := -1
var map_idx := 0
var lobby_note := ""

# --- view ---
var zoom := 4.0
var zoom_goal := 4.0               # wheel / buttons set the goal; _process eases the real zoom toward it
var zoom_anchor := Vector2.ZERO    # screen point that stays fixed while zooming
var view_pos := Vector2.ZERO
var base_data := PackedByteArray()
var img: Image
var tex: ImageTexture
var drag := false
var drag_start := Vector2.ZERO
var drag_view := Vector2.ZERO
var drag_moved := false

# --- ui ---
var hud: PanelContainer
var lb_panel: PanelContainer
var ctl: PanelContainer
var zoom_panel: PanelContainer
var msg_panel: PanelContainer
var end_panel: PanelContainer
var troops_l: Label
var share_l: Label
var gold_l: Label
var lb_box: VBoxContainer
var pct_l: Label
var slider: HSlider
var msg_label: Label
var end_label: Label
var msg_token := 0
var cards := {}                   # type -> {"btn", "price", "count"}
var sub_panel: PanelContainer
var sub_open := false
var arrow_btn: ArrowBtn
var launcher_arrow: ArrowBtn     # arrow on the Bomb Launcher card: opens the bombs
var nuke_panel: PanelContainer   # popup with Small Bomb / Nuke / Mega Bomb
var nuke_open := false
var atk_panel: PanelContainer
var atk_box: VBoxContainer
# lobby ui
var lobby_root: Control
var preview_rect: TextureRect
var lb_map: Label
var lb_info: Label
var lb_players: Label
var lb_bar: ProgressBar
var lb_time: Label
var lb_join: Button
var lb_spec: Button
var spectating := false           # watching an all-bot match: no commands, any nation can be followed
var sim_speed := 1.0              # spectator speed-up (offline only)
var spec_panel: PanelContainer
var spec_label: Label
var lb_next: Label
var lb_note: Label


func _ready() -> void:
	headless = DisplayServer.get_name() == "headless" or OS.has_feature("dedicated_server")
	randomize()
	_make_theme()
	_setup_cursor()
	_build_ui()
	_build_background()
	_build_terrain()
	_setup_touch()
	get_viewport().size_changed.connect(fit)
	enter_lobby()
	_layout.call_deferred()
	_touch_post_layout.call_deferred()


func _process(delta: float) -> void:
	clock += delta
	if perf_on:
		_perf_overlay(delta)
	_perf_adapt(delta)
	sp_budget = SPARK_PER_FRAME if perf_level < 1 else 0
	if online:
		net_poll()
	if phase == "lobby":
		terrain.visible = false
		if not online:
			lobby_step(delta)
			_pub_retry_step(delta)
			_probe_poll(delta)
		elif net_pub:
			_pub_step(delta)
		return
	if phase == "spawn" and not online:
		_spawn_step(delta)
	if online:
		_net_run_turns(delta)   # online: the relay's numbered turns drive the simulation, never the frame time
	else:
		# Frame budget: at most 2 economy ticks / 3 attack steps per frame. If the machine falls behind the game simply runs a
		# little slower for a moment instead of spending ever longer catching up (that is what made crowded games stutter).
		acc += delta * sim_speed
		var nt := 0
		while acc >= TICK and nt < 1 + int(sim_speed):
			acc -= TICK
			nt += 1
			if phase == "play":
				tick()
				_after_tick()
		acc = minf(acc, TICK)
		atk_acc += delta * sim_speed
		var na := 0
		while atk_acc >= ATK_TICK and na < 2 + int(sim_speed):
			atk_acc -= ATK_TICK
			na += 1
			if phase == "play":
				atk_n += 1
				step_attacks()
		atk_acc = minf(atk_acc, ATK_TICK)
	for f in floats:
		f["age"] += delta
	if not floats.is_empty():
		floats = floats.filter(func(f): return f["age"] < 1.6)
	for sk in SPARK_MAX:
		if sp_age[sk] < SPARK_LIFE:
			sp_age[sk] += delta
	if not fx.is_empty():
		for e in fx:
			e["age"] += delta
		fx = fx.filter(func(e): return e["age"] < e["life"])
	if map_dirty and tex != null and clock - img_t >= img_interval:
		img_t = clock
		var u0 := Time.get_ticks_usec()
		rebuild_image()
		# the texture upload costs the same however little changed, so on a slow machine upload less often
		img_interval = clampf(float(Time.get_ticks_usec() - u0) / 1000000.0 * 8.0, img_floor, 0.25)
	_step_zoom(delta)
	terrain.position = view_pos
	terrain.scale = Vector2(zoom, zoom)
	terrain.visible = tex != null
	if bg_mat != null:
		bg_mat.set_shader_parameter("vp_size", get_viewport_rect().size)
		bg_mat.set_shader_parameter("now", clock)
		bg_mat.set_shader_parameter("map_rect", Vector4(view_pos.x, view_pos.y, float(W) * zoom, float(H) * zoom) if tex != null else Vector4(-9999.0, -9999.0, 1.0, 1.0))
	if tex != null:
		var smat := terrain.material as ShaderMaterial
		smat.set_shader_parameter("now", clock)
		smat.set_shader_parameter("px_tile", zoom)
		# soft highlight on the nation under the cursor (only while playing)
		var hov := 0
		if phase == "play":
			var ht := _hover_tile()
			if ht >= 0 and land[ht] == 1:
				hov = own[ht]
		if hov != hl_owner:
			hl_owner = hov
			hl_amt = 0.0
		hl_amt = minf(1.0, hl_amt + delta * 7.0)
		smat.set_shader_parameter("hl_owner", float(hl_owner))
		smat.set_shader_parameter("hl_amt", hl_amt)
		var sel := ctx_target if (ctx_panel.visible and ctx_target > 0) else 0
		if sel != sel_cur:
			sel_cur = sel
			sel_amt = 0.0
		sel_amt = minf(1.0, sel_amt + delta * 6.0)
		smat.set_shader_parameter("sel_owner", float(sel_cur))
		smat.set_shader_parameter("sel_amt", sel_amt * (0.80 + 0.20 * sin(clock * 3.0)))
	Input.set_default_cursor_shape(Input.CURSOR_CROSS if sel_ship != 0 else Input.CURSOR_ARROW)
	var mpn := get_viewport().get_mouse_position()
	if mpn.distance_to(tip_mp) > 3.0 or drag:
		tip_mp = mpn
		tip_still = 0.0
	else:
		tip_still += delta
	_update_info(delta)
	queue_redraw()


func init_map_data() -> void:
	map_data = PackedByteArray()
	map_data.resize(W * H * 4)
	map_data.fill(0)
	var tf := PackedFloat32Array()
	tf.resize(W * H)
	tf.fill(-100.0)
	time_data = tf.to_byte_array()
	for i in W * H:
		if land[i] == 1:
			map_data[i * 4 + 1] = 255
	img_interval = 0.05 if W * H < 300000 else 0.1
	map_dirty = true


# Every ownership change goes through here. The tile fades to its new owner starting at clock + delay, so a batch of
# tiles taken in one game tick is spread over the whole tick and the front moves continuously on screen.
func _set_own(i: int, o: int, delay: float = 0.0) -> void:
	if perf_on:
		perf_setown += 1
	var old: int = own[i]
	own[i] = o
	map_data[i * 4] = o
	map_data[i * 4 + 2] = old
	if o > 0:
		map_data[i * 4 + 3] = 0   # claimed: the fallout mark is gone
	time_data.encode_float(i * 4, clock + delay)
	map_dirty = true
	if old != o:
		if old > 0 and o > 0 and phase == "play":
			_fx_spark(i, o)   # a tile really changed hands between two nations (look only)
		var c: int = comp[i]
		var ctx_x := i % W
		var ctx_y := i / W
		if old > 0:
			(border[old] as Dictionary).erase(i)
			var op: Player = players[old]
			op.comps[c] = int(op.comps.get(c, 0)) - 1
			op.csx -= ctx_x
			op.csy -= ctx_y
		if o > 0:
			var np: Player = players[o]
			np.comps[c] = int(np.comps.get(c, 0)) + 1
			np.csx += ctx_x
			np.csy += ctx_y
		if is_coast[i] == 1:
			if old > 0:
				(coast[old] as Dictionary).erase(i)
			if o > 0:
				(coast[o] as Dictionary)[i] = true
	_border_upd(i)
	var sx := i % W
	if sx > 0:
		_border_upd(i - 1)
	if sx < W - 1:
		_border_upd(i + 1)
	if i >= W:
		_border_upd(i - W)
	if i < W * (H - 1):
		_border_upd(i + W)


func _border_upd(j: int) -> void:
	var q: int = own[j]
	if q == 0 or land[j] == 0:
		return
	var x := j % W
	var edge := false
	if x > 0 and land[j - 1] == 1 and own[j - 1] != q:
		edge = true
	elif x < W - 1 and land[j + 1] == 1 and own[j + 1] != q:
		edge = true
	elif j >= W and land[j - W] == 1 and own[j - W] != q:
		edge = true
	elif j < W * (H - 1) and land[j + W] == 1 and own[j + W] != q:
		edge = true
	if edge:
		(border[q] as Dictionary)[j] = true
	else:
		(border[q] as Dictionary).erase(j)


func _build_background() -> void:
	var cl := CanvasLayer.new()
	cl.layer = -10
	add_child(cl)
	var rect := ColorRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = BG_SHADER
	bg_mat = ShaderMaterial.new()
	bg_mat.shader = sh
	rect.material = bg_mat
	cl.add_child(rect)
	sp_pos.resize(SPARK_MAX)
	sp_vel.resize(SPARK_MAX)
	sp_age.resize(SPARK_MAX)
	sp_col.resize(SPARK_MAX)
	sp_age.fill(SPARK_LIFE)


func _build_terrain() -> void:
	terrain = Sprite2D.new()
	terrain.centered = false
	terrain.show_behind_parent = true
	terrain.visible = false
	var sh := Shader.new()
	sh.code = TERRAIN_SHADER
	var sm := ShaderMaterial.new()
	sm.shader = sh
	terrain.material = sm
	add_child(terrain)


# ======================= lobby =======================

func enter_lobby(rollover: bool = false) -> void:
	spectating = false
	sim_speed = 1.0
	_net_close()
	my_slot = 1   # offline practice games always use slot 1 (an earlier online match may have left another number here)
	phase = "lobby"
	mode = "attack"
	_set_game_ui(false)
	lobby_root.visible = true
	new_lobby(next_idx if next_idx >= 0 else randi() % MAPS.size())
	lobby_refresh()
	if rollover:
		_pub_probe()     # the practice lobby just rolled over: look for the official server silently, no 'Connecting...' flash, no timer reset
	else:
		_pub_connect()   # the lobby you see is the official server's; if it cannot be reached the offline practice lobby above stays


func new_lobby(idx: int) -> void:
	map_idx = idx
	var m: Dictionary = MAPS[idx]
	W = int(int(m["w"]) * MAP_SCALE)
	H = int(int(m["h"]) * MAP_SCALE)
	make_map(m)
	of_k = clampf(REF_LAND / maxf(1.0, float(land_count)), 1.0, 60.0)
	label_comps()
	build_base()
	var pimg := Image.create_from_data(W, H, false, Image.FORMAT_RGBA8, base_data)
	preview_rect.texture = ImageTexture.create_from_image(pimg)
	var cap: int = m["max"]
	lobby = {
		"cap": cap,
		"joined": cap - LOBBY_OPEN_SLOTS,   # LOBBY_OPEN_SLOTS slots stay free; the lobby starts when it is full or the timer ends
		"time": LOBBY_SECS,
		"rate": 0.0,
		"me": false,
	}
	var n := randi() % MAPS.size()
	if n == idx:
		n = (n + 1) % MAPS.size()
	next_idx = n


func lobby_step(delta: float) -> void:
	var cap: int = lobby["cap"]
	lobby["time"] = float(lobby["time"]) - delta
	if int(lobby["joined"]) < cap and randf() < float(lobby["rate"]) * delta:
		lobby["joined"] = int(lobby["joined"]) + 1
	var full := int(lobby["joined"]) >= cap
	if full or float(lobby["time"]) <= 0.0:
		if lobby["me"]:
			start_game()
		else:
			lobby_note = "%s started without you (%d/%d players)." % [MAPS[map_idx]["name"], int(lobby["joined"]), cap]
			enter_lobby(true)
		return
	lobby_refresh()


func lobby_refresh() -> void:
	if lobby.is_empty():
		return
	if online:
		_net_lobby_refresh()
		return
	var m: Dictionary = MAPS[map_idx]
	var cap: int = lobby["cap"]
	var joined: int = lobby["joined"]
	lb_map.text = m["name"]
	lb_info.text = "%d x %d tiles   -   up to %d players" % [W, H, cap]
	lb_players.text = "Players   %d / %d   (%d open)" % [joined, cap, cap - joined]
	lb_bar.max_value = cap
	lb_bar.value = joined
	var t := int(ceil(float(lobby["time"])))
	lb_time.text = "Starts in %d:%02d" % [t / 60, t % 60]
	lb_join.text = "Leave lobby" if lobby["me"] else "Join game"
	lb_join.disabled = (not lobby["me"]) and joined >= cap
	if lb_join.disabled:
		lb_join.text = "Lobby full"
	var nm: Dictionary = MAPS[next_idx]
	lb_next.text = "Up next:  %s   -   %d players" % [nm["name"], nm["max"]]
	lb_note.text = lobby_note


func _lobby_join() -> void:
	if online:
		if net_pub:
			if net_state == "watching":
				lobby_note = ""
				_net_send({"t": "pleave"} if pub_in else {"t": "pjoin", "name": net_name_edit.text.strip_edges()})
		elif net_host and net_state == "lobby":
			_net_send({"t": "start", "n": _net_nations()})
		return
	if lobby["me"]:
		lobby["me"] = false
		lobby["joined"] = int(lobby["joined"]) - 1
	elif int(lobby["joined"]) < int(lobby["cap"]):
		lobby["me"] = true
		lobby["joined"] = int(lobby["joined"]) + 1
		lobby_note = ""
	lobby_refresh()


# Watch an all-bot match: every nation is an AI. Nothing you click can issue a command (validate() already refuses human
# commands for AI nations); clicking a nation just makes the HUD follow it.
func _lobby_spectate() -> void:
	_net_close()
	new_lobby(map_idx)   # make sure the loaded map is the one on screen (the online lobby may have changed it)
	spectating = true
	sim_speed = 1.0
	my_slot = 1
	lobby["me"] = false
	lobby["joined"] = clampi(SPEC_NATIONS, 2, int(MAPS[map_idx]["max"]))
	start_game()
	begin_play()   # no spawn countdown: every nation appears at once
	_spec_refresh()


func _spec_set_speed(v: float) -> void:
	sim_speed = v
	_spec_refresh()


func _spec_follow(i: int) -> void:
	if phase != "play" or land[i] == 0:
		return
	var o := int(own[i])
	if o <= 0 or not (players[o] as Player).alive:
		return
	my_slot = o
	ui()
	_spec_refresh()


func _spec_auto_follow() -> void:
	var best := 0
	var bt := -1
	for p in range(1, N + 1):
		var pl: Player = players[p]
		if pl.alive and pl.tiles > bt:
			bt = pl.tiles
			best = p
	if best > 0:
		my_slot = best
		ui()


func _spec_refresh() -> void:
	if not spectating or spec_label == null:
		return
	spec_label.text = "Spectating %dx   -   following %s   (click any nation to follow it)" % [int(sim_speed), (players[my_slot] as Player).nm]


func _set_game_ui(v: bool) -> void:
	hud.visible = v
	lb_panel.visible = v
	ctl.visible = v and not spectating
	if spec_panel != null:
		spec_panel.visible = v and spectating
	zoom_panel.visible = v
	msg_panel.visible = v
	end_panel.visible = false
	atk_panel.visible = false
	info_panel.visible = false
	ctx_panel.visible = false
	sub_panel.visible = false
	sub_open = false
	arrow_btn.open = false
	arrow_btn.queue_redraw()
	nuke_panel.visible = false
	nuke_open = false
	launcher_arrow.open = false
	launcher_arrow.queue_redraw()


# ======================= online (lockstep through a relay) =======================
# There is NO server-side simulation. server/relay.py gives every player the same match (map, seed, who is human) and then
# sends one numbered "turn" every 0.1 s holding the commands players sent in that turn. Every client runs the SAME
# deterministic simulation on the SAME turns, so everybody sees the same game. Bots are never sent over the network: they run
# inside each client from the shared seed. A player who leaves turns into a bot on every client.
# Consequence: nothing in the rules may depend on my_slot, frame time, the global random generator or on UI state.
# Every client sends a checksum of its state every NET_SUM_EVERY turns; the relay shouts "desync" when two differ.

func _net_send(d: Dictionary) -> void:
	if net_ws != null and net_ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		net_ws.send_text(JSON.stringify(d))


func _net_nations() -> int:
	return clampi(ONLINE_NATIONS, 2, int(MAPS[map_idx]["max"]) - 1)


# A command as JSON: the only non-JSON value in a command is the focus Vector2.
func _cmd_pack(cmd: Dictionary) -> Dictionary:
	var d := {}
	for k in cmd:
		var v: Variant = cmd[k]
		if typeof(v) == TYPE_VECTOR2:
			d[k] = [(v as Vector2).x, (v as Vector2).y]
		else:
			d[k] = v
	return d


# ... and back: JSON numbers arrive as floats, validate() wants real ints.
func _cmd_unpack(d: Dictionary) -> Dictionary:
	var c := {}
	for k in d:
		var v: Variant = d[k]
		if String(k) == "focus":
			if typeof(v) == TYPE_ARRAY and (v as Array).size() == 2:
				c["focus"] = Vector2(float(v[0]), float(v[1]))
		elif String(k) == "frac":
			c["frac"] = float(v)
		elif typeof(v) == TYPE_FLOAT:
			c[k] = int(v)
		else:
			c[k] = v
	return c


func _net_load_settings() -> void:
	var cf := ConfigFile.new()
	if cf.load("user://online.cfg") == OK:
		net_name_edit.text = String(cf.get_value("net", "name", net_name_edit.text))
		net_room_edit.text = String(cf.get_value("net", "room", net_room_edit.text))
		net_server_edit.text = String(cf.get_value("net", "server", net_server_edit.text))


func _net_save_settings() -> void:
	var cf := ConfigFile.new()
	cf.set_value("net", "name", net_name_edit.text)
	cf.set_value("net", "room", net_room_edit.text)
	cf.set_value("net", "server", net_server_edit.text)
	cf.save("user://online.cfg")


func _net_button() -> void:
	if online and not net_pub:     # leave the private room -> back to the official lobby
		_net_close()
		lobby_note = ""
		lobby_refresh()
		_pub_connect()
	else:                          # official lobby (or practice lobby) -> private room
		if net_pub:
			_net_close()
		_net_connect()


func _net_connect() -> void:
	_probe_stop()
	var url := net_server_edit.text.strip_edges()
	if net_room_edit.text.strip_edges() == "":   # no code typed: make one to share with friends
		var chars := "abcdefghjkmnpqrstuvwxyz23456789"
		var code := ""
		for k in 5:
			code += chars[randi() % chars.length()]
		net_room_edit.text = code
	if url == "":
		lobby_note = "Type the server address first."
		lobby_refresh()
		return
	url = _ws_url(url)
	var ws := WebSocketPeer.new()
	if ws.connect_to_url(url) != OK:
		lobby_note = "That server address does not work."
		lobby_refresh()
		return
	_net_save_settings()
	net_ws = ws
	online = true
	net_state = "connecting"
	net_host = false
	net_players = []
	lobby_note = ""
	net_btn.text = "Leave private room"
	_net_lobby_refresh()


# Back to offline: closes the socket and forgets everything about the online match.
func _net_close() -> void:
	if net_ws != null:
		net_ws.close()
	net_ws = null
	online = false
	net_pub = false
	pub_in = false
	pub_seq = -1
	net_state = ""
	net_host = false
	net_players = []
	net_slots = {}
	net_turn_q = []
	net_turn = 0
	net_desync_shown = false
	human_picks = {}
	fallen_shown = false
	if net_btn != null:
		net_btn.text = "Private room"
		net_map_btn.visible = false


func net_poll() -> void:
	if net_ws == null:
		return
	net_ws.poll()
	var st := net_ws.get_ready_state()
	if st == WebSocketPeer.STATE_OPEN:
		if net_state == "connecting":
			if net_pub:
				net_state = "handshake"
				_net_send({"t": "watch", "ver": NET_VER})
			else:
				net_state = "lobby"
				_net_send({"t": "join", "name": net_name_edit.text.strip_edges(), "room": net_room_edit.text.strip_edges(), "ver": NET_VER})
		while net_ws != null and net_ws.get_available_packet_count() > 0:
			var txt := net_ws.get_packet().get_string_from_utf8()
			var d: Variant = JSON.parse_string(txt)
			if typeof(d) == TYPE_DICTIONARY:
				_net_msg(d)
	elif st == WebSocketPeer.STATE_CLOSED:
		if net_state == "playing":
			net_state = "lost"
			net_ws = null
			_show_end("Connection to the server lost")
		else:
			var was := net_state
			var was_pub := net_pub
			_net_close()
			if was_pub:
				pub_retry = 3.0 if was == "watching" else 5.0
				if was == "watching" and not lobby.is_empty():
					lobby["time"] = maxf(1.0, pub_left)   # the practice countdown goes on from the server's time instead of restarting
				lobby_note = "Lost the connection to the official server - practice lobby until it is back." if was == "watching" else "Official server not reachable - practice lobby (retrying)."
			elif lobby_note == "":
				lobby_note = "Could not reach the server." if was == "connecting" else "Disconnected from the server."
				if OS.has_feature("web"):
					lobby_note += " (In a browser the address must start with wss:// - plain ws:// is blocked on https pages.)"
			lobby_refresh()


func _net_msg(d: Dictionary) -> void:
	match String(d.get("t", "")):
		"joined":
			my_slot = int(d.get("you", 1))
			net_host = bool(d.get("host", false))
			if net_host:
				_net_send({"t": "map", "idx": map_idx})
		"lobby":
			net_players = d.get("players", [])
			net_host = int(d.get("host", 0)) == my_slot
			var mi := int(d.get("map", map_idx))
			if mi >= 0 and mi < MAPS.size() and mi != map_idx:
				new_lobby(mi)
			_net_lobby_refresh()
		"pub":
			_pub_msg(d)
		"pnote":
			lobby_note = String(d.get("m", ""))
			_net_lobby_refresh()
		"begin":
			_net_begin(d)
		"turn":
			net_turn_q.append(d)
		"desync":
			if not net_desync_shown:
				net_desync_shown = true
				say("The game went out of sync with the other players (turn %d). Please tell the developer." % int(d.get("n", 0)), 10.0, "bad")
		"err":
			lobby_note = String(d.get("m", "Server error"))
			if net_pub:
				pub_retry = 60.0
			_net_close()
			lobby_refresh()


func _net_begin(d: Dictionary) -> void:
	net_slots = {}
	for e in d.get("players", []):
		net_slots[int(e["slot"])] = String(e["name"])
	my_slot = int(d["you"])
	var mi := int(d["map"])
	if mi != map_idx and mi >= 0 and mi < MAPS.size():
		new_lobby(mi)
	lobby["joined"] = int(d["n"])
	match_seed = int(d["seed"])
	net_pub = false   # from now on this connection is a match (public or private), not the lobby watcher
	net_turn_q = []
	net_turn = 0
	net_state = "playing"
	start_game()


func _net_lobby_refresh() -> void:
	if lobby.is_empty():
		return
	if net_pub:
		_pub_refresh()
		return
	var m: Dictionary = MAPS[map_idx]
	lb_map.text = m["name"]
	lb_info.text = "%d x %d tiles   -   %d nations (the rest are bots)" % [W, H, _net_nations()]
	var names := PackedStringArray()
	for e in net_players:
		names.append(String(e["name"]) + ("  (you)" if int(e["slot"]) == my_slot else ""))
	lb_players.text = "Online   %d player%s:   %s" % [net_players.size(), "" if net_players.size() == 1 else "s", ", ".join(names)]
	lb_bar.max_value = 8
	lb_bar.value = net_players.size()
	if net_state == "connecting":
		lb_time.text = "Connecting..."
	elif net_host:
		lb_time.text = "You are the host"
	else:
		lb_time.text = "Waiting for the host"
	lb_join.text = "Start match" if net_host else "Waiting for the host..."
	lb_join.disabled = not (net_host and net_state == "lobby")
	net_map_btn.visible = net_host and net_state == "lobby"
	lb_next.text = "Private room  %s  -  friends type this code (same server address) and press Private room" % net_room_edit.text.strip_edges()
	lb_note.text = lobby_note


# ---- official public lobby --------------------------------------------------------------------------------------------
# The server owns the map, the countdown and the player slots. The other nations (cap - open slots, e.g. 63 on a 65 map) are
# bots shown as placeholders; when the countdown ends everybody who joined plays together and the bots fill the rest.

# Any way of writing a server address -> a WebSocket address. "https://x" -> "wss://x", "http://x" -> "ws://x", "x" -> "wss://x".
# (An address written as https://... used to become "wss://https://..." which can never connect: the official lobby then silently failed
# and every player ended up in his own offline practice lobby - "everybody is in a different lobby".)
func _ws_url(raw: String) -> String:
	var u := raw.strip_edges()
	while u.ends_with("/"):
		u = u.left(u.length() - 1)
	if u.begins_with("https://"):
		u = "wss://" + u.substr(8)
	elif u.begins_with("http://"):
		u = "ws://" + u.substr(7)
	elif not u.begins_with("ws://") and not u.begins_with("wss://"):
		u = "wss://" + u
	return u


func _pub_connect() -> void:
	if OFFICIAL_SERVER == "" or online:
		return
	var url := _ws_url(OFFICIAL_SERVER)
	var ws := WebSocketPeer.new()
	if ws.connect_to_url(url) != OK:
		pub_retry = 15.0
		return
	net_ws = ws
	online = true
	net_pub = true
	net_state = "connecting"
	net_host = false
	net_players = []
	pub_in = false
	pub_me = -1
	pub_seq = -1
	pub_conn_t = 0.0
	net_btn.text = "Private room"
	net_map_btn.visible = false
	_net_lobby_refresh()


# Offline practice lobby only: every 15 s try the official server again (not while you sit in the practice lobby yourself).
func _pub_retry_step(delta: float) -> void:
	if OFFICIAL_SERVER == "" or bool(lobby.get("me", false)):
		return
	pub_retry -= delta
	if pub_retry <= 0.0:
		pub_retry = 15.0
		_pub_probe()


# Practice lobby only: try the official server in the BACKGROUND. The practice lobby and its countdown stay on screen untouched, nothing says
# "Connecting...", and only when the server really answers does the lobby switch over to the server's one (map + countdown).
func _pub_probe() -> void:
	if OFFICIAL_SERVER == "" or online or probe_ws != null or bool(lobby.get("me", false)):
		return
	var url := _ws_url(OFFICIAL_SERVER)
	var ws := WebSocketPeer.new()
	if ws.connect_to_url(url) != OK:
		return
	probe_ws = ws
	probe_t = 0.0
	probe_sent = false


func _probe_stop() -> void:
	if probe_ws != null:
		probe_ws.close()
		probe_ws = null


func _probe_poll(delta: float) -> void:
	if probe_ws == null:
		return
	probe_t += delta
	probe_ws.poll()
	var st := probe_ws.get_ready_state()
	if st == WebSocketPeer.STATE_OPEN:
		if not probe_sent:
			probe_sent = true
			probe_ws.send_text(JSON.stringify({"t": "watch", "ver": NET_VER}))
		while probe_ws != null and probe_ws.get_available_packet_count() > 0:
			var d: Variant = JSON.parse_string(probe_ws.get_packet().get_string_from_utf8())
			if typeof(d) != TYPE_DICTIONARY:
				continue
			var mt := String((d as Dictionary).get("t", ""))
			if mt == "pub":
				if bool(lobby.get("me", false)):   # you pressed Join in the practice lobby meanwhile: stay there
					_probe_stop()
					return
				net_ws = probe_ws   # the probe becomes THE connection
				probe_ws = null
				online = true
				net_pub = true
				net_state = "watching"
				net_host = false
				net_players = []
				pub_in = false
				pub_me = -1
				pub_seq = -1
				pub_conn_t = 0.0
				lobby_note = ""
				net_btn.text = "Private room"
				net_map_btn.visible = false
				_pub_msg(d as Dictionary)
				return
			if mt == "err":   # e.g. a version mismatch: say so, try again much later
				lobby_note = String((d as Dictionary).get("m", ""))
				pub_retry = 60.0
				_probe_stop()
				lobby_refresh()
				return
	elif st == WebSocketPeer.STATE_CLOSED or probe_t > 20.0:
		_probe_stop()


func _pub_step(delta: float) -> void:
	if pub_seq < 0:
		pub_conn_t += delta
		if pub_conn_t > 6.0:
			# Do not make the player wait: after 6 s the practice lobby takes over (Join works at once) and the real server keeps being tried
			# silently in the background for up to 20 s more (a server that was asleep needs that long); when it answers the lobby switches over.
			_net_close()
			lobby_note = "Server not answering yet (%s) - practice lobby meanwhile (still trying to connect)." % _ws_url(OFFICIAL_SERVER)
			pub_retry = 0.5
			lobby_refresh()
		else:
			lb_time.text = "Connecting...  %d s" % int(pub_conn_t)   # visibly alive, not frozen
		return
	pub_left = maxf(0.0, pub_left - delta)
	var sec := ceili(pub_left)
	if sec != pub_shown:
		pub_shown = sec
		_pub_refresh()


func _pub_msg(d: Dictionary) -> void:
	if not net_pub:
		return
	net_state = "watching"
	var seq := int(d.get("seq", 0))
	if seq != pub_seq:
		lobby_note = ""
		var last: Variant = d.get("last", null)
		if pub_seq >= 0 and typeof(last) == TYPE_DICTIONARY:
			var lm := int((last as Dictionary).get("map", 0))
			var lh := int((last as Dictionary).get("humans", 0))
			if lh > 0 and lm >= 0 and lm < MAPS.size():
				lobby_note = "%s started with %d player%s - you are in the next lobby." % [MAPS[lm]["name"], lh, "" if lh == 1 else "s"]
	pub_seq = seq
	pub_cap = int(d.get("cap", 65))
	pub_open = int(d.get("open", 2))
	pub_next = clampi(int(d.get("next", 0)), 0, MAPS.size() - 1)
	pub_next_cap = int(d.get("next_cap", 65))
	pub_srv = String(d.get("srv", ""))
	pub_online = int(d.get("online", 0))
	pub_left = float(d.get("left", 120))
	pub_shown = -1
	pub_in = bool(d.get("in", false))
	pub_me = int(d.get("me", -1))
	net_players = d.get("humans", [])
	var mi := int(d.get("map", map_idx))
	if mi >= 0 and mi < MAPS.size() and mi != map_idx:
		new_lobby(mi)
	_pub_refresh()


func _pub_refresh() -> void:
	if lobby.is_empty():
		return
	var m: Dictionary = MAPS[map_idx]
	lb_map.text = m["name"]
	net_map_btn.visible = false
	if pub_seq < 0:
		lb_info.text = "%d x %d tiles" % [W, H]
		lb_players.text = "Connecting to the official server..."
		lb_bar.max_value = 65
		lb_bar.value = 0
		lb_time.text = "Connecting..."
		lb_join.text = "Connecting..."
		lb_join.disabled = true
		lb_next.text = ""
		lb_note.text = lobby_note
		return
	var humans := net_players.size()
	var bots := pub_cap - pub_open
	lb_info.text = "%d x %d tiles   -   %d nations: %d bots + up to %d players" % [W, H, pub_cap, bots, pub_open]
	var names := PackedStringArray()
	for i in humans:
		names.append(String(net_players[i]) + ("  (you)" if i == pub_me else ""))
	lb_players.text = "Players   %d / %d   (%d open)" % [bots + humans, pub_cap, maxi(0, pub_open - humans)]
	if humans > 0:
		lb_players.text += "\n" + ", ".join(names)
	lb_bar.max_value = pub_cap
	lb_bar.value = bots + humans
	var t := ceili(pub_left)
	lb_time.text = "Starts in %d:%02d" % [t / 60, t % 60]
	if pub_in:
		lb_join.text = "Leave lobby"
		lb_join.disabled = false
	elif humans >= pub_open:
		lb_join.text = "Lobby full"
		lb_join.disabled = true
	else:
		lb_join.text = "Join game"
		lb_join.disabled = false
	lb_next.text = "Up next:  %s   -   %d players" % [MAPS[pub_next]["name"], pub_next_cap]
	if pub_srv != "":
		lb_next.text += "        Server %s  -  %d online" % [pub_srv, pub_online]
	lb_note.text = lobby_note


func _net_next_map() -> void:
	if net_host:
		_net_send({"t": "map", "idx": (map_idx + 1) % MAPS.size()})


func _net_run_turns(delta: float) -> void:
	acc = minf(acc + delta, TICK)   # only for smooth drawing between economy ticks
	if net_state != "playing":
		return
	if phase == "over":
		net_turn_q.clear()
		return
	var lag := net_turn_q.size()
	var budget := 3 if lag < 10 else (8 if lag < 40 else 20)   # when behind, catch up faster
	var n := 0
	while not net_turn_q.is_empty() and n < budget and (phase == "spawn" or phase == "play"):
		_net_exec_turn(net_turn_q.pop_front())
		n += 1


# The ONLY place that moves an online match forward. Everything here must give the same result on every client.
func _net_exec_turn(t: Dictionary) -> void:
	net_turn = int(t.get("n", net_turn + 1))
	for ds in t.get("d", []):   # players that left: their country is now run by the AI
		var di := int(ds)
		if di >= 1 and di <= N:
			(players[di] as Player).bot = true
			(players[di] as Player).think_at = tick_n
	for raw in t.get("c", []):
		_net_cmd(raw)
	if phase == "spawn":
		spawn_left = SPAWN_SECS - float(net_turn) * TURN_SECS
		if net_turn >= NET_SPAWN_TURNS:
			begin_play()
		else:
			var txt := "Starting in %d s   -   click any land to choose where you start; click again to move it." % ceili(spawn_left)
			if msg_label.text != txt:
				msg_label.text = txt
		return
	if phase != "play":
		return
	atk_n += 1
	step_attacks()
	if atk_n % 5 == 0:
		tick()
		acc = 0.0
		_after_tick()
	if net_turn % NET_SUM_EVERY == 0:
		_net_send({"t": "sum", "n": net_turn, "h": _net_checksum()})


func _net_cmd(raw: Variant) -> void:
	if typeof(raw) != TYPE_DICTIONARY:
		return
	var c := _cmd_unpack(raw)
	var slot := int(c.get("slot", 0))
	if slot < 1 or slot > N:
		return
	if String(c.get("type", "")) == "pick":   # spawn phase: where this human wants to start
		var tl := int(c.get("tile", -1))
		if phase == "spawn" and not (players[slot] as Player).bot and tl >= 0 and tl < W * H and land[tl] == 1:
			human_picks[slot] = Vector2i(tl % W, tl / W)
		return
	var why := validate(slot, c)
	if why == "":
		apply(c)
	elif slot == my_slot:
		say(why, 2.5, "bad")


func _net_checksum() -> int:
	var h := 7
	for p in range(1, N + 1):
		var pl: Player = players[p]
		h = (h * 31 + pl.tiles * 7 + int(pl.troops) + int(pl.gold) * 3 + (1 if pl.alive else 0)) % 2147483647
	# naval state: a transport / warship that differs between two clients (position, health, existence) shows up as a desync
	for sh in ships:
		h = (h * 31 + int(sh["id"]) * 5 + int(sh["t"]) + int(sh["hp"]) * 3 + int(sh["tgt"]) + int(sh.get("cid", 0)) * 7 + int(sh.get("ccd", 0))) % 2147483647
	for tb2 in trade:
		h = (h * 31 + int(tb2["id"]) * 5 + int(tb2["k"]) + int(tb2["o"]) * 3 + int(tb2.get("capt", 0))) % 2147483647
	for bt in boats:
		h = (h * 31 + int(bt["id"]) * 5 + int(bt["k"]) + int(bt.get("hp", BOAT_HP)) * 3) % 2147483647
	# nuclear state: bombs in flight, silo / SAM reload counters and the number of buildings
	for nk in nukes:
		h = (h * 31 + int(nk["id"]) * 5 + int(nk["k"]) + int(nk["b"])) % 2147483647
	for bk in bld:
		var bb2: Dictionary = bld[bk]
		if bb2.has("rl"):
			h = (h * 31 + int(bk) + int(bb2["rl"])) % 2147483647
	for jb in blast_jobs:
		h = (h * 31 + int(jb["y"]) + int(jb["cx"]) * 3 + int(jb["cy"])) % 2147483647
	h = (h * 31 + bld.size()) % 2147483647
	return (h + absi(hash(own))) % 2147483647


# ======================= setup =======================

func start_game() -> void:
	_probe_stop()
	N = maxi(2, int(lobby["joined"]))
	var used_seed := match_seed
	if used_seed == 0:
		used_seed = randi()
	match_seed = 0   # a seed is used once: the next offline match picks a new one
	sim_rng.seed = used_seed
	winner_slot = 0
	fallen_shown = false
	human_picks = {}
	own = PackedByteArray()
	own.resize(W * H)
	own.fill(0)
	border = []
	coast = []
	ally_ask = {}
	ally_req = {}
	for bi in N + 1:
		border.append({})
		coast.append({})
	lab_cache = {}
	atk_acc = 0.0
	init_map_data()
	attacks = []
	boats = []
	trade = []
	no_trade = {}
	port_sea = {}
	route_cache = {}
	_naval_init()
	floats = []
	fx = []
	ships = []
	mines = []
	nukes = []
	blast_jobs = []
	lb_sig = ""
	blasts = []
	labels = []
	sel_ship = 0
	atk_sig = ""
	atk_lbls = {}
	next_atk_id = 1
	_hide_ctx()
	bld = {}
	occ = {}
	rails = []
	rails_dirty = true
	adj = []
	tick_n = 0
	atk_n = 0
	perf_level = 0
	img_floor = 0.05
	lod_zoom = 3.0
	perf_acc = 0.0
	perf_n = 0
	perf_since = clock
	rails_t = -100
	rails_force = false
	acc = 0.0
	phase = "spawn"
	lobby_root.visible = false
	_set_game_ui(true)
	players = [null]
	for i in range(1, N + 1):
		var p := Player.new()
		if online and net_slots.has(i):
			p.nm = String(net_slots[i])
			p.col = HUMAN_COLS[(i - 1) % HUMAN_COLS.size()]
		elif not online and i == my_slot and not spectating:
			p.nm = NAMES[0]
			p.col = Color("d9ac4f")
		else:
			var nn := NAMES.size() - 1
			p.nm = NAMES[1 + (i - 2) % nn] + ("" if i - 2 < nn else " %d" % ((i - 2) / nn + 1))
			var hue := fmod(i * 0.61803, 1.0)
			if hue > 0.20 and hue < 0.36:
				hue += 0.16   # greens vanish against the grass
			p.col = Color.from_hsv(fmod(hue, 1.0), 0.44 if i % 2 == 0 else 0.56, 0.88 if i % 3 == 0 else 0.76)
		p.bot = (not net_slots.has(i)) if online else (spectating or i != my_slot)
		players.append(p)
	set_mode("attack")
	spawn_left = SPAWN_SECS
	my_start = Vector2i(-1, -1)
	pstart = []
	_plan_bot_starts()
	msg_label.text = "Click any land to choose your starting point."
	msg_panel.visible = true
	msg_token += 1
	tex = null
	fit()
	rebuild_image()
	ui()


func fit() -> void:
	var vp := get_viewport_rect().size
	zoom = minf(vp.x / W, vp.y / H)
	zoom_goal = zoom
	view_pos = (vp - Vector2(W, H) * zoom) / 2.0
	_place_sub.call_deferred()


# Loads the fixed map image (res://maps/*.png) and fills land[] and terr[] from it. No randomness.
func make_map(m: Dictionary) -> void:
	land = PackedByteArray()
	land.resize(W * H)
	land.fill(0)
	terr = PackedByteArray()
	terr.resize(W * H)
	terr.fill(T_GREEN)
	var mtex := load(String(m["img"])) as Texture2D
	if mtex == null:
		push_error("Map image missing: %s (run tools/bake_maps.py)" % String(m["img"]))
		land_count = 0
		_calc_coast()
		return
	var img := mtex.get_image()
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGB8)
	var sw := img.get_width()
	var sh := img.get_height()
	var sd := img.get_data()
	var xmap := PackedInt32Array()
	xmap.resize(W)
	for x in W:
		xmap[x] = mini(sw - 1, int((float(x) + 0.5) * float(sw) / float(W)))
	land_count = 0
	for y in H:
		var row := mini(sh - 1, int((float(y) + 0.5) * float(sh) / float(H))) * sw
		var base := y * W
		for x in W:
			var o := (row + xmap[x]) * 3
			var r: int = sd[o]
			var b: int = sd[o + 2]
			if b > r + 30:
				continue   # water
			land[base + x] = 1
			land_count += 1
			if r > 200 and b > 200:
				terr[base + x] = T_SNOW
			elif r > 180:
				terr[base + x] = T_DESERT
	_calc_coast()
	_calc_shore()


# Water distance to the nearest coast (1..12), used by the shader for the shallow-water gradient and the foam line.
func _calc_shore() -> void:
	shore = PackedByteArray()
	shore.resize(W * H)
	shore.fill(0)
	var q: Array[int] = []
	var wm1 := W - 1
	var last := W * (H - 1)
	for i in W * H:
		if land[i] == 1 and is_coast[i] == 1:
			shore[i] = 250
			var x := i % W
			var n: int
			if x > 0:
				n = i - 1
				if land[n] == 0 and shore[n] == 0:
					shore[n] = 1
					q.append(n)
			if x < wm1:
				n = i + 1
				if land[n] == 0 and shore[n] == 0:
					shore[n] = 1
					q.append(n)
			if i >= W:
				n = i - W
				if land[n] == 0 and shore[n] == 0:
					shore[n] = 1
					q.append(n)
			if i < last:
				n = i + W
				if land[n] == 0 and shore[n] == 0:
					shore[n] = 1
					q.append(n)
	var head := 0
	while head < q.size():
		var cur: int = q[head]
		head += 1
		var d: int = shore[cur]
		if d >= 12:
			continue
		var cx := cur % W
		var m: int
		if cx > 0:
			m = cur - 1
			if land[m] == 0 and shore[m] == 0:
				shore[m] = d + 1
				q.append(m)
		if cx < wm1:
			m = cur + 1
			if land[m] == 0 and shore[m] == 0:
				shore[m] = d + 1
				q.append(m)
		if cur >= W:
			m = cur - W
			if land[m] == 0 and shore[m] == 0:
				shore[m] = d + 1
				q.append(m)
		if cur < last:
			m = cur + W
			if land[m] == 0 and shore[m] == 0:
				shore[m] = d + 1
				q.append(m)


func _calc_coast() -> void:
	is_coast = PackedByteArray()
	is_coast.resize(W * H)
	is_coast.fill(0)
	for i in W * H:
		if land[i] == 0:
			continue
		var x := i % W
		if (x > 0 and land[i - 1] == 0) or (x < W - 1 and land[i + 1] == 0) \
				or (i >= W and land[i - W] == 0) or (i < W * (H - 1) and land[i + W] == 0):
			is_coast[i] = 1


func _nb(i: int) -> Array[int]:
	var r: Array[int] = []
	var x := i % W
	if x > 0: r.append(i - 1)
	if x < W - 1: r.append(i + 1)
	if i >= W: r.append(i - W)
	if i < W * (H - 1): r.append(i + W)
	return r


func _touches(i: int, o: int) -> bool:
	var x := i % W
	return (x > 0 and own[i - 1] == o) or (x < W - 1 and own[i + 1] == o) \
		or (i >= W and own[i - W] == o) or (i < W * (H - 1) and own[i + W] == o)


func label_comps() -> void:
	comp = PackedInt32Array()
	comp.resize(W * H)
	comp.fill(0)
	var cn := 0
	var stack := PackedInt32Array()
	for s in W * H:
		if land[s] == 0 or comp[s] != 0:
			continue
		cn += 1
		comp[s] = cn
		stack.clear()
		stack.append(s)
		while stack.size() > 0:
			var c: int = stack[stack.size() - 1]
			stack.resize(stack.size() - 1)
			var x := c % W
			if x > 0 and land[c - 1] == 1 and comp[c - 1] == 0:
				comp[c - 1] = cn
				stack.append(c - 1)
			if x < W - 1 and land[c + 1] == 1 and comp[c + 1] == 0:
				comp[c + 1] = cn
				stack.append(c + 1)
			if c >= W and land[c - W] == 1 and comp[c - W] == 0:
				comp[c - W] = cn
				stack.append(c - W)
			if c < W * (H - 1) and land[c + W] == 1 and comp[c + W] == 0:
				comp[c + W] = cn
				stack.append(c + W)


func owns_comp(o: int, c: int) -> bool:
	return int((players[o] as Player).comps.get(c, 0)) > 0


# ======================= rendering =======================

func build_base() -> void:
	base_data = PackedByteArray()
	base_data.resize(W * H * 4)
	var tcols: Array = []
	for tc in TERRAIN_COL:
		var c: Color = tc
		tcols.append([c.r8, c.g8, c.b8])
	for y in H:
		for x in W:
			var i := y * W + x
			if land[i] == 0:
				var dark := ((x + y) & 1) == 1
				base_data[i * 4] = 0x2c if dark else 0x1f
				base_data[i * 4 + 1] = 0x5a if dark else 0x45
				base_data[i * 4 + 2] = 0x7a if dark else 0x61
			else:
				var tcl: Array = tcols[terr[i]]
				base_data[i * 4] = tcl[0]
				base_data[i * 4 + 1] = tcl[1]
				base_data[i * 4 + 2] = tcl[2]
			base_data[i * 4 + 3] = 255


func rebuild_image() -> void:
	var t0 := _pf0()
	_rebuild_image_body()
	_pf1("map upload", t0)


func _rebuild_image_body() -> void:
	var pd := PackedByteArray()
	pd.resize(128 * 4)
	pd.fill(0)
	pd[0] = 0xc9
	pd[1] = 0xbb
	pd[2] = 0x93
	pd[3] = 255
	for k in range(1, mini(players.size(), 128)):
		var c: Color = (players[k] as Player).col
		pd[k * 4] = c.r8
		pd[k * 4 + 1] = c.g8
		pd[k * 4 + 2] = c.b8
		pd[k * 4 + 3] = 255
	var pimg := Image.create_from_data(128, 1, false, Image.FORMAT_RGBA8, pd)
	if pal_tex == null:
		pal_tex = ImageTexture.create_from_image(pimg)
	else:
		pal_tex.update(pimg)
	img = Image.create_from_data(W, H, false, Image.FORMAT_RGBA8, map_data)
	var timg := Image.create_from_data(W, H, false, Image.FORMAT_RF, time_data)
	if tex == null:
		tex = ImageTexture.create_from_image(img)
		time_tex = ImageTexture.create_from_image(timg)
		terrain.texture = tex
		var sm := terrain.material as ShaderMaterial
		sm.set_shader_parameter("map_tex", tex)
		sm.set_shader_parameter("time_tex", time_tex)
		sm.set_shader_parameter("pal_tex", pal_tex)
		var terimg := Image.create_from_data(W, H, false, Image.FORMAT_R8, terr)
		ter_tex = ImageTexture.create_from_image(terimg)
		sm.set_shader_parameter("ter_tex", ter_tex)
		if shore.size() != W * H:
			shore = PackedByteArray()
			shore.resize(W * H)
			shore.fill(0)
		shore_tex = ImageTexture.create_from_image(Image.create_from_data(W, H, false, Image.FORMAT_R8, shore))
		sm.set_shader_parameter("shore_tex", shore_tex)
		var lbytes := PackedByteArray()
		lbytes.resize(W * H)
		for li in W * H:
			lbytes[li] = 255 if land[li] == 1 else 0
		land_tex = ImageTexture.create_from_image(Image.create_from_data(W, H, false, Image.FORMAT_R8, lbytes))
		sm.set_shader_parameter("land_tex", land_tex)
		sm.set_shader_parameter("map_size", Vector2(W, H))
	else:
		tex.update(img)
		time_tex.update(timg)
	map_dirty = false


# Where to print each player's name + troops: on their biggest landmass, at the owned tile nearest its centre.
func calc_labels() -> void:
	var t0 := _pf0()
	_calc_labels_body()
	_pf1("name labels", t0)


func _calc_labels_body() -> void:
	# built from each player's border tiles only (never scans the whole map); 1/4 of the players refresh per call
	var part := tick_n / 4
	for p in range(1, N + 1):
		var pl: Player = players[p]
		if not pl.alive:
			lab_cache.erase(p)
			continue
		if (p + part) % 4 != 0 and lab_cache.has(p):
			continue
		var bset: Dictionary = border[p]
		if bset.is_empty():
			continue
		var best_c := 0
		var best_n := -1
		for c in pl.comps:
			if int(pl.comps[c]) > best_n:
				best_n = int(pl.comps[c])
				best_c = int(c)
		var sx := 0.0
		var sy := 0.0
		var n := 0
		var minx := W
		var maxx := 0
		for k in bset:
			if comp[k] != best_c:
				continue
			var x: int = k % W
			sx += x
			sy += k / W
			n += 1
			minx = mini(minx, x)
			maxx = maxi(maxx, x)
		if n == 0:
			continue
		var cx := int(sx / n)
		var cy := int(sy / n)
		var tile := cy * W + cx
		if land[tile] == 0 or own[tile] != p:
			var bd := 1e9
			for k in bset:
				if comp[k] != best_c:
					continue
				var dd := float((k % W - cx) * (k % W - cx) + (k / W - cy) * (k / W - cy))
				if dd < bd:
					bd = dd
					tile = k
		lab_cache[p] = {"o": p, "t": tile, "w": maxx - minx + 1}
	labels = lab_cache.values()
	# biggest nations first (you first of all) so that, when two names collide on screen, the important one stays
	labels.sort_custom(func(a, b):
		if int(a["o"]) == my_slot or int(b["o"]) == my_slot:
			return int(a["o"]) == my_slot
		return int(a["w"]) > int(b["w"]))


func _tile_px(i: int) -> Vector2:
	return view_pos + Vector2(i % W + 0.5, i / W + 0.5) * zoom


func _path_pos(path: Array, kv: float) -> Vector2:
	var k0 := clampi(int(floor(kv)), 0, path.size() - 1)
	var k1 := mini(k0 + 1, path.size() - 1)
	var c0: int = path[k0]
	var c1: int = path[k1]
	var p0 := Vector2(c0 % W + 0.5, c0 / W + 0.5)
	var p1 := Vector2(c1 % W + 0.5, c1 / W + 0.5)
	return p0.lerp(p1, clampf(kv - k0, 0.0, 1.0))


func _draw() -> void:
	var t0 := _pf0()
	_draw_body()
	_pf1("_draw (script)", t0)


func _draw_body() -> void:
	if phase == "lobby" or tex == null:
		return
	var t := Time.get_ticks_msec() / 600.0
	var f := clampf(acc / TICK, 0.0, 1.0)
	var font: Font = ui_font if ui_font != null else ThemeDB.fallback_font
	# Only draw what is on screen: a crowded map has hundreds of buildings, rails, ships and boats, and drawing the ones
	# nobody can see was the biggest per-frame cost.
	view_r = Rect2(Vector2(-70.0, -70.0), get_viewport_rect().size + Vector2(140.0, 140.0))
	if phase == "spawn":
		_draw_spawn(font)
	var pd0 := _pf0()
	_draw_rails()
	_pf1("draw: rails", pd0)
	pd0 = _pf0()
	# Buildings: important ones first, villages last; two icons never sit on top of each other (a 14 px grid keeps the
	# first one), and villages disappear when zoomed far out where they would only be clutter.
	var bsize := clampf(zoom * 3.0, 13.0, 44.0)
	var vis_big := PackedInt32Array()
	var vis_vil := PackedInt32Array()
	for key in bld:
		var i0: int = key
		if not view_r.has_point(_tile_px(i0)):
			continue
		if String((bld[key] as Dictionary)["t"]) == "village":
			if zoom >= 0.8:
				vis_vil.append(i0)
		else:
			vis_big.append(i0)
	var occ_px := {}
	# Crowded + zoomed out (end game): the full building art is ~20 draw calls each, so far away it is drawn as a simple coloured icon.
	var lod_b := zoom < lod_zoom and (vis_big.size() + vis_vil.size()) > 90
	for pass_n in 2:
		for i in (vis_big if pass_n == 0 else vis_vil):
			var b: Dictionary = bld[i]
			var bp := _tile_px(i)
			var gk := int(bp.x / 14.0) * 8192 + int(bp.y / 14.0)
			if occ_px.has(gk):
				continue
			occ_px[gk] = true
			if lod_b:
				_draw_bld_lod(String(b["t"]), bp, bsize, (players[b["o"]] as Player).col)
				continue
			draw_building(self, b["t"], bp, bsize, (players[b["o"]] as Player).col, 1.0)
			if (b["t"] == "port" or b["t"] == "silo") and int(b["lv"]) > 1:
				var lp := bp + Vector2(-zoom * 1.0, -zoom * 2.0)
				draw_string_outline(font, lp, "Lv%d" % int(b["lv"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, 4, Color(0, 0, 0, 0.85))
				draw_string(font, lp, "Lv%d" % int(b["lv"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color.WHITE)
	_pf1("draw: buildings", pd0)
	pd0 = _pf0()
	_draw_labels(font)
	_pf1("draw: labels", pd0)
	pd0 = _pf0()
	var lod_t := zoom < lod_zoom and trade.size() > 40
	var dot_bg := PackedVector2Array()   # LOD dots: every trade ship far away is one square in two batched draw calls (was 2 calls each)
	var dot_fg := PackedVector2Array()
	var dot_cols := PackedColorArray()
	var dot_bgc := PackedColorArray()
	for tb in trade:
		var tpath: Array = tb["path"]
		var tkv := lerpf(float(tb["pk"]), float(tb["k"]), f)
		var tcap := int(tb.get("capt", 0))
		var tdot: bool = lod_t and tcap == 0 and int(tb.get("flash", 0)) == 0
		var tpos: Vector2
		if tdot:
			var tcell: int = tpath[clampi(int(tkv + 0.5), 0, tpath.size() - 1)]
			tpos = view_pos + Vector2(float(tcell % W) + 0.5, float(tcell / W) + 0.5) * zoom
		else:
			tpos = view_pos + _path_pos(tpath, tkv) * zoom
		if not view_r.has_point(tpos):
			continue
		if tdot:
			dot_bg.append(tpos + Vector2(-3.6, 0.0))
			dot_bg.append(tpos + Vector2(3.6, 0.0))
			dot_bgc.append(Color(0.13, 0.19, 0.25, 0.9))
			dot_fg.append(tpos + Vector2(-2.5, 0.0))
			dot_fg.append(tpos + Vector2(2.5, 0.0))
			dot_cols.append((players[int(tb["o"])] as Player).col)
			continue
		tpos.y += sin(t + tkv) * zoom * 0.1
		var tsz := maxf(8.0, zoom * 1.7)
		var tcol: Color = (players[int(tb["o"])] as Player).col
		if tcap > 0:
			# being boarded: the sail colour changes from the owner's to the captor's while the ring fills (look only)
			var cprog := 1.0 - float(tcap) / float(CAPTURE_STEPS)
			var ccol: Color = (players[int(tb["cto"])] as Player).col
			tcol = tcol.lerp(ccol, cprog)
			draw_arc(tpos, tsz * 0.95, -PI * 0.5, -PI * 0.5 + TAU * cprog, 28, Color(ccol, 0.9), 2.5, true)
		_draw_paper_boat(tpos, tsz, tcol)
		var tfl := int(tb.get("flash", 0))
		if tfl > 0:
			var fk := 1.0 - float(tfl) / float(CAPTURE_FLASH_STEPS)
			draw_arc(tpos, tsz * (0.7 + 1.1 * fk), 0.0, TAU, 28, Color(1, 1, 1, 0.9 * (1.0 - fk)), 3.0, true)
	if not dot_cols.is_empty():
		draw_multiline_colors(dot_bg, dot_bgc, 7.2)   # a line as wide as it is long = a square
		draw_multiline_colors(dot_fg, dot_cols, 5.0)
	_pf1("draw: trade ships", pd0)
	pd0 = _pf0()
	var lod_s := zoom < lod_zoom and ships.size() > 10   # crowded + zoomed out: other nations' warships become simple discs
	for s in ships:
		var sp0 := Vector2(int(s["pt"]) % W + 0.5, int(s["pt"]) / W + 0.5)
		var sp1 := Vector2(int(s["t"]) % W + 0.5, int(s["t"]) / W + 0.5)
		var spos := view_pos + sp0.lerp(sp1, f) * zoom
		if not view_r.has_point(spos):
			continue
		spos.y += sin(t + sp1.x) * zoom * 0.12
		var ssz := maxf(16.0, zoom * 3.0)
		var sown := int(s["o"])
		var smine := sown == my_slot
		if lod_s and not smine and int(s["shot"]) < 0 and int(s.get("cid", 0)) == 0 and int(s["hp"]) >= int(s["mhp"]):
			draw_circle(spos, 6.5, OUT)
			draw_circle(spos, 5.0, (players[sown] as Player).col)
			draw_arc(spos, 8.5, 0.0, TAU, 12, Color(RED, 0.5), 1.5, true)
			continue
		draw_building(self, "warship", spos, ssz, (players[sown] as Player).col, 1.0)
		var shpf := clampf(float(int(s["hp"])) / float(int(s["mhp"])), 0.0, 1.0)
		if shpf < 1.0 or smine:
			_hp_bar(spos + Vector2(0.0, -ssz * 0.8), ssz, shpf)
		if not smine:
			draw_arc(spos, maxf(12.0, zoom * 2.4), 0.0, TAU, 20, Color(RED, 0.5), 1.5, true)
		if int(s["shot"]) >= 0:
			draw_line(spos, _tile_px(int(s["shot"])), Color(1.0, 0.86, 0.4, 0.9), 2.0)
		if int(s.get("cid", 0)) != 0:
			_draw_boarding(spos, ssz, int(s["cid"]))
		if smine:
			_draw_ship_orders(s, spos, font, t)
	_pf1("draw: warships", pd0)
	pd0 = _pf0()
	var lod_m := zoom < lod_zoom and mines.size() > 16   # crowded + zoomed out: every mine is one small square in two batched calls
	var mine_bg := PackedVector2Array()
	var mine_fg := PackedVector2Array()
	var mine_bgc := PackedColorArray()
	var mine_fgc := PackedColorArray()
	for mn in mines:
		if int(mn["o"]) != my_slot and not spectating:
			continue   # mines are hidden: you only ever see your own (spectators see all). Look only - enemy boats still hit them.
		var mpos := _tile_px(int(mn["t"]))
		if not view_r.has_point(mpos):
			continue
		if lod_m:
			mine_bg.append(mpos + Vector2(-3.0, 0.0))
			mine_bg.append(mpos + Vector2(3.0, 0.0))
			mine_bgc.append(Color(0.1, 0.12, 0.15, 0.9))
			mine_fg.append(mpos + Vector2(-2.0, 0.0))
			mine_fg.append(mpos + Vector2(2.0, 0.0))
			mine_fgc.append((players[int(mn["o"])] as Player).col)
			continue
		mpos.y += sin(t * 1.3 + float(int(mn["t"]) % 7)) * zoom * 0.1
		draw_building(self, "mine", mpos, maxf(12.0, zoom * 2.0), (players[int(mn["o"])] as Player).col, 0.9)
	if not mine_fgc.is_empty():
		draw_multiline_colors(mine_bg, mine_bgc, 6.0)
		draw_multiline_colors(mine_fg, mine_fgc, 4.0)
	for b in boats:
		var path: Array = b["path"]
		var kv := clampf(float(b["k"]) - float(BOAT_STEP) + float(BOAT_STEP) * acc / TICK, 0.0, float(path.size() - 1))
		var pos := view_pos + _path_pos(path, kv) * zoom
		if not view_r.has_point(pos):
			continue
		# faint wake: dots on the real route behind the boat (fewer when many boats sail at once)
		var ndots := 4 if boats.size() <= 10 else 2
		for j in range(1, ndots + 1):
			var wp: Vector2 = view_pos + _path_pos(path, maxf(0.0, kv - float(j) * 0.9)) * zoom
			draw_circle(wp, maxf(1.5, zoom * 0.45) * (1.0 - 0.12 * float(j)), Color(1, 1, 1, 0.30 * (1.0 - float(j) / float(ndots + 1))))
		pos.y += sin(t + kv) * zoom * 0.15
		_draw_paper_boat(pos, maxf(12.0, zoom * 2.8), (players[b["o"]] as Player).col)
		var bhpf := clampf(float(int(b.get("hp", BOAT_HP))) / float(BOAT_HP), 0.0, 1.0)
		if bhpf < 1.0:
			_hp_bar(pos + Vector2(0.0, -maxf(12.0, zoom * 2.8) * 0.75), maxf(12.0, zoom * 2.8), bhpf)
		if int(b["o"]) != my_slot and not (players[my_slot] as Player).allies.has(int(b["o"])):
			draw_arc(pos, maxf(10.0, zoom * 2.2), 0.0, TAU, 20, Color(RED, 0.55), 1.5, true)
		if int(b["o"]) == my_slot:
			_tag(font, pos + Vector2(0, -maxf(12.0, zoom * 2.8) * 0.9), "", str(int(b["troops"])), BLUE)
	_pf1("draw: mines+boats", pd0)
	pd0 = _pf0()
	var tag_pts: Array[Vector2] = []   # where tags were drawn this frame: two tags never overlap (an attack and its counter share one front)
	for a in attacks:
		if (int(a["o"]) == my_slot or int(a["t"]) == my_slot) and a.has("pos"):
			var tgt_pos: Vector2 = a["pos"]
			var dp: Vector2 = a.get("dp", tgt_pos)
			dp = dp.lerp(tgt_pos, 1.0 - exp(-7.0 * get_process_delta_time()))
			a["dp"] = dp
			var ap: Vector2 = view_pos + dp * zoom
			if not view_r.has_point(ap):
				continue
			var mine := int(a["o"]) == my_slot
			# soft breathing ring on the front of your attacks / attacks against you (only these two kinds are ever drawn)
			var br := 0.5 + 0.5 * sin(t * 3.0 + float(int(a["id"])))
			draw_arc(ap, clampf(zoom * 2.2, 9.0, 22.0) * (0.9 + 0.15 * br), 0.0, TAU, 24, Color(BLUE if mine else RED, 0.16 + 0.22 * br), 2.0, true)
			var sname: String = STAGE_NAMES[clampi(int(a.get("stage", 0)), 0, 2)]
			var tgp := ap
			for _n in 4:
				var overlap := false
				for q in tag_pts:
					if absf(q.x - tgp.x) < 78.0 and absf(q.y - tgp.y) < 32.0:
						overlap = true
						break
				if not overlap:
					break
				tgp.y += 32.0
			tag_pts.append(tgp)
			if mine:
				_tag(font, tgp, sname, _fmt(float(a["troops"]) / 10.0), BLUE)
			else:
				_tag(font, tgp, _aname(int(a["o"])), _fmt(float(a["troops"]) / 10.0), RED)
	_pf1("draw: attack tags", pd0)
	pd0 = _pf0()
	_draw_ship_cmd(t)
	_draw_preview(t)
	_draw_fx()
	_draw_nukes()
	_pf1("draw: fx+preview", pd0)
	for fl in floats:
		var p: Vector2 = view_pos + (fl["p"] as Vector2) * zoom
		p.y -= float(fl["age"]) * 26.0
		var al := clampf(1.6 - float(fl["age"]), 0.0, 1.0)
		draw_string_outline(font, p, fl["t"], HORIZONTAL_ALIGNMENT_LEFT, -1, 18, 4, Color(0, 0, 0, 0.8 * al))
		var fc: Color = fl["c"]
		draw_string(font, p, fl["t"], HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(fc, al))


# Warship boarding a trade ship (client look only): muzzle flash + smoke at the gun, sparks on the trade ship. No lines.
func _draw_boarding(spos: Vector2, ssz: float, tid: int) -> void:
	var tb := _trade_by_id(tid)
	if tb.is_empty():
		return
	var f := clampf(acc / TICK, 0.0, 1.0)
	var tpath: Array = tb["path"]
	var bpos := view_pos + _path_pos(tpath, lerpf(float(tb["pk"]), float(tb["k"]), f)) * zoom
	var gun := spos + Vector2(ssz * 0.64, -ssz * 0.2)
	var ph := fmod(clock * 4.0, 1.0)   # one volley every 0.25 s
	if ph < 0.3:
		var fr := 1.0 - ph / 0.3
		for k in 4:
			var ang := float(k) * PI * 0.5 + PI * 0.25
			draw_line(gun, gun + Vector2(cos(ang), sin(ang)) * ssz * 0.22 * fr, Color(1.0, 0.9, 0.5, 0.95 * fr), 2.0)
	draw_arc(gun + Vector2(ph * ssz * 0.15, -ph * ssz * 0.3), ssz * (0.08 + 0.14 * ph), 0.0, TAU, 12, Color(0.85, 0.87, 0.9, 0.6 * (1.0 - ph)), 2.0, true)
	draw_arc(bpos, ssz * (0.12 + 0.3 * ph), 0.0, TAU, 14, Color(1.0, 0.85, 0.4, 0.8 * (1.0 - ph)), 2.0, true)


# Conquest sparks. Look only: reads no random numbers and changes no simulation state (positions come from the tile number).
# Only a real nation-against-nation capture calls this, about one in five of them makes a burst, and at most SPARK_PER_FRAME bursts
# are made per rendered frame, so a fast-forwarded match cannot flood the screen.
func _fx_spark(i: int, o: int) -> void:
	if sp_budget <= 0 or i % 5 != tick_n % 5:
		return
	sp_budget -= 1
	var h := (i * 2654435761) & 0xFFFF
	var base := float(h) / 65535.0 * TAU
	var col: Color = (players[o] as Player).col.lightened(0.45)
	var wp := Vector2(i % W + 0.5, i / W + 0.5)
	for k in 3:
		var a := base + float(k) * 2.09
		sp_pos[sp_head] = wp
		sp_vel[sp_head] = Vector2(cos(a), sin(a)) * (16.0 + float((h >> (k * 3)) & 7) * 3.0)
		sp_age[sp_head] = 0.0
		sp_col[sp_head] = col
		sp_head = (sp_head + 1) % SPARK_MAX


# Short expanding ring at a map tile. Only called for real events (attack launched, stage reached, building built / captured).
# Capped at 24 live rings; positions are world tiles so a ring stays on its territory while you pan or zoom.
func _fx_ring(tile_pos: Vector2, col: Color, life: float = 0.6, r_tiles: float = 3.0) -> void:
	if phase != "play":
		return
	if fx.size() >= 24:
		fx.pop_front()
	fx.append({"p": tile_pos, "col": col, "age": 0.0, "life": life, "r": r_tiles})


# Targeting preview for the selected bomb: inner circle = destroyed, outer circle = random losses.
func _draw_nuke_preview() -> void:
	var i := _hover_tile()
	if i < 0:
		return
	var why := validate(my_slot, {"slot": my_slot, "type": "nuke", "kind": mode, "tile": i})
	var ok := why == ""
	var pos := _tile_px(i)
	var rin := _bomb_inner(mode)
	var rout := _bomb_outer(mode)
	draw_circle(pos, rout * zoom, Color(1.0, 0.55, 0.1, 0.10 if ok else 0.05))
	draw_arc(pos, rout * zoom, 0.0, TAU, 64, Color(1.0, 0.55, 0.1, 0.8 if ok else 0.35), 2.0)
	draw_circle(pos, rin * zoom, Color(1.0, 0.15, 0.1, 0.22 if ok else 0.10))
	draw_arc(pos, rin * zoom, 0.0, TAU, 48, Color(1.0, 0.2, 0.15, 0.9 if ok else 0.4), 2.5)
	var font: Font = ui_font if ui_font != null else ThemeDB.fallback_font
	var mega_hint := "Click to launch: about 85%% of %s's land is destroyed   (Shift = keep firing, Esc = cancel)" % _aname(int(own[i])) if (mode == "mega" and ok) else "Click to launch   (Shift = keep firing, Esc = cancel)"
	_tip(font, "%s  -  %s gold" % [BUILD_LABEL[mode], _fmt(price(my_slot, mode))], mega_hint if ok else why, Color("ffb347") if ok else Color("ff5b5b"), ok)


# Bombs in flight (arc + trail), a warning ring on the target, and the blast flashes. Reads sim state, never changes it.
func _draw_nukes() -> void:
	var fr := clampf(atk_acc / ATK_TICK, 0.0, 1.0)
	for nk in nukes:
		var pa := _wpos(int(nk["a"])) + Vector2(0.5, 0.5)
		var pb := _wpos(int(nk["b"])) + Vector2(0.5, 0.5)
		var u := clampf((float(int(nk["k"])) + fr) / float(int(nk["n"])), 0.0, 1.0)
		var arc_h := minf(pa.distance_to(pb) * 0.18, 18.0)
		var tp := view_pos + pb * zoom
		var pulse := 0.5 + 0.5 * sin(clock * 6.0)
		var nrout := _bomb_outer(String(nk["kind"]))
		var nrin := _bomb_inner(String(nk["kind"]))
		draw_arc(tp, nrout * zoom, 0.0, TAU, 48, Color(1.0, 0.3, 0.2, 0.18 + 0.20 * pulse), 1.5)
		draw_arc(tp, nrin * zoom, 0.0, TAU, 32, Color(1.0, 0.2, 0.15, 0.35 + 0.30 * pulse), 2.0)
		var prev := Vector2.ZERO
		for q in 13:
			var uu := maxf(0.0, u - 0.012 * float(12 - q))
			var gp := pa.lerp(pb, uu)
			var sp := view_pos + gp * zoom - Vector2(0.0, sin(uu * PI) * arc_h * zoom)
			if q > 0:
				draw_line(prev, sp, Color(1.0, 0.85, 0.5, 0.08 + 0.05 * float(q)), maxf(1.5, zoom * 0.25))
			prev = sp
		var head := view_pos + pa.lerp(pb, u) * zoom - Vector2(0.0, sin(u * PI) * arc_h * zoom)
		draw_circle(head, maxf(4.0, zoom * 0.7), Color(1.0, 0.95, 0.7))
		draw_arc(head, maxf(5.0, zoom * 0.9), 0.0, TAU, 16, (players[int(nk["o"])] as Player).col, 2.0)
	var live: Array = []
	for e in blasts:
		var age := clock - float(e["t0"])
		var life := 1.8 if bool(e["big"]) else 0.6
		if age > life:
			continue
		live.append(e)
		var k := clampf(age / life, 0.0, 1.0)
		var bp: Vector2 = view_pos + (e["p"] as Vector2) * zoom
		var rmax := (float(e.get("r", 10.0)) if bool(e["big"]) else 2.5) * zoom
		draw_circle(bp, rmax * (0.3 + 0.7 * (1.0 - pow(1.0 - k, 3.0))) * (1.0 if bool(e["big"]) else 0.6), Color(1.0, 0.7, 0.25, 0.55 * (1.0 - k)))
		draw_arc(bp, rmax * (0.2 + 0.8 * k), 0.0, TAU, 48, Color(1.0, 1.0, 0.85, 0.9 * (1.0 - k)), maxf(2.0, zoom * 0.5))
		if bool(e["big"]):
			draw_circle(bp, float(e.get("ri", 5.0)) * zoom * (1.0 - k * 0.5), Color(1.0, 1.0, 0.9, 0.5 * (1.0 - k) * (1.0 - k)))
	blasts = live


func _draw_fx() -> void:
	for sk in SPARK_MAX:
		var sa := sp_age[sk]
		if sa >= SPARK_LIFE:
			continue
		var sk_k := sa / SPARK_LIFE
		var spp: Vector2 = view_pos + sp_pos[sk] * zoom + sp_vel[sk] * (sa * (1.0 - 0.5 * sk_k))
		if not view_r.has_point(spp):
			continue
		var sal := (1.0 - sk_k) * (1.0 - sk_k)
		var sc: Color = sp_col[sk]
		draw_circle(spp, 2.6 * (1.0 - 0.5 * sk_k), Color(sc, 0.75 * sal))
		draw_circle(spp, 1.1, Color(1.0, 1.0, 1.0, 0.9 * sal))
	for e in fx:
		var ep: Vector2 = view_pos + (e["p"] as Vector2) * zoom
		if not view_r.has_point(ep):
			continue
		var k := clampf(float(e["age"]) / float(e["life"]), 0.0, 1.0)
		var grow := 1.0 - pow(1.0 - k, 3.0)
		var r := clampf(zoom * float(e["r"]), 10.0, 46.0) * (0.35 + 0.65 * grow)
		var al := (1.0 - k) * (1.0 - k)
		var ec: Color = e["col"]
		draw_circle(ep, r * 0.6, Color(ec, 0.14 * al))
		draw_arc(ep, r, 0.0, TAU, 32, Color(ec, 0.85 * al), 3.0 - 1.8 * k, true)


# Premium two-line tag: small caps title + big troop number, on a rounded glowing card.
# Small floating text (no box): a tiny caps title over the troop count, thinly outlined so it reads on any colour.
func _tag(font: Font, center: Vector2, title: String, sub: String, col: Color) -> void:
	var s2 := font.get_string_size(sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 13)
	var p2 := center + Vector2(-s2.x / 2.0, 6.0)
	if title != "":
		var s1 := font.get_string_size(title.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, 9)
		var p1 := center + Vector2(-s1.x / 2.0, -4.0)
		draw_string_outline(font, p1, title.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, 9, 3, Color(0, 0, 0, 0.45))
		draw_string(font, p1, title.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(col, 0.95))
	draw_string_outline(font, p2, sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, 4, Color(0, 0, 0, 0.5))
	draw_string(font, p2, sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, col.lightened(0.45))


# Warship waiting for an order: a crosshair on the cursor (green = water to sail to, orange = enemy to attack, red = land).
func _draw_ship_cmd(t: float) -> void:
	if sel_ship == 0 or phase != "play":
		return
	if _ship_by_id(sel_ship).is_empty():
		sel_ship = 0
		return
	var i := _hover_tile()
	if i < 0:
		return
	var font: Font = ui_font if ui_font != null else ThemeDB.fallback_font
	var eu := _enemy_unit_at(i)
	var col := Color("45e06a") if land[i] == 0 else Color("ff5b5b")
	if eu != 0:
		col = Color("ff9f43")
	var cp := _tile_px(i)
	var r := 9.0
	draw_arc(cp, r, 0.0, TAU, 24, col, 2.0, true)
	draw_line(cp + Vector2(-r - 6.0, 0.0), cp + Vector2(-r + 3.0, 0.0), col, 2.0)
	draw_line(cp + Vector2(r + 6.0, 0.0), cp + Vector2(r - 3.0, 0.0), col, 2.0)
	draw_line(cp + Vector2(0.0, -r - 6.0), cp + Vector2(0.0, -r + 3.0), col, 2.0)
	draw_line(cp + Vector2(0.0, r + 6.0), cp + Vector2(0.0, r - 3.0), col, 2.0)
	if eu != 0:
		_tip(font, "Attack", "Click: your warship sails out to intercept it", col, true)
	elif land[i] == 1:
		_tip(font, "Land", "Pick open water (or an enemy boat / warship)", col, false)
	else:
		_tip(font, "Move", "Click: sail here  -  any water on the map", col, true)


func _hp_bar(c: Vector2, w: float, f: float) -> void:
	var r := Rect2(c - Vector2(w * 0.5, 2.0), Vector2(w, 4.0))
	draw_rect(r, Color(0, 0, 0, 0.65))
	draw_rect(Rect2(r.position, Vector2(w * f, 4.0)), Color("45e06a") if f > 0.5 else (Color("ffcc4d") if f > 0.25 else Color("ff5b5b")))


func _ship_status(s: Dictionary) -> String:
	if int(s.get("cid", 0)) != 0:
		return "Boarding"
	if int(s["tgt"]) != 0:
		return "Intercepting" if bool(s["auto"]) else "Attacking"
	if int(s.get("pi", 0)) < (s["path"] as Array).size() - 1:
		return "Moving"
	return "On station"


# Route, destination and target of one of MY warships (all of them are outlined faintly, the selected one fully with an info tag).
func _draw_ship_orders(s: Dictionary, spos: Vector2, font: Font, t: float) -> void:
	var sel := sel_ship != 0 and int(s["id"]) == sel_ship
	var a := 0.95 if sel else 0.4
	var path: Array = s["path"]
	var spi := int(s["pi"])
	if spi < path.size() - 1:
		var pts := PackedVector2Array([spos])
		var j := spi + 1
		while j < path.size() - 1:
			pts.append(_tile_px(int(path[j])))
			j += 4
		var endp := _tile_px(int(path[path.size() - 1]))
		pts.append(endp)
		draw_polyline(pts, Color(ACC, a * 0.7), 2.0 if sel else 1.2, true)
		if int(s["tgt"]) == 0:
			draw_arc(endp, maxf(5.0, zoom * 0.9), 0.0, TAU, 16, Color(ACC, a), 2.0, true)
	if int(s["tgt"]) != 0:
		var tt := _unit_tile(int(s["tgt"]))
		if tt >= 0:
			var tp := _tile_px(tt)
			draw_line(spos, tp, Color(1.0, 0.62, 0.26, a * 0.8), 1.5)
			draw_arc(tp, maxf(8.0, zoom * 1.6), 0.0, TAU, 20, Color(1.0, 0.62, 0.26, a), 2.0, true)
	if sel:
		draw_arc(spos, maxf(14.0, zoom * 2.6), 0.0, TAU, 28, Color(ACC, 0.6 + 0.4 * sin(t * 4.0)), 2.5, true)
		_tag(font, spos + Vector2(0.0, -maxf(16.0, zoom * 3.0) * 1.15), "Warship", "HP %d/%d   %s" % [int(s["hp"]), int(s["mhp"]), _ship_status(s)], ACC)


func _aname(t: int) -> String:
	if t <= 0:
		return "wilderness"
	return (players[t] as Player).nm


func _pill(font: Font, center: Vector2, text: String, col: Color) -> void:
	var fs := 13
	var sz := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
	var r := Rect2(center - Vector2(sz.x / 2.0 + 6.0, 10.0), Vector2(sz.x + 12.0, 20.0))
	draw_rect(r, Color(0.03, 0.08, 0.12, 0.88))
	draw_rect(r, col, false, 1.5)
	draw_string(font, center + Vector2(-sz.x / 2.0, 5.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)


# Name + troop count printed on every nation's land (hidden when the nation is too small on screen).
func _draw_labels(font: Font) -> void:
	var nfont: Font = ui_title_font if ui_title_font != null else font   # nation names: Baskerville, like an atlas
	var vfont: Font = ui_bold_font if ui_bold_font != null else font     # troop numbers
	var taken: Array[Rect2] = []
	var vps := get_viewport_rect().size
	var panels: Array[Rect2] = []
	for pn in [hud, lb_panel, ctl, zoom_panel, atk_panel, sub_panel, nuke_panel]:
		if pn != null and (pn as Control).visible:
			panels.append((pn as Control).get_global_rect().grow(4.0))
	if str_sz.size() > 800:
		str_sz.clear()
	for lb in labels:
		var o: int = lb["o"]
		var pl: Player = players[o]
		if not pl.alive:
			continue
		var fs := int(clampf(float(lb["w"]) * zoom * 0.12, 0.0, 28.0))
		if fs < 9:
			continue
		var fs2 := maxi(8, int(fs * 0.82))
		var c := _tile_px(int(lb["t"]))
		if not view_r.has_point(c):
			continue
		var trs := _fmt(pl.troops / 10.0)
		var k1 := "%s|%d" % [pl.nm, fs]
		if not str_sz.has(k1):
			str_sz[k1] = nfont.get_string_size(pl.nm, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
		var k2 := "%s|%d" % [trs, fs2]
		if not str_sz.has(k2):
			str_sz[k2] = vfont.get_string_size(trs, HORIZONTAL_ALIGNMENT_LEFT, -1, fs2)
		var s1: Vector2 = str_sz[k1]
		var s2: Vector2 = str_sz[k2]
		# a label whose centre is on screen is nudged so the whole text stays inside the window
		var hw := maxf(s1.x, s2.x) / 2.0 + 6.0
		if c.x > 0.0 and c.x < vps.x and c.y > 0.0 and c.y < vps.y:
			c.x = clampf(c.x, hw, maxf(hw, vps.x - hw))
			c.y = clampf(c.y, float(fs) + 6.0, maxf(float(fs) + 6.0, vps.y - float(fs2) - 10.0))
		# skip a label that would sit on top of a more important one (you and the biggest nations are drawn first)
		var box := Rect2(c + Vector2(-maxf(s1.x, s2.x) / 2.0 - 3.0, -float(fs) - 1.0), Vector2(maxf(s1.x, s2.x) + 6.0, float(fs + fs2) + 8.0))
		var hit := false
		for r in taken:
			if r.intersects(box):
				hit = true
				break
		if hit and o != my_slot:
			continue
		if o != my_slot:
			var under_ui := false
			for pr in panels:
				if pr.intersects(box):
					under_ui = true
					break
			if under_ui:
				continue
		taken.append(box)
		var p1 := c + Vector2(-s1.x / 2.0, -2.0)
		var p2 := c + Vector2(-s2.x / 2.0, fs2 + 2.0)
		var ncol := ACC if o == my_slot else (UI_GOOD.lightened(0.2) if (players[my_slot] as Player).allies.has(o) else Color("f7efd6"))
		# thin dark-ink outline + soft shadow keeps the text readable on every nation colour
		draw_string_outline(nfont, p1 + Vector2(0, 1), pl.nm, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 6, Color(0, 0, 0, 0.35))
		draw_string_outline(nfont, p1, pl.nm, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 4, Color(0.07, 0.05, 0.03, 0.92))
		draw_string(nfont, p1, pl.nm, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, ncol)
		draw_string_outline(vfont, p2, trs, HORIZONTAL_ALIGNMENT_LEFT, -1, fs2, 4, Color(0.07, 0.05, 0.03, 0.92))
		draw_string(vfont, p2, trs, HORIZONTAL_ALIGNMENT_LEFT, -1, fs2, Color("efe3c6"))


func _draw_rails() -> void:
	var f := clampf(acc / TICK, 0.0, 1.0)
	for r in rails:
		var pa := _tile_px(r["a"])
		var pb := _tile_px(r["b"])
		if not view_r.intersects(Rect2(pa, Vector2.ZERO).expand(pb)):
			continue
		var xr: bool = r.get("x", false)
		draw_line(pa, pb, Color(0.17, 0.15, 0.13, 0.9), maxf(2.0, zoom * 0.55))
		if xr:
			draw_dashed_line(pa, pb, ACC, maxf(1.5, zoom * 0.3), maxf(5.0, zoom * 1.4))
		else:
			draw_line(pa, pb, Color("b9b2a4"), maxf(1.0, zoom * 0.2))
		var u := lerpf(float(r["pu"]), float(r["u"]), f)
		var tp := pa.lerp(pb, u)
		var sz := maxf(4.0, zoom * 1.0)
		var col: Color = Color("fff1c4") if xr else (players[r["o"]] as Player).col
		draw_rect(Rect2(tp - Vector2(sz * 0.5, sz * 0.35), Vector2(sz, sz * 0.7)), col)
		draw_rect(Rect2(tp - Vector2(sz * 0.5, sz * 0.35), Vector2(sz, sz * 0.7)), OUT, false, 1.0)


# ---------- building art (works on any CanvasItem so the UI cards can reuse it) ----------

func _k(c: Color, a: float) -> Color:
	return Color(c.r, c.g, c.b, c.a * a)


func _shadow(ci: CanvasItem, pos: Vector2, s: float, a: float) -> void:
	ci.draw_set_transform(pos + Vector2(0, s * 0.36), 0.0, Vector2(1, 0.22))
	ci.draw_circle(Vector2.ZERO, s * 0.55, Color(0, 0, 0, 0.25 * a))
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _hut(ci: CanvasItem, o: Vector2, cx: float, cy: float, w: float, h: float, rc: Color, lw: float, a: float) -> void:
	var wall := Rect2(o.x + cx - w / 2.0, o.y + cy - h * 0.15, w, h * 0.65)
	ci.draw_rect(wall, _k(Color("f3e6c8"), a))
	ci.draw_rect(wall, _k(OUT, a), false, lw)
	var roof := PackedVector2Array([
		o + Vector2(cx - w * 0.62, cy - h * 0.15),
		o + Vector2(cx, cy - h * 0.85),
		o + Vector2(cx + w * 0.62, cy - h * 0.15)])
	ci.draw_colored_polygon(roof, _k(rc, a))
	roof.append(roof[0])
	ci.draw_polyline(roof, _k(OUT, a), lw)
	ci.draw_rect(Rect2(o.x + cx - w * 0.1, o.y + cy + h * 0.18, w * 0.2, h * 0.32), _k(Color("7a4a24"), a))


func draw_building(ci: CanvasItem, kind: String, pos: Vector2, s: float, c: Color, a: float = 1.0) -> void:
	match kind:
		"village": _draw_village(ci, pos, s, c, a)
		"city": _draw_city(ci, pos, s, c, a)
		"duchy": _draw_duchy(ci, pos, s, c, a)
		"station": _draw_station(ci, pos, s, c, a)
		"port": _draw_port(ci, pos, s, c, a)
		"warship": _draw_warship(ci, pos, s, c, a)
		"mine": _draw_mine(ci, pos, s, c, a)
		"silo": _draw_silo(ci, pos, s, c, a)
		"sam": _draw_sam(ci, pos, s, c, a)
		"atom": _draw_atom(ci, pos, s, c, a)
		"nuke": _draw_atom(ci, pos, s, c, a, Color("ee6a3a"), 1)
		"mega": _draw_atom(ci, pos, s, c, a, Color("d8353f"), 2)


func _draw_village(ci: CanvasItem, pos: Vector2, s: float, c: Color, a: float) -> void:
	var lw := maxf(1.0, s * 0.045)
	_shadow(ci, pos, s, a)
	_hut(ci, pos, -s * 0.18, 0.0, s * 0.5, s * 0.6, c, lw, a)
	_hut(ci, pos, s * 0.28, s * 0.1, s * 0.34, s * 0.42, c, lw, a)


func _draw_city(ci: CanvasItem, pos: Vector2, s: float, c: Color, a: float) -> void:
	var lw := maxf(1.0, s * 0.04)
	_shadow(ci, pos, s * 1.1, a)
	_hut(ci, pos, -s * 0.36, s * 0.12, s * 0.3, s * 0.38, c, lw, a)
	_hut(ci, pos, s * 0.36, s * 0.14, s * 0.28, s * 0.36, c, lw, a)
	var keep := Rect2(pos.x - s * 0.17, pos.y - s * 0.34, s * 0.34, s * 0.62)
	ci.draw_rect(keep, _k(Color("e4dccb"), a))
	ci.draw_rect(keep, _k(OUT, a), false, lw)
	for k in 3:
		var bx := keep.position.x + keep.size.x * (0.04 + k * 0.34)
		ci.draw_rect(Rect2(bx, keep.position.y - s * 0.07, keep.size.x * 0.26, s * 0.07), _k(Color("e4dccb"), a))
		ci.draw_rect(Rect2(bx, keep.position.y - s * 0.07, keep.size.x * 0.26, s * 0.07), _k(OUT, a), false, lw)
	ci.draw_rect(Rect2(pos.x - s * 0.05, pos.y + s * 0.12, s * 0.1, s * 0.16), _k(Color("7a4a24"), a))
	ci.draw_rect(Rect2(pos.x - s * 0.04, pos.y - s * 0.2, s * 0.08, s * 0.1), _k(Color("33485a"), a))
	var top := pos + Vector2(0, -s * 0.41)
	ci.draw_line(top, top + Vector2(0, -s * 0.3), _k(OUT, a), lw)
	ci.draw_colored_polygon(PackedVector2Array([
		top + Vector2(0, -s * 0.3), top + Vector2(s * 0.22, -s * 0.23), top + Vector2(0, -s * 0.16)]), _k(c, a))


func _draw_duchy(ci: CanvasItem, pos: Vector2, s: float, c: Color, a: float) -> void:
	var lw := maxf(1.0, s * 0.04)
	_shadow(ci, pos, s * 1.25, a)
	var wall := Rect2(pos.x - s * 0.5, pos.y - s * 0.02, s * 1.0, s * 0.3)
	ci.draw_rect(wall, _k(Color("d9d1bd"), a))
	ci.draw_rect(wall, _k(OUT, a), false, lw)
	for k in 6:
		var cx := wall.position.x + k * wall.size.x / 6.0 + wall.size.x * 0.02
		ci.draw_rect(Rect2(cx, wall.position.y - s * 0.06, wall.size.x / 6.0 * 0.6, s * 0.06), _k(Color("d9d1bd"), a))
		ci.draw_rect(Rect2(cx, wall.position.y - s * 0.06, wall.size.x / 6.0 * 0.6, s * 0.06), _k(OUT, a), false, lw)
	for sx in [-1.0, 1.0]:
		var tw := Rect2(pos.x + sx * s * 0.42 - s * 0.09, pos.y - s * 0.34, s * 0.18, s * 0.62)
		ci.draw_rect(tw, _k(Color("e4dccb"), a))
		ci.draw_rect(tw, _k(OUT, a), false, lw)
		var roof := PackedVector2Array([
			Vector2(tw.position.x - s * 0.03, tw.position.y),
			Vector2(tw.position.x + tw.size.x * 0.5, tw.position.y - s * 0.18),
			Vector2(tw.end.x + s * 0.03, tw.position.y)])
		ci.draw_colored_polygon(roof, _k(c, a))
		roof.append(roof[0])
		ci.draw_polyline(roof, _k(OUT, a), lw)
	var keep := Rect2(pos.x - s * 0.2, pos.y - s * 0.5, s * 0.4, s * 0.78)
	ci.draw_rect(keep, _k(Color("ece5d4"), a))
	ci.draw_rect(keep, _k(OUT, a), false, lw)
	var kr := PackedVector2Array([
		Vector2(keep.position.x - s * 0.04, keep.position.y),
		Vector2(pos.x, keep.position.y - s * 0.24),
		Vector2(keep.end.x + s * 0.04, keep.position.y)])
	ci.draw_colored_polygon(kr, _k(c, a))
	kr.append(kr[0])
	ci.draw_polyline(kr, _k(OUT, a), lw)
	var top := Vector2(pos.x, keep.position.y - s * 0.24)
	ci.draw_line(top, top + Vector2(0, -s * 0.22), _k(OUT, a), lw)
	ci.draw_colored_polygon(PackedVector2Array([
		top + Vector2(0, -s * 0.22), top + Vector2(s * 0.2, -s * 0.15), top + Vector2(0, -s * 0.08)]), _k(c, a))
	ci.draw_rect(Rect2(pos.x - s * 0.07, pos.y + s * 0.1, s * 0.14, s * 0.18), _k(Color("7a4a24"), a))
	ci.draw_rect(Rect2(pos.x - s * 0.04, pos.y - s * 0.22, s * 0.08, s * 0.12), _k(Color("33485a"), a))


func _draw_station(ci: CanvasItem, pos: Vector2, s: float, c: Color, a: float) -> void:
	var lw := maxf(1.0, s * 0.04)
	_shadow(ci, pos, s, a)
	var rail_y := pos.y + s * 0.34
	for dy in [0.0, s * 0.07]:
		ci.draw_line(Vector2(pos.x - s * 0.5, rail_y + dy), Vector2(pos.x + s * 0.5, rail_y + dy), _k(Color("6f7378"), a), lw)
	for k in 6:
		var tx := pos.x - s * 0.45 + k * s * 0.18
		ci.draw_line(Vector2(tx, rail_y - s * 0.03), Vector2(tx, rail_y + s * 0.1), _k(Color("5a4026"), a), lw)
	var plat := Rect2(pos.x - s * 0.44, pos.y + s * 0.14, s * 0.88, s * 0.14)
	ci.draw_rect(plat, _k(Color("a7a9ab"), a))
	ci.draw_rect(plat, _k(OUT, a), false, lw)
	var body := Rect2(pos.x - s * 0.3, pos.y - s * 0.16, s * 0.6, s * 0.3)
	ci.draw_rect(body, _k(Color("ece6d6"), a))
	ci.draw_rect(body, _k(OUT, a), false, lw)
	var roof := Rect2(pos.x - s * 0.37, pos.y - s * 0.26, s * 0.74, s * 0.11)
	ci.draw_rect(roof, _k(c, a))
	ci.draw_rect(roof, _k(OUT, a), false, lw)
	ci.draw_circle(Vector2(pos.x, pos.y - s * 0.03), s * 0.07, _k(Color.WHITE, a))
	ci.draw_arc(Vector2(pos.x, pos.y - s * 0.03), s * 0.07, 0.0, TAU, 14, _k(OUT, a), lw)
	ci.draw_rect(Rect2(pos.x - s * 0.22, pos.y - s * 0.04, s * 0.1, s * 0.16), _k(Color("7a4a24"), a))
	ci.draw_rect(Rect2(pos.x + s * 0.12, pos.y - s * 0.04, s * 0.1, s * 0.16), _k(Color("7a4a24"), a))


func _draw_port(ci: CanvasItem, pos: Vector2, s: float, c: Color, a: float) -> void:
	var lw := maxf(1.0, s * 0.04)
	ci.draw_arc(Vector2(pos.x + s * 0.1, pos.y + s * 0.42), s * 0.36, PI * 1.1, PI * 1.9, 12, _k(Color(1, 1, 1, 0.55), a), lw)
	var pier := Rect2(pos.x - s * 0.46, pos.y + s * 0.12, s * 0.92, s * 0.15)
	ci.draw_rect(pier, _k(Color("9a6a36"), a))
	ci.draw_rect(pier, _k(OUT, a), false, lw)
	for k in 4:
		var px := pier.position.x + s * 0.06 + k * s * 0.27
		ci.draw_rect(Rect2(px, pier.position.y + pier.size.y, s * 0.06, s * 0.14), _k(Color("5a4026"), a))
	var shed := Rect2(pos.x - s * 0.44, pos.y - s * 0.12, s * 0.34, s * 0.24)
	ci.draw_rect(shed, _k(Color("e9dfc6"), a))
	ci.draw_rect(shed, _k(OUT, a), false, lw)
	ci.draw_colored_polygon(PackedVector2Array([
		Vector2(shed.position.x - s * 0.04, shed.position.y),
		Vector2(shed.position.x + shed.size.x * 0.5, shed.position.y - s * 0.14),
		Vector2(shed.end.x + s * 0.04, shed.position.y)]), _k(c, a))
	var mast := Vector2(pos.x + s * 0.1, pos.y + s * 0.12)
	ci.draw_line(mast, mast + Vector2(0, -s * 0.5), _k(OUT, a), lw * 1.6)
	ci.draw_line(mast + Vector2(0, -s * 0.5), mast + Vector2(s * 0.3, -s * 0.4), _k(OUT, a), lw * 1.4)
	ci.draw_line(mast + Vector2(s * 0.3, -s * 0.4), mast + Vector2(s * 0.3, -s * 0.2), _k(OUT, a), lw)
	var crate := Rect2(mast.x + s * 0.22, mast.y - s * 0.2, s * 0.16, s * 0.12)
	ci.draw_rect(crate, _k(Color("c9a24b"), a))
	ci.draw_rect(crate, _k(OUT, a), false, lw)


func _draw_warship(ci: CanvasItem, pos: Vector2, s: float, c: Color, a: float) -> void:
	var lw := maxf(1.0, s * 0.045)
	var ink := Color("2f3a45")
	ci.draw_set_transform(pos + Vector2(0, s * 0.3), 0.0, Vector2(1, 0.2))
	ci.draw_arc(Vector2.ZERO, s * 0.6, 0.0, TAU, 24, _k(Color(1, 1, 1, 0.5), a), lw)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var hull := PackedVector2Array([
		pos + Vector2(-s * 0.62, -s * 0.05), pos + Vector2(s * 0.7, -s * 0.05),
		pos + Vector2(s * 0.45, s * 0.28), pos + Vector2(-s * 0.45, s * 0.28)])
	ci.draw_colored_polygon(hull, _k(Color("7b8794"), a))
	hull.append(hull[0])
	ci.draw_polyline(hull, _k(ink, a), lw)
	var cab := Rect2(pos.x - s * 0.22, pos.y - s * 0.3, s * 0.36, s * 0.25)
	ci.draw_rect(cab, _k(Color("c3ccd4"), a))
	ci.draw_rect(cab, _k(ink, a), false, lw)
	ci.draw_line(pos + Vector2(s * 0.3, -s * 0.1), pos + Vector2(s * 0.64, -s * 0.2), _k(ink, a), lw * 2.2)
	var top := pos + Vector2(-s * 0.04, -s * 0.3)
	ci.draw_line(top, top + Vector2(0, -s * 0.34), _k(ink, a), lw)
	ci.draw_colored_polygon(PackedVector2Array([
		top + Vector2(0, -s * 0.34), top + Vector2(s * 0.22, -s * 0.27), top + Vector2(0, -s * 0.2)]), _k(c, a))


func _draw_silo(ci: CanvasItem, pos: Vector2, s: float, c: Color, a: float) -> void:
	var lw := maxf(1.0, s * 0.045)
	_shadow(ci, pos, s, a)
	var r := s * 0.34
	ci.draw_circle(pos, r, _k(Color("56616b"), a))
	ci.draw_arc(pos, r, 0.0, TAU, 20, _k(OUT, a), lw)
	ci.draw_circle(pos, r * 0.62, _k(Color("2b333a"), a))
	var body := Rect2(pos.x - s * 0.07, pos.y - s * 0.42, s * 0.14, s * 0.5)
	ci.draw_rect(body, _k(Color("e9edf0"), a))
	ci.draw_rect(body, _k(OUT, a), false, lw)
	var nose := PackedVector2Array([Vector2(pos.x - s * 0.07, pos.y - s * 0.42), Vector2(pos.x, pos.y - s * 0.6), Vector2(pos.x + s * 0.07, pos.y - s * 0.42)])
	ci.draw_colored_polygon(nose, _k(c, a))
	ci.draw_polyline(PackedVector2Array([nose[0], nose[1], nose[2]]), _k(OUT, a), lw)
	for n in 2:
		var sx := -1.0 + 2.0 * float(n)
		var fin := PackedVector2Array([Vector2(pos.x + sx * s * 0.07, pos.y + s * 0.0), Vector2(pos.x + sx * s * 0.17, pos.y + s * 0.1), Vector2(pos.x + sx * s * 0.07, pos.y + s * 0.08)])
		ci.draw_colored_polygon(fin, _k(c, a))


func _draw_sam(ci: CanvasItem, pos: Vector2, s: float, c: Color, a: float) -> void:
	var lw := maxf(1.0, s * 0.045)
	_shadow(ci, pos, s, a)
	var base := Rect2(pos.x - s * 0.3, pos.y + s * 0.02, s * 0.6, s * 0.2)
	ci.draw_rect(base, _k(Color("56616b"), a))
	ci.draw_rect(base, _k(OUT, a), false, lw)
	for n in 2:
		var sx := -1.0 + 2.0 * float(n)
		var b0 := pos + Vector2(sx * s * 0.1, s * 0.04)
		var b1 := b0 + Vector2(sx * s * 0.15, -s * 0.42)
		ci.draw_line(b0, b1, _k(OUT, a), s * 0.14)
		ci.draw_line(b0, b1, _k(c, a), s * 0.09)
		ci.draw_circle(b1, s * 0.05, _k(Color("e8483f"), a))
	ci.draw_circle(pos + Vector2(0.0, s * 0.04), s * 0.1, _k(Color("2b333a"), a))


func _draw_atom(ci: CanvasItem, pos: Vector2, s: float, c: Color, a: float, tone: Color = Color("f2b84b"), rings: int = 0) -> void:
	var lw := maxf(1.0, s * 0.045)
	var r := s * 0.3
	ci.draw_circle(pos, r, _k(Color("2b333a"), a))
	ci.draw_arc(pos, r, 0.0, TAU, 24, _k(OUT, a), lw)
	for n in 3:
		var a0 := -PI / 2.0 + TAU * float(n) / 3.0 - PI / 6.0
		var wedge := PackedVector2Array([pos])
		for q in 7:
			var ang := a0 + (PI / 3.0) * float(q) / 6.0
			wedge.append(pos + Vector2(cos(ang), sin(ang)) * r * 0.9)
		ci.draw_colored_polygon(wedge, _k(tone, a))
	ci.draw_circle(pos, r * 0.2, _k(Color("2b333a"), a))
	for q in rings:
		ci.draw_arc(pos, r * (1.25 + 0.28 * float(q)), 0.0, TAU, 28, _k(tone, a * 0.85), lw)


func _draw_mine(ci: CanvasItem, pos: Vector2, s: float, c: Color, a: float) -> void:
	var lw := maxf(1.0, s * 0.05)
	var ink := Color("2f3a45")
	var r := s * 0.26
	ci.draw_set_transform(pos + Vector2(0, r * 1.1), 0.0, Vector2(1, 0.25))
	ci.draw_arc(Vector2.ZERO, r * 1.8, 0.0, TAU, 20, _k(Color(1, 1, 1, 0.45), a), lw)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	for k in 8:
		var ang := TAU * k / 8.0
		var dir := Vector2(cos(ang), sin(ang))
		ci.draw_line(pos + dir * r, pos + dir * r * 1.65, _k(ink, a), lw * 1.8)
	ci.draw_circle(pos, r, _k(ink, a))
	ci.draw_arc(pos, r, 0.0, TAU, 16, _k(OUT, a), lw)
	ci.draw_circle(pos + Vector2(-r * 0.3, -r * 0.3), r * 0.28, _k(Color("e8483f"), a))
	ci.draw_circle(pos + Vector2(r * 0.35, r * 0.25), r * 0.16, _k(c, a))


func _draw_paper_boat(pos: Vector2, s: float, c: Color) -> void:
	var lw := maxf(1.0, s * 0.06)
	var ink := Color("33485a")
	draw_set_transform(pos + Vector2(0, s * 0.28), 0.0, Vector2(1, 0.2))
	draw_arc(Vector2.ZERO, s * 0.5, 0.0, TAU, 24, Color(1, 1, 1, 0.55), lw)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var hull := PackedVector2Array([
		pos + Vector2(-s * 0.5, 0), pos + Vector2(s * 0.5, 0),
		pos + Vector2(s * 0.3, s * 0.26), pos + Vector2(-s * 0.3, s * 0.26)])
	draw_colored_polygon(hull, Color.WHITE)
	hull.append(hull[0])
	draw_polyline(hull, ink, lw)
	var sail := PackedVector2Array([
		pos + Vector2(-s * 0.32, -s * 0.02), pos + Vector2(0, -s * 0.5), pos + Vector2(s * 0.32, -s * 0.02)])
	draw_colored_polygon(sail, c)
	sail.append(sail[0])
	draw_polyline(sail, ink, lw)
	draw_line(pos + Vector2(0, -s * 0.5), pos + Vector2(0, -s * 0.02), ink, lw)


func _hover_tile() -> int:
	var mp := get_viewport().get_mouse_position()
	if _over_ui(mp):
		return -1
	var x := int(floor((mp.x - view_pos.x) / zoom))
	var y := int(floor((mp.y - view_pos.y) / zoom))
	if x < 0 or y < 0 or x >= W or y >= H:
		return -1
	return y * W + x


func _over_ui(pos: Vector2) -> bool:
	for c in [hud, lb_panel, ctl, zoom_panel, end_panel, sub_panel, nuke_panel, atk_panel, ctx_panel]:
		if c != null and c.visible and c.get_global_rect().has_point(pos):
			return true
	return false


func _tip(font: Font, title: String, sub: String, col: Color, ok: bool, alpha: float = 1.0) -> void:
	var tw := maxf(font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x, font.get_string_size(sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x)
	var mp := get_viewport().get_mouse_position() + Vector2(18, 22)
	var vp := get_viewport_rect().size
	mp.x = maxf(10.0, minf(mp.x, vp.x - tw - 20.0))
	mp.y = maxf(20.0, minf(mp.y, vp.y - 44.0))
	var bg := Rect2(mp - Vector2(6, 12), Vector2(tw + 12, 34))
	draw_rect(bg, Color(0.03, 0.08, 0.12, 0.88 * alpha))
	draw_rect(bg, Color(col, 0.9 * alpha), false, 1.5)
	draw_string(font, mp, title, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1, 1, 1, alpha))
	draw_string(font, mp + Vector2(0, 14), sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(Color("b9d3e0") if ok else col, alpha))


# Warship / mine placement: tints the water you can reach from your ports and shows a ghost under the cursor.
func _draw_sea_preview() -> void:
	var font: Font = ui_font if ui_font != null else ThemeDB.fallback_font
	if mode == "mine":
		_sea_reach(my_slot)
		for k in reach_list:
			draw_rect(Rect2(view_pos + Vector2(k % W, k / W) * zoom, Vector2(zoom, zoom)), Color(0.35, 0.8, 1.0, 0.14))
	else:   # warship: show the ports it can leave from
		for k in bld:
			var pb: Dictionary = bld[k]
			if pb["t"] == "port" and int(pb["o"]) == my_slot:
				draw_arc(_tile_px(int(k)), maxf(10.0, zoom * 2.2), 0.0, TAU, 24, Color(0.35, 0.8, 1.0, 0.8), 2.0, true)
	var i := _hover_tile()
	if i < 0:
		return
	var why := can_place_sea(my_slot, mode, i)
	var ok := why == ""
	var col := Color("45e06a") if ok else Color("ff5b5b")
	var pos := _tile_px(i)
	draw_arc(pos, maxf(6.0, zoom * 0.9), 0.0, TAU, 20, col, 2.5)
	draw_building(self, mode, pos, maxf(16.0, zoom * 3.0), ACC, 0.75 if ok else 0.4)
	var title := "%s  -  %s gold" % [BUILD_LABEL[mode], _fmt(price(my_slot, mode))]
	var okt := "Click: launches from your nearest port and sails here   (Shift = keep placing)" if mode == "warship" else "Click to place   (Shift = keep placing, Esc = cancel)"
	_tip(font, title, okt if ok else why, col, ok)


func _draw_terrain_tip() -> void:
	var i := _hover_tile()
	if i < 0 or land[i] == 0:
		return
	var tt: int = terr[i]
	var sp: float = TERRAIN_SLOW[tt]
	var sub := "Advance speed %s   -   troop losses %sx" % ["1x" if sp == 1.0 else "1/%sx" % str(sp), str(TERRAIN_LOSS[tt])]
	if map_data[i * 4 + 3] > 0:
		sub = "Nuclear fallout - nobody owns it. Attack it to claim it.   " + sub
	# the terrain tooltip only appears once the mouse rests (0.45 s) so it never trails over the map while you move or drag
	if drag or tip_still < 0.45:
		return
	_tip(ui_font if ui_font != null else ThemeDB.fallback_font, TERRAIN_NAME[tt], sub, TERRAIN_COL[tt], true, clampf((tip_still - 0.45) / 0.15, 0.0, 1.0))


func _draw_preview(t: float) -> void:
	if phase == "play" and mode == "attack" and sel_ship == 0:
		_draw_terrain_tip()
	if phase != "play" or mode == "attack":
		return
	if NUKE_ORDER.has(mode):
		_draw_nuke_preview()
		return
	if SEA_ORDER.has(mode):
		_draw_sea_preview()
		return
	if mode == "sam":
		for sk2 in bld:   # the reach of every SAM Site you own while the SAM tool is active
			var sb2: Dictionary = bld[sk2]
			if String(sb2["t"]) == "sam" and int(sb2["o"]) == my_slot:
				draw_arc(_tile_px(int(sk2)), SAM_RANGE * zoom, 0.0, TAU, 64, Color(0.4, 0.85, 1.0, 0.30), 1.5)
	var i := _hover_tile()
	if i < 0:
		return
	if mode == "sam":
		draw_circle(_tile_px(i), SAM_RANGE * zoom, Color(0.3, 0.8, 1.0, 0.07))
		draw_arc(_tile_px(i), SAM_RANGE * zoom, 0.0, TAU, 64, Color(0.4, 0.85, 1.0, 0.75), 1.8)
	var why := can_place(my_slot, mode, i)
	var ok := why == ""
	var upgrade := false
	var target := i
	var ghost: String = mode
	var up_text := ""
	if occ.has(i):
		var cb: Dictionary = bld[occ[i]]
		if _can_upgrade(my_slot, mode, cb):
			upgrade = true
			target = occ[i]
			up_text = _upgrade_label(mode, cb)
			ghost = _upgrade_kind(mode, cb)
	var good := Color("ffd24a") if upgrade else Color("45e06a")
	var col := good if ok else Color("ff5b5b")
	var pulse := 0.75 + 0.25 * sin(t * 4.0)
	var cx := target % W
	var cy := target / W
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var xx := cx + dx
			var yy := cy + dy
			if xx < 0 or yy < 0 or xx >= W or yy >= H:
				continue
			var j := yy * W + xx
			var r := Rect2(view_pos + Vector2(xx, yy) * zoom, Vector2(zoom, zoom))
			if land[j] == 1:
				var bad := (own[j] != my_slot or (occ.has(j) and not upgrade)) and not ok
				draw_rect(r, Color(1.0, 0.25, 0.25, 0.32) if bad else Color(col, 0.30))
			else:
				draw_rect(r, Color(1, 1, 1, 0.07))
	var box := Rect2(view_pos + Vector2(cx - 1, cy - 1) * zoom, Vector2(3, 3) * zoom)
	draw_rect(box, Color(col, pulse), false, 2.5)
	var ck := zoom * 0.7   # corner ticks
	for corner in [box.position, Vector2(box.end.x, box.position.y), Vector2(box.position.x, box.end.y), box.end]:
		var sx := 1.0 if corner.x <= box.position.x + 1.0 else -1.0
		var sy := 1.0 if corner.y <= box.position.y + 1.0 else -1.0
		draw_line(corner, corner + Vector2(ck * sx, 0), col, 4.0)
		draw_line(corner, corner + Vector2(0, ck * sy), col, 4.0)
	var links: Array[int] = []
	if mode == "station":
		links = _rail_links_for(target)
		draw_arc(_tile_px(target), RAIL_REACH * zoom, 0.0, TAU, 96, Color(0.27, 0.88, 0.42, 0.28), 2.0)
		for n in links:
			draw_line(_tile_px(target), _tile_px(n), Color(0.05, 0.2, 0.08, 0.9), maxf(4.0, zoom * 0.7))
			draw_line(_tile_px(target), _tile_px(n), Color("45e06a"), maxf(2.0, zoom * 0.4))
			draw_circle(_tile_px(n), maxf(4.0, zoom * 0.7), Color("45e06a"))
	draw_building(self, ghost, _tile_px(target), maxf(14.0, zoom * 3.0), ACC, 0.72 if ok else 0.4)
	# tooltip
	var font: Font = ui_font if ui_font != null else ThemeDB.fallback_font
	var title := "%s  -  %s gold" % [up_text if upgrade else BUILD_LABEL[mode], _fmt(_place_cost(my_slot, mode, i))]
	var ok_text := "Click to build   (Shift = keep placing, Esc = cancel)"
	if mode == "station":
		ok_text = "Rail links in reach: %d  (green)   -   Click to build" % links.size() if links.size() > 0 else "No rail link in reach   -   Click to build"
	_tip(font, title, ok_text if ok else why, col, ok)


# ======================= buildings =======================

func price(p: int, t: String) -> int:
	if t == "silo":
		return PRICE_SILO   # nuclear items have flat prices (OpenFront): no escalation
	if t == "sam":
		return PRICE_SAM
	if BOMB_PRICE.has(t):
		return int(BOMB_PRICE[t])
	var n: int = (players[p] as Player).bought[t]
	if t == "warship":
		return mini(WARSHIP_PRICE_CAP, (n + 1) * WARSHIP_STEP_PRICE)   # 250K, 500K, 750K, then always 750K
	if t == "mine":
		return mini(250000, (n + 1) * 50000)
	# village / station / port: 125K, 250K, 500K, 1M, then 1M (upgrades count as purchases too)
	return mini(PRICE_CAP, int(BASE_PRICE[t]) * (1 << mini(n, 10)))

# What clicking tile i with tool t really costs: upgrading a Bomb Launcher has its own price list.
func _place_cost(p: int, t: String, i: int) -> int:
	if t == "silo" and occ.has(i):
		var b: Dictionary = bld[occ[i]]
		if String(b["t"]) == "silo" and int(b["o"]) == p and int(b["lv"]) < LAUNCHER_MAX:
			return int(LAUNCHER_UPGRADE_PRICE[int(b["lv"]) + 1])
	return price(p, t)


# OpenFront: bigger territories attack more cheaply and are cheaper to attack (logistic in log(tiles)).
func _large_bonus(n: int, depth: float) -> float:
	var x := log(maxf(1.0, float(n)))
	var sg := 1.0 / (1.0 + exp(-2.5 * (x - log(300000.0))))
	return 1.0 - depth * sg

# OpenFront-style number: 3.52K, 12.1K, 125K, 1.25M
func _fmt(v: float) -> String:
	var a := absf(v)
	if a >= 10000000.0:
		return "%.1fM" % (v / 1000000.0)
	if a >= 1000000.0:
		return "%.2fM" % (v / 1000000.0)
	if a >= 100000.0:
		return "%dK" % roundi(v / 1000.0)
	if a >= 10000.0:
		return "%.1fK" % (v / 1000.0)
	if a >= 1000.0:
		return "%.2fK" % (v / 1000.0)
	return "%d" % roundi(v)


func _footprint(i: int) -> Array[int]:
	var r: Array[int] = []
	var x := i % W
	var y := i / W
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var xx := x + dx
			var yy := y + dy
			if xx < 0 or yy < 0 or xx >= W or yy >= H:
				continue
			var j := yy * W + xx
			if land[j] == 1:
				r.append(j)
	return r


func _coastal(i: int) -> bool:
	for n in _nb(i):
		if land[n] == 0:
			return true
	return false


# Returns "" when the building can be placed, otherwise the reason it can't.
func _can_upgrade(p: int, t: String, b: Dictionary) -> bool:
	if b["o"] != p:
		return false
	if t == "village":
		return b["t"] == "village" or b["t"] == "city"
	if t == "port":
		return b["t"] == "port" and int(b["lv"]) < PORT_MAX
	if t == "silo":
		return b["t"] == "silo" and int(b["lv"]) < LAUNCHER_MAX
	return false


func _upgrade_kind(t: String, b: Dictionary) -> String:
	if t == "village":
		return "city" if b["t"] == "village" else "duchy"
	return b["t"]


func _upgrade_label(t: String, b: Dictionary) -> String:
	if t == "village":
		return "Upgrade to City" if b["t"] == "village" else "Upgrade to Duchy"
	var lv := int(b["lv"]) + 1
	if t == "silo":
		return "Upgrade Bomb Launcher to Lv %d  (%s)" % [lv, "Nuke" if lv == 2 else ("Mega Bomb" if lv == 4 else "reloads in %d s" % (int(SILO_RELOAD_BY_LEVEL[lv]) / 10))]
	return "Upgrade Port to Lv %d  (trade income x%.1f, new warships +%d HP)" % [lv, PORT_INCOME_MULT[lv], PORT_HP_PER_LEVEL * (lv - 1)]


# Returns "" when the building can be placed, otherwise the reason it can't.
func can_place(p: int, t: String, i: int) -> String:
	if land[i] == 0:
		return "You can only build on land"
	if own[i] != p:
		return "Build inside your own territory"
	var pl: Player = players[p]
	var upgrade := false
	if occ.has(i):
		var b: Dictionary = bld[occ[i]]
		if _can_upgrade(p, t, b):
			upgrade = true
		elif b["o"] == p and t == "village" and b["t"] == "duchy":
			return "Already a Duchy (max level)"
		elif b["o"] == p and t == "port" and b["t"] == "port":
			return "Port is already level %d (max)" % PORT_MAX
		elif b["o"] == p and t == "silo" and b["t"] == "silo":
			return "Bomb Launcher is already level %d (max)" % LAUNCHER_MAX
		else:
			return "Too close to another building"
	if not upgrade:
		for j in _footprint(i):
			if own[j] != p:
				return "The whole footprint must be your land"
			if occ.has(j):
				return "Too close to another building"
		if t == "port" and not _coastal(i):
			return "Ports must touch the water"
	if pl.gold < _place_cost(p, t, i):
		return "Not enough gold (need %s)" % _fmt(_place_cost(p, t, i))
	return ""


func _has_port(p: int) -> bool:
	for k in bld:
		if bld[k]["t"] == "port" and int(bld[k]["o"]) == p:
			return true
	return false


# Water tiles within SEA_RANGE of any of p's ports (cached per tick). reach_list holds the same tiles as a list.
func _sea_reach(p: int) -> PackedInt32Array:
	var stamp := "%d_%d_%d" % [tick_n, bld.size(), p]
	if stamp == reach_stamp:
		return reach_dist
	reach_stamp = stamp
	reach_dist = PackedInt32Array()
	reach_dist.resize(W * H)
	reach_dist.fill(-1)
	var q: Array[int] = []
	for k in bld:
		var b: Dictionary = bld[k]
		if b["t"] != "port" or int(b["o"]) != p:
			continue
		for n in _nb(int(k)):
			if land[n] == 0 and reach_dist[n] < 0:
				reach_dist[n] = 0
				q.append(n)
	var head := 0
	while head < q.size():
		var cur: int = q[head]
		head += 1
		var d := reach_dist[cur]
		if d >= SEA_RANGE:
			continue
		for n in _nb(cur):
			if land[n] == 0 and reach_dist[n] < 0:
				reach_dist[n] = d + 1
				q.append(n)
	reach_list = q
	return reach_dist


func can_place_sea(p: int, t: String, i: int) -> String:
	if land[i] == 1:
		return "Place it on the water"
	if not _has_port(p):
		return "Build a port first"
	if t == "mine":
		var r := _sea_reach(p)
		if r[i] < 0:
			return "Too far from your ports (range %d tiles)" % SEA_RANGE
		for m in mines:
			if int(m["t"]) == i and int(m["o"]) == p:
				return "There is already a mine here"   # only YOUR mine blocks the tile: refusing because of an enemy's hidden mine would reveal it
	var pl: Player = players[p]
	if pl.gold < price(p, t):
		return "Not enough gold (need %s)" % _fmt(price(p, t))
	return ""


# A warship is built at the port with the shortest sea route to the clicked water and sails there on its own. After that it is
# independent of the port: no range limit, any reachable water, orders can be changed at any time.
func place_sea(p: int, t: String, i: int) -> bool:
	if can_place_sea(p, t, i) != "":
		return false   # defence in depth: never take gold for a placement the rules refuse
	var route: Array[int] = []
	if t == "warship":
		route = _fleet_route(p, i)
		if route.is_empty():
			return false
	var pl: Player = players[p]
	pl.gold -= price(p, t)
	pl.bought[t] += 1
	if t == "warship":
		var mhp := SHIP_HP + PORT_HP_PER_LEVEL * (_port_level_at(p, route[0]) - 1)
		ships.append({"id": next_atk_id, "o": p, "t": route[0], "pt": route[0], "home": i, "ang": 0.0, "hp": mhp, "mhp": mhp, "cd": 0, "tgt": 0,
			"auto": false, "path": route, "pi": 0, "rp": 0, "ban": 0, "shot": -1, "cid": 0, "cprog": 0, "ccd": 0})
		next_atk_id += 1
	else:
		mines.append({"o": p, "t": i})
	return true


func place_building(p: int, t: String, i: int) -> bool:
	if can_place(p, t, i) != "":
		return false   # defence in depth: never take gold for a placement the rules refuse
	var pl: Player = players[p]
	pl.gold -= _place_cost(p, t, i)
	pl.bought[t] += 1
	if occ.has(i):
		var b: Dictionary = bld[occ[i]]
		if t == "village":
			b["t"] = _upgrade_kind(t, b)
		else:
			b["lv"] = int(b["lv"]) + 1
		rails_dirty = true
		if not (players[p] as Player).bot:   # NOT my_slot: the rail rebuild time must be the same on every client
			rails_force = true
		return true
	bld[i] = {"t": t, "o": p, "cd": 8, "lv": 1}
	for j in _footprint(i):
		occ[j] = i
	if t == "station":
		rails_dirty = true
		if not (players[p] as Player).bot:   # NOT my_slot: the rail rebuild time must be the same on every client
			rails_force = true
	return true


func _cap_bonus(t: String) -> float:
	match t:
		"village":
			return CAP_VILLAGE
		"city":
			return CAP_CITY
		"duchy":
			return CAP_DUCHY
	return 0.0


func _flip_building(i: int, o: int) -> void:
	if not bld.has(i):
		return
	var b: Dictionary = bld[i]
	var old: int = b["o"]
	if old == o:
		return
	var bonus := _cap_bonus(String(b["t"]))
	var loss := 0.0
	if bonus > 0.0 and old > 0:
		# the old owner loses the troops this building supported (its share of their troop capacity)
		var pl: Player = players[old]
		var cap := maxf(1.0, max_troops(pl, _counts_of(old)))
		loss = minf(pl.troops, pl.troops * clampf(bonus * CAPTURE_TROOP_LOSS / cap, 0.0, 1.0))
		pl.troops -= loss
	b["o"] = o
	if b["t"] != "village" and b["t"] != "port":
		rails_dirty = true
	_ev_ring(o, Vector2(i % W + 0.5, i / W + 0.5), UI_GOOD, 0.8, 3.5)
	_ev_ring(old, Vector2(i % W + 0.5, i / W + 0.5), UI_BAD, 0.8, 3.5)
	if loss >= 1.0:
		_ev_float(old, i, "-%s troops" % _fmt(loss / 10.0), Color("ff6b5b"))
		_ev_say(old, "You lost a %s!  -%s troops" % [String(b["t"]), _fmt(loss / 10.0)], 3.0, "bad")
	if bonus > 0.0:
		_ev_say(o, "You captured a %s!" % String(b["t"]), 2.5, "good")


func _counts() -> Array:
	var r: Array = []
	for p in N + 1:
		r.append({"village": 0, "city": 0, "duchy": 0, "station": 0, "port": 0, "silo": 0, "sam": 0})
	for k in bld:
		var b: Dictionary = bld[k]
		r[int(b["o"])][String(b["t"])] += 1
	return r


func _counts_of(p: int) -> Dictionary:
	var r := {"village": 0, "city": 0, "duchy": 0, "station": 0, "port": 0, "silo": 0, "sam": 0}
	for k in bld:
		var b: Dictionary = bld[k]
		if int(b["o"]) == p:
			r[String(b["t"])] += 1
	return r


func max_troops(pl: Player, c: Dictionary) -> float:
	# OpenFront: 2 * (tiles^0.6 * 1000 + 50000) + 250,000 per city level; bots get a third
	var m: float = 2.0 * (pow(float(pl.tiles) * of_k, 0.6) * 1000.0 + 50000.0) \
		+ c["village"] * CAP_VILLAGE + c["city"] * CAP_CITY + c["duchy"] * CAP_DUCHY
	return m   # bots play by the same rules as you


# Two rail points can link only when they are within RAIL_REACH and the straight line between them is all land.
func _rail_ok(a: int, b: int) -> bool:
	var ddx := a % W - b % W
	var ddy := a / W - b / W
	if float(ddx * ddx + ddy * ddy) > RAIL_REACH * RAIL_REACH:
		return false
	var pa := Vector2(a % W, a / W)
	var pb := Vector2(b % W, b / W)
	var d := pa.distance_to(pb)
	var steps := maxi(1, int(ceil(d * 2.0)))
	for s in steps + 1:
		var p := pa.lerp(pb, float(s) / float(steps))
		if land[roundi(p.y) * W + roundi(p.x)] == 0:
			return false
	return true


# Every rail point (station / city / duchy) of mine that a new station on tile t would connect to.
func _rail_links_for(t: int) -> Array[int]:
	var r: Array[int] = []
	for k in bld:
		var b: Dictionary = bld[k]
		if int(k) == t:
			continue
		var bt: String = b["t"]
		if int(b["o"]) != my_slot and bt != "station":
			continue
		if bt != "station" and bt != "city" and bt != "duchy":
			continue
		if _rail_ok(t, int(k)):
			r.append(int(k))
	return r


func rebuild_rails() -> void:
	var t0 := _pf0()
	_rebuild_rails_body()
	_pf1("rails rebuild", t0)


func _rebuild_rails_body() -> void:
	# Minimum spanning network over each player's stations + cities + duchies, but only along links that are
	# in reach and over land. Separate islands / far-apart groups form separate networks.
	# A network only gets rails if it contains at least one station (stations are what run the trains).
	rails_dirty = false
	rails = []
	var groups := {}
	for k in bld:
		var t: String = bld[k]["t"]
		if t == "village" or t == "port":
			continue
		var key := "%d_%d" % [int(bld[k]["o"]), comp[int(k)]]
		if not groups.has(key):
			groups[key] = {"o": int(bld[k]["o"]), "nodes": []}
		groups[key]["nodes"].append(int(k))
	for key in groups:
		var g: Dictionary = groups[key]
		var nodes: Array = g["nodes"]
		if nodes.size() < 2:
			continue
		var seen := {}
		for start in nodes:
			if seen.has(start):
				continue
			seen[start] = true
			var in_tree: Array = [start]
			var edges: Array = []
			# Prim: every node outside the tree remembers its closest tree node, so a new tree node is compared with each outside node once
			# (the old version compared every tree node with every outside node on every step: cubic, a visible hitch with many stations)
			var bestd := {}
			var bestf := {}
			var last: int = start
			while true:
				var lp := Vector2(last % W, last / W)
				for b in nodes:
					if seen.has(b) or not _rail_ok(last, int(b)):
						continue
					var d := lp.distance_to(Vector2(int(b) % W, int(b) / W))
					if not bestd.has(b) or d < float(bestd[b]):
						bestd[b] = d
						bestf[b] = last
				var bd := 1e9
				var ba := -1
				var bb := -1
				for b in nodes:
					if seen.has(b) or not bestd.has(b):
						continue
					if float(bestd[b]) < bd:
						bd = float(bestd[b])
						ba = int(bestf[b])
						bb = int(b)
				if bb < 0:
					break
				seen[bb] = true
				in_tree.append(bb)
				edges.append([ba, bb, bd])
				last = bb
			var has_st := false
			for n in in_tree:
				if bld[n]["t"] == "station":
					has_st = true
			if not has_st:
				continue
			for e in edges:
				var u0 := sim_rng.randf()
				rails.append({"a": int(e[0]), "b": int(e[1]), "o": g["o"], "len": maxf(1.0, float(e[2])), "u": u0, "pu": u0, "dir": 1})
	# Stations of DIFFERENT nations link up too when they are in reach and the line between them is land.
	# Trains on these links pay BOTH nations.
	var sts: Array[int] = []
	for k in bld:
		if bld[k]["t"] == "station":
			sts.append(int(k))
	var linked := {}
	var cells := {}   # grid of RAIL_REACH-sized cells: a station only looks at the stations in the 9 cells around it, not at all of them
	var cs := int(RAIL_REACH) + 1
	for a in sts:
		var ck := (a / W / cs) * 1000 + (a % W) / cs
		if not cells.has(ck):
			cells[ck] = []
		(cells[ck] as Array).append(a)
	for a in sts:
		var bd := 1e9
		var bb := -1
		var ao := int(bld[a]["o"])
		var acx := (a % W) / cs
		var acy := a / W / cs
		for gy in range(acy - 1, acy + 2):
			for gx in range(acx - 1, acx + 2):
				if not cells.has(gy * 1000 + gx):
					continue
				for b in (cells[gy * 1000 + gx] as Array):
					if ao == int(bld[b]["o"]) or not _rail_ok(a, b):
						continue
					var d := Vector2(a % W, a / W).distance_to(Vector2(b % W, b / W))
					if d < bd:
						bd = d
						bb = b
		if bb < 0:
			continue
		var lk := "%d_%d" % [mini(a, bb), maxi(a, bb)]
		if linked.has(lk):
			continue
		linked[lk] = true
		var u1 := sim_rng.randf()
		rails.append({"a": a, "b": bb, "o": int(bld[a]["o"]), "o2": int(bld[bb]["o"]), "len": maxf(1.0, bd), "u": u1, "pu": u1, "dir": 1, "x": true})


func step_rails() -> void:
	for r in rails:
		r["pu"] = r["u"]
		var u: float = float(r["u"]) + float(r["dir"]) * RAIL_SPEED / float(r["len"])
		if u >= 1.0:
			u = 1.0
			r["dir"] = -1
			_rail_pay(r, r["b"])
		elif u <= 0.0:
			u = 0.0
			r["dir"] = 1
			_rail_pay(r, r["a"])
		r["u"] = u


func _rail_pay(r: Dictionary, tile: int) -> void:
	if not bld.has(tile):
		return
	if r.get("x", false):
		for oo in [int(r["o"]), int(r["o2"])]:
			var pl2: Player = players[oo]
			var g2: float = INTL_RAIL_PAY
			pl2.gold += g2
			_ev_float(oo, tile, "+" + _fmt(float(g2)))
		return
	var amt: float = RAIL_PAY[bld[tile]["t"]]
	if amt <= 0.0:
		return
	var o: int = r["o"]
	var pl: Player = players[o]
	pl.gold += amt
	_ev_float(o, tile, "+" + _fmt(float(amt)))


# ---------- ports and sea routes ----------

# Breadth-first search over water. The buffers are SHARED and only the tiles the previous search touched get reset, so a
# search costs what it visits instead of clearing 2 whole-map arrays. The result stays valid until the next call.
func _water_bfs(s: int, maxd: int, goal: int = -1) -> Dictionary:
	return _water_bfs_multi([s], maxd, goal)


# Same search from several start tiles at once (all at distance 0). Stops as soon as `goal` is reached (goal = -1: explores everything
# within maxd). Gives up after NAV_NODE_CAP tiles so an unreachable goal on a huge ocean cannot stall the game.
func _water_bfs_multi(srcs: Array, maxd: int, goal: int = -1) -> Dictionary:
	if _bfs_par.size() != W * H:
		_bfs_par = PackedInt32Array()
		_bfs_par.resize(W * H)
		_bfs_par.fill(-2)
		_bfs_dist = PackedInt32Array()
		_bfs_dist.resize(W * H)
		_bfs_q = []
	for old in _bfs_q:
		_bfs_par[old] = -2
	var par := _bfs_par
	var dist := _bfs_dist
	var q: Array[int] = []
	for sv in srcs:
		var si: int = sv
		if land[si] == 0 and par[si] == -2:
			par[si] = -1
			dist[si] = 0
			q.append(si)
	var head := 0
	var wm1 := W - 1
	var last := W * (H - 1)
	while head < q.size():
		var cur: int = q[head]
		head += 1
		if cur == goal or head > NAV_NODE_CAP:
			break
		var d := dist[cur]
		if d >= maxd:
			continue
		var x := cur % W
		var n: int
		if x > 0:
			n = cur - 1
			if land[n] == 0 and par[n] == -2:
				par[n] = cur
				dist[n] = d + 1
				q.append(n)
		if x < wm1:
			n = cur + 1
			if land[n] == 0 and par[n] == -2:
				par[n] = cur
				dist[n] = d + 1
				q.append(n)
		if cur >= W:
			n = cur - W
			if land[n] == 0 and par[n] == -2:
				par[n] = cur
				dist[n] = d + 1
				q.append(n)
		if cur < last:
			n = cur + W
			if land[n] == 0 and par[n] == -2:
				par[n] = cur
				dist[n] = d + 1
				q.append(n)
	_bfs_q = q
	return {"par": par, "dist": dist, "q": q}


# ======================= naval simulation: ports, warships, transport boats, mines =======================
# A PORT is where boats and warships leave from: troop boats sail from your ports (see _boat_plan) and a new warship appears at your
# nearest port (see place_sea). Once afloat a warship is independent: it sails ANY real water route (breadth-first search, never through
# land), has no range limit and can be redirected at any time. Everything here is deterministic (no frame time, no global random
# numbers, no UI state), so every multiplayer client computes the same fights.

func _wpos(i: int) -> Vector2:
	return Vector2(i % W, i / W)


func _boat_tile(b: Dictionary) -> int:
	var bp: Array = b["path"]
	return int(bp[clampi(int(b["k"]), 0, bp.size() - 1)])


# Water tiles that touch one of p's ports: where boats and new warships enter the sea.
func _port_waters(p: int) -> Array[int]:
	var r: Array[int] = []
	for k in bld:
		var b: Dictionary = bld[k]
		if b["t"] != "port" or int(b["o"]) != p:
			continue
		for n in _nb(int(k)):
			if land[n] == 0 and not r.has(n):
				r.append(n)
	return r


# Sea route from the nearest of p's ports to `goal` ([] = none). path[0] is the water tile where the ship leaves the port.
func _fleet_route(p: int, goal: int) -> Array[int]:
	if land[goal] == 1:
		return []
	var srcs := _port_waters(p)
	if srcs.is_empty():
		return []
	var par: PackedInt32Array = _water_bfs_multi(srcs, SHIP_MAXD, goal)["par"]
	if par[goal] == -2:
		return []
	return _water_path(par, goal)


func _water_path(par: PackedInt32Array, goal: int) -> Array[int]:
	var path: Array[int] = []
	var step := goal
	while step >= 0:
		path.append(step)
		step = par[step]
	path.reverse()
	return path


# Everything `o` may shoot at: enemy transport boats and enemy warships. Your own units and your allies' units are never targets.
func _enemy_targets(o: int) -> Array:
	var me: Player = players[o]
	var r: Array = []
	for b in boats:
		var bo := int(b["o"])
		if bo == o or me.allies.has(bo):
			continue
		r.append({"kind": "boat", "ref": b, "owner": bo, "tile": _boat_tile(b)})
	for tb in trade:
		var to := int(tb["o"])
		if to == o or me.allies.has(to) or not _trade_capturable_by(o, tb):
			continue   # own / allied ships, and ships sailing to MY port, are never capture targets
		r.append({"kind": "trade", "ref": tb, "owner": to, "tile": _boat_tile(tb)})
	for s in ships:
		var so := int(s["o"])
		if so == o or me.allies.has(so) or int(s["hp"]) <= 0:
			continue
		r.append({"kind": "ship", "ref": s, "owner": so, "tile": int(s["t"])})
	return r


# Same rules as _enemy_targets, but only units within `radius` tiles of `tile`, and no dictionary is made for a far unit (a warship used to
# build a list of EVERY enemy unit on the map each tick: with hundreds of trade ships and boats that was a constant stream of garbage).
func _targets_near(o: int, tile: int, radius: float) -> Array:
	var me: Player = players[o]
	var r: Array = []
	var cx := tile % W
	var cy := tile / W
	var r2 := radius * radius + 1.0
	for b in boats:
		var bo := int(b["o"])
		if bo == o or me.allies.has(bo):
			continue
		var bt := _boat_tile(b)
		var dx := bt % W - cx
		var dy := bt / W - cy
		if float(dx * dx + dy * dy) <= r2:
			r.append({"kind": "boat", "ref": b, "owner": bo, "tile": bt})
	var use_grid := _tn_ok and _tn_pos.size() == trade.size() and radius <= float(TN_CELL)
	var cand: Array = trade
	if use_grid:
		# only the 3x3 grid cells around the warship, in ascending trade index = exactly the order of the full scan
		var ids := PackedInt32Array()
		var ccx := cx / TN_CELL
		var ccy := cy / TN_CELL
		for gy in range(maxi(0, ccy - 1), ccy + 2):
			for gx in range(maxi(0, ccx - 1), ccx + 2):
				var ck := gy * _tn_cols + gx
				if _tn_cells.has(ck):
					ids.append_array(_tn_cells[ck])
		ids.sort()
		cand = []
		for ti in ids:
			cand.append(trade[ti])
	for tb in cand:
		var to := int(tb["o"])
		if to == o or me.allies.has(to):
			continue
		var tt := _boat_tile(tb)
		var tx := tt % W - cx
		var ty := tt / W - cy
		if float(tx * tx + ty * ty) <= r2 and _trade_capturable_by(o, tb):
			r.append({"kind": "trade", "ref": tb, "owner": to, "tile": tt})
	for s in ships:
		var so := int(s["o"])
		if so == o or me.allies.has(so) or int(s["hp"]) <= 0:
			continue
		var st := int(s["t"])
		var sx := st % W - cx
		var sy := st / W - cy
		if float(sx * sx + sy * sy) <= r2:
			r.append({"kind": "ship", "ref": s, "owner": so, "tile": st})
	return r


# The one unit with this id if nation o may target it (same rules as _enemy_targets), anywhere on the map; {} if not.
func _target_by_id(o: int, id: int) -> Dictionary:
	var me: Player = players[o]
	for b in boats:
		if int(b["id"]) == id:
			var bo := int(b["o"])
			if bo == o or me.allies.has(bo):
				return {}
			return {"kind": "boat", "ref": b, "owner": bo, "tile": _boat_tile(b)}
	var tcand: Array = trade
	if _tn_ok and _tn_pos.size() == trade.size():
		tcand = [_tn_ids[id]] if _tn_ids.has(id) else []
	for tb in tcand:
		if int(tb["id"]) == id:
			var to := int(tb["o"])
			if to == o or me.allies.has(to) or not _trade_capturable_by(o, tb):
				return {}
			return {"kind": "trade", "ref": tb, "owner": to, "tile": _boat_tile(tb)}
	for s in ships:
		if int(s["id"]) == id:
			var so := int(s["o"])
			if so == o or me.allies.has(so) or int(s["hp"]) <= 0:
				return {}
			return {"kind": "ship", "ref": s, "owner": so, "tile": int(s["t"])}
	return {}


func _erase_id(arr: Array, id: int) -> void:
	for i in arr.size():
		if int((arr[i] as Dictionary).get("id", 0)) == id:
			arr.remove_at(i)
			return


# A unit is destroyed: it leaves the simulation for good. A sunk transport takes its troops with it - they never land.
func _sink(tg: Dictionary, by_owner: int) -> void:
	var ref: Dictionary = tg["ref"]
	ref["hp"] = 0
	var vic := int(tg["owner"])
	if tg["kind"] == "boat":
		_erase_id(boats, int(ref["id"]))
		_ev_float(by_owner, int(tg["tile"]), "Sunk!")
		_ev_say(by_owner, "Enemy transport sunk - its troops are lost", 2.5, "good")
		_ev_float(vic, int(tg["tile"]), "Boat lost", RED)
		_ev_say(vic, "Your transport was sunk!", 2.5, "bad")
	else:
		_erase_id(ships, int(ref["id"]))
		_ev_float(by_owner, int(tg["tile"]), "Warship sunk!")
		_ev_say(by_owner, "Enemy warship sunk!", 2.5, "good")
		_ev_float(vic, int(tg["tile"]), "Ship lost", RED)
		_ev_say(vic, "Your warship was sunk!", 2.5, "bad")


func _fire(s: Dictionary, tg: Dictionary) -> void:
	if tg["kind"] == "trade":
		return   # trade ships are never shot: they are boarded and captured (step_capture)
	s["cd"] = WARSHIP_CD
	s["shot"] = int(tg["tile"])
	var ref: Dictionary = tg["ref"]
	var isboat: bool = tg["kind"] == "boat"
	var hp := int(ref.get("hp", BOAT_HP if isboat else SHIP_HP)) - (SHOT_VS_BOAT if isboat else SHOT_VS_SHIP)
	ref["hp"] = hp
	_ev_ring(int(s["o"]), _wpos(int(tg["tile"])) + Vector2(0.5, 0.5), Color(1.0, 0.8, 0.3), 0.35, 1.6)
	if hp <= 0:
		_sink(tg, int(s["o"]))
	elif int(tg["owner"]) != int(s["o"]):
		_ev_float(int(tg["owner"]), int(tg["tile"]), "Under fire", RED)


func _ship_by_id(id: int) -> Dictionary:
	for s in ships:
		if int(s.get("id", 0)) == id:
			return s
	return {}


# My own warship near tile i (0 = none) - for clicking it.
func _ship_at(i: int) -> int:
	var cp := Vector2(i % W + 0.5, i / W + 0.5)
	var best := 0
	var bd := maxf(2.0, 14.0 / zoom)
	for s in ships:
		if int(s["o"]) != my_slot:
			continue
		var d := cp.distance_to(Vector2(int(s["t"]) % W + 0.5, int(s["t"]) / W + 0.5))
		if d < bd:
			bd = d
			best = int(s["id"])
	return best


# An enemy transport / warship near tile i (id, 0 = none) - for clicking a target.
func _enemy_unit_at(i: int) -> int:
	var cp := Vector2(i % W + 0.5, i / W + 0.5)
	var best := 0
	var bd := maxf(3.0, 18.0 / zoom)
	for tg in _enemy_targets(my_slot):
		var d := cp.distance_to(Vector2(int(tg["tile"]) % W + 0.5, int(tg["tile"]) / W + 0.5))
		if d < bd:
			bd = d
			best = int((tg["ref"] as Dictionary)["id"])
	return best


# Tile of a transport / warship by id (-1 if it is gone). UI use: drawing an attack line.
func _unit_tile(id: int) -> int:
	for tb in trade:
		if int(tb["id"]) == id:
			return _boat_tile(tb)
	for b in boats:
		if int(b["id"]) == id:
			return _boat_tile(b)
	for s in ships:
		if int(s["id"]) == id:
			return int(s["t"])
	return -1


# Greedy single step (used only to circle around the station point).
func _ship_step(s: Dictionary, goal: Vector2) -> void:
	var cur: int = s["t"]
	var bd := _wpos(cur).distance_to(goal)
	var best := -1
	var opts: Array[int] = []
	for n in _nb(cur):
		if land[n] != 0:
			continue
		opts.append(n)
		var d := _wpos(n).distance_to(goal)
		if d < bd:
			bd = d
			best = n
	if best < 0 and not opts.is_empty():
		best = opts[sim_rng.randi() % opts.size()]
	if best >= 0:
		s["t"] = best


# Sea route for a warship from where it is to `goal` (true = path stored in the ship). maxd bounds the search.
func _plan_to(s: Dictionary, goal: int, maxd: int) -> bool:
	if land[goal] == 1:
		return false
	var par: PackedInt32Array = _water_bfs(int(s["t"]), maxd, goal)["par"]
	if par[goal] == -2:
		return false
	s["path"] = _water_path(par, goal)
	s["pi"] = 0
	return true


# Why a warship cannot go to `goal` ("" = it can).
func _ship_order_why(s: Dictionary, goal: int) -> String:
	if land[goal] == 1:
		return "Pick open water"
	if int(s["t"]) == goal:
		return "Already there"
	var par: PackedInt32Array = _water_bfs(int(s["t"]), SHIP_MAXD, goal)["par"]
	if par[goal] == -2:
		return "No sea route to that spot"
	return ""


# Apply only (no messages): validate() has already asked _ship_order_why. A new order replaces whatever the ship was doing.
func order_ship(s: Dictionary, goal: int) -> bool:
	if s.is_empty() or not _plan_to(s, goal, SHIP_MAXD):
		return false
	s["home"] = goal
	s["ang"] = 0.0
	s["tgt"] = 0
	s["auto"] = false
	return true


# Intercept course: sail to the first point of the transport's own route that the warship can reach before the transport does
# (or straight at a warship). False = no sea route to it.
func _plan_chase(s: Dictionary, tg: Dictionary) -> bool:
	var from := int(s["t"])
	var tt := int(tg["tile"])
	var maxd := clampi(int(_wpos(from).distance_to(_wpos(tt)) * 2.0) + 40, 40, SHIP_MAXD)
	var r := _water_bfs(from, maxd)
	var par: PackedInt32Array = r["par"]
	var dist: PackedInt32Array = r["dist"]
	var goal := -1
	if tg["kind"] != "ship":
		var spd := float(BOAT_STEP if tg["kind"] == "boat" else TRADE_STEP)
		var b: Dictionary = tg["ref"]
		var bp: Array = b["path"]
		var k := clampi(int(b["k"]), 0, bp.size() - 1)
		var j := k
		var last_ok := -1
		while j < bp.size():
			var tl := int(bp[j])
			if par[tl] != -2:
				last_ok = tl
				if float(dist[tl]) / float(SHIP_SPEED) <= float(j - k) / spd + 0.5:
					goal = tl
					break
			j += 1
		if goal < 0:
			goal = last_ok
	elif par[tt] != -2:
		goal = tt
	if goal < 0:
		return false
	s["path"] = _water_path(par, goal)
	s["pi"] = 0
	return true


func _ship_follow(s: Dictionary) -> void:
	var path: Array = s.get("path", [])
	var pi := int(s.get("pi", 0))
	if pi >= path.size() - 1:
		return
	pi = mini(pi + SHIP_SPEED, path.size() - 1)
	s["pi"] = pi
	s["t"] = path[pi]


func _ship_idle(s: Dictionary) -> bool:
	var path: Array = s.get("path", [])
	return int(s["tgt"]) == 0 and int(s.get("pi", 0)) >= path.size() - 1


func step_ships() -> void:
	chase_budget = CHASE_SEARCHES_PER_TICK
	_tn_build()
	var fleet: Array = ships.duplicate()   # ships can sink during the loop
	for s in fleet:
		if int(s["hp"]) <= 0:
			continue
		var o := int(s["o"])
		if not (players[o] as Player).alive:
			_erase_id(ships, int(s["id"]))
			continue
		s["pt"] = s["t"]
		s["shot"] = -1
		if int(s["cd"]) > 0:
			s["cd"] = int(s["cd"]) - 1
		var targets := _targets_near(o, int(s["t"]), WARSHIP_SIGHT)   # everything it could shoot or go after by itself
		# ---- 1. who is it after? ----
		var locked: Dictionary = {}
		var tid := int(s["tgt"])
		if tid != 0:
			locked = _target_by_id(o, tid)   # a chosen target can be anywhere on the map
			if not locked.is_empty() and locked["kind"] == "trade" and not _trade_lockable(s, locked["ref"]):
				locked = {}   # another warship got it first (or it was just captured): let go
			if locked.is_empty():   # sunk, landed, or now allied: stop here (manual order) or go back to the station (automatic chase)
				if not bool(s["auto"]):
					s["home"] = int(s["t"])
				s["tgt"] = 0
				s["auto"] = false
				s["path"] = []
				s["pi"] = 0
		elif _ship_idle(s):
			var here0 := _wpos(int(s["t"]))
			var bd0 := WARSHIP_SIGHT
			for tg in targets:
				if tg["kind"] == "trade" and (int(s.get("ccd", 0)) > 0 or not _trade_free(tg["ref"])):
					continue   # capture cooldown, or somebody is already boarding / just captured it
				var d0 := here0.distance_to(_wpos(int(tg["tile"])))
				if d0 <= bd0:
					bd0 = d0
					locked = tg
			if not locked.is_empty():
				s["tgt"] = int((locked["ref"] as Dictionary)["id"])
				s["auto"] = true
				s["rp"] = 0
		# ---- 2. move ----
		if not locked.is_empty():
			var here := _wpos(int(s["t"]))
			var ld := here.distance_to(_wpos(int(locked["tile"])))
			if locked["kind"] == "ship" and ld <= WARSHIP_RANGE * 0.6:
				pass   # in gun range of a warship: hold position and shoot
			elif locked["kind"] == "trade" and ld <= CAPTURE_HOLD_DIST:
				pass   # alongside the trade ship: hold position while boarding
			else:
				var path: Array = s["path"]
				if (int(s["pi"]) >= path.size() - 1 or tick_n >= int(s["rp"])) and chase_budget > 0:
					chase_budget -= 1
					var pc0 := _pf0()
					var pc_ok := _plan_chase(s, locked)
					_pf1("ships: chase search", pc0)
					if pc_ok:
						s["rp"] = tick_n + clampi(int(ld / 6.0), 2, 20)
					else:   # no sea route to it: drop the order, do not retry at once
						if not bool(s["auto"]):
							s["home"] = int(s["t"])
						_ev_say(o, "No sea route to that target", 2.5, "bad")
						s["tgt"] = 0
						s["auto"] = false
						s["path"] = []
						s["pi"] = 0
						s["ban"] = tick_n + 40
						locked = {}
				if not locked.is_empty():
					_ship_follow(s)
		elif int(s["pi"]) < (s["path"] as Array).size() - 1:
			_ship_follow(s)   # sailing to a move order (guns still fire on the way)
		else:
			var hm: int = s["home"]
			var hv := _wpos(hm)
			var hd := _wpos(int(s["t"])).distance_to(hv)
			if hd > ORBIT_R + 6.0:   # back to the station point after a chase
				if chase_budget > 0 and tick_n >= int(s["rp"]):
					chase_budget -= 1
					s["rp"] = tick_n + 10
					var ph0 := _pf0()
					var ph_ok := _plan_to(s, hm, clampi(int(hd * 2.0) + 40, 40, SHIP_MAXD))
					_pf1("ships: go-home search", ph0)
					if not ph_ok:
						s["home"] = int(s["t"])
			else:
				s["ang"] = float(s.get("ang", 0.0)) + 0.25
				var ang: float = s["ang"]
				_ship_step(s, hv + Vector2(cos(ang), sin(ang)) * ORBIT_R)
		# ---- 3. shoot: the locked target if it is in range, otherwise the nearest enemy in range ----
		if int(s["cd"]) <= 0:
			var here2 := _wpos(int(s["t"]))
			var shot: Dictionary = {}
			if not locked.is_empty() and locked["kind"] != "trade" and here2.distance_to(_wpos(int(locked["tile"]))) <= WARSHIP_RANGE:
				shot = locked
			else:
				var bd2 := WARSHIP_RANGE
				for tg in targets:
					if tg["kind"] == "trade":
						continue   # trade ships are boarded, never shot
					var d2 := here2.distance_to(_wpos(int(tg["tile"])))
					if d2 <= bd2 and int((tg["ref"] as Dictionary).get("hp", 1)) > 0:
						bd2 = d2
						shot = tg
			if not shot.is_empty():
				_fire(s, shot)
	_tn_ok = false


func _tn_build() -> void:
	var tn0 := _pf0()
	_tn_pos.resize(trade.size())
	_tn_ids.clear()
	_tn_cells.clear()
	_tn_cols = (W + TN_CELL - 1) / TN_CELL
	for ti in trade.size():
		var tbi: Dictionary = trade[ti]
		var tt := _boat_tile(tbi)
		_tn_pos[ti] = tt
		_tn_ids[int(tbi["id"])] = tbi
		var ck := (tt / W / TN_CELL) * _tn_cols + (tt % W) / TN_CELL
		if _tn_cells.has(ck):
			(_tn_cells[ck] as PackedInt32Array).append(ti)
		else:
			var na := PackedInt32Array()
			na.append(ti)
			_tn_cells[ck] = na
	_tn_ok = true
	_pf1("ships: grid build", tn0)


func _port_level_at(p: int, w: int) -> int:
	var best := 1
	for k in bld:
		var b: Dictionary = bld[k]
		if b["t"] == "port" and int(b["o"]) == p and _nb(int(k)).has(w):
			best = maxi(best, int(b["lv"]))
	return best


# OpenFront-style trade: every port keeps sending trade ships to other ports (yours, neutral or foreign). When one arrives, BOTH port
# owners are paid for the distance it sailed. A warship can steal a trade ship of a nation it is not allied with (see step_capture).
func step_ports() -> void:
	trade_budget = TRADE_ROUTES_PER_TICK   # new (uncached) sea routes are the costly part: a few per tick at most
	trade_ports = []
	for k in bld:
		if (bld[k] as Dictionary)["t"] == "port":
			trade_ports.append(int(k))
	if trade_ports.is_empty():
		return
	var per_port := {}   # port -> trade ships it has at sea (counted once, not once per port)
	for tb in trade:
		per_port[int(tb["pi"])] = int(per_port.get(int(tb["pi"]), 0)) + 1
	for k in trade_ports:
		var b: Dictionary = bld[k]
		b["cd"] = int(b["cd"]) - 1
		if int(b["cd"]) > 0:
			continue
		if int(per_port.get(k, 0)) >= PORT_BOATS or trade.size() >= TRADE_SHIPS_MAX:
			b["cd"] = 4
			continue
		var r := launch_trade(k)
		if r < 0:
			b["cd"] = 1                   # this tick's route searches are used up: try again next tick
		else:
			b["cd"] = maxi(2, TRADE_COOLDOWN - TRADE_COOLDOWN_PER_LEVEL * (int(b["lv"]) - 1))   # 15 s at Lv 1, 1.5 s less per level


# One trade ship from port `pi` to a RANDOM other port anywhere on the map that is reachable over water (any distance, any sea, rivers and
# lakes if they are water tiles) and not cancelled by either nation. Returns 1 = launched, 0 = nobody to trade with (nothing sails: this is
# also the case when yours is the only port on the map), -1 = no route search left this tick (try again next tick).
func launch_trade(pi: int) -> int:
	var sw := _port_sea(pi)
	if sw < 0:
		return 0
	var oi := int(bld[pi]["o"])
	var cands: Array[int] = []
	for k in trade_ports:
		if k == pi or not bld.has(k):
			continue
		var b: Dictionary = bld[k]
		var o2 := int(b["o"])
		if not (players[o2] as Player).alive or _trade_blocked(oi, o2):
			continue
		var w2 := _port_sea(k)
		if w2 >= 0 and wcomp[w2] == wcomp[sw]:
			cands.append(k)
	if cands.is_empty():
		return 0
	var dst: int = cands[sim_rng.randi() % cands.size()]
	if not route_cache.has(pi * (W * H) + dst) and not route_cache.has(dst * (W * H) + pi) and trade_budget <= 0:
		return -1
	var route := _trade_route(pi, dst)
	if route.size() < 2:
		return 0
	var path: Array[int] = []
	for v in route:
		path.append(v)
	trade.append({"id": next_atk_id, "o": oi, "pi": pi, "dst": dst, "path": path, "k": 0, "pk": 0, "lv": int(bld[pi]["lv"]), "capt": 0, "prot": 0, "flash": 0})
	next_atk_id += 1
	return 1


# Connected water bodies + the sea-route grid, built once per match (the map never changes).
func _naval_init() -> void:
	wcomp = PackedInt32Array()
	wcomp.resize(W * H)
	wcomp.fill(0)
	wsize = PackedInt32Array()
	wsize.append(0)
	var cn := 0
	var stack := PackedInt32Array()
	for s0 in W * H:
		if land[s0] == 1 or wcomp[s0] != 0:
			continue
		cn += 1
		var cnt := 1
		wcomp[s0] = cn
		stack.resize(0)
		stack.append(s0)
		while stack.size() > 0:
			var c: int = stack[stack.size() - 1]
			stack.resize(stack.size() - 1)
			var x := c % W
			if x > 0 and land[c - 1] == 0 and wcomp[c - 1] == 0:
				wcomp[c - 1] = cn
				cnt += 1
				stack.append(c - 1)
			if x < W - 1 and land[c + 1] == 0 and wcomp[c + 1] == 0:
				wcomp[c + 1] = cn
				cnt += 1
				stack.append(c + 1)
			if c >= W and land[c - W] == 0 and wcomp[c - W] == 0:
				wcomp[c - W] = cn
				cnt += 1
				stack.append(c - W)
			if c < W * (H - 1) and land[c + W] == 0 and wcomp[c + W] == 0:
				wcomp[c + W] = cn
				cnt += 1
				stack.append(c + W)
		wsize.append(cnt)
	nav = AStarGrid2D.new()
	nav.region = Rect2i(0, 0, W, H)
	nav.cell_size = Vector2.ONE
	nav.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	# Manhattan costs are whole numbers, so every machine finds the identical route (multiplayer clients must agree)
	nav.default_compute_heuristic = AStarGrid2D.HEURISTIC_MANHATTAN
	nav.default_estimate_heuristic = AStarGrid2D.HEURISTIC_MANHATTAN
	nav.update()
	for i in W * H:
		if land[i] == 1:
			nav.set_point_solid(Vector2i(i % W, i / W), true)


# The water tile a port's ships use: its neighbouring water in the biggest water body (-1 = the port touches no water).
func _port_sea(k: int) -> int:
	if port_sea.has(k):
		return port_sea[k]
	var best := -1
	var bs := -1
	for n in _nb(k):
		if land[n] == 0 and wsize[wcomp[n]] > bs:
			bs = wsize[wcomp[n]]
			best = n
	port_sea[k] = best
	return best


# Water route between two ports (tile list, first = next to the source port). Searched once, then remembered for the whole match.
func _trade_route(src: int, dst: int) -> PackedInt32Array:
	var key := src * (W * H) + dst
	if route_cache.has(key):
		return route_cache[key]
	var rkey := dst * (W * H) + src
	if route_cache.has(rkey):
		# the same sea lane sailed the other way round: no new search (the A* is the costly part), just reverse the remembered route
		var fwd: PackedInt32Array = route_cache[rkey]
		var rev := PackedInt32Array()
		for ri in range(fwd.size() - 1, -1, -1):
			rev.append(fwd[ri])
		if route_cache.size() >= ROUTE_CACHE_MAX:
			route_cache.clear()
		route_cache[key] = rev
		return rev
	trade_budget -= 1
	var out := PackedInt32Array()
	var a := _port_sea(src)
	var b := _port_sea(dst)
	if a >= 0 and b >= 0:
		for v in nav.get_id_path(Vector2i(a % W, a / W), Vector2i(b % W, b / W)):
			var vv: Vector2i = v
			out.append(vv.y * W + vv.x)
	if route_cache.size() >= ROUTE_CACHE_MAX:
		route_cache.clear()   # bounded: it used to grow with every port pair ever used (hundreds of MB late in a big match)
	route_cache[key] = out
	return out


# Has either nation cancelled trade with the other?
func _trade_blocked(a: int, b: int) -> bool:
	return a != b and (no_trade.has(a * 1000 + b) or no_trade.has(b * 1000 + a))


func step_trade() -> void:
	var keep: Array = []
	for tb in trade:
		var dst: int = tb["dst"]
		if not bld.has(dst) or bld[dst]["t"] != "port":
			continue   # the destination port is gone: the ship turns back and earns nothing
		if _trade_blocked(int(tb["o"]), int(bld[dst]["o"])):
			continue   # one side cancelled trade while the ship was at sea: it turns back and earns nothing
		tb["pk"] = tb["k"]
		tb["k"] = int(tb["k"]) + TRADE_STEP
		var path: Array = tb["path"]
		if int(tb["k"]) >= path.size() - 1:
			_pay_trade(tb)
			continue
		keep.append(tb)
	trade = keep


func _trade_base(tb: Dictionary) -> float:
	return float((tb["path"] as Array).size() - 1) * TRADE_GOLD_PER_TILE


# Value of a trade ship for its source port's owner (and for a thief): distance x the level of the port it left from.
func _trade_gold(tb: Dictionary) -> float:
	return _trade_base(tb) * PORT_INCOME_MULT[clampi(int(tb.get("lv", 1)), 1, PORT_MAX)]


func _pay_trade(tb: Dictionary) -> void:
	var end: int = (tb["path"] as Array)[(tb["path"] as Array).size() - 1]
	var o: int = tb["o"]
	var dst: Dictionary = bld[tb["dst"]]
	var d: int = int(dst["o"])
	var pay := {o: _trade_gold(tb)}
	if d != o:   # the destination port's owner is paid by the level of HIS port
		pay[d] = _trade_base(tb) * PORT_INCOME_MULT[clampi(int(dst["lv"]), 1, PORT_MAX)]
	for who in pay:
		var pl: Player = players[who]
		if not pl.alive:
			continue
		var g: float = pay[who]
		pl.gold += g
		_ev_float(who, end, "+" + _fmt(g))
		_ev_say(who, "Trade ship arrived: +%s gold" % _fmt(g), 2.5, "good")


func _trade_by_id(id: int) -> Dictionary:
	for tb in trade:
		if int(tb["id"]) == id:
			return tb
	return {}


func _is_trade_enemy(o: int, tb: Dictionary) -> bool:
	var to := int(tb["o"])
	return to != o and not (players[o] as Player).allies.has(to)


# Owner of the port a trade ship is sailing to (0 if that port no longer exists / is no longer a port - step_trade will turn the ship back).
func _trade_dest_owner(tb: Dictionary) -> int:
	var dst := int(tb.get("dst", -1))
	if not bld.has(dst) or String((bld[dst] as Dictionary)["t"]) != "port":
		return 0
	return int((bld[dst] as Dictionary)["o"])


# THE capture rule (used by target selection, boarding and validate): nation o may capture this trade ship only if its owner is neither o
# nor an ally of o, AND it is not sailing to a port of o. A port of an ALLY protects nothing - only o's own ports do.
func _trade_capturable_by(o: int, tb: Dictionary) -> bool:
	if not _is_trade_enemy(o, tb):
		return false
	if CAPTURE_OWN_PORT_PROTECTED and _trade_dest_owner(tb) == o:
		return false
	return true


# A trade ship nobody is boarding and that was not captured a moment ago.
func _trade_free(tb: Dictionary) -> bool:
	return int(tb.get("capt", 0)) == 0 and int(tb.get("prot", 0)) == 0


# May warship s keep (or take) a lock on this trade ship? Yes if it is free, or if s itself is the one boarding it.
func _trade_lockable(s: Dictionary, tb: Dictionary) -> bool:
	if int(tb.get("prot", 0)) > 0:
		return false
	return int(tb.get("capt", 0)) == 0 or int(s.get("cid", 0)) == int(tb["id"])


func _abort_boarding(s: Dictionary, tb: Dictionary) -> void:
	s["cid"] = 0
	s["cprog"] = 0
	if not tb.is_empty() and int(tb.get("capt", 0)) > 0:
		tb["capt"] = 0


# Boarding / capture of trade ships. Called at the start of every attack step (0.1 s). A warship locked on an enemy trade ship that
# comes within CAPTURE_RANGE starts boarding; CAPTURE_STEPS steps later the ship changes owner and keeps sailing its route for the new
# owner (who is paid when it arrives). Then the warship waits CAPTURE_COOLDOWN_STEPS steps (1.2 s) before it can start another capture.
# Same rules for human and AI warships, nothing here reads my_slot, randomness or the clock.
func step_capture() -> void:
	if ships.is_empty() and trade.is_empty():
		return
	var boarding := {}   # trade ship id -> true while a warship is boarding it
	for s in ships:
		if int(s.get("cid", 0)) != 0:
			boarding[int(s["cid"])] = true
	for tb in trade:
		if int(tb.get("prot", 0)) > 0:
			tb["prot"] = int(tb["prot"]) - 1
		if int(tb.get("flash", 0)) > 0:
			tb["flash"] = int(tb["flash"]) - 1
		if int(tb.get("capt", 0)) > 0 and not boarding.has(int(tb["id"])):
			tb["capt"] = 0   # the warship that was boarding it is gone
	for s in ships:
		if int(s["hp"]) <= 0:
			continue
		if int(s.get("ccd", 0)) > 0:
			s["ccd"] = int(s["ccd"]) - 1
		var o := int(s["o"])
		var cid := int(s.get("cid", 0))
		if cid != 0:
			var boat := _trade_by_id(cid)
			# broken off if it is gone, became an ally's (an alliance was made), or sailed out of reach
			if boat.is_empty() or not _trade_capturable_by(o, boat) or _wpos(int(s["t"])).distance_to(_wpos(_boat_tile(boat))) > CAPTURE_HOLD_RANGE:
				_abort_boarding(s, boat)
				continue
			s["cprog"] = int(s.get("cprog", 0)) + 1
			boat["capt"] = maxi(0, CAPTURE_STEPS - int(s["cprog"]))
			if int(s["cprog"]) >= CAPTURE_STEPS:
				_complete_capture(s, boat)
			continue
		var tid := int(s["tgt"])
		if tid == 0 or int(s.get("ccd", 0)) > 0:
			continue
		var prey := _trade_by_id(tid)
		if prey.is_empty() or not _trade_capturable_by(o, prey) or not _trade_free(prey):
			continue
		if _wpos(int(s["t"])).distance_to(_wpos(_boat_tile(prey))) <= CAPTURE_RANGE:
			s["cid"] = tid
			s["cprog"] = 0
			prey["capt"] = CAPTURE_STEPS
			prey["cto"] = o


func _complete_capture(s: Dictionary, tb: Dictionary) -> void:
	var by := int(s["o"])
	var old := int(tb["o"])
	tb["o"] = by
	tb["capt"] = 0
	tb["prot"] = CAPTURE_PROTECT_STEPS
	tb["flash"] = CAPTURE_FLASH_STEPS
	s["cid"] = 0
	s["cprog"] = 0
	s["ccd"] = CAPTURE_COOLDOWN_STEPS
	var tile := _boat_tile(tb)
	_ev_float(by, tile, "Captured!")
	_ev_say(by, "Trade ship captured - it now sails for you", 3.0, "good")
	_ev_ring(by, _wpos(tile) + Vector2(0.5, 0.5), (players[by] as Player).col, 0.6, 2.5)
	_ev_float(old, tile, "Ship stolen", RED)
	_ev_say(old, "Your trade ship was captured!", 3.0, "bad")


func _has_building(p: int, t: String) -> bool:
	for k in bld:
		var b: Dictionary = bld[k]
		if String(b["t"]) == t and int(b["o"]) == p:
			return true
	return false


# The ready Bomb Launcher of nation p (level >= need) that is nearest to `target` (ties: lowest tile index). -1 = none ready.
func _silo_for(p: int, target: int, need: int = 1) -> int:
	var best := -1
	var bd := 1e18
	for k in bld:
		var b: Dictionary = bld[k]
		if String(b["t"]) != "silo" or int(b["o"]) != p or int(b.get("rl", 0)) > 0 or int(b.get("lv", 1)) < need:
			continue
		var d := _wpos(int(k)).distance_squared_to(_wpos(target))
		if d < bd or (d == bd and int(k) < best):
			bd = d
			best = int(k)
	return best


func _silo_ready(p: int, need: int = 1) -> bool:
	return _silo_for(p, 0, need) >= 0


func _bomb_inner(kind: String) -> float:
	if kind == "mega":
		return 6.0   # only the aiming marker: the real crater is worked out at impact (see _detonate_mega)
	return float(BOMB_INNER[kind])


func _bomb_outer(kind: String) -> float:
	if kind == "mega":
		return 12.0
	return float(BOMB_OUTER[kind])


# Rules for a launch (validate() has already passed): pay, put the launcher on cooldown, start the flight. Nothing here reads my_slot.
func _launch_nuke(p: int, kind: String, target: int) -> void:
	var silo := _silo_for(p, target, int(BOMB_NEED_LEVEL[kind]))
	if silo < 0:
		return
	var pl: Player = players[p]
	var cost := price(p, kind)
	if pl.gold < float(cost):
		return
	pl.gold -= float(cost)
	pl.bought[kind] += 1
	var sb: Dictionary = bld[silo]
	sb["rl"] = int(SILO_RELOAD_BY_LEVEL[clampi(int(sb.get("lv", 1)), 1, LAUNCHER_MAX)])
	var dist := _wpos(silo).distance_to(_wpos(target))
	nukes.append({"id": next_atk_id, "o": p, "kind": kind, "tn": int(own[target]), "a": silo, "b": target, "k": 0, "n": maxi(1, int(ceil(dist / NUKE_SPEED)))})
	next_atk_id += 1
	var tow := int(own[target])
	if tow > 0:
		_ev_say(tow, "NUCLEAR LAUNCH! A %s is heading for your land" % String(BUILD_LABEL[kind]), 4.0, "bad")


func _nuke_pos(nk: Dictionary) -> Vector2:
	var u := clampf(float(int(nk["k"])) / float(int(nk["n"])), 0.0, 1.0)
	return _wpos(int(nk["a"])).lerp(_wpos(int(nk["b"])), u)


# Every attack step (0.1 s): silo / SAM reload counters, then every bomb in flight moves, may be shot down, or lands.
func step_nukes() -> void:
	for k in bld:
		var b: Dictionary = bld[k]
		if int(b.get("rl", 0)) > 0:
			b["rl"] = int(b["rl"]) - 1
	if not nukes.is_empty():
		var keep: Array = []
		for nk in nukes:
			nk["k"] = int(nk["k"]) + 1
			if _sam_intercept(nk, _nuke_pos(nk)):
				continue
			if int(nk["k"]) >= int(nk["n"]):
				_detonate(nk)
				continue
			keep.append(nk)
		nukes = keep
	if not blast_jobs.is_empty():
		_blast_jobs_step()


# Every ready SAM of a nation that is neither the bomb's owner nor its ally and is within SAM_RANGE fires once (then reloads).
func _sam_intercept(nk: Dictionary, pos: Vector2) -> bool:
	var no := int(nk["o"])
	var me: Player = players[no]
	for k in bld:
		var b: Dictionary = bld[k]
		if String(b["t"]) != "sam" or int(b.get("rl", 0)) > 0:
			continue
		var so := int(b["o"])
		if so == no or me.allies.has(so) or not (players[so] as Player).alive:
			continue
		if _wpos(int(k)).distance_to(pos) > SAM_RANGE:
			continue
		b["rl"] = SAM_RELOAD_STEPS
		if sim_rng.randf() < float(BOMB_SAM_HIT[String(nk["kind"])]):
			_ev_say(no, "Your %s was shot down by a SAM!" % String(BUILD_LABEL[String(nk["kind"])]), 3.0, "bad")
			_ev_say(so, "SAM Site intercepted an incoming %s!" % String(BUILD_LABEL[String(nk["kind"])]), 3.0, "good")
			if not headless:
				blasts.append({"p": pos + Vector2(0.5, 0.5), "t0": clock, "big": false})
			return true
	return false


func _destroy_building(k: int) -> void:
	for j in _footprint(k):
		if int(occ.get(j, -1)) == k:
			occ.erase(j)
	bld.erase(k)


# Marks a land tile as nuclear fallout (drawn green by the map shader). The mark is removed by _set_own the moment someone owns the tile.
func _mark_fallout(i: int) -> void:
	map_data[i * 4 + 3] = 255
	map_dirty = true


# Impact. The blast does not change the whole map in one go: it becomes a job that sweeps over the map row by row, at most
# BLAST_TILE_BUDGET changed tiles per attack step (so a Mega Bomb takes a few seconds, never a freeze). Row-major loops, integer
# distances and sim_rng only, so every client computes exactly the same result. Every land tile inside the inner radius (and every
# tile that lost its owner in the ring) ends up unowned AND contaminated: nobody owns it, it is drawn as a green fallout zone, and
# anyone can claim it again by attacking it like normal free land.
func _detonate(nk: Dictionary) -> void:
	if String(nk["kind"]) == "mega":
		_detonate_mega(nk)
		return
	var kind := String(nk["kind"])
	var rin := _bomb_inner(kind)
	var rout := _bomb_outer(kind)
	var tt := int(nk["b"])
	var cx := tt % W
	var cy := tt / W
	var r2 := int(ceil(rout))
	var tiles_before := {}
	for pp in range(1, N + 1):
		tiles_before[pp] = (players[pp] as Player).tiles
	blast_jobs.append({"o": int(nk["o"]), "cx": cx, "cy": cy, "rin": rin, "rout": rout, "y": maxi(0, cy - r2), "y1": mini(H - 1, cy + r2),
		"tb": tiles_before, "hit": {}})
	if not headless:
		blasts.append({"p": Vector2(float(cx) + 0.5, float(cy) + 0.5), "t0": clock, "big": true, "r": rout, "ri": rin})
		if blasts.size() > 12:
			blasts.pop_front()


# Mega Bomb: finds the crater radius R around the impact tile that holds MEGA_LAND_SHARE (85 %) of the target nation's tiles
# (distance histogram, no sorting, integer buckets = identical on every client), then a sweep job destroys exactly that nation's
# tiles inside R. Other nations and free land inside the circle are untouched.
func _detonate_mega(nk: Dictionary) -> void:
	var tn := int(nk.get("tn", 0))
	var tt := int(nk["b"])
	var cx := tt % W
	var cy := tt / W
	if tn <= 0 or tn > N or not (players[tn] as Player).alive:
		_ev_say(int(nk["o"]), "The Mega Bomb found nothing left to destroy", 3.0, "bad")
		return
	var buckets := PackedInt32Array()
	buckets.resize(W + H + 2)
	var total := 0
	for y in H:
		var dy2 := (y - cy) * (y - cy)
		var row := y * W
		for x in W:
			if own[row + x] == tn:
				buckets[int(ceil(sqrt(float((x - cx) * (x - cx) + dy2))))] += 1
				total += 1
	if total == 0:
		return
	var goal := int(ceil(float(total) * MEGA_LAND_SHARE))
	var acc := 0
	var r := 0
	while r < buckets.size() and acc < goal:
		acc += buckets[r]
		r += 1
	var crater := float(maxi(1, r - 1))   # every tile of the target within `crater` tiles of the impact is destroyed
	var rr := int(ceil(crater))
	blast_jobs.append({"o": int(nk["o"]), "cx": cx, "cy": cy, "rin": crater, "rout": crater, "y": maxi(0, cy - rr), "y1": mini(H - 1, cy + rr),
		"tb": {tn: (players[tn] as Player).tiles}, "hit": {}, "only": tn})
	if not headless:
		blasts.append({"p": Vector2(float(cx) + 0.5, float(cy) + 0.5), "t0": clock, "big": true, "r": crater, "ri": crater * 0.35})
		if blasts.size() > 12:
			blasts.pop_front()


func _blast_jobs_step() -> void:
	var keep: Array = []
	for job in blast_jobs:
		if _blast_rows(job):
			_blast_finish(job)
		else:
			keep.append(job)
	blast_jobs = keep


# Land: inside rin every owned tile is lost, in the ring each one with probability NUKE_RING_LOSS. Whole rows are processed until
# BLAST_TILE_BUDGET tiles changed owner this step. Returns true when every row is done.
func _blast_rows(job: Dictionary) -> bool:
	var cx := int(job["cx"])
	var cy := int(job["cy"])
	var rin2 := float(job["rin"]) * float(job["rin"])
	var rout2 := float(job["rout"]) * float(job["rout"])
	var rr := int(ceil(float(job["rout"])))
	var by := int(job["o"])
	var only := int(job.get("only", 0))   # Mega Bomb: only this nation's tiles are hit
	var hit: Dictionary = job["hit"]
	var x0 := maxi(0, cx - rr)
	var x1 := mini(W - 1, cx + rr)
	var y1 := int(job["y1"])
	var y := int(job["y"])
	var changed := 0
	while y <= y1 and changed < BLAST_TILE_BUDGET:
		var dy2 := (y - cy) * (y - cy)
		for x in range(x0, x1 + 1):
			var d2 := float((x - cx) * (x - cx) + dy2)
			if d2 > rout2:
				continue
			var i := y * W + x
			if land[i] == 0:
				continue
			var ow := int(own[i])
			if only > 0 and ow != only:
				continue
			if ow == 0:
				if d2 <= rin2:
					_mark_fallout(i)   # free land in the blast is contaminated too
				continue
			if d2 > rin2 and sim_rng.randf() >= NUKE_RING_LOSS:
				continue
			hit[ow] = int(hit.get(ow, 0)) + 1
			var f: Player = players[ow]
			f.tiles -= 1
			_set_own(i, 0)
			_mark_fallout(i)
			changed += 1
			if f.tiles <= 0 and f.alive:
				eliminate(f, by)
		y += 1
	job["y"] = y
	return y > y1


# The sweep is over: troops, buildings and ships.
func _blast_finish(job: Dictionary) -> void:
	var cx := int(job["cx"])
	var cy := int(job["cy"])
	var rin := float(job["rin"])
	var rout := float(job["rout"])
	var hit: Dictionary = job["hit"]
	var tiles_before: Dictionary = job["tb"]
	var only := int(job.get("only", 0))
	var centre := Vector2(float(cx), float(cy))
	# 2. troops: proportional to the share of land lost
	for who in hit:
		var f2: Player = players[int(who)]
		var tb0 := maxi(1, int(tiles_before[int(who)]))
		f2.troops *= 1.0 - clampf(NUKE_TROOP_KILL * float(int(hit[who])) / float(tb0), 0.0, 1.0)
		_ev_say(int(who), "Nuclear strike! You lost %d tiles" % int(hit[who]), 4.0, "bad")
	# 3. buildings: everything within rin, plus any building whose tile just lost its owner
	var lost_b := {}
	for k in bld.keys():
		var bb: Dictionary = bld[k]
		var kd := _wpos(int(k)).distance_to(centre)
		var gone: bool = kd <= rin or (kd <= rout and int(own[int(k)]) != int(bb["o"]))
		if only > 0:
			gone = int(bb["o"]) == only and int(own[int(k)]) != only   # Mega Bomb: only the target's buildings that lost their land
		if gone:
			var bo := int(bb["o"])
			lost_b[bo] = int(lost_b.get(bo, 0)) + 1
			_destroy_building(int(k))
	for bo2 in lost_b:
		_ev_say(int(bo2), "Nuclear strike destroyed %d of your buildings" % int(lost_b[bo2]), 4.0, "bad")
	if not lost_b.is_empty():
		rebuild_rails()
	if only > 0:
		return   # a Mega Bomb never touches ships, boats or mines
	# 4. units at sea inside rin are destroyed (no gold, no troops)
	for sh in ships.duplicate():
		if _wpos(int(sh["t"])).distance_to(centre) <= rin:
			sh["hp"] = 0
			_erase_id(ships, int(sh["id"]))
	for bt in boats.duplicate():
		if _wpos(_boat_tile(bt)).distance_to(centre) <= rin:
			_erase_id(boats, int(bt["id"]))
	for td in trade.duplicate():
		if _wpos(_boat_tile(td)).distance_to(centre) <= rin:
			_erase_id(trade, int(td["id"]))
	var keep_m: Array = []
	for mn in mines:
		if _wpos(int(mn["t"])).distance_to(centre) > rin:
			keep_m.append(mn)
	mines = keep_m


func step_mines() -> void:
	if mines.is_empty():
		return
	var spent: Array = []
	for m in mines:
		var mo := int(m["o"])
		if not (players[mo] as Player).alive:
			spent.append(m)
			continue
		var me: Player = players[mo]
		var mp := _wpos(int(m["t"]))
		for bt in boats:   # mines only hit enemy transports: look at the boats directly, no target list is built
			var bo := int(bt["o"])
			if bo == mo or me.allies.has(bo):
				continue
			var btile := _boat_tile(bt)
			if mp.distance_to(_wpos(btile)) <= MINE_TRIGGER:
				_sink({"kind": "boat", "ref": bt, "owner": bo, "tile": btile}, mo)
				spent.append(m)
				break
	for m in spent:
		mines.erase(m)


# ---- sim -> player event hooks ----
# Rule code must never call say / _float_at / _fx_ring directly. It calls these instead, naming the slot the message is FOR.
# Offline / on a client: shown only if that slot is mine and a UI exists. On a server (step 5) these will queue an event for that peer.
func _ev_say(slot: int, text: String, secs: float = 2.5, kind: String = "info") -> void:
	if headless or slot != my_slot:
		return
	say(text, secs, kind)


func _ev_float(slot: int, tile: int, text: String, col: Color = ACC) -> void:
	if headless or slot != my_slot:
		return
	_float_at(tile, text, slot, col)


func _ev_ring(slot: int, pos: Vector2, col: Color, life: float = 0.6, r_tiles: float = 3.0) -> void:
	if headless or slot != my_slot:
		return
	_fx_ring(pos, col, life, r_tiles)


func _float_at(tile: int, text: String, o: int, col: Color = ACC) -> void:
	if o != my_slot:
		return
	floats.append({"p": Vector2(tile % W + 0.5, tile / W + 0.5), "t": text, "age": 0.0, "c": col})


# ======================= game logic =======================

func spawn(p: int, x: int, y: int) -> void:
	var pl: Player = players[p]
	pl.alive = true
	pl.troops = 25000.0   # OpenFront start: 25,000 (shown as 2.5K) - bots too, they are "real players"
	# the start patch is ~50 OpenFront tiles, i.e. 50 / of_k of ours
	var sr := clampf(sqrt(50.0 / (of_k * PI)), 1.5, 4.0)
	var sri := int(ceil(sr))
	for dy in range(-sri, sri + 1):
		for dx in range(-sri, sri + 1):
			var xx := x + dx
			var yy := y + dy
			if xx < 0 or yy < 0 or xx >= W or yy >= H:
				continue
			var i := yy * W + xx
			if land[i] == 1 and own[i] == 0 and float(dx * dx + dy * dy) <= sr * sr + 0.5:
				_set_own(i, p)
				pl.tiles += 1


# Fisher-Yates with the seeded generator (Array.shuffle() would use the global one).
func _shuffle(a: Array) -> void:
	for i in range(a.size() - 1, 0, -1):
		var j := sim_rng.randi() % (i + 1)
		var tmp: Variant = a[i]
		a[i] = a[j]
		a[j] = tmp


func _base_lim() -> float:
	return clampf(sqrt(float(land_count) / float(N)) * 0.8, 8.0, 40.0)


# Minimum distance between two HUMAN starts: half of the bot spacing, so friends can start close together.
func _human_lim() -> float:
	return maxf(4.0, _base_lim() * 0.5)


# A start tile is fine when it is land, free, away from the map edge and not too close to another start.
func _start_ok(x: int, y: int, starts: Array, lim: float) -> bool:
	if x < 3 or y < 3 or x >= W - 3 or y >= H - 3:
		return false
	var i := y * W + x
	if land[i] != 1 or own[i] != 0:
		return false
	var lim2 := lim * lim
	for s in starts:
		var sv: Vector2i = s
		var ddx := sv.x - x
		var ddy := sv.y - y
		if float(ddx * ddx + ddy * ddy) < lim2:
			return false
	return true


# The valid start closest to `want` (used when a human's pick is too close to another start). Fixed scan order and integer
# distances, so every client in an online match finds the same tile. (-1, -1) = nothing valid nearby.
func _nearest_start(want: Vector2i, starts: Array, lim: float) -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_d := 1 << 60
	var rad := int(lim * 2.0) + 4
	for dy in range(-rad, rad + 1):
		for dx in range(-rad, rad + 1):
			var d := dx * dx + dy * dy
			if d >= best_d:
				continue
			var x := want.x + dx
			var y := want.y + dy
			if x < 0 or y < 0 or x >= W or y >= H:
				continue
			if _start_ok(x, y, starts, lim):
				best = Vector2i(x, y)
				best_d = d
	return best


func _random_start(starts: Array, lim: float) -> Vector2i:
	for t in 300:
		var x := 3 + sim_rng.randi() % (W - 6)
		var y := 3 + sim_rng.randi() % (H - 6)
		if _start_ok(x, y, starts, lim if t < 200 else lim * 0.35):
			return Vector2i(x, y)
	return Vector2i(-1, -1)


# The other slots are placeholders for players, so they choose a start during the countdown too: each one picks a random
# spot at a random moment, and about a third of them change their mind once.
func _plan_bot_starts() -> void:
	bot_picks = {}
	var taken: Array = []
	var lim := _base_lim()
	for p in range(1, N + 1):
		if not (players[p] as Player).bot:
			continue
		var a := _random_start(taken, lim)
		if a.x < 0:
			continue
		taken.append(a)
		var e := {"tile": a, "at": sim_rng.randf_range(0.5, SPAWN_SECS * 0.8), "redo_at": -1.0, "redo_tile": a}
		if sim_rng.randf() < 0.3:
			var b := _random_start(taken, lim)
			if b.x >= 0:
				taken.append(b)
				e["redo_at"] = float(e["at"]) + sim_rng.randf_range(2.0, 8.0)
				e["redo_tile"] = b
		bot_picks[p] = e


# Where a placeholder player's marker is after `el` seconds of the countdown ((-1, -1) = it has not chosen yet).
func _bot_tile(e: Dictionary, el: float) -> Vector2i:
	if el < float(e["at"]):
		return Vector2i(-1, -1)
	if float(e["redo_at"]) >= 0.0 and el >= float(e["redo_at"]):
		return e["redo_tile"]
	return e["tile"]


func _spawn_step(delta: float) -> void:
	spawn_left -= delta
	if spawn_left <= 0.0:
		begin_play()
		return
	var txt := "Starting in %d s   -   click any land to choose where you start; click again to move it." % ceili(spawn_left)
	if msg_label.text != txt:
		msg_label.text = txt


# The countdown is over: you appear where you last clicked (a random free spot if you never clicked), then the other
# slots appear where they picked - unless someone else already took or crowded that spot, then they get a free one.
func begin_play() -> void:
	var lim := _human_lim()   # spacing between humans; the bots use _base_lim() in spawn_bots()
	var start_moved := false
	if not online:
		human_picks = {my_slot: my_start}
	var starts: Array = []
	# every human appears where they picked (slot order); online a bad or crowded pick gets a free spot instead
	for p in range(1, N + 1):
		if (players[p] as Player).bot:
			continue
		var hs: Vector2i = human_picks.get(p, Vector2i(-1, -1))
		var bad: bool = hs.x < 0 or land[hs.y * W + hs.x] == 0
		if not bad and online and not _start_ok(hs.x, hs.y, starts, lim):
			# too close to another human's start: take the nearest free spot instead of a random one far away
			var near := _nearest_start(hs, starts, lim)
			if near.x >= 0:
				if p == my_slot:
					start_moved = true
				hs = near
			else:
				bad = true
		if bad:
			hs = _random_start(starts, lim if online else 0.0)
			if hs.x < 0:
				for k in W * H:
					if land[k] == 1 and own[k] == 0:
						hs = Vector2i(k % W, k / W)
						break
		spawn(p, hs.x, hs.y)
		starts.append(hs)
	pstart = starts
	spawn_bots()
	phase = "play"
	acc = 0.0
	atk_acc = 0.0
	rebuild_image()
	calc_labels()
	if start_moved:
		say("Your start was too close to another player, so you were placed on the nearest free spot.", 6.0, "bad")
	else:
		if spectating:
			say("Spectating: click a nation to follow it. Use the speed buttons at the top.", 6.0)
		else:
			say("Click land to attack, or across the sea to send a boat. Pick a building (1/2/3) to spend gold.", 6.0)
	ui()


func spawn_bots() -> void:
	var starts: Array = pstart.duplicate()
	var lim := _base_lim()
	for p in range(1, N + 1):
		if not (players[p] as Player).bot:
			continue
		var want := Vector2i(-1, -1)
		if bot_picks.has(p):
			want = _bot_tile(bot_picks[p], SPAWN_SECS)
		var tries := 0
		while tries < 6:
			tries += 1
			if want.x < 0 or not _start_ok(want.x, want.y, starts, lim):
				want = _random_start(starts, lim)
			if want.x < 0:
				break
			spawn(p, want.x, want.y)
			(players[p] as Player).think_at = sim_rng.randi() % 6
			if (players[p] as Player).tiles > 3:
				starts.append(want)
				break
			want = Vector2i(-1, -1)


# Spawn countdown visuals: every placeholder player's chosen spot, your own spot (with a time-left ring) and a big timer.
func _draw_spawn(font: Font) -> void:
	var el := SPAWN_SECS - spawn_left
	var tt := Time.get_ticks_msec() / 1000.0
	for p in bot_picks:
		var bt := _bot_tile(bot_picks[p], el)
		if bt.x < 0:
			continue
		var c := _tile_px(bt.y * W + bt.x)
		if not view_r.has_point(c):
			continue
		var r := maxf(3.0, zoom * 0.9)
		draw_circle(c, r + 1.5, Color(0, 0, 0, 0.55))
		draw_circle(c, r, (players[p] as Player).col)
	for hp in human_picks:
		if int(hp) == my_slot:
			continue
		var hv: Vector2i = human_picks[hp]
		var hc := _tile_px(hv.y * W + hv.x)
		if not view_r.has_point(hc):
			continue
		var hr := maxf(5.0, zoom * 1.2)
		draw_circle(hc, hr + 1.5, Color(0, 0, 0, 0.6))
		draw_circle(hc, hr, (players[int(hp)] as Player).col)
		draw_arc(hc, _human_lim() * zoom, 0.0, TAU, 64, Color(1, 1, 1, 0.35), 2.0, true)
		draw_string_outline(font, hc + Vector2(-20.0, -hr - 6.0), (players[int(hp)] as Player).nm, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, 4, Color(0, 0, 0, 0.85))
		draw_string(font, hc + Vector2(-20.0, -hr - 6.0), (players[int(hp)] as Player).nm, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color.WHITE)
	if my_start.x >= 0:
		var mc := _tile_px(my_start.y * W + my_start.x)
		var pr := maxf(12.0, zoom * 2.2)
		var pulse := 0.5 + 0.5 * sin(tt * 4.0)
		draw_circle(mc, pr + 5.0 * pulse, Color(ACC, 0.18))
		draw_arc(mc, pr, 0.0, TAU, 40, Color(ACC, 0.95), 3.0, true)
		draw_arc(mc, pr + 7.0, -PI * 0.5, -PI * 0.5 + TAU * clampf(spawn_left / SPAWN_SECS, 0.0, 1.0), 48, Color(1, 1, 1, 0.85), 3.0, true)
		draw_circle(mc, 4.0, ACC)
		draw_string_outline(font, mc + Vector2(-14.0, -pr - 12.0), "You", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, 4, Color(0, 0, 0, 0.85))
		draw_string(font, mc + Vector2(-14.0, -pr - 12.0), "You", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, ACC)
	if spawn_sb == null:
		spawn_sb = StyleBoxFlat.new()
		spawn_sb.bg_color = Color(0.04, 0.08, 0.12, 0.92)
		spawn_sb.set_corner_radius_all(16)
		spawn_sb.set_border_width_all(2)
		spawn_sb.border_color = Color(ACC, 0.65)
		spawn_sb.shadow_color = Color(0, 0, 0, 0.4)
		spawn_sb.shadow_size = 8
	var vp := get_viewport_rect().size
	var box := Rect2(Vector2((vp.x - 200.0) * 0.5, 14.0), Vector2(200.0, 78.0))
	draw_style_box(spawn_sb, box)
	draw_string(font, box.position + Vector2(0.0, 24.0), "GAME STARTS IN", HORIZONTAL_ALIGNMENT_CENTER, box.size.x, 12, Color(0.7, 0.8, 0.88))
	draw_string(font, box.position + Vector2(0.0, 64.0), str(maxi(0, ceili(spawn_left))), HORIZONTAL_ALIGNMENT_CENTER, box.size.x, 40, Color.WHITE)


# Effect only - reached through apply() after validate(). The guards below are a last line of defence, not the rule path.
func start_attack(o: int, t: int, frac: float, focus: Vector2 = Vector2(-1.0, -1.0)) -> void:
	if o < 1 or o > N or t < 0 or t > N:
		return
	var p: Player = players[o]
	if not p.alive or p.troops < 100.0 or o == t:
		return
	if t > 0 and p.allies.has(t):
		return
	frac = clampf(frac, 0.0, 1.0)
	if frac <= 0.0:
		return
	var amt := p.troops * frac
	p.troops -= amt
	if focus.x >= 0.0:
		_ev_ring(o, focus, BLUE, 0.45, 1.8)   # visual only: confirms where your attack was launched
	for a in attacks:
		if a["o"] == o and a["t"] == t:
			a["troops"] += amt
			if focus.x >= 0.0:
				a["focus"] = focus
			return
	attacks.append({"id": next_atk_id, "o": o, "t": t, "troops": amt, "focus": focus, "stage": 0, "gained": 0, "dmin": 0.0})
	next_atk_id += 1


func _is_human(sl: int) -> bool:
	return sl >= 1 and sl < players.size() and not (players[sl] as Player).bot


func step_attacks() -> void:
	var t0 := _pf0()
	_step_attacks_body()
	_pf1("attacks", t0)


func _step_attacks_body() -> void:
	step_capture()
	step_nukes()
	_resolve_clashes()
	var keep: Array = []
	for a in attacks:
		var mine: bool = _is_human(int(a["o"])) or _is_human(int(a["t"]))   # NOT my_slot: every client must step the same attacks
		if not mine and (int(a["id"]) + atk_n) % 3 != 0:
			keep.append(a)
			continue
		if step_attack(a, 1.0 if mine else 3.0):
			keep.append(a)
	attacks = keep


# Two nations attacking EACH OTHER (an attack and the counter-attack against it): the armies meet and cancel out, man for man.
#  - land attack: whoever has troops left keeps attacking with what is left, the other attack is over;
#  - the attack being countered came by BOAT: the counter only destroys the landing force. The counter army stops there, and whatever
#    is left of it goes back to its nation (the landing, if it was bigger, simply continues with what survives).
# The older attack (smaller id) is the one being countered. Runs on every client on the same state, no randomness, no UI state.
func _resolve_clashes() -> void:
	if attacks.size() < 2:
		return
	var by_pair := {}   # o * 1000 + t -> attacks of o against t
	for a in attacks:
		var at := int(a["t"])
		if at > 0:
			var key := int(a["o"]) * 1000 + at
			if not by_pair.has(key):
				by_pair[key] = []
			(by_pair[key] as Array).append(a)
	var clashed := false
	for key in by_pair:
		var ao := int(key) / 1000
		var at2 := int(key) % 1000
		if ao > at2 or not by_pair.has(at2 * 1000 + ao):
			continue   # each pair of nations once; nothing to clash with
		for a in (by_pair[key] as Array):
			for b in (by_pair[at2 * 1000 + ao] as Array):
				if bool(a.get("dead", false)) or bool(b.get("dead", false)):
					continue
				_clash(a, b)
				clashed = true
	if clashed:
		var keep: Array = []
		for a in attacks:
			if not bool(a.get("dead", false)):
				keep.append(a)
		attacks = keep


func _clash(a: Dictionary, b: Dictionary) -> void:
	var first: Dictionary = a if int(a["id"]) < int(b["id"]) else b    # the attack that was already running
	var counter: Dictionary = b if int(first["id"]) == int(a["id"]) else a   # the answer to it
	var m := minf(float(a["troops"]), float(b["troops"]))
	a["troops"] = float(a["troops"]) - m
	b["troops"] = float(b["troops"]) - m
	var fo := int(first["o"])
	var co := int(counter["o"])
	if bool(first.get("sea", false)):
		# a landing was countered: the counter army is spent on it, what is left of the counter goes home
		var back := float(counter["troops"])
		if back > 0.0:
			(players[co] as Player).troops += back
		counter["troops"] = 0.0
		counter["dead"] = true
		if float(first["troops"]) < 1.0:
			first["troops"] = 0.0
			first["dead"] = true
			_ev_say(co, "Counter-attack destroyed the landing force", 3.0, "good")
			_ev_say(fo, "Your landing force was destroyed by a counter-attack", 3.0, "bad")
		else:
			_ev_say(co, "The landing was stronger: your counter-attack was wiped out", 3.0, "bad")
			_ev_say(fo, "Your landing beat the counter-attack and goes on", 3.0, "good")
		return
	for x in [a, b]:
		if float((x as Dictionary)["troops"]) < 1.0:
			(x as Dictionary)["troops"] = 0.0
			(x as Dictionary)["dead"] = true
	var winner: Dictionary = a if not bool(a.get("dead", false)) else (b if not bool(b.get("dead", false)) else {})
	if not winner.is_empty():
		var lo := int(b["o"]) if int(winner["id"]) == int(a["id"]) else int(a["o"])
		_ev_say(int(winner["o"]), "Armies clashed: your attack goes on with %s" % _fmt(float(winner["troops"]) / 10.0), 3.0, "good")
		_ev_say(lo, "Armies clashed: your attack was beaten back", 3.0, "bad")


# Target-owned land tiles that touch the attacker (built from the attacker's border set, never the whole map).
func _build_front(o: int, t: int) -> Dictionary:
	var fr := {}
	var bset: Dictionary = border[o]
	for b in bset:
		var x: int = b % W
		if x > 0 and land[b - 1] == 1 and own[b - 1] == t:
			fr[b - 1] = true
		if x < W - 1 and land[b + 1] == 1 and own[b + 1] == t:
			fr[b + 1] = true
		if b >= W and land[b - W] == 1 and own[b - W] == t:
			fr[b - W] = true
		if b < W * (H - 1) and land[b + W] == 1 and own[b + W] == t:
			fr[b + W] = true
	return fr


# One OpenFront-style expansion step (10 per second). The attack advances along its whole front like a growing blob:
# every step it takes a share of the contact tiles, notches and pockets first, so the edge stays smooth.
# The share is ATK_FRONT_SPEED * ATK_TICK, i.e. the front moves ~1.3 tiles/s into empty land (like the reference video),
# and it escalates Skirmish -> Assault -> Surge as the attack gains ground.
func step_attack(a: Dictionary, mult: float = 1.0) -> bool:
	var o: int = a["o"]
	var t: int = a["t"]
	var me: Player = players[o]
	var foe: Player = players[t] if t > 0 else null
	if foe != null and me.allies.has(t):
		me.troops += a["troops"]
		return false
	a["age"] = int(a.get("age", 0)) + 1
	var fr: Dictionary = a.get("fr", {})
	if fr.is_empty() or (int(a["age"]) + int(a["id"])) % 120 == 0:
		fr = _build_front(o, t)
		a["fr"] = fr
	var tier3: Array[int] = []
	var tier2: Array[int] = []
	var tier1: Array[int] = []
	var total := 0
	for pass_n in 2:
		tier3.clear()
		tier2.clear()
		tier1.clear()
		var stale: Array[int] = []
		for i in fr:
			if own[i] != t:
				stale.append(i)
				continue
			var x: int = i % W
			var cnt := 0
			if x > 0 and own[i - 1] == o:
				cnt += 1
			if x < W - 1 and own[i + 1] == o:
				cnt += 1
			if i >= W and own[i - W] == o:
				cnt += 1
			if i < W * (H - 1) and own[i + W] == o:
				cnt += 1
			if cnt >= 3:
				tier3.append(i)
			elif cnt == 2:
				tier2.append(i)
			elif cnt == 1:
				tier1.append(i)
			else:
				stale.append(i)
		for sidx in stale:
			fr.erase(sidx)
		total = tier3.size() + tier2.size() + tier1.size()
		if total > 0 or pass_n == 1:
			break
		fr = _build_front(o, t)
		a["fr"] = fr
	if total == 0 or float(a["troops"]) < 1.0:
		me.troops += a["troops"]
		return false
	var age: int = a["age"]
	if not a.has("pos") or ((o == my_slot or t == my_slot) and age % 3 == 0):
		# where the front is (drawing only): a sample of at most ~40 front tiles is enough, a big front is not scanned twice
		var stp := maxi(1, total / 40)
		var idx := 0
		var ns := 0
		var sx := 0.0
		var sy := 0.0
		for arr in [tier3, tier2, tier1]:
			for c in arr:
				idx += 1
				if idx % stp != 0:
					continue
				sx += c % W
				sy += c / W
				ns += 1
		var mid := Vector2(sx, sy) / float(maxi(1, ns))
		var bi := -1
		var bdd := 1e9
		idx = 0
		for arr in [tier3, tier2, tier1]:
			for c in arr:
				idx += 1
				if idx % stp != 0:
					continue
				var dd := Vector2(c % W, c / W).distance_squared_to(mid)
				if dd < bdd:
					bdd = dd
					bi = c
		a["pos"] = Vector2(bi % W + 0.5, bi / W + 0.5)
	var order: Array[int] = []
	var end3 := tier3.size()
	order.append_array(tier3)
	order.append_array(tier2)
	order.append_array(tier1)
	# ---- OpenFront attackLogic (every tile is "plains": magnitude 80, tile cost 16.5) ----
	var atk_troops := maxf(1.0, float(a["troops"]))
	var mag := 80.0
	var tile_cost := 16.5
	var bsz := float(total)
	var loss_per_tile := 0.0
	var foe_loss := 0.0
	var frac_per_tile := 0.0
	if foe == null:
		loss_per_tile = mag / 5.0 * of_k
		frac_per_tile = clampf(2000.0 * tile_cost / atk_troops, 5.0, 100.0) / (bsz * 2.0) * sqrt(of_k)
	else:
		var lab := _large_bonus(int(float(me.tiles) * of_k), 0.7)
		var lad := _large_bonus(int(float(foe.tiles) * of_k), 0.3)
		foe_loss = foe.troops / maxf(1.0, float(foe.tiles))
		var ratio := foe.troops / atk_troops
		loss_per_tile = mag * clampf(ratio, 0.6, 2.0) * (0.463 * lab * lad * of_k + 0.0039 * foe_loss) * ATK_LOSS_MULT
		var speed_cost := clampf(ratio, 0.82, 7.5) * clampf(ratio / 20.0, 1.0, 50.0) / 8.55
		var adv := 1.0
		var rr := atk_troops / maxf(1.0, foe.troops)   # how many times stronger the attacker is
		if rr > ATK_ADV_START:
			adv = clampf(1.0 + ATK_ADV_SLOPE * log(rr / ATK_ADV_START) / log(2.0), 1.0, ATK_ADV_MAX)
		frac_per_tile = speed_cost * tile_cost * _large_bonus(int(float(me.tiles) * of_k), 0.73) * lad / bsz * sqrt(of_k) / ATK_SPEED_MULT / adv
	var done: Array[int] = []
	var fsum := 0.0
	var k := 0
	var round_bias := foe == null and me.tiles > 0
	var ccx := float(me.csx) / float(maxi(1, me.tiles))
	var ccy := float(me.csy) / float(maxi(1, me.tiles))
	# an attack keeps conquering tiles until their cost fractions add up to 1 (one 0.1 s OpenFront tick)
	while k < order.size() and fsum < mult:
		if k >= end3:
			# Notch tiles (3+ own neighbours) go first; every other front tile is drawn at random from ONE pool (the old "corners before
			# flat sides" rule made every nation grow as a square). Free-land growth also prefers, out of two random candidates, the one
			# nearer to the nation's centre, so a nation grows as a round blob. Lazy: only the tiles really taken this step are drawn
			# (shuffling a whole big front every step was a big late-game cost); sim_rng only, so every client picks the same tiles.
			var hi := order.size()
			var j := k + sim_rng.randi() % (hi - k)
			if round_bias:
				var j2 := k + sim_rng.randi() % (hi - k)
				if sim_rng.randf() < 0.75 and _cdist2(order[j2], ccx, ccy) < _cdist2(order[j], ccx, ccy):
					j = j2
			var sw: int = order[k]
			order[k] = order[j]
			order[j] = sw
		var i: int = order[k]
		var tt: int = terr[i]
		a["troops"] = float(a["troops"]) - loss_per_tile * TERRAIN_LOSS[tt]
		if foe != null:
			foe.troops = maxf(0.0, foe.troops - foe_loss)
			foe.tiles -= 1
			if foe.tiles <= 0:
				eliminate(foe, o)
		_set_own(i, o, ATK_TICK * mult * minf(fsum / mult, 1.0))
		me.tiles += 1
		_flip_building(i, o)
		done.append(i)
		fr.erase(i)
		var fx := i % W
		if fx > 0 and land[i - 1] == 1 and own[i - 1] == t:
			fr[i - 1] = true
		if fx < W - 1 and land[i + 1] == 1 and own[i + 1] == t:
			fr[i + 1] = true
		if i >= W and land[i - W] == 1 and own[i - W] == t:
			fr[i - W] = true
		if i < W * (H - 1) and land[i + W] == 1 and own[i + W] == t:
			fr[i + W] = true
		fsum += frac_per_tile * TERRAIN_SLOW[tt]   # slower terrain = each tile eats more of the step
		k += 1
		if float(a["troops"]) <= 0.0:
			break
	if float(a["troops"]) <= 0.0:
		_fill_holes(o, done)
		return false
	_fill_holes(o, done)
	a["gained"] = int(a.get("gained", 0)) + done.size()
	var gnd := int(a["gained"])
	var new_stage := 0 if gnd < 30 else (1 if gnd < 150 else 2)
	if new_stage > int(a.get("stage", 0)) and a.has("pos"):
		_ev_ring(o, a["pos"], BLUE, 0.7, 4.0)   # visual only: your attack escalated
	a["stage"] = new_stage
	return true


func _cdist2(i: int, cx: float, cy: float) -> float:
	var dx := float(i % W) - cx
	var dy := float(i / W) - cy
	return dx * dx + dy * dy


# Any small pocket of non-mine land that is completely enclosed by my territory (it never touches water or the map
# edge and is at most 14 tiles) becomes mine too, so conquests never leave holes inside a base.
func _fill_holes(o: int, around: Array[int]) -> void:
	if _seen.size() != W * H:
		_seen = PackedInt32Array()
		_seen.resize(W * H)
		_seen.fill(0)
		_seen_n = 0
	_seen_n += 1
	var stamp := _seen_n
	var wm1 := W - 1
	var last := W * (H - 1)
	var nbr: Array[int] = [0, 0, 0, 0]
	for c in around:
		var cx0 := c % W
		var cn := 0
		if cx0 > 0:
			nbr[cn] = c - 1
			cn += 1
		if cx0 < wm1:
			nbr[cn] = c + 1
			cn += 1
		if c >= W:
			nbr[cn] = c - W
			cn += 1
		if c < last:
			nbr[cn] = c + W
			cn += 1
		for ni in cn:
			var q: int = nbr[ni]
			if land[q] == 0 or own[q] == o or _seen[q] == stamp:
				continue
			var comp: Array[int] = []
			var stack: Array[int] = [q]
			_seen[q] = stamp
			var open := false
			while not stack.is_empty():
				var cur: int = stack.pop_back()
				comp.append(cur)
				if comp.size() > 14:
					open = true
					break
				var x := cur % W
				if x == 0 or x == wm1 or cur < W or cur >= last:
					open = true
					break
				var m: int
				m = cur - 1
				if land[m] == 0:
					open = true
				elif own[m] != o and _seen[m] != stamp:
					_seen[m] = stamp
					stack.append(m)
				m = cur + 1
				if land[m] == 0:
					open = true
				elif own[m] != o and _seen[m] != stamp:
					_seen[m] = stamp
					stack.append(m)
				m = cur - W
				if land[m] == 0:
					open = true
				elif own[m] != o and _seen[m] != stamp:
					_seen[m] = stamp
					stack.append(m)
				m = cur + W
				if land[m] == 0:
					open = true
				elif own[m] != o and _seen[m] != stamp:
					_seen[m] = stamp
					stack.append(m)
				if open:
					break
			if not open:
				for h in comp:
					grab(o, h)


func grab(o: int, i: int) -> void:
	var f: Player = players[own[i]] if own[i] > 0 else null
	var me: Player = players[o]
	if f != null:
		f.tiles -= 1
		if f.tiles <= 0:
			eliminate(f, o)
	_set_own(i, o, randf() * ATK_TICK)
	me.tiles += 1
	_flip_building(i, o)


func eliminate(f: Player, o: int) -> void:
	f.alive = false
	f.troops = 0.0
	# OpenFront conquerGoldAmount: take all of a bot's gold, half of a human's
	var g: float = f.gold if f.bot else f.gold / 2.0
	f.gold = 0.0
	(players[o] as Player).gold += g
	if g >= 1.0:
		_ev_say(o, "Conquered %s!  +%s gold" % [f.nm, _fmt(g)], 2.5, "good")


# Finds a sea route for a troop boat to the enemy (or neutral) land around tile `clicked`.
# The landing spot is the target's coastal tile closest to where you clicked; the boat leaves from whichever of
# YOUR ports has the shortest sea route to it. Returns {"ok": true, "path", "landing"} or {"why": reason}.
func _boat_plan(o: int, clicked: int) -> Dictionary:
	if land[clicked] == 0:
		return {"why": "Pick land"}
	var t: int = own[clicked]
	var cx := clicked % W
	var cy := clicked / W
	var cands: Array = []
	if t > 0:
		var same_c: Array = []
		var other_c: Array = []
		for k in (coast[t] as Dictionary):
			var kx: int = int(k) % W
			var ky: int = int(k) / W
			var dd := float((kx - cx) * (kx - cx) + (ky - cy) * (ky - cy))
			if comp[k] == comp[clicked]:
				same_c.append([dd, int(k)])
			else:
				other_c.append([dd, int(k)])
		cands = same_c if not same_c.is_empty() else other_c
	else:
		for r in range(0, 90):
			for dy in range(-r, r + 1):
				var step := 1 if absi(dy) == r else maxi(1, 2 * r)
				for dx in range(-r, r + 1, step):
					var xx := cx + dx
					var yy := cy + dy
					if xx < 0 or yy < 0 or xx >= W or yy >= H:
						continue
					var j := yy * W + xx
					if land[j] == 1 and is_coast[j] == 1 and own[j] == 0 and comp[j] == comp[clicked]:
						cands.append([float(dx * dx + dy * dy), j])
			if cands.size() >= 8:
				break
	if cands.is_empty():
		return {"why": "No coast to land on there"}
	cands.sort_custom(func(a, b): return a[0] < b[0])
	var wt := {}
	for e in cands.slice(0, 8):
		for n in _nb(int(e[1])):
			if land[n] == 0:
				wt[n] = int(e[1])
	if wt.is_empty():
		return {"why": "No coast to land on there"}
	# multi-source sea search from every coast tile of mine, on the shared buffers (see _water_bfs)
	if _bfs_par.size() != W * H:
		_bfs_par = PackedInt32Array()
		_bfs_par.resize(W * H)
		_bfs_par.fill(-2)
		_bfs_dist = PackedInt32Array()
		_bfs_dist.resize(W * H)
		_bfs_q = []
	for old in _bfs_q:
		_bfs_par[old] = -2
	var par := _bfs_par
	var dist := _bfs_dist
	var q: Array[int] = []
	var wm1 := W - 1
	var last := W * (H - 1)
	# the boat leaves from any water next to my coast (no port needed); a big coast is sampled so the search stays cheap
	for wn in _coast_waters(o):
		if par[wn] == -2:
			par[wn] = -1
			dist[wn] = 0
			q.append(wn)
	if q.is_empty():
		_bfs_q = q
		return {"why": "Your land does not touch the sea - a boat needs a coast to leave from"}
	var head := 0
	var end := -1
	while head < q.size():
		var cur: int = q[head]
		head += 1
		if wt.has(cur):
			end = cur
			break
		if head > BOAT_NODE_CAP:
			break
		var d := dist[cur]
		if d >= BOAT_MAX_PATH:
			continue
		var x := cur % W
		var m: int
		if x > 0:
			m = cur - 1
			if land[m] == 0 and par[m] == -2:
				par[m] = cur
				dist[m] = d + 1
				q.append(m)
		if x < wm1:
			m = cur + 1
			if land[m] == 0 and par[m] == -2:
				par[m] = cur
				dist[m] = d + 1
				q.append(m)
		if cur >= W:
			m = cur - W
			if land[m] == 0 and par[m] == -2:
				par[m] = cur
				dist[m] = d + 1
				q.append(m)
		if cur < last:
			m = cur + W
			if land[m] == 0 and par[m] == -2:
				par[m] = cur
				dist[m] = d + 1
				q.append(m)
	_bfs_q = q
	if end < 0:
		return {"why": "No sea route from your coast to there"}
	return {"ok": true, "path": _water_path(par, end), "landing": int(wt[end]), "t": t}


# Water tiles touching nation o's coast (every `stp`-th coast tile when the coast is huge). Fixed dictionary order = same list on every client.
func _coast_waters(o: int) -> Array[int]:
	var out: Array[int] = []
	var cd: Dictionary = coast[o]
	var stp := maxi(1, cd.size() / 1500)
	var n := 0
	for k in cd:
		n += 1
		if n % stp != 0:
			continue
		var ki: int = int(k)
		var kx := ki % W
		if kx > 0 and land[ki - 1] == 0:
			out.append(ki - 1)
		if kx < W - 1 and land[ki + 1] == 0:
			out.append(ki + 1)
		if ki >= W and land[ki - W] == 0:
			out.append(ki - W)
		if ki < W * (H - 1) and land[ki + W] == 0:
			out.append(ki + W)
	return out


func launch_boat_plan(o: int, plan: Dictionary, frac: float) -> bool:
	var p: Player = players[o]
	if not p.alive or p.troops < 100.0 or not plan.get("ok", false):
		return false
	var amt := p.troops * frac
	p.troops -= amt
	boats.append({"id": next_atk_id, "o": o, "i": int(plan["landing"]), "troops": amt, "path": plan["path"], "k": 0, "hp": BOAT_HP})
	next_atk_id += 1
	return true


func launch_boat(o: int, target: int, frac: float) -> bool:
	return launch_boat_plan(o, _boat_plan(o, target), frac)


func step_boats() -> void:
	var keep: Array = []
	for b in boats:
		b["k"] += BOAT_STEP
		var path: Array = b["path"]
		if int(b["k"]) < path.size():
			keep.append(b)
			continue
		var o: int = b["o"]
		var tgt: int = b["i"]
		var me: Player = players[o]
		var t: int = own[tgt]
		if not me.alive or t == o or (t > 0 and me.allies.has(t)):
			me.troops += b["troops"]
			continue
		var x := tgt % W
		var y := tgt / W
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				var xx := x + dx
				var yy := y + dy
				if xx < 0 or yy < 0 or xx >= W or yy >= H:
					continue
				var j := yy * W + xx
				if land[j] == 1 and own[j] == t:
					grab(o, j)
		if t > 0:
			var foe: Player = players[t]
			foe.troops = maxf(0.0, foe.troops - float(b["troops"]) * 0.25)
		attacks.append({"id": next_atk_id, "o": o, "t": t, "troops": b["troops"], "focus": Vector2(tgt % W + 0.5, tgt / W + 0.5), "stage": 0, "gained": 0, "dmin": 0.0, "sea": true})
		next_atk_id += 1
	boats = keep


# ======================= commands: ONE rule path for humans, bots and (later) network clients =======================
# A command is a plain Dictionary {"slot": int, "type": String, ...}. Types and fields:
#   attack      target (owner id, 0 = free land), frac (0 < f <= 1), optional focus (Vector2 tile position)
#   boat        tile (any tile of the land to invade), frac           (the route is ALWAYS recomputed here, never trusted)
#   build       kind (village / station / port), tile                 (also upgrades)
#   sea         kind (warship / mine), tile
#   ship        ship (warship id), tile                               (send a warship to open water: any water on the map)
#   shipatk     ship (warship id), tgt (enemy transport / warship id) (intercept and destroy it)
#   cancel      id (attack or boat id)                                (get the unspent troops back)
#   ally_ask    target          ally_cancel    target
#   trade_off   target (cancel trade ships with that nation, both ways)          trade_on   target (take it back)
# validate(slot, cmd, ai) -> "" when allowed, otherwise the reason as player-facing text. `slot` is WHO SENT it (on a server: the slot
# of the peer, never a field the client wrote); cmd["slot"] must match it. ai=false means a human sender (slot must not be a bot),
# ai=true means the built-in AI (slot must be a bot) - so a human and the AI can never both drive one country.
# apply(cmd) performs it and assumes validate() passed. submit() = validate + apply, returns the reason or "".

func _is_int(v) -> bool:
	return typeof(v) == TYPE_INT


func _is_num(v) -> bool:
	return typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT


# Does `o` have a border tile touching a land tile owned by `t` (t = 0: free land)? Early exit, so it is cheap when the answer is yes.
func _has_contact(o: int, t: int) -> bool:
	var bset: Dictionary = border[o]
	for b in bset:
		var x: int = b % W
		if x > 0 and land[b - 1] == 1 and own[b - 1] == t:
			return true
		if x < W - 1 and land[b + 1] == 1 and own[b + 1] == t:
			return true
		if b >= W and land[b - W] == 1 and own[b - W] == t:
			return true
		if b < W * (H - 1) and land[b + W] == 1 and own[b + W] == t:
			return true
	return false


func validate(slot: int, cmd: Dictionary, ai: bool = false) -> String:
	if phase != "play":
		return "The match is not running"
	if not _is_int(slot) or slot < 1 or slot > N:
		return "Unknown country"
	if not cmd.has("type") or typeof(cmd["type"]) != TYPE_STRING or not cmd.has("slot") or not _is_int(cmd["slot"]):
		return "Malformed command"
	if int(cmd["slot"]) != slot:
		return "That country is not yours"
	var pl: Player = players[slot]
	if pl.bot != ai:
		return "That country is not yours"
	if not pl.alive:
		return "Your nation has fallen"
	match String(cmd["type"]):
		"attack":
			if not _is_int(cmd.get("target")) or not _is_num(cmd.get("frac")):
				return "Malformed command"
			var t: int = cmd["target"]
			var f: float = cmd["frac"]
			if t < 0 or t > N or t == slot:
				return "Pick an enemy"
			if not (f > 0.0 and f <= 1.0):
				return "Bad troop share"
			if cmd.has("focus"):
				if typeof(cmd["focus"]) != TYPE_VECTOR2:
					return "Malformed command"
				var fv: Vector2 = cmd["focus"]
				if fv.x >= float(W) or fv.y >= float(H):
					return "Malformed command"
			if t > 0 and not (players[t] as Player).alive:
				return "That nation is already gone"
			if t > 0 and pl.allies.has(t):
				return "You are allied with %s - cancel the alliance first" % _aname(t)
			if pl.troops < 100.0:
				return "Not enough troops"
			if not _has_contact(slot, t):
				return "Your land does not touch theirs - use the boat" if t > 0 else "No free land next to your border"
			return ""
		"boat":
			if not _is_int(cmd.get("tile")) or not _is_num(cmd.get("frac")):
				return "Malformed command"
			var tile: int = cmd["tile"]
			var f2: float = cmd["frac"]
			if tile < 0 or tile >= W * H:
				return "Pick land"
			if not (f2 > 0.0 and f2 <= 1.0):
				return "Bad troop share"
			if pl.troops < 100.0:
				return "Not enough troops"
			var town: int = own[tile]
			if town == slot:
				return "That is already your land"
			if town > 0 and pl.allies.has(town):
				return "You are allied with %s - cancel the alliance first" % _aname(town)
			if town > 0 and not (players[town] as Player).alive:
				return "That nation is already gone"
			var plan := _boat_plan(slot, tile)
			if not plan.get("ok", false):
				return String(plan.get("why", "No sea route to that land"))
			return ""
		"build":
			if not _is_int(cmd.get("tile")) or typeof(cmd.get("kind")) != TYPE_STRING:
				return "Malformed command"
			var kind: String = cmd["kind"]
			var bt: int = cmd["tile"]
			if not BUILD_ORDER.has(kind) and not LAND_EXTRA.has(kind):
				return "Unknown building"
			if bt < 0 or bt >= W * H:
				return "Pick a tile on the map"
			return can_place(slot, kind, bt)
		"sea":
			if not _is_int(cmd.get("tile")) or typeof(cmd.get("kind")) != TYPE_STRING:
				return "Malformed command"
			var sk: String = cmd["kind"]
			var st: int = cmd["tile"]
			if not SEA_ORDER.has(sk):
				return "Unknown sea unit"
			if st < 0 or st >= W * H:
				return "Pick a tile on the map"
			var swhy := can_place_sea(slot, sk, st)
			if swhy == "" and sk == "warship" and _fleet_route(slot, st).is_empty():
				return "No sea route from your ports to there"
			return swhy
		"ship":
			if not _is_int(cmd.get("ship")) or not _is_int(cmd.get("tile")):
				return "Malformed command"
			var gt: int = cmd["tile"]
			if gt < 0 or gt >= W * H:
				return "Pick open water"
			var sh := _ship_by_id(int(cmd["ship"]))
			if sh.is_empty() or int(sh["o"]) != slot:
				return "That is not your ship"
			return _ship_order_why(sh, gt)
		"shipatk":
			if not _is_int(cmd.get("ship")) or not _is_int(cmd.get("tgt")):
				return "Malformed command"
			var sh2 := _ship_by_id(int(cmd["ship"]))
			if sh2.is_empty() or int(sh2["o"]) != slot:
				return "That is not your ship"
			if ai and tick_n < int(sh2.get("ban", 0)):
				return "No route yet"
			var ptb := _trade_by_id(int(cmd["tgt"]))
			if not ptb.is_empty() and _is_trade_enemy(slot, ptb) and not _trade_capturable_by(slot, ptb):
				return "That ship is sailing to your own port"
			for tg in _enemy_targets(slot):   # _enemy_targets never lists your allies' ships, nor trade ships sailing to your own port
				if int((tg["ref"] as Dictionary)["id"]) == int(cmd["tgt"]):
					if tg["kind"] == "trade" and not _trade_lockable(sh2, tg["ref"]):
						return "That trade ship is already being captured"
					return ""
			return "Pick an enemy warship or transport"
		"nuke":
			if not _is_int(cmd.get("tile")) or typeof(cmd.get("kind")) != TYPE_STRING:
				return "Malformed command"
			var nkind := String(cmd["kind"])
			if not NUKE_ORDER.has(nkind):
				return "Unknown weapon"
			var nt: int = cmd["tile"]
			if nt < 0 or nt >= W * H:
				return "Pick a target on the map"
			if not _has_building(slot, "silo"):
				return "Build a Bomb Launcher first"
			if pl.gold < float(price(slot, nkind)):
				return "Not enough gold (need %s)" % _fmt(price(slot, nkind))
			if nkind == "mega":
				var mtn := int(own[nt])
				if land[nt] == 0 or mtn <= 0:
					return "The Mega Bomb needs a nation: click its land"
				if mtn == slot:
					return "That is your own land"
				if pl.allies.has(mtn):
					return "You are allied with %s - cancel the alliance first" % _aname(mtn)
				if not (players[mtn] as Player).alive:
					return "That nation is already gone"
			var nneed := int(BOMB_NEED_LEVEL[nkind])
			if _silo_for(slot, nt, nneed) < 0:
				if _silo_for(slot, nt, 1) < 0:
					return "Your Bomb Launchers are still reloading"
				return "A %s needs a Bomb Launcher of level %d - upgrade one first" % [String(BUILD_LABEL[nkind]), nneed]
			var nown: int = own[nt]
			if nown == slot:
				return "You cannot nuke your own land"
			if nown > 0 and pl.allies.has(nown):
				return "You are allied with %s - cancel the alliance first" % _aname(nown)
			return ""
		"cancel":
			if not _is_int(cmd.get("id")):
				return "Malformed command"
			if _own_attack_or_boat(slot, int(cmd["id"])).is_empty():
				return "That is not your attack"
			return ""
		"ally_ask":
			if not _is_int(cmd.get("target")):
				return "Malformed command"
			var at: int = cmd["target"]
			if at < 1 or at > N or at == slot:
				return "Pick a nation"
			var ap: Player = players[at]
			if not ap.alive:
				return "That nation is already gone"
			if pl.allies.has(at):
				return "Already allied"
			if ap.bot:
				if tick_n < int(ally_ask.get("%d_%d" % [slot, at], -1)):
					return "%s just turned you down - try again in a moment" % ap.nm
			elif tick_n < int(ally_req.get("%d_%d" % [slot, at], -1)):
				return "Request already sent - waiting for %s to accept" % ap.nm
			return ""
		"ally_cancel":
			if not _is_int(cmd.get("target")):
				return "Malformed command"
			var ct: int = cmd["target"]
			if ct < 1 or ct > N or not pl.allies.has(ct):
				return "You have no alliance with that nation"
			return ""
		"trade_off":
			if not _is_int(cmd.get("target")):
				return "Malformed command"
			var tf1: int = cmd["target"]
			if tf1 < 1 or tf1 > N or tf1 == slot:
				return "Pick a nation"
			if no_trade.has(slot * 1000 + tf1):
				return "You already cancelled trade with that nation"
			return ""
		"trade_on":
			if not _is_int(cmd.get("target")):
				return "Malformed command"
			var tf2: int = cmd["target"]
			if tf2 < 1 or tf2 > N or tf2 == slot:
				return "Pick a nation"
			if not no_trade.has(slot * 1000 + tf2):
				return "You have not cancelled trade with that nation"
			return ""
	return "Unknown command"


# Finds the attack or troop boat with this id that belongs to `slot` ({} if none).
func _own_attack_or_boat(slot: int, id: int) -> Dictionary:
	for a in attacks:
		if int(a["id"]) == id and int(a["o"]) == slot:
			return a
	for b in boats:
		if int(b["id"]) == id and int(b["o"]) == slot:
			return b
	return {}


# Performs an already validated command. The only place the sim's state-changing entry points are called from.
func apply(cmd: Dictionary) -> void:
	var slot: int = cmd["slot"]
	match String(cmd["type"]):
		"attack":
			start_attack(slot, int(cmd["target"]), float(cmd["frac"]), cmd.get("focus", Vector2(-1.0, -1.0)))
		"boat":
			launch_boat_plan(slot, _boat_plan(slot, int(cmd["tile"])), float(cmd["frac"]))
		"build":
			place_building(slot, String(cmd["kind"]), int(cmd["tile"]))
		"sea":
			place_sea(slot, String(cmd["kind"]), int(cmd["tile"]))
		"ship":
			order_ship(_ship_by_id(int(cmd["ship"])), int(cmd["tile"]))
		"shipatk":
			var sa := _ship_by_id(int(cmd["ship"]))
			sa["tgt"] = int(cmd["tgt"])
			sa["auto"] = false
			sa["path"] = []
			sa["pi"] = 0
			sa["rp"] = 0
		"nuke":
			_launch_nuke(slot, String(cmd["kind"]), int(cmd["tile"]))
		"cancel":
			var a := _own_attack_or_boat(slot, int(cmd["id"]))
			if attacks.has(a):
				attacks.erase(a)
			else:
				boats.erase(a)
			(players[slot] as Player).troops += float(a["troops"])
		"ally_ask":
			_apply_ally_ask(slot, int(cmd["target"]))
		"ally_cancel":
			var ct: int = int(cmd["target"])
			(players[slot] as Player).allies.erase(ct)
			(players[ct] as Player).allies.erase(slot)
			_ev_say(slot, "Alliance with %s ended" % _aname(ct), 3.0)
			_ev_say(ct, "%s ended the alliance" % _aname(slot), 3.0)
		"trade_off":
			var tg1: int = int(cmd["target"])
			no_trade[slot * 1000 + tg1] = true
			_ev_say(slot, "You cancelled trade with %s" % _aname(tg1), 3.0)
			_ev_say(tg1, "%s cancelled trade with you" % _aname(slot), 3.0, "bad")
		"trade_on":
			var tg2: int = int(cmd["target"])
			no_trade.erase(slot * 1000 + tg2)
			_ev_say(slot, "Trade with %s resumes" % _aname(tg2), 3.0, "good")


func submit(slot: int, cmd: Dictionary, ai: bool = false) -> String:
	var why := validate(slot, cmd, ai)
	if why == "":
		if ai:
			apply(cmd)   # bots run inside every client from the shared seed: never sent over the network
		else:
			_exec(cmd)
	return why


# A human's command: offline it is applied at once; online it goes to the relay and is applied by EVERY client (this one too)
# when the turn that carries it arrives.
func _exec(cmd: Dictionary) -> void:
	if online:
		_net_send({"t": "cmd", "c": _cmd_pack(cmd)})
	else:
		apply(cmd)


# A bot answers at once (60 % yes, and it will not be asked again by the same nation for 25 s = 50 ticks).
func _apply_ally_ask(slot: int, t: int) -> void:
	var me: Player = players[slot]
	var pl: Player = players[t]
	if not pl.bot:
		# A real player decides for themselves: the first "Make alliance" is a request, and when the other player presses it
		# back (their menu then says "Accept alliance") the alliance is formed. No randomness: every client does the same.
		var back := "%d_%d" % [t, slot]
		if tick_n < int(ally_req.get(back, -1)):
			ally_req.erase(back)
			ally_req.erase("%d_%d" % [slot, t])
			me.allies[t] = true
			pl.allies[slot] = true
			_cancel_between(slot, t)
			_ev_say(slot, "Alliance formed with %s" % pl.nm, 3.5, "good")
			_ev_say(t, "Alliance formed with %s" % me.nm, 3.5, "good")
		else:
			ally_req["%d_%d" % [slot, t]] = tick_n + ALLY_REQ_TICKS
			_ev_say(slot, "Alliance request sent to %s" % pl.nm, 3.0, "good")
			_ev_say(t, "%s asks you for an alliance - right-click their land and press Accept alliance" % me.nm, 9.0, "good")
		return
	if sim_rng.randf() < 0.6:
		me.allies[t] = true
		pl.allies[slot] = true
		_cancel_between(slot, t)
		_ev_say(slot, "Alliance formed with %s" % pl.nm, 3.0)
	else:
		ally_ask["%d_%d" % [slot, t]] = tick_n + 50
		_ev_say(slot, "%s declined your alliance" % pl.nm, 3.0)


# Bots play like a careful human. Roughly every 1-2 s a bot (1) answers attacks against it, (2) keeps or ends alliances,
# (3) picks the best target (free land first, then the neighbour it can beat most easily, finishing off tiny nations),
# and (4) never sends more than half of its troops out, so it keeps a home guard. Everything uses sim_rng and the same
# submit() commands as a human, so online clients stay in sync.
func bot_think() -> void:
	var out := {}
	var inc := {}      # defender slot -> {attacker slot -> troops}
	for a in attacks:
		var ao: int = a["o"]
		out[ao] = float(out.get(ao, 0.0)) + float(a["troops"])
		var at: int = a["t"]
		if at > 0:
			if not inc.has(at):
				inc[at] = {}
			inc[at][ao] = float((inc[at] as Dictionary).get(ao, 0.0)) + float(a["troops"])
	var cnt := _counts()
	for p in range(1, N + 1):
		if not (players[p] as Player).bot:
			continue
		var pl: Player = players[p]
		if not pl.alive or tick_n < pl.think_at:
			continue
		pl.think_at = tick_n + sim_rng.randi_range(2, 4)
		_bot_fleet(p)
		_bot_diplomacy(p, inc)
		var cap := max_troops(pl, cnt[p])
		var crowded := pl.troops > cap * 0.85          # troops are piling up at the cap: wasted growth, so use them
		var outp := float(out.get(p, 0.0))
		# --- who borders us? ---
		var nbs := {}
		var seen := 0
		var bset: Dictionary = border[p]
		for b in bset:
			var bx: int = b % W
			if bx > 0 and land[b - 1] == 1 and own[b - 1] != p:
				nbs[int(own[b - 1])] = true
			if bx < W - 1 and land[b + 1] == 1 and own[b + 1] != p:
				nbs[int(own[b + 1])] = true
			if b >= W and land[b - W] == 1 and own[b - W] != p:
				nbs[int(own[b - W])] = true
			if b < W * (H - 1) and land[b + W] == 1 and own[b + W] != p:
				nbs[int(own[b + W])] = true
			seen += 1
			if seen >= 300:
				break
		# --- defence: hit back at the strongest nation that is attacking us ---
		if inc.has(p) and tick_n >= pl.counter_at and pl.troops >= 1500.0 and outp < pl.troops * 0.6:
			var foe := 0
			var ft := 0.0
			for q in (inc[p] as Dictionary).keys():
				if float(inc[p][q]) > ft and not pl.allies.has(int(q)):
					ft = float(inc[p][q])
					foe = int(q)
			if foe > 0 and (players[foe] as Player).alive:
				var cf := clampf(ft / maxf(1.0, pl.troops) + 0.2, 0.25, 0.5)
				if submit(p, {"slot": p, "type": "attack", "target": foe, "frac": cf}, true) == "":
					pl.counter_at = tick_n + 8
					continue
		if pl.troops < 2000.0 or outp > pl.troops * 0.5:
			continue
		if not crowded and sim_rng.randf() < 0.15:
			continue
		# --- pick the best target ---
		var best := -1
		var best_s := 0.0
		for q in nbs.keys():
			if q <= 0:
				continue
			var fp: Player = players[q]
			if not fp.alive or pl.allies.has(q) or fp.troops * 1.15 > pl.troops:
				continue
			var sc := pl.troops / maxf(1.0, fp.troops)
			if inc.has(p) and (inc[p] as Dictionary).has(q):
				sc += 2.0                                  # revenge
			if fp.tiles < 40:
				sc += 1.5                                  # finish a nearly dead nation
			if fp.troops / maxf(1.0, float(fp.tiles)) < pl.troops / maxf(1.0, float(pl.tiles)):
				sc += 0.5                                  # thinly defended land
			if sc > best_s:
				best_s = sc
				best = q
		var wild_first: bool = nbs.has(0) and (best < 0 or pl.tiles < 400 or sim_rng.randf() < 0.6)
		var ratio := sim_rng.randf_range(0.2, 0.35)
		if crowded:
			ratio = sim_rng.randf_range(0.3, 0.5)
		if wild_first:
			submit(p, {"slot": p, "type": "attack", "target": 0, "frac": ratio}, true)
		elif best > 0:
			var er := clampf(0.22 + (best_s - 1.0) * 0.08, 0.22, 0.55)
			submit(p, {"slot": p, "type": "attack", "target": best, "frac": er}, true)
		elif tick_n >= pl.naval_at and _has_port(p):
			_bot_naval(p, ratio)


# Alliances the way a player would use them: ask a much stronger neighbour for peace, and drop an alliance after a while
# once we are the stronger one (so alliances never freeze the whole map).
func _bot_diplomacy(p: int, inc: Dictionary) -> void:
	var pl: Player = players[p]
	for al in pl.allies.keys():
		var a: Player = players[int(al)]
		if not a.bot:
			continue
		if not pl.ally_until.has(al):
			pl.ally_until[al] = tick_n + sim_rng.randi_range(500, 1000)
		elif tick_n >= int(pl.ally_until[al]) and pl.troops > a.troops * 1.2:
			submit(p, {"slot": p, "type": "ally_cancel", "target": int(al)}, true)
			return
	if tick_n < pl.ally_at or pl.allies.size() >= 2:
		return
	pl.ally_at = tick_n + 120
	var pick := 0
	var pt := 0.0
	var seen := 0
	for b in (border[p] as Dictionary):
		for n in _nb(int(b)):
			var q := int(own[n])
			if q > 0 and q != p and land[n] == 1:
				var fp: Player = players[q]
				if fp.alive and fp.bot and not pl.allies.has(q) and fp.troops > pl.troops * 1.3 and fp.troops > pt:
					pt = fp.troops
					pick = q
		seen += 1
		if seen >= 200:
			break
	if pick > 0 and not (inc.has(p) and (inc[p] as Dictionary).has(pick)):
		submit(p, {"slot": p, "type": "ally_ask", "target": pick}, true)


func _count_ships(p: int) -> int:
	var n := 0
	for s in ships:
		if int(s["o"]) == p:
			n += 1
	return n


# An AI nation sends its idle warships against enemy transports that are heading for ITS land.
func _bot_fleet(p: int) -> void:
	var me: Player = players[p]
	var idle: Array = []
	var busy := {}
	for s in ships:
		if int(s["o"]) != p:
			continue
		if int(s["tgt"]) != 0:
			busy[int(s["tgt"])] = true
		elif tick_n >= int(s["ban"]):
			idle.append(s)
	if idle.is_empty():
		return
	for b in boats:
		var bo := int(b["o"])
		if bo == p or me.allies.has(bo) or busy.has(int(b["id"])) or int(own[int(b["i"])]) != p:
			continue
		var bv := _wpos(_boat_tile(b))
		var best: Dictionary = {}
		var bd := 1e9
		for s in idle:
			var d := _wpos(int(s["t"])).distance_to(bv)
			if d < bd:
				bd = d
				best = s
		if best.is_empty():
			continue
		submit(p, {"slot": p, "type": "shipatk", "ship": int(best["id"]), "tgt": int(b["id"])}, true)
		best["ban"] = tick_n + 20   # at most one new order per ship every 10 s
		return


# An AI nation with a port sometimes lands troops across the sea when its land borders give it nothing to attack.
func _bot_naval(p: int, ratio: float) -> void:
	var pl: Player = players[p]
	pl.naval_at = tick_n + 30
	for n in 12:
		var j := sim_rng.randi() % (W * H)
		if land[j] == 0 or own[j] == p or owns_comp(p, comp[j]):
			continue
		var oj := int(own[j])
		if oj > 0:
			var fp: Player = players[oj]
			if pl.allies.has(oj) or not fp.alive or fp.troops * 1.2 > pl.troops:
				continue
		if submit(p, {"slot": p, "type": "boat", "tile": j, "frac": ratio}, true) == "":
			pl.naval_at = tick_n + 60
		else:
			pl.naval_at = tick_n + 120   # no route / not possible: do not try again right away
		return


func _count_mines(p: int) -> int:
	var n := 0
	for m in mines:
		if int(m["o"]) == p:
			n += 1
	return n


# An existing building of ours that the tool `kind` can upgrade: village -> city -> duchy, or a port level.
func _bot_upgrade_tile(p: int, kind: String) -> int:
	var pick := -1
	var k := 0
	for key in bld:
		var b: Dictionary = bld[key]
		if int(b["o"]) != p:
			continue
		var ok := false
		if kind == "village":
			ok = b["t"] == "village" or b["t"] == "city"
		elif kind == "port":
			ok = b["t"] == "port" and int(b["lv"]) < PORT_MAX
		if ok:
			k += 1
			if sim_rng.randi() % k == 0:   # uniform pick without building a list
				pick = int(key)
	return pick


# How far inside our own land a tile is (0-25): villages and stations go where enemies cannot reach them quickly.
func _bot_safety(p: int, tile: int) -> int:
	var sc := 0
	var tx := tile % W
	var ty := tile / W
	for dy in [-6, -3, 0, 3, 6]:
		for dx in [-6, -3, 0, 3, 6]:
			var x: int = tx + dx
			var y: int = ty + dy
			if x >= 0 and y >= 0 and x < W and y < H and own[y * W + x] == p:
				sc += 1
	return sc


# Best valid spot for a NEW building: ports on our coast, stations next to our cities, everything else deep inside.
func _bot_spot(p: int, kind: String) -> int:
	var src: Array = []
	if kind == "port":
		src = (coast[p] as Dictionary).keys()
	elif kind == "station":
		for key in bld:
			var b: Dictionary = bld[key]
			if int(b["o"]) == p and (b["t"] == "city" or b["t"] == "duchy" or b["t"] == "village"):
				src.append(int(key))
	if src.is_empty():
		src = (border[p] as Dictionary).keys()
	if src.is_empty():
		return -1
	var best := -1
	var best_s := -1
	for n in 28:
		var base: int = src[sim_rng.randi() % src.size()]
		var tile := base
		if kind != "port":
			var cx := base % W + sim_rng.randi_range(-6, 6)
			var cy := base / W + sim_rng.randi_range(-6, 6)
			if cx < 0 or cy < 0 or cx >= W or cy >= H:
				continue
			tile = cy * W + cx
		if can_place(p, kind, tile) != "":
			continue
		var sc := 1 if kind == "port" else _bot_safety(p, tile)
		if sc > best_s:
			best_s = sc
			best = tile
	return best


func _bot_warship(p: int) -> bool:
	var pw := _port_waters(p)
	if pw.is_empty():
		return false
	var base: int = pw[sim_rng.randi() % pw.size()]
	for n in 6:
		var gx := base % W + sim_rng.randi_range(-12, 12)
		var gy := base / W + sim_rng.randi_range(-12, 12)
		if gx < 0 or gy < 0 or gx >= W or gy >= H:
			continue
		if submit(p, {"slot": p, "type": "sea", "kind": "warship", "tile": gy * W + gx}, true) == "":
			return true
	return false


func _bot_mine(p: int) -> bool:
	var pw := _port_waters(p)
	if pw.is_empty():
		return false
	var base: int = pw[sim_rng.randi() % pw.size()]
	for n in 6:
		var gx := base % W + sim_rng.randi_range(-8, 8)
		var gy := base / W + sim_rng.randi_range(-8, 8)
		if gx < 0 or gy < 0 or gx >= W or gy >= H:
			continue
		if submit(p, {"slot": p, "type": "sea", "kind": "mine", "tile": gy * W + gx}, true) == "":
			return true
	return false


func _bot_try(p: int, kind: String) -> bool:
	match kind:
		"village":
			var up := -1
			if sim_rng.randf() < 0.5:
				up = _bot_upgrade_tile(p, "village")        # village -> city -> duchy
			if up < 0:
				up = _bot_spot(p, "village")                 # or a new village somewhere safe
			if up < 0:
				up = _bot_upgrade_tile(p, "village")
			return up >= 0 and submit(p, {"slot": p, "type": "build", "kind": "village", "tile": up}, true) == ""
		"port":
			var t := _bot_spot(p, "port")
			return t >= 0 and submit(p, {"slot": p, "type": "build", "kind": "port", "tile": t}, true) == ""
		"portup":
			var u := _bot_upgrade_tile(p, "port")
			return u >= 0 and submit(p, {"slot": p, "type": "build", "kind": "port", "tile": u}, true) == ""
		"station":
			var st := _bot_spot(p, "station")
			return st >= 0 and submit(p, {"slot": p, "type": "build", "kind": "station", "tile": st}, true) == ""
		"warship":
			return _bot_warship(p)
		"mine":
			return _bot_mine(p)
	return false


# A bot spends gold like a planner: it ranks what its nation needs most right now and SAVES for the important things
# (troop capacity, a first port) instead of wasting gold on lesser ones.
func bot_build(p: int, c: Dictionary) -> void:
	var pl: Player = players[p]
	pl.cd -= 1
	if pl.cd > 0:
		return
	var homes: int = int(c["village"]) + int(c["city"]) + int(c["duchy"])
	var hubs: int = int(c["city"]) + int(c["duchy"])
	var cap := max_troops(pl, c)
	var coastal := not (coast[p] as Dictionary).is_empty()
	var opts: Array = []
	# Troop capacity is what makes a nation grow, but each extra village matters less than the one before it, and a coastal
	# nation gets its FIRST PORT right after its first village (boats and warships need it).
	var levels: int = int(c["village"]) + int(c["city"]) * 2 + int(c["duchy"]) * 3
	var v := maxf(45.0, 105.0 - 14.0 * levels)
	if homes == 0:
		v = 150.0
	if pl.troops > cap * 0.8:
		v += 40.0                                           # troops are stuck at the cap: capacity first
	opts.append([v, "village"])
	if coastal:
		if int(c["port"]) == 0:
			opts.append([160.0 if homes >= 1 else 90.0, "port"])   # beats any village once the first village stands
		elif int(c["port"]) < 2 and pl.tiles > 300:
			opts.append([40.0, "port"])
		if int(c["port"]) > 0:
			opts.append([18.0, "portup"])                   # cheaper warships
	if hubs >= 1 and int(c["station"]) < mini(4, 1 + hubs / 2):
		opts.append([55.0, "station"])                      # rails between cities pay gold
	if int(c["port"]) > 0 and _count_ships(p) < BOT_FLEET:
		opts.append([60.0, "warship"])                      # defend against landings
	if int(c["port"]) > 0 and _count_mines(p) < 3:
		opts.append([12.0, "mine"])
	opts.sort_custom(func(a, b): return float(a[0]) > float(b[0]))
	for o in opts:
		var kind: String = o[1]
		var cost := price(p, "port" if kind == "portup" else kind)
		if pl.gold < cost:
			if float(o[0]) >= 80.0:
				pl.cd = 4          # important and not affordable yet: keep saving
				return
			continue
		if _bot_try(p, kind):
			pl.cd = 10
			return
	pl.cd = 20


func tick() -> void:
	var t0 := _pf0()
	_tick_body()
	_pf1("tick (all)", t0)


func _tick_body() -> void:
	tick_n += 1
	if rails_dirty and (rails_force or tick_n - rails_t >= 6):
		rails_force = false
		rails_t = tick_n
		rebuild_rails()
	var cnt := _counts()
	for p in range(1, N + 1):
		var pl: Player = players[p]
		if not pl.alive:
			continue
		var c: Dictionary = cnt[p]
		pl.peak = maxi(pl.peak, pl.tiles)
		var cap := max_troops(pl, c)
		# OpenFront troopIncreaseRate: (10 + troops^0.73 / 4) * (1 - troops / max), bots x0.5; applied 10x per second
		var to_add: float = (10.0 + pow(pl.troops, 0.73) / 4.0) * (1.0 - pl.troops / cap)
		pl.troops = minf(pl.troops + to_add * OF_TICKS_PER_ECON, cap)
		pl.grow = to_add * OF_TICKS_PER_ECON / TICK
		# OpenFront goldAdditionRate: 100 per tick (bots 50), nothing else
		pl.gold += GOLD_PER_OF_TICK * OF_TICKS_PER_ECON
		if pl.bot:
			var pb0 := _pf0()
			bot_build(p, c)
			_pf1("bot_build", pb0)
	var ps0 := _pf0()
	bot_think()
	_pf1("bot_think", ps0)
	ps0 = _pf0()
	step_boats()
	_pf1("step_boats", ps0)
	ps0 = _pf0()
	step_rails()
	_pf1("step_rails", ps0)
	ps0 = _pf0()
	step_ports()
	_pf1("step_ports", ps0)
	ps0 = _pf0()
	step_trade()
	_pf1("step_trade", ps0)
	ps0 = _pf0()
	step_ships()
	_pf1("step_ships", ps0)
	ps0 = _pf0()
	step_mines()
	_pf1("step_mines", ps0)
	# The match is decided for everybody: the first slot (human or bot) that owns WIN_SHARE of the land wins.
	for wp in range(1, N + 1):
		var pw: Player = players[wp]
		if pw.alive and pw.tiles >= land_count * WIN_SHARE:
			winner_slot = wp
			phase = "over"   # rules only: the client shows the end screen from _after_tick()
			break


# CLIENT ONLY (never runs when headless): everything that draws or updates UI after a rules tick.
func _after_tick() -> void:
	var t0 := _pf0()
	_after_tick_body()
	_pf1("_after_tick (HUD)", t0)


func _after_tick_body() -> void:
	if headless:
		return
	if tick_n % 4 == 1:
		calc_labels()
	_refresh_attacks()
	if spectating and not (players[my_slot] as Player).alive:
		_spec_auto_follow()
	if tick_n % 3 == 0:
		ui()
		_spec_refresh()
	if winner_slot > 0:
		finish("You conquered the map!" if (winner_slot == my_slot and not spectating) else "%s conquered the map" % (players[winner_slot] as Player).nm)
	elif phase == "play" and not spectating and not (players[my_slot] as Player).alive:
		if online:
			if not fallen_shown:
				fallen_shown = true
				_show_end("Your nation has fallen")   # the match goes on for the others (and keeps running here)
		else:
			finish("Your nation has fallen")


func finish(t: String) -> void:
	phase = "over"
	_show_end(t)


func _show_end(t: String) -> void:
	end_label.text = t
	end_label.add_theme_color_override("font_color", UI_GOOD if t.begins_with("You conquered") else UI_BAD)
	end_panel.visible = true


func _toggle_build(t: String) -> void:
	if spectating:
		return
	if phase != "play":
		return
	if SEA_ORDER.has(t) and not _has_port(my_slot):
		_card_deny(t)
		say("Build a port first - warships are built at ports and mines are laid from them.", 3.0, "bad")
		return
	if NUKE_ORDER.has(t) and mode != t:
		var tneed := int(BOMB_NEED_LEVEL[t])
		if not _silo_ready(my_slot, tneed):
			_card_deny(t)
			if not _has_building(my_slot, "silo"):
				say("Build a Bomb Launcher first - the bombs are fired from it.", 3.5, "bad")
			elif _silo_ready(my_slot, 1):
				say("A %s needs a Bomb Launcher of level %d - click your launcher with the Bomb Launcher tool to upgrade it." % [String(BUILD_LABEL[t]), tneed], 4.0, "bad")
			else:
				say("Your Bomb Launchers are still reloading.", 3.0, "bad")
			return
	if mode == t:
		set_mode("attack")
	else:
		set_mode(t)
		if (players[my_slot] as Player).gold < float(price(my_slot, t)):
			_card_deny(t)
			say("Not enough gold yet - a %s costs %s." % [BUILD_LABEL[t], _fmt(price(my_slot, t))], 3.0, "bad")
		elif NUKE_ORDER.has(t):
			say("Click the target: everything inside the inner circle is destroyed and turns into fallout. Right click / Esc cancels.", 3.5)
		elif SEA_ORDER.has(t):
			say(("Click any water: the warship launches from your nearest port and sails there.  Right click / Esc cancels." if t == "warship" else "Click the water near your ports to place a %s.  Right click / Esc cancels." % BUILD_LABEL[t]), 3.5)
		else:
			say("Click inside your territory to build a %s.  Right click / Esc cancels." % BUILD_LABEL[t], 3.0)
	ui()


func set_mode(m: String) -> void:
	sel_ship = 0
	mode = m
	_refresh_cards()


# ======================= input =======================

func zoom_at(f: float, c: Vector2) -> void:
	zoom_goal = clampf(zoom_goal * f, 0.6, 30.0)
	zoom_anchor = c


# Eases the real zoom toward zoom_goal around the anchor point (frame-rate independent, ~0.15 s).
func _step_zoom(delta: float) -> void:
	if absf(zoom_goal - zoom) < 0.0005:
		return
	var nz := lerpf(zoom, zoom_goal, 1.0 - exp(-16.0 * delta))
	if absf(nz - zoom_goal) < zoom_goal * 0.003:
		nz = zoom_goal
	var k := nz / zoom
	view_pos = zoom_anchor - (zoom_anchor - view_pos) * k
	zoom = nz


# ---- cursor: a small brass pointer / reticle (res://ui/cursor_*.png). Hotspots: arrow tip (2,2), reticle centre (16,16). ----
# F7 switches to the game-drawn fallback cursor (use it if a browser shows no / a wrong custom cursor). Not used on phones (no cursor there).
func _setup_cursor() -> void:
	if _mobile_browser():
		return
	cur_arrow = load("res://ui/cursor_arrow.png") as Texture2D if ResourceLoader.exists("res://ui/cursor_arrow.png") else null
	cur_cross = load("res://ui/cursor_cross.png") as Texture2D if ResourceLoader.exists("res://ui/cursor_cross.png") else null
	cur_hand = load("res://ui/cursor_hand.png") as Texture2D if ResourceLoader.exists("res://ui/cursor_hand.png") else null
	if cur_arrow == null or cur_cross == null:
		return   # images missing: the normal system cursor stays
	var layer := CanvasLayer.new()
	layer.layer = 120
	add_child(layer)
	var sc := SoftCursor.new()
	sc.main = self
	sc.tex_arrow = cur_arrow
	sc.tex_cross = cur_cross
	sc.visible = false
	layer.add_child(sc)
	cur_node = sc
	_apply_cursor()


func _apply_cursor() -> void:
	if cur_arrow == null or cur_node == null:
		return
	if cur_soft:
		Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
		cur_node.visible = true
	else:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		cur_node.visible = false
		Input.set_custom_mouse_cursor(cur_arrow, Input.CURSOR_ARROW, Vector2(2, 2))
		Input.set_custom_mouse_cursor(cur_cross, Input.CURSOR_CROSS, Vector2(16, 16))
		if cur_hand != null:
			Input.set_custom_mouse_cursor(cur_hand, Input.CURSOR_POINTING_HAND, Vector2(2, 2))


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and (event as InputEventKey).pressed and not (event as InputEventKey).echo and (event as InputEventKey).keycode == KEY_F7:
		cur_soft = not cur_soft
		_apply_cursor()
		return
	if event is InputEventKey and (event as InputEventKey).pressed and not (event as InputEventKey).echo and (event as InputEventKey).keycode == KEY_F3:
		_perf_toggle()
		return
	if phase == "lobby":
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_hide_ctx()
				drag = true
				drag_start = mb.position
				drag_view = view_pos
				drag_moved = false
			else:
				if drag and not drag_moved:
					_click(mb.position)
				drag = false
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_RIGHT:
			_hide_ctx()
			if sel_ship != 0 or mode != "attack":
				sel_ship = 0
				if mode != "attack":
					set_mode("attack")
					ui()
			elif phase == "play":
				var rt := _tile_at(mb.position)
				if rt >= 0 and land[rt] == 1 and own[rt] > 0 and own[rt] != my_slot and (players[own[rt]] as Player).alive:
					_open_ctx(mb.position, rt)
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom_at(1.15, mb.position)
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom_at(1.0 / 1.15, mb.position)
	elif event is InputEventMouseMotion and drag:
		var mm := event as InputEventMouseMotion
		var d := mm.position - drag_start
		if d.length() > 5.0:
			drag_moved = true
		if drag_moved:
			view_pos = drag_view + d
	elif event is InputEventMagnifyGesture:
		var mg := event as InputEventMagnifyGesture
		zoom_at(mg.factor, mg.position)
	elif event is InputEventKey:
		var ke := event as InputEventKey
		if ke.pressed and not ke.echo:
			var k := ke.keycode
			if k == KEY_1:
				_toggle_build("village")
			elif k == KEY_2:
				_toggle_build("station")
			elif k == KEY_3:
				_toggle_build("port")
			elif k == KEY_4:
				_toggle_build("warship")
			elif k == KEY_5:
				_toggle_build("mine")
			elif k == KEY_6:
				_toggle_build("silo")
			elif k == KEY_7:
				_toggle_build("sam")
			elif k == KEY_8:
				_toggle_build("atom")
			elif k == KEY_9:
				_toggle_build("nuke")
			elif k == KEY_0:
				_toggle_build("mega")
			elif k == KEY_ESCAPE:
				_hide_ctx()
				sel_ship = 0
				if mode != "attack":
					set_mode("attack")
					ui()


func _click(sp: Vector2) -> void:
	var x := int(floor((sp.x - view_pos.x) / zoom))
	var y := int(floor((sp.y - view_pos.y) / zoom))
	if x < 0 or y < 0 or x >= W or y >= H:
		return
	var i := y * W + x
	if spectating:
		_spec_follow(i)
		return
	if phase == "spawn":
		# nothing starts yet: the click only (re)sets where you will spawn when the countdown ends
		if land[i] == 0:
			return
		my_start = Vector2i(x, y)
		if online:
			_net_send({"t": "cmd", "c": {"type": "pick", "tile": i}})
			var lim_c := _human_lim()
			for hp in human_picks:
				if int(hp) == my_slot:
					continue
				var hv: Vector2i = human_picks[hp]
				if float((hv.x - x) * (hv.x - x) + (hv.y - y) * (hv.y - y)) < lim_c * lim_c:
					say("Too close to another player's start (white circle) - one of you would be moved. Pick further away.", 3.5, "bad")
					break
		return
	if phase == "play" and mode == "attack":
		if sel_ship != 0:
			var ss := _ship_by_id(sel_ship)
			if ss.is_empty():
				sel_ship = 0
			else:
				var other := _ship_at(i)
				if other == sel_ship:
					sel_ship = 0   # click the selected ship again: deselect
					return
				if other != 0:
					sel_ship = other
					return
				var eu := _enemy_unit_at(i)
				var shy := ""
				if eu != 0:
					shy = submit(my_slot, {"slot": my_slot, "type": "shipatk", "ship": sel_ship, "tgt": eu})
					if shy == "":
						say("Warship sent to intercept", 2.0, "good")
				else:
					shy = submit(my_slot, {"slot": my_slot, "type": "ship", "ship": sel_ship, "tile": i})
				if shy == "":
					sel_ship = 0
				else:
					say(shy, 2.5, "bad")
			return
		var shp := _ship_at(i)
		if shp != 0:
			sel_ship = shp
			say("Warship selected: click water to sail there, or an enemy boat / warship to attack it.  Right click / Esc cancels.", 4.0)
			return
	if phase == "play" and SEA_ORDER.has(mode):
		var swhy := submit(my_slot, {"slot": my_slot, "type": "sea", "kind": mode, "tile": i})
		if swhy == "":
			_fx_ring(Vector2(i % W + 0.5, i / W + 0.5), ACC, 0.7, 2.5)
			_card_pop(mode)
			say("%s placed" % BUILD_LABEL[mode], 2.5, "good")
			if not Input.is_key_pressed(KEY_SHIFT):
				set_mode("attack")
		else:
			if swhy.begins_with("Not enough gold"):
				_card_deny(mode)
			say(swhy, 2.5, "bad")
		ui()
		return
	if phase == "play" and NUKE_ORDER.has(mode):
		var nwhy := submit(my_slot, {"slot": my_slot, "type": "nuke", "kind": mode, "tile": i})
		if nwhy == "":
			_card_pop(mode)
			say("%s launched!" % String(BUILD_LABEL[mode]), 2.5, "good")
			if not Input.is_key_pressed(KEY_SHIFT):
				set_mode("attack")
		else:
			if nwhy.begins_with("Not enough gold"):
				_card_deny(mode)
			say(nwhy, 2.5, "bad")
		ui()
		return
	if phase == "play" and mode != "attack":
		var bcmd := {"slot": my_slot, "type": "build", "kind": mode, "tile": i}
		var why := validate(my_slot, bcmd)
		if why == "":
			var msg: String = "%s built" % BUILD_LABEL[mode]
			if occ.has(i):
				msg = _upgrade_label(mode, bld[occ[i]]) + "  -  done"   # worded BEFORE apply (the upgrade changes the building)
			var fxt: int = int(occ[i]) if occ.has(i) else i
			_exec(bcmd)
			_fx_ring(Vector2(fxt % W + 0.5, fxt / W + 0.5), ACC, 0.7, 3.0)
			_card_pop(mode)
			say(msg, 2.5, "good")
			if not Input.is_key_pressed(KEY_SHIFT):
				set_mode("attack")
		else:
			if why.begins_with("Not enough gold"):
				_card_deny(mode)
			say(why, 2.5, "bad")
		ui()
		return
	if phase != "play" or land[i] == 0 or own[i] == my_slot:
		return
	var f := slider.value / 100.0
	var acmd: Dictionary
	if owns_comp(my_slot, comp[i]):
		acmd = {"slot": my_slot, "type": "attack", "target": int(own[i]), "frac": f, "focus": Vector2(x + 0.5, y + 0.5)}
	else:
		acmd = {"slot": my_slot, "type": "boat", "tile": i, "frac": f}
	var awhy := submit(my_slot, acmd)
	if awhy != "":
		say(awhy, 2.5, "bad")


# ======================= ui =======================

func _tile_at(sp: Vector2) -> int:
	if _over_ui(sp):
		return -1
	var x := int(floor((sp.x - view_pos.x) / zoom))
	var y := int(floor((sp.y - view_pos.y) / zoom))
	if x < 0 or y < 0 or x >= W or y >= H:
		return -1
	return y * W + x


# The warship / trade ship under the mouse (read only, client only): {"kind", "owner", "ref"} or {}. Uses the same interpolation as
# _draw so it follows the moving ship, with a forgiving pixel radius. A warship wins over a trade ship when both are close.
func _hover_unit() -> Dictionary:
	var mp := get_viewport().get_mouse_position()
	if _over_ui(mp):
		return {}
	var f := clampf(acc / TICK, 0.0, 1.0)
	var best: Dictionary = {}
	var best_r := 1.0
	for s in ships:
		if int(s["hp"]) <= 0:
			continue
		var p0 := Vector2(int(s["pt"]) % W + 0.5, int(s["pt"]) / W + 0.5)
		var p1 := Vector2(int(s["t"]) % W + 0.5, int(s["t"]) / W + 0.5)
		var sp := view_pos + p0.lerp(p1, f) * zoom
		var rad := maxf(HOVER_SHIP_PX, maxf(16.0, zoom * 3.0) * 0.7)
		var q := sp.distance_to(mp) / rad
		if q < best_r:
			best_r = q
			best = {"kind": "ship", "owner": int(s["o"]), "ref": s}
	var trad := maxf(HOVER_SHIP_PX, maxf(8.0, zoom * 1.7) * 0.9)
	for tb in trade:
		var tpath: Array = tb["path"]
		var tkv := lerpf(float(tb["pk"]), float(tb["k"]), f)
		var tc: int = tpath[clampi(int(tkv + 0.5), 0, tpath.size() - 1)]   # nearest tile: at most half a tile off, so this margin never drops a hit
		if absf(view_pos.x + (float(tc % W) + 0.5) * zoom - mp.x) > trad + zoom or absf(view_pos.y + (float(tc / W) + 0.5) * zoom - mp.y) > trad + zoom:
			continue
		var tp := view_pos + _path_pos(tpath, tkv) * zoom
		var tq := tp.distance_to(mp) / trad + 0.05   # a tiny handicap so an overlapping warship wins
		if tq < best_r:
			best_r = tq
			best = {"kind": "trade", "owner": int(tb["o"]), "ref": tb}
	return best


# Top bar for a hovered ship: owner name (+ HP for a warship). Green when it is yours or an ally's (UI_GOOD, the same colour as the ALLY tag).
func _show_unit_info(hu: Dictionary) -> void:
	var o := int(hu["owner"])
	var pl: Player = players[o]
	var mine := o == my_slot
	var ally := (players[my_slot] as Player).allies.has(o)
	var col := UI_GOOD if (mine or ally) else Color.WHITE
	var ref: Dictionary = hu["ref"]
	info_o = -2   # the nation text must be rebuilt when the mouse goes back to the land
	info_t = 0.0
	info_sw.color = pl.col
	info_name.text = pl.nm
	if hu["kind"] == "ship":
		info_bld.text = "Warship   HP %d / %d" % [maxi(0, int(ref["hp"])), int(ref["mhp"])]
	else:
		info_bld.text = "Trade boat"
	info_troops.text = ""
	info_gold.text = ""
	info_ally.text = "YOURS" if mine else ("ALLY" if ally else "")
	info_name.add_theme_color_override("font_color", col)
	info_bld.add_theme_color_override("font_color", col)
	info_panel.visible = true


# Top bar: hover anybody's land to see their buildings, troops (now / max) and gold.
func _update_info(delta: float) -> void:
	var t0 := _pf0()
	_update_info_body(delta)
	_pf1("hover info", t0)


func _update_info_body(delta: float) -> void:
	if phase != "play" and phase != "over":
		info_panel.visible = false
		return
	var hu := _hover_unit()
	if not hu.is_empty():
		_show_unit_info(hu)
		return
	var i := _hover_tile()
	var o := 0
	if i >= 0 and land[i] == 1:
		o = own[i]
	if o <= 0:
		info_panel.visible = false
		info_o = -1
		return
	info_t -= delta
	if o == info_o and info_t > 0.0 and info_panel.visible:
		return
	info_o = o
	info_t = 0.2
	var pl: Player = players[o]
	var c: Dictionary = _counts_of(o)
	var parts: Array[String] = []
	for key in ["village", "city", "duchy", "station", "port", "silo", "sam"]:
		if int(c[key]) > 0:
			parts.append("%s %d" % [("SAM" if key == "sam" else String(key).capitalize()), int(c[key])])
	info_sw.color = pl.col
	info_name.text = pl.nm
	info_name.add_theme_color_override("font_color", Color.WHITE)
	info_bld.add_theme_color_override("font_color", UI_MUTED)
	info_ally.text = "ALLY" if (players[my_slot] as Player).allies.has(o) else ""
	info_bld.text = "   ".join(parts) if not parts.is_empty() else "No buildings"
	info_troops.text = "Troops %s / %s" % [_fmt(pl.troops / 10.0), _fmt(max_troops(pl, c) / 10.0)]
	info_gold.text = "Gold %s" % _fmt(pl.gold)
	info_panel.visible = true


func _cancel_between(a: int, b: int) -> void:
	var keep: Array = []
	for at in attacks:
		if (int(at["o"]) == a and int(at["t"]) == b) or (int(at["o"]) == b and int(at["t"]) == a):
			(players[int(at["o"])] as Player).troops += float(at["troops"])
		else:
			keep.append(at)
	attacks = keep
	atk_sig = ""


func _ally_make(t: int) -> void:
	var why := submit(my_slot, {"slot": my_slot, "type": "ally_ask", "target": t})
	if why != "":
		say(why, 2.5, "bad")
	ui()


func _ally_cancel(t: int) -> void:
	var why := submit(my_slot, {"slot": my_slot, "type": "ally_cancel", "target": t})
	if why != "":
		say(why, 2.5, "bad")
	ui()


func _hide_ctx() -> void:
	if ctx_panel != null:
		ctx_panel.visible = false


# Right-click menu on an enemy nation: alliance (green), cancel alliance (red), boat attack (blue), attack.
func _open_ctx(sp: Vector2, tile: int) -> void:
	if spectating:
		return
	var t: int = own[tile]
	var pl: Player = players[t]
	var me: Player = players[my_slot]
	var allied := me.allies.has(t)
	ctx_target = t
	ctx_tile = tile
	ctx_title.text = pl.nm
	ctx_title.add_theme_color_override("font_color", pl.col.lightened(0.3))
	var asked_me := tick_n < int(ally_req.get("%d_%d" % [t, my_slot], -1))
	var i_asked := tick_n < int(ally_req.get("%d_%d" % [my_slot, t], -1))
	ctx_make.text = "Accept alliance" if asked_me else "Make alliance"
	ctx_make.disabled = allied or (i_asked and not asked_me)
	if allied:
		ctx_make.tooltip_text = "Already allied"
	elif asked_me:
		ctx_make.tooltip_text = "%s asked you for an alliance - press to accept" % pl.nm
	elif i_asked:
		ctx_make.tooltip_text = "Request sent - waiting for %s to accept" % pl.nm
	else:
		ctx_make.tooltip_text = "Ask %s for an alliance" % pl.nm
	ctx_cancel.disabled = not allied
	ctx_cancel.tooltip_text = "End the alliance" if allied else "You have no alliance with %s" % pl.nm
	var tr_off := no_trade.has(my_slot * 1000 + t)
	ctx_trade.text = "Resume trade" if tr_off else "Cancel trade"
	if tr_off:
		ctx_trade.tooltip_text = "Let trade ships sail between you and %s again" % pl.nm
	elif no_trade.has(t * 1000 + my_slot):
		ctx_trade.tooltip_text = "%s already cancelled trade with you" % pl.nm
	else:
		ctx_trade.tooltip_text = "No trade ships between you and %s any more" % pl.nm
	var plan := _boat_plan(my_slot, tile)
	ctx_boat.disabled = allied or not plan.get("ok", false)
	ctx_boat.tooltip_text = "Cancel the alliance first" if allied else ("Send troops by sea" if plan.get("ok", false) else String(plan.get("why", "")))
	ctx_atk.disabled = allied or not owns_comp(my_slot, comp[tile])
	ctx_atk.tooltip_text = "Cancel the alliance first" if allied else ("Attack over land" if not ctx_atk.disabled else "Your land does not touch theirs - use the boat")
	ctx_panel.visible = true
	ctx_panel.position = sp + Vector2(8, 8)
	_clamp_ctx.call_deferred()


func _clamp_ctx() -> void:
	var vp := get_viewport_rect().size
	ctx_panel.position.x = clampf(ctx_panel.position.x, 4.0, maxf(4.0, vp.x - ctx_panel.size.x - 4.0))
	ctx_panel.position.y = clampf(ctx_panel.position.y, 4.0, maxf(4.0, vp.y - ctx_panel.size.y - 4.0))


func _ctx_do_make() -> void:
	_hide_ctx()
	_ally_make(ctx_target)


func _ctx_do_cancel() -> void:
	_hide_ctx()
	_ally_cancel(ctx_target)


func _ctx_do_trade() -> void:
	_hide_ctx()
	var off := no_trade.has(my_slot * 1000 + ctx_target)
	var twhy := submit(my_slot, {"slot": my_slot, "type": "trade_on" if off else "trade_off", "target": ctx_target})
	if twhy != "":
		say(twhy, 2.5, "bad")


func _ctx_do_boat() -> void:
	_hide_ctx()
	if own[ctx_tile] != ctx_target:
		say("That land changed hands - try again")
		return
	var bwhy := submit(my_slot, {"slot": my_slot, "type": "boat", "tile": ctx_tile, "frac": slider.value / 100.0})
	if bwhy == "":
		say("Boat launched against %s" % _aname(ctx_target), 2.5)
	else:
		say(bwhy, 2.5, "bad")


func _ctx_do_attack() -> void:
	_hide_ctx()
	var cwhy := submit(my_slot, {"slot": my_slot, "type": "attack", "target": ctx_target, "frac": slider.value / 100.0, "focus": Vector2(ctx_tile % W + 0.5, ctx_tile / W + 0.5)})
	if cwhy != "":
		say(cwhy, 2.5, "bad")


func _ctx_btn(text: String, col: Color) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.custom_minimum_size = Vector2(0, 26)
	b.add_theme_font_size_override("font_size", 12)
	var grey := Color("6b7680")
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		var sb := StyleBoxFlat.new()
		sb.set_corner_radius_all(6)
		sb.set_border_width_all(1)
		sb.content_margin_left = 9
		sb.content_margin_right = 9
		sb.content_margin_top = 3
		sb.content_margin_bottom = 3
		if state == "disabled":
			sb.bg_color = Color(0.16, 0.19, 0.22, 0.92)
			sb.border_color = Color(grey, 0.5)
		else:
			sb.bg_color = Color(col, 0.4 if (state == "hover" or state == "pressed") else 0.2)
			sb.border_color = col
		b.add_theme_stylebox_override(state, sb)
	b.add_theme_color_override("font_color", col.lightened(0.35))
	b.add_theme_color_override("font_focus_color", col.lightened(0.35))
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_color_override("font_pressed_color", Color.WHITE)
	b.add_theme_color_override("font_disabled_color", grey)
	_hover_fx(b, 1.02)
	return b


func _commas(v: int) -> String:
	var s := str(absi(v))
	var out := ""
	var n := s.length()
	for k in n:
		if k > 0 and (n - k) % 3 == 0:
			out += ","
		out += s[k]
	return ("-" if v < 0 else "") + out


func ui() -> void:
	var t0 := _pf0()
	_ui_body()
	_pf1("ui()", t0)


func _ui_body() -> void:
	if players.size() < 2:
		return
	var me: Player = players[my_slot]
	var mxt := max_troops(me, _counts_of(my_slot))
	troops_l.text = "%s / %s" % [_fmt(me.troops / 10.0), _fmt(mxt / 10.0)]
	troops_bar.value = clampf(me.troops / maxf(1.0, mxt), 0.0, 1.0)
	troops_rate.text = "+%s/s" % _fmt(me.grow / 10.0) if me.grow >= 1.0 else ""
	gold_rate.text = "+%s/s" % _fmt(GOLD_PER_OF_TICK * 10.0)
	share_l.text = "%.1f%%" % (me.tiles * 100.0 / land_count)
	gold_l.text = _fmt(me.gold)
	_refresh_cards()
	var alive: Array = []
	for i in range(1, N + 1):
		if (players[i] as Player).alive:
			alive.append(players[i])
	alive.sort_custom(func(a, b): return a.tiles > b.tiles)
	var shown := alive.slice(0, 6)
	# the leaderboard nodes are only rebuilt when what they show (names, share to 0.1%, my rank) actually changed
	var sig := "%d|" % alive.find(me)
	for sp in shown:
		sig += "%s:%d," % [(sp as Player).nm, int((sp as Player).tiles * 1000 / maxi(1, land_count))]
	sig += "%d" % int(me.tiles * 1000 / maxi(1, land_count))
	if sig == lb_sig and lb_box.get_child_count() > 0:
		return
	lb_sig = sig
	for c in lb_box.get_children():
		c.queue_free()
	lb_box.add_theme_constant_override("separation", 1)
	lb_box.add_child(_small_label("LEADERBOARD", 9, UI_MUTED))
	for k in shown.size():
		_lb_row(k + 1, shown[k], me)
	var my_rank := alive.find(me)
	if my_rank >= 6:
		lb_box.add_child(_small_label("...", 10, UI_MUTED))
		_lb_row(my_rank + 1, me, me)


func _lb_row(rank: int, p: Player, me: Player) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 5)
	var rk := _small_label(str(rank), 10, UI_MUTED)
	rk.custom_minimum_size = Vector2(10, 0)
	row.add_child(rk)
	var sw := ColorRect.new()
	sw.color = p.col
	sw.custom_minimum_size = Vector2(8, 8)
	sw.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(sw)
	var nl := Label.new()
	nl.text = p.nm
	nl.clip_text = true
	nl.add_theme_font_size_override("font_size", 11)
	nl.add_theme_color_override("font_color", ACC if p == me else UI_TEXT)
	nl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(nl)
	var pl := Label.new()
	pl.text = "%.1f%%" % (p.tiles * 100.0 / land_count)
	pl.add_theme_font_size_override("font_size", 11)
	pl.add_theme_color_override("font_color", ACC if p == me else UI_MUTED)
	row.add_child(pl)
	lb_box.add_child(row)


func _refresh_cards() -> void:
	if cards.is_empty() or players.size() < 2:
		return
	var me: Player = players[my_slot]
	var c: Dictionary = _counts_of(my_slot)
	var has_port := _has_port(my_slot)
	for t in BUILD_ORDER + DEFENSE_ORDER + SEA_ORDER + NUKE_ORDER:
		var card: Dictionary = cards[t]
		var cost := price(my_slot, t)
		var sea: bool = SEA_ORDER.has(t)
		var bomb: bool = NUKE_ORDER.has(t)
		var locked: bool = (sea and not has_port) or (bomb and not _silo_ready(my_slot, int(BOMB_NEED_LEVEL[t])))
		(card["price"] as Label).text = ("needs port" if sea else "launcher Lv%d" % int(BOMB_NEED_LEVEL[t])) if locked else "%s gold" % _fmt(cost)
		var can_pay: bool = me.gold >= cost and not locked
		(card["price"] as Label).add_theme_color_override("font_color", ACC if can_pay else UI_BAD)
		var owned := 0
		if t == "warship":
			for s in ships:
				if int(s["o"]) == my_slot:
					owned += 1
		elif t == "mine":
			for m in mines:
				if int(m["o"]) == my_slot:
					owned += 1
		elif bomb:
			owned = 0
		else:
			owned = int(c[t])
			if t == "village":
				owned += int(c["city"]) + int(c["duchy"])
		(card["count"] as Label).text = "\u00d7%d" % owned if owned > 0 else ""
		var tip: String = BUILD_TIP[t]
		if locked:
			tip += ("\n\nNeeds a ready Bomb Launcher of level %d or higher." % int(BOMB_NEED_LEVEL[t])) if bomb else "\n\nNeeds a port first."
		elif not can_pay:
			tip += "\n\nNot enough gold yet."
		(card["btn"] as Button).tooltip_text = tip
		(card["btn"] as Button).modulate = Color(1, 1, 1, 0.5) if locked else (Color(1, 1, 1, 1) if can_pay else Color(0.80, 0.82, 0.86, 1))
		_style_card(card["btn"], mode == t)
	if sub_panel.visible:
		_place_sub()
	if nuke_panel.visible:
		_place_nuke()


# Sea-units menu (warship / mine) that pops up above the card bar when the Port arrow is pressed.
func _toggle_sub() -> void:
	if phase != "play":
		return
	sub_open = not sub_open
	sub_panel.visible = sub_open
	arrow_btn.open = sub_open
	arrow_btn.queue_redraw()
	if sub_open and nuke_open:   # only one popup at a time
		nuke_open = false
		nuke_panel.visible = false
		launcher_arrow.open = false
		launcher_arrow.queue_redraw()
		if NUKE_ORDER.has(mode):
			set_mode("attack")
	if not sub_open and SEA_ORDER.has(mode):
		set_mode("attack")
	_place_sub.call_deferred()
	_refresh_attacks.call_deferred()


# Bombs menu (Small Bomb / Nuke / Mega Bomb) that pops up above the card bar when the Bomb Launcher arrow is pressed.
func _toggle_nuke() -> void:
	if phase != "play":
		return
	nuke_open = not nuke_open
	nuke_panel.visible = nuke_open
	launcher_arrow.open = nuke_open
	launcher_arrow.queue_redraw()
	if nuke_open and sub_open:
		sub_open = false
		sub_panel.visible = false
		arrow_btn.open = false
		arrow_btn.queue_redraw()
		if SEA_ORDER.has(mode):
			set_mode("attack")
	if not nuke_open and NUKE_ORDER.has(mode):
		set_mode("attack")
	_place_nuke.call_deferred()
	_refresh_attacks.call_deferred()


func _place_nuke() -> void:
	if nuke_panel == null or not nuke_panel.visible:
		return
	# the popup opens right above the card whose arrow was pressed (kept inside the window)
	var nx := (cards["silo"]["btn"] as Control).global_position.x
	nuke_panel.position = Vector2(clampf(nx, 4.0, maxf(4.0, get_viewport_rect().size.x - nuke_panel.size.x - 4.0)), ctl.global_position.y - nuke_panel.size.y - 8.0)


func _place_sub() -> void:
	if sub_panel == null or not sub_panel.visible:
		return
	var sx := (cards["port"]["btn"] as Control).global_position.x
	sub_panel.position = Vector2(clampf(sx, 4.0, maxf(4.0, get_viewport_rect().size.x - sub_panel.size.x - 4.0)), ctl.global_position.y - sub_panel.size.y - 8.0)


func _style_arrow(b: Button) -> void:
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.24, 0.17, 0.08, 0.98) if state == "hover" else Color(0.13, 0.10, 0.06, 0.98)
		sb.set_corner_radius_all(5)
		sb.set_border_width_all(1)
		sb.border_color = ACC
		b.add_theme_stylebox_override(state, sb)


func _atk_row(a: Dictionary, kind: String) -> void:
	var incoming := kind == "incoming"
	var col: Color = RED if incoming else BLUE
	var pc := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(col, 0.10)
	sb.border_color = col
	sb.border_width_left = 3
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 10
	sb.content_margin_right = 4
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	pc.add_theme_stylebox_override("panel", sb)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	pc.add_child(row)
	var vb := VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_theme_constant_override("separation", -2)
	var title := ""
	if kind == "boat":
		title = "Boat to %s" % _aname(own[int(a["i"])])
	elif incoming:
		title = "%s attacks you" % _aname(int(a["o"]))
	else:
		title = "Attacking %s" % _aname(int(a["t"]))
	vb.add_child(_small_label(title, 12, col))
	var sub := _small_label("", 9, UI_MUTED)
	vb.add_child(sub)
	row.add_child(vb)
	var tl := _small_label("", 12, Color.WHITE)
	tl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(tl)
	var btn := IconBtn.new()
	btn.custom_minimum_size = Vector2(atk_btn_px, atk_btn_px)
	btn.focus_mode = Control.FOCUS_NONE
	btn.flat = true
	btn.col = col
	if incoming:
		btn.kind = "sword"
		btn.tooltip_text = "Counter-attack"
		btn.pressed.connect(_counter_attack.bind(a))
	else:
		btn.kind = "x"
		btn.tooltip_text = "Cancel"
		btn.pressed.connect(_cancel_attack.bind(a))
	row.add_child(btn)
	atk_box.add_child(pc)
	atk_lbls[kind + str(int(a.get("id", 0)))] = {"tl": tl, "sub": sub, "a": a, "kind": kind}


# X: stop one of your attacks (or recall a boat) and get the unspent troops back.
func _cancel_attack(a: Dictionary) -> void:
	var back := int(a["troops"])   # read before the command removes it
	var why := submit(my_slot, {"slot": my_slot, "type": "cancel", "id": int(a["id"])})
	if why != "":
		return   # already finished / not mine: nothing to do
	say("Attack cancelled - %d troops returned" % back, 2.5)
	atk_sig = ""
	_refresh_attacks.call_deferred()
	ui()


# Sword: answer an incoming attack by hitting back at the attacker, at the front line where they are striking.
func _counter_attack(a: Dictionary) -> void:
	var o := int(a["o"])
	if not (players[o] as Player).alive:
		return
	var why := submit(my_slot, {"slot": my_slot, "type": "attack", "target": o, "frac": slider.value / 100.0, "focus": a.get("pos", Vector2(-1.0, -1.0))})
	if why == "":
		say("Counter-attack launched on %s" % _aname(o), 2.5)
	else:
		say(why, 2.5, "bad")
	atk_sig = ""
	_refresh_attacks.call_deferred()
	ui()


# Left-hand list: blue rows = attacks you launched (X cancels), red rows = attacks against you (sword counters).
func _refresh_attacks() -> void:
	if atk_box == null or players.size() < 2 or phase == "lobby":
		return
	var rows: Array = []
	for a in attacks:
		if int(a["o"]) == my_slot:
			rows.append(["mine", a])
		elif int(a["t"]) == my_slot:
			rows.append(["incoming", a])
	for b in boats:
		if int(b["o"]) == my_slot:
			rows.append(["boat", b])
	# incoming attacks first (they need an answer), then yours, then boats; never let the list grow into the card bar
	var ordered: Array = []
	for kn in ["incoming", "mine", "boat"]:
		for r in rows:
			if r[0] == kn:
				ordered.append(r)
	rows = ordered
	var floor_y := ctl.position.y
	for pop in [sub_panel, nuke_panel]:
		if pop != null and (pop as Control).visible:
			floor_y = minf(floor_y, (pop as Control).position.y - 4.0)   # the list stops above an open popup instead of running under it
	var avail := floor_y - (hud.position.y + hud.size.y + 8.0) - 44.0
	var max_rows := maxi(2, int(avail / 50.0))
	var hidden := maxi(0, rows.size() - max_rows)
	if hidden > 0:
		rows = rows.slice(0, max_rows)
	var sig := "+%d|" % hidden
	for r in rows:
		var rd: Dictionary = r[1]
		sig += "%s%d," % [r[0], int(rd.get("id", 0))]
	if sig != atk_sig:
		atk_sig = sig
		atk_lbls = {}
		for ch in atk_box.get_children():
			atk_box.remove_child(ch)
			ch.queue_free()
		atk_box.add_theme_constant_override("separation", 5)
		atk_box.add_child(_small_label("ATTACKS", 11, UI_MUTED))
		for r in rows:
			_atk_row(r[1], r[0])
		if hidden > 0:
			atk_box.add_child(_small_label("+%d more attacks" % hidden, 12, UI_MUTED))
	for key in atk_lbls:
		var e: Dictionary = atk_lbls[key]
		var ad: Dictionary = e["a"]
		(e["tl"] as Label).text = _fmt(float(ad["troops"]) / 10.0)
		if e["kind"] == "boat":
			(e["sub"] as Label).text = "At sea"
		else:
			(e["sub"] as Label).text = "%s  -  %d tiles" % [STAGE_NAMES[clampi(int(ad.get("stage", 0)), 0, 2)], int(ad.get("gained", 0))]
	atk_panel.visible = rows.size() > 0
	if atk_panel.visible:
		atk_panel.position = Vector2(float(UI_MARGIN) + safe_cur.x, hud.position.y + hud.size.y + 8.0)


func say(t: String, secs: float = 2.5, kind: String = "info") -> void:
	msg_label.text = t
	# kind: "info" (default), "good" (success) or "bad" (invalid action / not enough gold) - only tints text and border
	var col := UI_TEXT
	var edge := UI_LINE
	if kind == "good":
		col = UI_GOOD
		edge = Color(UI_GOOD, 0.55)
	elif kind == "bad":
		col = UI_BAD
		edge = Color(UI_BAD, 0.60)
	msg_label.add_theme_color_override("font_color", col)
	var sbx := msg_panel.get_theme_stylebox("panel")
	if sbx is HistBox:
		(sbx as HistBox).set_edge(UI_BRASS if kind == "info" else (UI_GOOD if kind == "good" else UI_BAD))
	elif sbx is StyleBoxFlat:
		(sbx as StyleBoxFlat).border_color = edge
		(sbx as StyleBoxFlat).set_border_width_all(1 if kind == "info" else 2)
	msg_panel.visible = true
	# short pop so a new message is noticed even when the previous one is still showing
	if msg_panel.has_meta("pop_tw"):
		var old_tw: Variant = msg_panel.get_meta("pop_tw")
		if old_tw is Tween and (old_tw as Tween).is_valid():
			(old_tw as Tween).kill()
	msg_panel.pivot_offset = msg_panel.size / 2.0
	msg_panel.scale = Vector2(0.95, 0.95)
	var ptw := msg_panel.create_tween()
	ptw.set_trans(Tween.TRANS_BACK)
	ptw.set_ease(Tween.EASE_OUT)
	ptw.tween_property(msg_panel, "scale", Vector2.ONE, 0.16)
	msg_panel.set_meta("pop_tw", ptw)
	msg_token += 1
	var tok := msg_token
	await get_tree().create_timer(secs).timeout
	if tok == msg_token and phase == "play":
		msg_panel.visible = false


# Card feedback: a quick pop after a successful purchase, a short shake when you cannot pay / cannot build.
# Purely visual; the card keeps its price and purchase logic.
func _card_fx_tween(b: Control) -> Tween:
	if b.has_meta("fb_tw"):
		var old: Variant = b.get_meta("fb_tw")
		if old is Tween and (old as Tween).is_valid():
			(old as Tween).kill()
	b.pivot_offset = b.size / 2.0
	var tw := b.create_tween()
	b.set_meta("fb_tw", tw)
	return tw


func _card_pop(t: String) -> void:
	if not cards.has(t):
		return
	var b: Control = cards[t]["btn"]
	var tw := _card_fx_tween(b)
	tw.set_trans(Tween.TRANS_CUBIC)
	tw.set_ease(Tween.EASE_OUT)
	tw.tween_property(b, "scale", Vector2.ONE * 1.10, 0.08)
	tw.tween_property(b, "scale", Vector2.ONE, 0.16)


func _card_deny(t: String) -> void:
	if not cards.has(t):
		return
	var b: Control = cards[t]["btn"]
	var tw := _card_fx_tween(b)
	for r in [0.05, -0.05, 0.03, 0.0]:
		tw.tween_property(b, "rotation", r, 0.05)


# One Theme for the whole window: bundled antique typefaces, parchment tooltips, engraved text fields, a brass attack slider.
func _make_theme() -> void:
	var body_f: Font = null
	var title_f: Font = null
	if ResourceLoader.exists("res://fonts/Lora-Variable.ttf"):
		body_f = load("res://fonts/Lora-Variable.ttf") as Font
	if ResourceLoader.exists("res://fonts/GFSBaskerville.otf"):
		title_f = load("res://fonts/GFSBaskerville.otf") as Font
	if body_f == null:   # fonts not imported yet / missing: a system serif (browsers fall back to their default)
		var sf := SystemFont.new()
		sf.font_names = PackedStringArray(["Georgia", "Palatino Linotype", "Book Antiqua", "Cambria", "Times New Roman", "serif"])
		sf.hinting = TextServer.HINTING_LIGHT
		body_f = sf
	ui_font = body_f
	var bold := FontVariation.new()
	bold.base_font = body_f
	bold.variation_opentype = {2003265652: 650.0}   # 'wght' axis of the variable Lora (ignored by fonts without it)
	ui_bold_font = bold
	if title_f != null:
		var tv := FontVariation.new()
		tv.base_font = title_f
		tv.spacing_glyph = 1
		ui_title_font = tv
	else:
		ui_title_font = body_f
	var th := Theme.new()
	th.default_font = body_f
	th.default_font_size = 14
	th.set_color("font_color", "Label", UI_TEXT)
	# tooltips: small parchment cards
	var tip := StyleBoxFlat.new()
	tip.bg_color = Color("efe2bf")
	tip.border_color = UI_BRASS
	tip.set_border_width_all(1)
	tip.set_corner_radius_all(2)
	tip.content_margin_left = 10
	tip.content_margin_right = 10
	tip.content_margin_top = 6
	tip.content_margin_bottom = 6
	th.set_stylebox("panel", "TooltipPanel", tip)
	th.set_color("font_color", "TooltipLabel", UI_INK)
	th.set_font_size("font_size", "TooltipLabel", 13)
	# text fields (lobby): dark ink with a brass line, gold when focused
	var le := StyleBoxFlat.new()
	le.bg_color = Color(0.03, 0.055, 0.095, 0.96)
	le.border_color = UI_BRASS
	le.set_border_width_all(1)
	le.set_corner_radius_all(2)
	le.content_margin_left = 8
	le.content_margin_right = 8
	le.content_margin_top = 4
	le.content_margin_bottom = 4
	var lef := le.duplicate() as StyleBoxFlat
	lef.border_color = ACC
	lef.set_border_width_all(2)
	th.set_stylebox("normal", "LineEdit", le)
	th.set_stylebox("read_only", "LineEdit", le)
	th.set_stylebox("focus", "LineEdit", lef)
	th.set_color("font_color", "LineEdit", UI_TEXT)
	th.set_color("font_placeholder_color", "LineEdit", UI_MUTED)
	th.set_color("caret_color", "LineEdit", ACC)
	th.set_color("selection_color", "LineEdit", Color(ACC, 0.35))
	# attack slider: thin brass track, gold fill, round gold handle
	var track := StyleBoxFlat.new()
	track.bg_color = Color(0.85, 0.67, 0.31, 0.16)
	track.set_corner_radius_all(2)
	track.content_margin_top = 3
	track.content_margin_bottom = 3
	var fill := StyleBoxFlat.new()
	fill.bg_color = ACC
	fill.set_corner_radius_all(2)
	fill.content_margin_top = 3
	fill.content_margin_bottom = 3
	th.set_stylebox("slider", "HSlider", track)
	th.set_stylebox("grabber_area", "HSlider", fill)
	th.set_stylebox("grabber_area_highlight", "HSlider", fill)
	for nm in ["grabber", "grabber_highlight"]:
		var g := Gradient.new()
		g.offsets = PackedFloat32Array([0.0, 0.80, 0.92, 1.0])
		var ring := ACC.lightened(0.25) if nm == "grabber_highlight" else ACC
		g.colors = PackedColorArray([ring, ring, Color(ring, 0.35), Color(ring, 0.0)])
		var gt := GradientTexture2D.new()
		gt.gradient = g
		gt.fill = GradientTexture2D.FILL_RADIAL
		gt.fill_from = Vector2(0.5, 0.5)
		gt.fill_to = Vector2(1.0, 0.5)
		gt.width = 22
		gt.height = 22
		th.set_icon(nm, "HSlider", gt)
	get_window().theme = th


func _panel() -> PanelContainer:
	var pc := PanelContainer.new()
	var hb := HistBox.new()
	hb.fill = UI_NAVY
	hb.edge = UI_BRASS
	hb.content_margin_left = 10.0
	hb.content_margin_right = 10.0
	hb.content_margin_top = 8.0
	hb.content_margin_bottom = 8.0
	pc.add_theme_stylebox_override("panel", hb)
	return pc


# primary = solid brass action button, otherwise a quiet navy button with a brass hairline (zoom +/-, spectate)
func _style_button(b: Button, primary: bool = true) -> void:
	for state in ["normal", "hover", "pressed", "disabled"]:
		var sb := StyleBoxFlat.new()
		if primary:
			sb.bg_color = Color("c9993f")
			if state == "hover":
				sb.bg_color = Color("c9993f").lightened(0.14)
			elif state == "pressed":
				sb.bg_color = Color("c9993f").darkened(0.16)
			elif state == "disabled":
				sb.bg_color = Color(0.79, 0.60, 0.25, 0.40)
			sb.border_color = Color("7a5a22")
			sb.set_border_width_all(1)
		else:
			sb.bg_color = Color(0.05, 0.085, 0.14, 0.92)
			if state == "hover":
				sb.bg_color = Color(0.11, 0.14, 0.20, 0.96)
			elif state == "pressed":
				sb.bg_color = Color(0.02, 0.04, 0.08, 0.96)
			sb.border_color = UI_BRASS if state != "hover" else ACC
			sb.set_border_width_all(1)
		sb.set_corner_radius_all(3)
		sb.content_margin_left = 10
		sb.content_margin_right = 10
		sb.content_margin_top = 4
		sb.content_margin_bottom = 4
		b.add_theme_stylebox_override(state, sb)
	var fc := UI_INK if primary else UI_TEXT
	for cn in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_disabled_color"]:
		b.add_theme_color_override(cn, fc)
	if ui_bold_font != null:
		b.add_theme_font_override("font", ui_bold_font)
	_hover_fx(b, 1.03)


func _style_card(b: Button, selected: bool) -> void:
	if b.has_meta("sel") and bool(b.get_meta("sel")) == selected:
		return   # unchanged since the last refresh: don't rebuild the styles
	b.set_meta("sel", selected)
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		var sb := StyleBoxFlat.new()
		var base := Color(0.055, 0.09, 0.15, 0.96)
		if selected:
			base = UI_BURGUNDY
		if state == "hover":
			base = base.lightened(0.10)
		elif state == "pressed":
			base = base.darkened(0.10)
		sb.bg_color = base
		sb.set_corner_radius_all(3)
		sb.set_border_width_all(2 if selected else 1)
		sb.border_color = ACC if selected else (ACC if state == "hover" else UI_BRASS)
		if selected:
			sb.shadow_color = Color(ACC, 0.22)
			sb.shadow_size = 6
		b.add_theme_stylebox_override(state, sb)


# HUD stat: thin coloured bar, small caps title, big value and (optionally) a small rate on the right.
func _stat(v: VBoxContainer, title: String, accent: Color = ACC) -> Label:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var bar := ColorRect.new()
	bar.color = accent
	bar.custom_minimum_size = Vector2(3, 0)
	row.add_child(bar)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", -2)
	var s := Label.new()
	s.text = title.to_upper()
	s.add_theme_font_size_override("font_size", 10)
	s.add_theme_color_override("font_color", UI_MUTED)
	if ui_title_font != null:
		s.add_theme_font_override("font", ui_title_font)
	col.add_child(s)
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 6)
	var l := Label.new()
	l.text = "-"
	l.add_theme_font_size_override("font_size", 16)
	if ui_bold_font != null:
		l.add_theme_font_override("font", ui_bold_font)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.add_child(l)
	var r := Label.new()
	r.add_theme_font_size_override("font_size", 10)
	r.add_theme_color_override("font_color", UI_GOOD)
	r.size_flags_vertical = Control.SIZE_SHRINK_END
	line.add_child(r)
	_last_rate_lbl = r
	col.add_child(line)
	row.add_child(col)
	v.add_child(row)
	return l


# Smooth hover / press scale for buttons and cards (purely visual, never changes layout).
func _hover_fx(b: Control, grow: float = 1.04) -> void:
	if b.has_meta("fx"):
		return
	b.set_meta("fx", true)
	b.resized.connect(func(): b.pivot_offset = b.size / 2.0)
	b.mouse_entered.connect(func():
		if b is BaseButton and (b as BaseButton).disabled:
			return
		_tween_scale(b, Vector2.ONE * grow, 0.12))
	b.mouse_exited.connect(func(): _tween_scale(b, Vector2.ONE, 0.12))
	if b is BaseButton:
		(b as BaseButton).button_down.connect(func(): _tween_scale(b, Vector2.ONE * 0.97, 0.06))
		(b as BaseButton).button_up.connect(func(): _tween_scale(b, Vector2.ONE * grow, 0.10))


func _tween_scale(c: Control, to: Vector2, t: float) -> void:
	if c.has_meta("sc_tw"):
		var old: Variant = c.get_meta("sc_tw")
		if old is Tween and (old as Tween).is_valid():
			(old as Tween).kill()
	var tw := c.create_tween()
	tw.set_trans(Tween.TRANS_CUBIC)
	tw.set_ease(Tween.EASE_OUT)
	tw.tween_property(c, "scale", to, t)
	c.set_meta("sc_tw", tw)


# Panels fade in whenever the game really shows them (hover info, attack list, menus, messages).
func _panel_fade(p: Control) -> void:
	if not p.visible:
		return
	p.modulate.a = 0.0
	var tw := p.create_tween()
	tw.set_trans(Tween.TRANS_CUBIC)
	tw.set_ease(Tween.EASE_OUT)
	tw.tween_property(p, "modulate:a", 1.0, 0.16)


# One look for every progress bar (HUD troop bar, lobby fill bar).
func _style_bar(bar: ProgressBar, fill_col: Color, radius: int) -> void:
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.85, 0.67, 0.31, 0.14)
	bg.set_corner_radius_all(radius)
	var fl := StyleBoxFlat.new()
	fl.bg_color = fill_col
	fl.set_corner_radius_all(radius)
	bar.add_theme_stylebox_override("background", bg)
	bar.add_theme_stylebox_override("fill", fl)


func _small_label(text: String, size: int, col: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if ui_title_font != null and text.length() > 3 and text == text.to_upper() and text != text.to_lower():
		l.add_theme_font_override("font", ui_title_font)   # ALL-CAPS headings (LEADERBOARD, ATTACKS, LANDGRAB ...) are set in Baskerville
	return l


func _make_card(t: String, hotkey: int) -> Dictionary:
	var b := Button.new()
	b.custom_minimum_size = Vector2(64, 62)   # _compact_ui() sets the real size (touch / narrow windows)
	b.tooltip_text = BUILD_TIP[t]
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(_toggle_build.bind(t))
	_hover_fx(b, 1.04)
	var v := VBoxContainer.new()
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 0)
	b.add_child(v)
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var ic := BldIcon.new()
	ic.main = self
	ic.kind = t
	ic.custom_minimum_size = Vector2(0, 26)
	ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(ic)
	var nm := _small_label(CARD_SHORT.get(t, BUILD_LABEL[t]), 10, UI_TEXT)
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nm.clip_text = true
	v.add_child(nm)
	var pr := _small_label("", 10, ACC)
	pr.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pr.clip_text = true
	v.add_child(pr)
	# small hotkey badge top-left, owned count top-right (primary info stays the name and the price)
	var hk := _small_label(str(hotkey), 9, UI_MUTED)
	hk.position = Vector2(5, 2)
	b.add_child(hk)
	var cn := _small_label("", 10, ACC)
	cn.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	cn.anchor_left = 1.0
	cn.anchor_right = 1.0
	cn.offset_left = -30.0
	cn.offset_right = -5.0
	cn.offset_top = 2.0
	b.add_child(cn)
	_style_card(b, false)
	return {"btn": b, "price": pr, "count": cn}


func _build_lobby_ui(root: Control) -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.032, 0.062, 0.105)
	root.add_child(bg)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var cc := CenterContainer.new()
	root.add_child(cc)
	cc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	cc.add_child(col)
	var title := _small_label("LANDGRAB", 40, ACC)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)
	col.add_child(HistRule.new())
	var sub := _small_label("Public lobbies  -  a new map every 2 minutes", 12, UI_MUTED)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(sub)
	var card := _panel()
	card.custom_minimum_size = Vector2(620, 0)
	col.add_child(card)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	card.add_child(row)
	preview_rect = TextureRect.new()
	preview_rect.custom_minimum_size = Vector2(290, 174)
	preview_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	preview_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	row.add_child(preview_rect)
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 8)
	row.add_child(right)
	lb_map = _small_label("", 22, UI_TEXT)
	if ui_title_font != null:
		lb_map.add_theme_font_override("font", ui_title_font)
	right.add_child(lb_map)
	lb_info = _small_label("", 11, UI_MUTED)
	right.add_child(lb_info)
	lb_players = _small_label("", 12, UI_TEXT)
	right.add_child(lb_players)
	lb_bar = ProgressBar.new()
	lb_bar.show_percentage = false
	lb_bar.custom_minimum_size = Vector2(0, 10)
	_style_bar(lb_bar, ACC, 6)
	right.add_child(lb_bar)
	lb_time = _small_label("", 18, ACC)
	right.add_child(lb_time)
	var hint := _small_label("Starts right away when every slot is filled.", 10, UI_MUTED)
	right.add_child(hint)
	var sp := Control.new()
	sp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(sp)
	lb_join = Button.new()
	lb_join.custom_minimum_size = Vector2(0, 38)
	lb_join.add_theme_font_size_override("font_size", 16)
	_style_button(lb_join)
	lb_join.pressed.connect(_lobby_join)
	right.add_child(lb_join)
	lb_spec = Button.new()
	lb_spec.text = "Spectate  (watch the bots play)"
	lb_spec.custom_minimum_size = Vector2(0, 30)
	_style_button(lb_spec, false)
	lb_spec.pressed.connect(_lobby_spectate)
	right.add_child(lb_spec)
	lb_next = _small_label("", 11, UI_MUTED)
	lb_next.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(lb_next)
	lb_note = _small_label("", 11, Color("e8a95f"))
	lb_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(lb_note)
	# online play: your name, a room name your friends also type, and the relay server's address
	var orow := HFlowContainer.new()   # wraps onto a second line when the screen is narrow (phones) instead of running off the edge
	orow.alignment = FlowContainer.ALIGNMENT_CENTER
	orow.add_theme_constant_override("h_separation", 8)
	orow.add_theme_constant_override("v_separation", 8)
	col.add_child(orow)
	var eh := 46 if _mobile_browser() else 32   # bigger touch targets on phones
	net_name_edit = LineEdit.new()
	net_name_edit.placeholder_text = "Your name"
	net_name_edit.text = "Player"
	net_name_edit.max_length = 16
	net_name_edit.custom_minimum_size = Vector2(120, eh)
	orow.add_child(net_name_edit)
	_mobile_edit(net_name_edit, "Your name")
	net_room_edit = LineEdit.new()
	net_room_edit.placeholder_text = "Private room code"
	net_room_edit.text = ""
	net_room_edit.max_length = 16
	net_room_edit.custom_minimum_size = Vector2(110, eh)
	orow.add_child(net_room_edit)
	_mobile_edit(net_room_edit, "Private room code")
	var room_paste := _paste_button(net_room_edit, "Private room code", eh)
	orow.add_child(room_paste)
	net_server_edit = LineEdit.new()
	net_server_edit.placeholder_text = "wss://server address"
	net_server_edit.text = DEFAULT_SERVER
	net_server_edit.custom_minimum_size = Vector2(230, eh)
	net_server_edit.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_URL
	orow.add_child(net_server_edit)
	_mobile_edit(net_server_edit, "Server address (wss://...)")
	var server_paste := _paste_button(net_server_edit, "Server address (wss://...)", eh)
	orow.add_child(server_paste)
	net_btn = Button.new()
	net_btn.text = "Private room"
	net_btn.custom_minimum_size = Vector2(120, eh)
	_style_button(net_btn)
	net_btn.pressed.connect(_net_button)
	orow.add_child(net_btn)
	net_map_btn = Button.new()
	net_map_btn.text = "Change map"
	net_map_btn.custom_minimum_size = Vector2(100, eh)
	net_map_btn.visible = false
	_style_button(net_map_btn)
	net_map_btn.pressed.connect(_net_next_map)
	orow.add_child(net_map_btn)
	_net_load_settings()


# ---- text input on phones / tablets (web export) ----
# A browser only opens the on-screen keyboard (and the paste menu) when a text field is focused INSIDE the tap itself. Godot's canvas
# handles the tap one frame later, so on iPhone and Android the keyboard never appears. A phone browser therefore uses the browser's own
# input box (window.prompt): it always shows the keyboard and has a native paste option. Desktop and native builds are untouched.
func _mobile_browser() -> bool:
	if mob_cache < 0:
		mob_cache = 0
		if OS.has_feature("web"):
			if OS.has_feature("web_android") or OS.has_feature("web_ios"):
				mob_cache = 1
			else:
				var r: Variant = JavaScriptBridge.eval("(/Android|iPhone|iPad|iPod|Mobile/i.test(navigator.userAgent) || (navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1))")
				mob_cache = 1 if (r != null and bool(r)) else 0
	return mob_cache == 1


func _mobile_edit(le: LineEdit, title: String) -> void:
	if not _mobile_browser():
		return
	le.virtual_keyboard_enabled = false   # Godot's own keyboard request cannot work here (see above)
	le.focus_entered.connect(func(): _mobile_prompt.call_deferred(le, title))


func _mobile_prompt(le: LineEdit, title: String) -> void:
	le.release_focus()
	var r: Variant = JavaScriptBridge.eval("window.prompt(%s, %s)" % [JSON.stringify(title), JSON.stringify(le.text)])
	if r == null:   # cancelled
		return
	var txt := String(r).strip_edges()
	if le.max_length > 0:
		txt = txt.left(le.max_length)
	le.text = txt
	le.caret_column = txt.length()
	le.text_changed.emit(txt)


# "Paste" button: reads the clipboard (browser asks for permission once); if the browser refuses, the input box opens so you can paste there.
func _paste_button(le: LineEdit, title: String, h: int) -> Button:
	var b := Button.new()
	b.text = "Paste"
	b.custom_minimum_size = Vector2(54, h)
	b.focus_mode = Control.FOCUS_NONE
	_style_button(b, false)
	b.pressed.connect(_paste_into.bind(le, title))
	return b


func _paste_into(le: LineEdit, title: String) -> void:
	if not OS.has_feature("web"):
		le.text = DisplayServer.clipboard_get().strip_edges()
		le.text_changed.emit(le.text)
		return
	paste_target = le
	var nav: Variant = JavaScriptBridge.get_interface("navigator")   # untyped on purpose: JavaScript objects are called dynamically
	var clip: Variant = null
	if nav != null:
		clip = nav.clipboard
	if clip == null:
		_mobile_prompt(le, title)
		return
	if paste_ok_cb == null:
		paste_ok_cb = JavaScriptBridge.create_callback(_on_js_paste)
		paste_err_cb = JavaScriptBridge.create_callback(_on_js_paste_denied)
	clip.readText().then(paste_ok_cb, paste_err_cb)


func _on_js_paste(args: Array) -> void:
	if paste_target == null or args.is_empty():
		return
	var txt := String(args[0]).strip_edges()
	if paste_target.max_length > 0:
		txt = txt.left(paste_target.max_length)
	paste_target.text = txt
	paste_target.caret_column = txt.length()
	paste_target.text_changed.emit(txt)


func _on_js_paste_denied(_args: Array) -> void:
	if paste_target != null:
		_mobile_prompt.call_deferred(paste_target, "Paste here")


func _build_ui() -> void:
	var cl := CanvasLayer.new()
	add_child(cl)

	hud = _panel()
	hud.custom_minimum_size = Vector2(128, 0)
	var hv := VBoxContainer.new()
	hud.add_child(hv)
	hv.add_theme_constant_override("separation", 3)
	troops_l = _stat(hv, "Troops", BLUE)
	troops_rate = _last_rate_lbl
	troops_bar = ProgressBar.new()
	troops_bar.show_percentage = false
	troops_bar.min_value = 0.0
	troops_bar.max_value = 1.0
	troops_bar.custom_minimum_size = Vector2(0, 3)
	_style_bar(troops_bar, BLUE, 3)
	hv.add_child(troops_bar)
	share_l = _stat(hv, "Territory", UI_GOOD)
	gold_l = _stat(hv, "Gold", ACC)
	gold_rate = _last_rate_lbl
	cl.add_child(hud)
	gold_rate.add_theme_color_override("font_color", ACC)

	# top bar shown while hovering a nation
	info_panel = _panel()
	info_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ih := HBoxContainer.new()
	ih.add_theme_constant_override("separation", 9)
	info_panel.add_child(ih)
	info_sw = ColorRect.new()
	info_sw.custom_minimum_size = Vector2(10, 10)
	info_sw.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	ih.add_child(info_sw)
	info_name = _small_label("", 13, Color.WHITE)
	ih.add_child(info_name)
	info_ally = _small_label("", 10, UI_GOOD)
	ih.add_child(info_ally)
	info_bld = _small_label("", 10, UI_MUTED)
	ih.add_child(info_bld)
	info_troops = _small_label("", 12, UI_TEXT)
	ih.add_child(info_troops)
	info_gold = _small_label("", 10, ACC)
	ih.add_child(info_gold)
	info_panel.visible = false
	cl.add_child(info_panel)

	# right-click menu
	ctx_panel = _panel()
	ctx_panel.custom_minimum_size = Vector2(150, 0)
	var cvb := VBoxContainer.new()
	cvb.add_theme_constant_override("separation", 3)
	ctx_panel.add_child(cvb)
	ctx_title = _small_label("", 12, Color.WHITE)
	cvb.add_child(ctx_title)
	ctx_make = _ctx_btn("Make alliance", UI_GOOD)
	ctx_make.pressed.connect(_ctx_do_make)
	cvb.add_child(ctx_make)
	ctx_cancel = _ctx_btn("Cancel alliance", UI_BAD)
	ctx_cancel.pressed.connect(_ctx_do_cancel)
	cvb.add_child(ctx_cancel)
	ctx_trade = _ctx_btn("Cancel trade", ACC)
	ctx_trade.pressed.connect(_ctx_do_trade)
	cvb.add_child(ctx_trade)
	ctx_boat = _ctx_btn("Attack with boat", BLUE)
	ctx_boat.pressed.connect(_ctx_do_boat)
	cvb.add_child(ctx_boat)
	ctx_atk = _ctx_btn("Attack", ACC)
	ctx_atk.pressed.connect(_ctx_do_attack)
	cvb.add_child(ctx_atk)
	ctx_panel.visible = false
	cl.add_child(ctx_panel)

	lb_panel = _panel()
	lb_panel.custom_minimum_size = Vector2(116, 0)
	lb_box = VBoxContainer.new()
	lb_panel.add_child(lb_box)
	cl.add_child(lb_panel)

	ctl = _panel()
	var cv := HBoxContainer.new()   # ONE horizontal bar along the bottom edge: the cards left to right, the troop slider at the end
	cv.add_theme_constant_override("separation", 4)
	ctl.add_child(cv)
	var crow := cv
	var hk := 1
	for t in BUILD_ORDER:
		var card := _make_card(t, hk)
		hk += 1
		cards[t] = card
		crow.add_child(card["btn"])
		if t == "port":
			arrow_btn = ArrowBtn.new()
			arrow_btn.focus_mode = Control.FOCUS_NONE
			arrow_btn.tooltip_text = "Warships and water mines (need a port)"
			card["btn"].add_child(arrow_btn)
			arrow_btn.position = Vector2(19, 1)
			arrow_btn.size = Vector2(26, 14)
			_style_arrow(arrow_btn)
			arrow_btn.pressed.connect(_toggle_sub)
	# second section: Bomb Launcher (arrow = the bombs) and SAM Site
	var crow2 := cv
	var hk5 := 6
	for t in DEFENSE_ORDER:
		var dcard := _make_card(t, hk5)
		hk5 += 1
		cards[t] = dcard
		crow2.add_child(dcard["btn"])
		if t == "silo":
			launcher_arrow = ArrowBtn.new()
			launcher_arrow.focus_mode = Control.FOCUS_NONE
			launcher_arrow.tooltip_text = "Bombs: Small Bomb, Nuke and Mega Bomb (fired from a Bomb Launcher)"
			dcard["btn"].add_child(launcher_arrow)
			launcher_arrow.position = Vector2(19, 1)
			launcher_arrow.size = Vector2(26, 14)
			_style_arrow(launcher_arrow)
			launcher_arrow.pressed.connect(_toggle_nuke)
	var sbox := VBoxContainer.new()
	sbox.custom_minimum_size = Vector2(150, 0)
	sbox.alignment = BoxContainer.ALIGNMENT_CENTER
	sbox.add_theme_constant_override("separation", 2)
	cv.add_child(sbox)
	bar_sbox = sbox
	pct_l = Label.new()
	pct_l.text = "Send 20% per attack"
	pct_l.add_theme_font_size_override("font_size", 10)
	pct_l.add_theme_color_override("font_color", UI_MUTED)
	sbox.add_child(pct_l)
	slider = HSlider.new()
	slider.min_value = 5
	slider.max_value = 100
	slider.step = 1
	slider.value = 20
	slider.custom_minimum_size = Vector2(0, 16)
	slider.value_changed.connect(func(v): pct_l.text = "Send %d%% per attack" % int(v))
	sbox.add_child(slider)
	cl.add_child(ctl)

	sub_panel = _panel()
	var sh := HBoxContainer.new()
	sh.add_theme_constant_override("separation", 4)
	sub_panel.add_child(sh)
	var hk2 := 4
	for t in SEA_ORDER:
		var scard := _make_card(t, hk2)
		hk2 += 1
		cards[t] = scard
		sh.add_child(scard["btn"])
	sub_panel.visible = false
	sub_panel.z_index = 20
	cl.add_child(sub_panel)

	nuke_panel = _panel()
	var nh := HBoxContainer.new()
	nh.add_theme_constant_override("separation", 4)
	nuke_panel.add_child(nh)
	var hk3 := 8
	for t in NUKE_ORDER:
		var ncard := _make_card(t, hk3 % 10)
		hk3 += 1
		cards[t] = ncard
		nh.add_child(ncard["btn"])
	nuke_panel.visible = false
	nuke_panel.z_index = 20   # popups always sit above the attack list
	cl.add_child(nuke_panel)

	atk_panel = _panel()
	atk_panel.custom_minimum_size = Vector2(190, 0)
	atk_box = VBoxContainer.new()
	atk_panel.add_child(atk_box)
	atk_panel.visible = false
	cl.add_child(atk_panel)

	zoom_panel = _panel()
	var zh := HBoxContainer.new()
	zoom_panel.add_child(zh)
	for spec in [["+", 1.3], ["-", 1.0 / 1.3]]:
		var zb := Button.new()
		zb.text = spec[0]
		_style_button(zb, false)
		zb.add_theme_font_size_override("font_size", 14)
		zb.custom_minimum_size = Vector2(30, 26)
		zb.focus_mode = Control.FOCUS_NONE   # Space/Enter/arrows must never trigger zoom after a click
		zb.tooltip_text = "Zoom in" if float(spec[1]) > 1.0 else "Zoom out"
		var f: float = spec[1]
		zb.pressed.connect(func(): zoom_at(f, get_viewport_rect().size / 2.0))
		zh.add_child(zb)
	cl.add_child(zoom_panel)
	spec_panel = _panel()
	var spec_row := HBoxContainer.new()
	spec_row.add_theme_constant_override("separation", 4)
	spec_panel.add_child(spec_row)
	spec_label = _small_label("Spectating", 12, UI_TEXT)
	spec_label.custom_minimum_size = Vector2(170, 0)
	spec_row.add_child(spec_label)
	for sp in [1, 2, 4, 8]:
		var sb := Button.new()
		sb.text = "%dx" % sp
		_style_button(sb, false)
		sb.pressed.connect(_spec_set_speed.bind(float(sp)))
		spec_row.add_child(sb)
	var sleave := Button.new()
	sleave.text = "Leave"
	_style_button(sleave, false)
	sleave.pressed.connect(enter_lobby)
	spec_row.add_child(sleave)
	spec_panel.visible = false
	cl.add_child(spec_panel)

	msg_panel = _panel()
	msg_label = Label.new()
	msg_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	msg_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	msg_label.custom_minimum_size = Vector2(300, 0)
	msg_label.add_theme_font_size_override("font_size", 12)
	msg_panel.add_child(msg_label)
	msg_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cl.add_child(msg_panel)

	end_panel = _panel()
	end_panel.custom_minimum_size = Vector2(230, 0)
	var ev := VBoxContainer.new()
	ev.alignment = BoxContainer.ALIGNMENT_CENTER
	ev.add_theme_constant_override("separation", 8)
	end_panel.add_child(ev)
	end_label = Label.new()
	end_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	end_label.add_theme_font_size_override("font_size", 18)
	ev.add_child(end_label)
	var again := Button.new()
	again.text = "Back to lobby"
	again.custom_minimum_size = Vector2(0, 34)
	_style_button(again)
	again.pressed.connect(enter_lobby)
	ev.add_child(again)
	end_panel.visible = false
	cl.add_child(end_panel)

	# lobby sits on its own layer above everything
	var ll := CanvasLayer.new()
	ll.layer = 20
	add_child(ll)
	lobby_root = Control.new()
	ll.add_child(lobby_root)
	lobby_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_lobby_ui(lobby_root)
	for fp in [info_panel, ctx_panel, atk_panel, sub_panel, nuke_panel, msg_panel, end_panel]:
		(fp as Control).visibility_changed.connect(_panel_fade.bind(fp))
	get_viewport().size_changed.connect(_compact_ui)
	get_window().size_changed.connect(_desktop_scale)
	_desktop_scale.call_deferred()


func _layout() -> void:
	hud.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT, Control.PRESET_MODE_MINSIZE, UI_MARGIN)
	info_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE, UI_MARGIN)
	info_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	lb_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE, UI_MARGIN)
	lb_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	ctl.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_MINSIZE, UI_MARGIN)   # the bar sits centred along the bottom edge
	ctl.grow_horizontal = Control.GROW_DIRECTION_BOTH
	ctl.grow_vertical = Control.GROW_DIRECTION_BEGIN
	zoom_panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_MINSIZE, UI_MARGIN)
	zoom_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	zoom_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	spec_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE, UI_MARGIN)
	spec_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	msg_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_MINSIZE, 76)
	msg_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	msg_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	end_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_MINSIZE, 0)
	end_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	end_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_compact_ui()



# ======================= touch / mobile =======================
# Everything for phones and tablets lives in this section. The mouse + keyboard code above is NOT changed: a finger still
# arrives as an emulated left mouse button (tap = click, drag = pan, the panels' buttons work), and this layer adds what a mouse
# had and a finger lacks: pinch-zoom + two-finger pan, long press = right click (nation menu / cancel), a confirm step before
# spawning / building (a fingertip hides the tile), a cancel button (= Esc), a centre-on-my-land button, bigger touch targets,
# notch (safe area) insets, the Android back button, a lighter map shader and a frame cap. It switches on by itself on phones /
# tablets, or the first time a screen is touched (touch laptops, phone browsers). Desktop with a mouse never sees any of it.

const TOUCH_MAX_SCALE := 1.5       # biggest UI scale on small high-DPI screens (the UI stays >= 480 units tall)
const TOUCH_MAX_FPS := 60          # frame cap on phones (120 Hz screens would double the battery use for nothing)
const TOUCH_SLOP := 16.0           # a finger may wobble this far (UI units) and still count as a tap
const TOUCH_HOLD := 0.45           # seconds of holding still = long press

var touch_mode := false
var touch_layer: CanvasLayer
var touch_fx: Control
var touch_col: VBoxContainer
var tb_ok: Button
var tb_cancel: Button
var tb_locate: Button
var touches := {}                  # finger index -> position
var touch_blocked := false         # the first finger went down on a panel: no pinch / long press this gesture
var pinching := false
var pinch_d := 1.0
var pinch_mid := Vector2.ZERO
var lp_idx := -1                   # finger being timed for a long press (-1 = none)
var lp_pos := Vector2.ZERO
var lp_t := 0.0
var pend_tile := -1                # tile waiting for the check button (spawn point / building / sea unit)
var layout_done := false
var safe_cur := Vector4.ZERO       # safe-area insets (left, top, right, bottom) already applied, in UI units
var safe_hooked := false
var atk_btn_px := 20.0             # size of the X / swords buttons in the attacks list (bigger on touch)


# Round-ish icon button for the touch column (check / cross / locate), drawn in code like IconBtn.
class TouchBtn extends Button:
	var kind := "x"
	var col := Color("f2b84b")
	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.5
		var lw := maxf(3.0, r * 0.14)
		if kind == "check":
			draw_polyline(PackedVector2Array([c + Vector2(-r * 0.40, r * 0.02), c + Vector2(-r * 0.12, r * 0.30), c + Vector2(r * 0.42, -r * 0.28)]), col, lw, true)
		elif kind == "x":
			draw_line(c + Vector2(-r * 0.30, -r * 0.30), c + Vector2(r * 0.30, r * 0.30), col, lw, true)
			draw_line(c + Vector2(r * 0.30, -r * 0.30), c + Vector2(-r * 0.30, r * 0.30), col, lw, true)
		else:
			draw_arc(c, r * 0.30, 0.0, TAU, 24, col, lw * 0.8, true)
			draw_circle(c, r * 0.09, col)
			for d in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
				draw_line(c + d * r * 0.44, c + d * r * 0.64, col, lw * 0.8, true)


# Full-screen, input-transparent layer that draws the long-press ring and the pending-tile marker and drives the touch timers.
class TouchFx extends Control:
	var main
	func _process(delta: float) -> void:
		if main != null:
			main._touch_step(delta)
	func _draw() -> void:
		if main != null:
			main._touch_draw(self)


func _setup_touch() -> void:
	if OS.has_feature("mobile") or OS.has_feature("web_android") or OS.has_feature("web_ios"):
		_enable_touch()


# Runs after the deferred _layout(): the safe-area shift must come after the panels got their anchors.
func _touch_post_layout() -> void:
	layout_done = true
	if touch_mode:
		_touch_safe_area()
		if not safe_hooked:
			safe_hooked = true
			get_viewport().size_changed.connect(_touch_safe_area)


func _enable_touch() -> void:
	if touch_mode:
		return
	touch_mode = true
	_touch_scale()
	_touch_adapt_ui()
	_touch_build_layer()
	_apply_lite_terrain()
	if OS.has_feature("mobile"):
		Engine.max_fps = TOUCH_MAX_FPS
		DisplayServer.screen_set_keep_on(true)
	if layout_done:
		_touch_post_layout()


# Small high-DPI screens: scale the whole UI + map view so a button is a fingertip big (about 120 UI units per inch).
func _touch_scale() -> void:
	var win := DisplayServer.window_get_size()
	var h := float(mini(win.x, win.y))
	var dpi := float(DisplayServer.screen_get_dpi())
	if h <= 0.0 or dpi <= 0.0:
		return
	get_window().content_scale_factor = clampf(6.0 * dpi / h, 1.0, TOUCH_MAX_SCALE)


func _touch_adapt_ui() -> void:
	atk_btn_px = 40.0
	for zb in (zoom_panel.get_child(0) as HBoxContainer).get_children():
		(zb as Control).custom_minimum_size = Vector2(54, 48)
	_compact_ui(true)   # fingertip-sized cards and the little arrows on the Port / Launcher cards
	# attack-percentage slider: taller grab zone + a big round handle
	slider.custom_minimum_size = Vector2(0, 38)
	for nm in ["grabber", "grabber_highlight"]:
		var g := Gradient.new()
		g.offsets = PackedFloat32Array([0.0, 0.80, 0.92, 1.0])
		var ring := ACC.lightened(0.25) if nm == "grabber_highlight" else ACC
		g.colors = PackedColorArray([ring, ring, Color(ring, 0.35), Color(ring, 0.0)])
		var gt := GradientTexture2D.new()
		gt.gradient = g
		gt.fill = GradientTexture2D.FILL_RADIAL
		gt.fill_from = Vector2(0.5, 0.5)
		gt.fill_to = Vector2(1.0, 0.5)
		gt.width = 40
		gt.height = 40
		slider.add_theme_icon_override(nm, gt)
	# nation menu (long press) and lobby button
	for cb in [ctx_make, ctx_cancel, ctx_trade, ctx_boat, ctx_atk]:
		(cb as Control).custom_minimum_size = Vector2(0, 46)
	ctx_panel.custom_minimum_size = Vector2(250, 0)
	lb_join.custom_minimum_size = Vector2(0, 60)


func _touch_btn(kind: String, col: Color, primary: bool, cb: Callable, tip: String) -> Button:
	var b := TouchBtn.new()
	b.kind = kind
	b.col = col
	b.custom_minimum_size = Vector2(58, 58)
	b.focus_mode = Control.FOCUS_NONE
	b.tooltip_text = tip
	_style_button(b, primary)
	b.pressed.connect(cb)
	b.visible = false
	touch_col.add_child(b)
	return b


func _touch_build_layer() -> void:
	touch_layer = CanvasLayer.new()
	touch_layer.layer = 5
	add_child(touch_layer)
	var root := Control.new()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	touch_layer.add_child(root)
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	touch_fx = TouchFx.new()
	touch_fx.main = self
	touch_fx.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(touch_fx)
	touch_fx.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	touch_col = VBoxContainer.new()
	touch_col.add_theme_constant_override("separation", 10)
	touch_col.custom_minimum_size = Vector2(60, 0)
	root.add_child(touch_col)
	tb_locate = _touch_btn("locate", Color("9fd0ff"), false, _touch_recenter, "Centre the view on your land")
	tb_cancel = _touch_btn("x", UI_BAD, false, _touch_cancel, "Cancel (same as Esc / right click)")
	tb_ok = _touch_btn("check", Color("1b1405"), true, _touch_confirm, "Confirm")
	touch_col.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_MINSIZE, UI_MARGIN)
	touch_col.offset_top -= 72.0       # sits above the zoom buttons
	touch_col.offset_bottom -= 72.0
	touch_col.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	touch_col.grow_vertical = Control.GROW_DIRECTION_BEGIN
	touch_layer.visible = phase != "lobby"


# The map shader's noise (ocean tone, land relief, speckle) is the costly part for a phone GPU: swap it for flat tones.
func _apply_lite_terrain() -> void:
	if terrain == null or terrain.material == null:
		return
	var code: String = TERRAIN_SHADER
	code = code.replace("float n = vnoise(fc * 0.07 + vec2(now * 0.02, now * 0.012));", "float n = 0.5;")
	code = code.replace("float lf = vnoise(fc * 0.045) * 0.55 + vnoise(fc * 0.17) * 0.45;", "float lf = 0.5;")
	code = code.replace("tcol *= 0.985 + 0.03 * hash(fc);", "")
	((terrain.material as ShaderMaterial).shader as Shader).code = code
	lite_on = true


func _shift(c: Control, dx: float, dy: float) -> void:
	c.offset_left += dx
	c.offset_right += dx
	c.offset_top += dy
	c.offset_bottom += dy


# Keeps the panels out of the notch / rounded corners / gesture bar (insets come in pixels, panels are in UI units).
func _touch_safe_area() -> void:
	var win := DisplayServer.window_get_size()
	var vp := get_viewport_rect().size
	if win.x <= 0 or vp.x <= 0.0:
		return
	var sa := DisplayServer.get_display_safe_area()
	var scr := DisplayServer.screen_get_size()
	var k := vp.x / float(win.x)
	var cap := 90.0
	var ins := Vector4(
		clampf(float(sa.position.x) * k, 0.0, cap),
		clampf(float(sa.position.y) * k, 0.0, cap),
		clampf(float(scr.x - sa.end.x) * k, 0.0, cap),
		clampf(float(scr.y - sa.end.y) * k, 0.0, cap))
	var d := ins - safe_cur
	safe_cur = ins
	_shift(hud, d.x, d.y)
	_shift(info_panel, 0.0, d.y)
	_shift(lb_panel, -d.z, d.y)
	_shift(ctl, 0.0, -d.w)
	_shift(zoom_panel, -d.z, -d.w)
	_shift(msg_panel, 0.0, -d.w)
	if touch_col != null:
		_shift(touch_col, -d.z, -d.w)


func _over_touch_ui(pos: Vector2) -> bool:
	for b in [tb_ok, tb_cancel, tb_locate]:
		if b != null and (b as Control).visible and (b as Control).get_global_rect().grow(8.0).has_point(pos):
			return true
	return false


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		if not touch_mode:
			_enable_touch()
		if phase == "lobby":
			return
		if st.pressed:
			touches[st.index] = st.position
			if touches.size() == 1:
				pinching = false
				lp_idx = -1
				touch_blocked = _over_ui(st.position) or _over_touch_ui(st.position)
				if not touch_blocked:
					lp_idx = st.index
					lp_pos = st.position
					lp_t = 0.0
			elif touches.size() == 2 and not touch_blocked:
				# second finger: cancel the one-finger drag / long press the emulated mouse started and pinch instead
				lp_idx = -1
				drag = false
				pinching = true
				_pinch_ref()
		else:
			touches.erase(st.index)
			if st.index == lp_idx:
				lp_idx = -1
			if touches.size() < 2:
				pinching = false
			elif pinching:
				_pinch_ref()
			if touches.is_empty():
				touch_blocked = false
	elif event is InputEventScreenDrag:
		var sd := event as InputEventScreenDrag
		touches[sd.index] = sd.position
		if lp_idx == sd.index and sd.position.distance_to(lp_pos) > TOUCH_SLOP:
			lp_idx = -1
		if pinching and touches.size() >= 2:
			_pinch_update()
	elif touch_mode and event is InputEventMouseMotion:
		# a fingertip always wobbles: movement inside the slop never turns a tap into a pan
		var mm := event as InputEventMouseMotion
		if mm.device == InputEvent.DEVICE_ID_EMULATION and drag and not drag_moved and not pinching:
			if mm.position.distance_to(drag_start) <= TOUCH_SLOP:
				get_viewport().set_input_as_handled()
	elif touch_mode and event is InputEventMouseButton:
		# a tap that would spawn / build is held back until the check button confirms it
		var mb := event as InputEventMouseButton
		if mb.device == InputEvent.DEVICE_ID_EMULATION and mb.button_index == MOUSE_BUTTON_LEFT and not mb.pressed:
			if drag and not drag_moved and not pinching and (phase == "spawn" or (phase == "play" and mode != "attack")):
				get_viewport().set_input_as_handled()
				drag = false
				var t := _tile_at(mb.position)
				if t >= 0 and (phase != "spawn" or land[t] == 1):
					pend_tile = t
					if phase == "spawn":
						say("Start here?  Press the gold check button, or tap another spot.", 4.0)
					else:
						say("%s here?  Press the gold check button, or tap another spot." % BUILD_LABEL[mode], 4.0)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST and touch_mode:
		_touch_cancel()   # Android back button = Esc (the game never quits on it)


func _pinch_pts() -> Array:
	var ks: Array = touches.keys()
	ks.sort()
	return [touches[ks[0]], touches[ks[1]]]


func _pinch_ref() -> void:
	var p := _pinch_pts()
	pinch_d = maxf(10.0, (p[0] as Vector2).distance_to(p[1]))
	pinch_mid = ((p[0] as Vector2) + (p[1] as Vector2)) * 0.5


# Two fingers: the map point between them stays under them (zoom + pan together). Same zoom limits as zoom_at().
func _pinch_update() -> void:
	var p := _pinch_pts()
	var d := maxf(10.0, (p[0] as Vector2).distance_to(p[1]))
	var mid := ((p[0] as Vector2) + (p[1] as Vector2)) * 0.5
	view_pos += mid - pinch_mid
	var nz := clampf(zoom * d / pinch_d, 0.6, 30.0)
	var k := nz / zoom
	view_pos = mid - (mid - view_pos) * k
	zoom = nz
	zoom_goal = nz
	pinch_d = d
	pinch_mid = mid


# Long press = right click: the existing right-click code opens the nation menu or cancels a build / ship order.
func _touch_longpress(pos: Vector2) -> void:
	lp_idx = -1
	drag = false
	Input.vibrate_handheld(25)
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_RIGHT
	ev.pressed = true
	ev.position = pos
	ev.global_position = pos
	get_viewport().push_input(ev)


func _touch_cancel() -> void:
	pend_tile = -1
	_hide_ctx()
	sel_ship = 0
	if mode != "attack":
		set_mode("attack")
		ui()


func _touch_confirm() -> void:
	if pend_tile < 0:
		return
	var sp := view_pos + Vector2(pend_tile % W + 0.5, pend_tile / W + 0.5) * zoom
	pend_tile = -1
	_click(sp)


func _touch_recenter() -> void:
	if players.size() < 2:
		return
	var b: Dictionary = border[my_slot]
	if b.is_empty():
		return
	var sx := 0.0
	var sy := 0.0
	var n := 0
	for k in b:
		sx += float(int(k) % W)
		sy += float(int(k) / W)
		n += 1
	zoom_goal = clampf(maxf(zoom_goal, 5.0), 0.6, 30.0)
	zoom = zoom_goal
	view_pos = get_viewport_rect().size * 0.5 - Vector2(sx / float(n) + 0.5, sy / float(n) + 0.5) * zoom


func _touch_step(delta: float) -> void:
	touch_layer.visible = phase != "lobby"
	if phase == "lobby":
		lp_idx = -1
		pend_tile = -1
		pinching = false
		touches.clear()
		return
	if lp_idx >= 0 and not pinching:
		lp_t += delta
		if lp_t >= TOUCH_HOLD:
			_touch_longpress(lp_pos)
	var placing := phase == "spawn" or (phase == "play" and mode != "attack")
	if pend_tile >= 0 and not placing:
		pend_tile = -1
	tb_ok.visible = pend_tile >= 0
	tb_cancel.visible = phase == "play" and (mode != "attack" or sel_ship != 0 or ctx_panel.visible or pend_tile >= 0)
	tb_locate.visible = phase == "play"
	touch_fx.queue_redraw()


func _touch_draw(ci: Control) -> void:
	if lp_idx >= 0 and not pinching and lp_t > 0.12:
		var k := clampf(lp_t / TOUCH_HOLD, 0.0, 1.0)
		ci.draw_arc(lp_pos, 26.0, -PI * 0.5, -PI * 0.5 + TAU * k, 32, Color(ACC, 0.9), 4.0, true)
	if pend_tile >= 0:
		var t := Time.get_ticks_msec() / 1000.0
		var c := view_pos + Vector2(pend_tile % W + 0.5, pend_tile / W + 0.5) * zoom
		var r := maxf(12.0, zoom * 1.6) + 2.0 * sin(t * 6.0)
		ci.draw_arc(c, r + 4.0, 0.0, TAU, 32, Color(0, 0, 0, 0.35), 2.0, true)
		ci.draw_arc(c, r, 0.0, TAU, 32, Color(ACC, 0.95), 3.0, true)
		for d in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
			ci.draw_line(c + d * (r + 2.0), c + d * (r + 11.0), Color(ACC, 0.95), 3.0, true)



# ======================= profiler (F3) =======================
# Press F3 in a match: an overlay shows, once per second, where the time goes (ms of work per second of play, average and worst
# single call) next to the engine's own counters (fps, draw calls, nodes, memory) and the size of the late-game load (attacks,
# front tiles, ships, buildings...). The same lines are saved to user://perf_log.txt every 5 s. Client only: never touches the rules.
func _pf0() -> int:
	return Time.get_ticks_usec() if perf_on else 0


func _pf1(key: String, t0: int) -> void:
	if not perf_on:
		return
	var d := Time.get_ticks_usec() - t0
	perf_us[key] = int(perf_us.get(key, 0)) + d
	perf_calls[key] = int(perf_calls.get(key, 0)) + 1
	if not perf_peak.has(key) or d > int(perf_peak[key]):
		perf_peak[key] = d   # always create the key: a 0 us call (e.g. nothing to draw) used to leave it missing and crash the overlay


func _perf_toggle() -> void:
	perf_on = not perf_on
	perf_us.clear()
	perf_calls.clear()
	perf_peak.clear()
	perf_win = 0.0
	perf_frames = 0
	perf_slow = 0
	perf_maxdt = 0.0
	perf_setown = 0
	if perf_on and perf_label == null:
		var pcl := CanvasLayer.new()
		pcl.layer = 100
		add_child(pcl)
		perf_label = Label.new()
		perf_label.add_theme_font_size_override("font_size", 13)
		perf_label.add_theme_color_override("font_color", Color(0.75, 1.0, 0.8))
		perf_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
		perf_label.add_theme_constant_override("outline_size", 5)
		perf_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pcl.add_child(perf_label)
	if perf_label != null:
		perf_label.visible = perf_on
		perf_label.text = "PROFILER on - collecting 1 s of data..."
		perf_label.position = Vector2(12.0, 150.0)


func _perf_overlay(delta_in: float) -> void:
	var delta := delta_in / maxf(Engine.time_scale, 0.001)   # REAL frame time: the editor's 8x button scales delta, which made every number lie
	perf_frames += 1
	perf_maxdt = maxf(perf_maxdt, delta)
	if delta > 0.034:
		perf_slow += 1
	perf_win += delta
	if perf_win < 1.0:
		return
	var secs := perf_win
	var lines: Array[String] = []
	lines.append("PROFILER (F3)  fps %d  frame avg %.1f ms  worst %.0f ms  slow frames %d  | quality level %d" % [
		int(Performance.get_monitor(Performance.TIME_FPS)), secs / float(maxi(1, perf_frames)) * 1000.0, perf_maxdt * 1000.0, perf_slow, perf_level])
	lines.append("engine: process %.1f ms | draw calls %d | nodes %d (orphans %d) | memory %.0f MB" % [
		Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0, int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)), int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)),
		Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0])
	var fronts := 0
	for a in attacks:
		fronts += (a.get("fr", {}) as Dictionary).size()
	lines.append("load: attacks %d (front tiles %d) | tiles changed/s %d | trade %d ships %d boats %d | buildings %d rails %d | fx %d | blasts %d" % [
		attacks.size(), fronts, int(float(perf_setown) / secs), trade.size(), ships.size(), boats.size(), bld.size(), rails.size(), fx.size(), blast_jobs.size()])
	lines.append("ms of work per REAL second%s (the slowest line is the bottleneck; a frame at 60 fps has 16.7 ms):" % ("" if absf(Engine.time_scale - 1.0) < 0.01 else "   !! editor speed x%.1f: test at 1x !!" % Engine.time_scale))
	var keys := perf_us.keys()
	keys.sort_custom(func(a, b): return int(perf_us[a]) > int(perf_us[b]))
	for k in keys:
		var tot := float(int(perf_us[k])) / 1000.0 / secs
		var cn := maxi(1, int(perf_calls.get(k, 1)))
		lines.append("  %-18s %6.1f ms/s   avg %6.2f ms   worst %6.1f ms   x%d" % [str(k), tot, float(int(perf_us[k])) / 1000.0 / float(cn), float(int(perf_peak.get(k, 0))) / 1000.0, cn])
	var txt := "\n".join(lines)
	if perf_label != null:
		perf_label.text = txt
		perf_label.position = Vector2(12.0, 150.0)
	perf_log.append("[t=%d]\n%s" % [int(clock), txt])
	if perf_log.size() > 120:
		perf_log.pop_front()
	perf_log_t += secs
	if perf_log_t >= 5.0:
		perf_log_t = 0.0
		var fa := FileAccess.open("user://perf_log.txt", FileAccess.WRITE)
		if fa != null:
			fa.store_string("\n\n".join(perf_log))
			fa.close()
	perf_us.clear()
	perf_calls.clear()
	perf_peak.clear()
	perf_win = 0.0
	perf_frames = 0
	perf_slow = 0
	perf_maxdt = 0.0
	perf_setown = 0


# ======================= performance (client look only - never touches the simulation, so lockstep clients stay in step) =======================

# Watches the real frame time. If the game stays slower than ~40 fps for 3 s it steps the quality down one level (at most once per 6 s):
#   1 = lite map shader + no conquest sparks, 2 = map texture uploaded less often, 3 = simplest icons everywhere.
# It never steps back up during a match (no flip-flopping); a new match starts at full quality again.
func _perf_adapt(delta: float) -> void:
	if phase != "play":
		perf_acc = 0.0
		perf_n = 0
		return
	perf_acc += minf(delta, 0.25)
	perf_n += 1
	if perf_acc < 3.0:
		return
	var avg_ms := perf_acc / float(perf_n) * 1000.0
	perf_acc = 0.0
	perf_n = 0
	if perf_level >= 3 or clock - perf_since < 6.0:
		return
	var cap_fps := 60.0
	if Engine.max_fps > 0:
		cap_fps = minf(60.0, float(Engine.max_fps))
	if avg_ms > 1000.0 / cap_fps * 1.5:
		perf_level += 1
		perf_since = clock
		match perf_level:
			1:
				if not lite_on:
					_apply_lite_terrain()
			2:
				img_floor = 0.12
				lod_zoom = 5.0
			3:
				img_floor = 0.2
				lod_zoom = 8.0
		print("Landgrab: automatic quality level %d (frame time %.1f ms)" % [perf_level, avg_ms])


# Far-away building: one or two shapes in the nation colour instead of the full hand-drawn building.
func _draw_bld_lod(kind: String, pos: Vector2, s: float, c: Color) -> void:
	var r := s * 0.3
	match kind:
		"village":
			draw_circle(pos, r * 0.8 + 1.2, OUT)
			draw_circle(pos, r * 0.8, c)
		"city":
			draw_circle(pos, r * 1.1 + 1.2, OUT)
			draw_circle(pos, r * 1.1, c)
			draw_circle(pos, r * 0.35, Color.WHITE)
		"duchy":
			draw_circle(pos, r * 1.4 + 1.2, OUT)
			draw_circle(pos, r * 1.4, c)
			draw_circle(pos, r * 0.85, OUT)
			draw_circle(pos, r * 0.55, Color.WHITE)
		"station":
			var rc := Rect2(pos - Vector2.ONE * r, Vector2.ONE * r * 2.0)
			draw_rect(rc, c)
			draw_rect(rc, OUT, false, 1.5)
		"port":
			var dm := PackedVector2Array([pos + Vector2(0, -r * 1.2), pos + Vector2(r * 1.2, 0), pos + Vector2(0, r * 1.2), pos + Vector2(-r * 1.2, 0)])
			draw_colored_polygon(dm, c)
			dm.append(dm[0])
			draw_polyline(dm, OUT, 1.5)
		"silo", "sam":
			var up := -1.0 if kind == "silo" else 1.0
			var tr := PackedVector2Array([pos + Vector2(0, up * r * 1.3), pos + Vector2(-r * 1.1, -up * r), pos + Vector2(r * 1.1, -up * r)])
			draw_colored_polygon(tr, c)
			tr.append(tr[0])
			draw_polyline(tr, OUT, 1.5)
		_:
			draw_circle(pos, r + 1.2, OUT)
			draw_circle(pos, r, c)


# Narrow windows / small phones: the bottom bar (five cards + the troop slider) would run into the zoom buttons, so shrink it.
# Desktop / browser: keep the UI at a sensible physical size. Without this a big window (full screen on a 1080p / 1440p monitor) scaled
# every panel up with the window and the UI ate the board. The factor is applied on top of the project's 1280x720 stretch, so
# the UI grows only slowly with the window (about 0.9x at 720p, 1.2x at 1080p) while the board gets all the extra room.
# Touch devices keep their own scale (_touch_scale).
func _desktop_scale() -> void:
	if touch_mode:
		return
	var win := Vector2(get_window().size)
	if win.x < 100.0 or win.y < 100.0:
		return
	var stretch := minf(win.x / 1280.0, win.y / 720.0)
	var want := clampf(minf(win.x / 1500.0, win.y / 880.0), 0.9, 1.3)
	var f := want / stretch
	if absf(f - get_window().content_scale_factor) > 0.01:
		get_window().content_scale_factor = f


func _compact_ui(force: bool = false) -> void:
	if cards.is_empty() or bar_sbox == null:
		return
	var compact := get_viewport_rect().size.x < 900.0
	if compact_init and compact == compact_cur and not force:
		return
	compact_init = true
	compact_cur = compact
	var csz := Vector2(64, 62)
	if touch_mode:
		csz = Vector2(86, 82)      # fingertip-sized cards
	elif compact:
		csz = Vector2(56, 56)
	for t in cards:
		((cards[t] as Dictionary)["btn"] as Control).custom_minimum_size = csz
	var asz := Vector2(40, 28) if touch_mode else Vector2(26, 14)
	for ab in [arrow_btn, launcher_arrow]:
		if ab != null:
			(ab as Control).size = asz
			(ab as Control).position = Vector2((csz.x - asz.x) * 0.5, 1.0)
	bar_sbox.custom_minimum_size = Vector2(104 if compact else 150, 0)
