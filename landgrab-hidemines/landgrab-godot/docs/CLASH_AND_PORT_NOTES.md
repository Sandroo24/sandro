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
