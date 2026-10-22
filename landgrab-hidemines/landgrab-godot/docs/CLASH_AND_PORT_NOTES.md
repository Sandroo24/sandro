# Counter-attack clashes, port timing, popup layering (static checks only - not run in Godot)

**Clashes** (`_resolve_clashes`, `_clash`, called at the start of every attack step): when nation X attacks Y and Y attacks X, the two armies cancel man for man.
- Land attack being countered: whoever has troops left keeps attacking with the rest (e.g. 134K attacked, 302K counter -> 168K keeps attacking X), the other attack ends.
- Attack came by BOAT (the landing attack is flagged `sea`): the counter only destroys the landing force and stops; what is left of the counter army returns to its nation. If the landing was bigger it simply continues with what survives.
- The older attack (smaller id) is "the one being countered". No randomness, runs identically on every client.
**Ports:** trade ship every 15 s at Lv 1, 1.5 s faster per level (Lv 5 = 9 s): `TRADE_COOLDOWN` 30 ticks, `TRADE_COOLDOWN_PER_LEVEL` 3. `PORT_BOATS` (12) still caps ships afloat per port.
**UI:** Port / Bomb popups now have `z_index = 20` (above the attack list), the attack list stops above an open popup, and on-map attack tags (your attack + the one against you share one front) are stacked instead of overlapping.
`NET_VER` / `PROTO_VERSION` = 10.

**Owned land is a solid nation colour again:** removed the shader block that let snow caps / sand / forest relief show through nation colours (`TERRAIN_SHADER`, owned-land branch). Terrain detail (mountains, desert, forest, shadows) now shows on UNOWNED land only; the 0.4 s colour hand-over when land changes owner is unchanged.

**Lobby "Connecting..." loop (fixed):** when the official server did not answer, the game showed an offline practice lobby with its OWN 2-minute timer, and every 15 s (and at every practice rollover) it reconnected in the foreground: "Connecting..." again and the timer jumped to the server's. Now:
- the first connect may take 20 s (was 8 s: a sleeping hosted server needed longer, the attempt was killed, then a 15 s wait = the "15 seconds of connecting");
- retries and practice rollovers use a SILENT background connection (`_pub_probe` / `_probe_poll`): the practice lobby and its timer stay untouched and only switch to the server's lobby once it has really answered;
- if an established connection drops, the practice countdown continues from the server's last time and the retry is silent (3 s).
NOTE: `OFFICIAL_SERVER` in main.gd is still `ws://localhost:8765` in this build: set it to your hosted relay's wss:// address for a release, and make sure the relay is running (otherwise you always get the practice lobby).

**Card bar:** the building cards (Village, Station, Port, Bomb Launcher, SAM Site) are now ONE horizontal bar centred along the bottom edge, the troop slider at its right end (was a two-row box at the bottom left). The Port / Bomb popups open right above their own card. Code: `ctl` construction + `_layout` + `_place_sub` / `_place_nuke`.

**Mobile lobby input (web export):** on iPhone / Android browsers the on-screen keyboard never opened because browsers only allow it when a field is focused inside the tap itself, and Godot's canvas handles taps a frame later. Phone browsers now open the browser's own input box (`window.prompt`, native keyboard + paste) when a lobby field is tapped (`_mobile_browser`, `_mobile_edit`, `_mobile_prompt`). Desktop / native builds keep the normal LineEdit. New "Paste" buttons next to the room code and server address read the clipboard (`_paste_into`; if the browser refuses, the input box opens instead). The lobby row wraps on narrow screens and fields are taller on phones.
**Attack progression:** `ATK_LOSS_MULT` (0.65) and `ATK_SPEED_MULT` (1.6) near the top of main.gd scale the OpenFront-style player-vs-player formulas (attacker loss per tile, tiles taken per step). Free-land expansion is unchanged. NET_VER / PROTO_VERSION = 14.

**Troop advantage -> speed:** `ATK_ADV_START` / `ATK_ADV_SLOPE` / `ATK_ADV_MAX` (main.gd): an attacker stronger than 1.2x the defender now conquers faster in proportion to the advantage (1.5x ~ +14 %, 5x ~ +80 %, 10x ~ +120 %, capped at 2.5x speed). Before, anything above ~1.2x was no faster. NET_VER / PROTO_VERSION = 15.

**"Everyone is in a different lobby" (fixed):** `OFFICIAL_SERVER` was written as `https://...trycloudflare.com`; the code only knew `ws://` / `wss://` and turned it into the invalid `wss://https://...`, so the public lobby could never connect and every player silently stayed in his own offline practice lobby. New `_ws_url()` converts https:// -> wss://, http:// -> ws://, adds wss:// when there is no scheme and strips a trailing slash; used by the public lobby, the silent retry and the private-room connect.
**Server id:** the relay prints `SERVER <id> protocol <n>` when it starts and sends the id and the number of connected players; the lobby shows "Server A3F9 - 4 online" under "Up next". Players who see the SAME id are on the same server. A different id (or no id = practice lobby) means they reach a different / no relay.
NOTE: a trycloudflare.com ("quick tunnel") address changes every time cloudflared restarts: after a restart put the NEW address into OFFICIAL_SERVER (and re-export) or players keep reaching an old address.

**Lobby no longer waits on a dead server:** since the https:// fix the official address really connects, so an unreachable relay / old tunnel address meant 20 s of "Connecting..." with Join disabled. Now: "Connecting... N s" for at most 6 s, then the practice lobby (Join works) while the silent background connection keeps trying for up to 20 s more and switches over when the server answers. A refused connection retries after 5 s.
