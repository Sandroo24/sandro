# Landgrab relay server

## What it serves
1. **The official public lobby** (the big "Join game" button). The server owns the map rotation, the 2:00 countdown and **2 real-player slots**.
   Every other nation is a bot (63 on a 65-nation map, 98 on World) that each client runs itself. When the timer ends, everybody who
   joined plays together; no players = it just rolls to the next map. Both slots taken = the match starts at once.
2. **Private rooms** (the "Private room" button): a room code the players choose; the first in is host and picks map / starts (24 nations).

Settings (top of `relay.py`): `PUBLIC_OPEN_SLOTS`, `PUBLIC_MAPS` (take a map out of the rotation), `LOBBY_SECS` (or env `LANDGRAB_LOBBY_SECS`), `MAX_CONNS`.
Whenever you change gameplay, bump `PROTO_VERSION` here AND `NET_VER` in `main.gd` together.

## Hosting it for real (the last step)
**Not connecting? Read `DEPLOY.md` and run `python check_server.py https://your-address` first.**

Run `python3 relay.py` on any always-on box (a small VPS is enough) and put TLS in front, because an itch.io page is https and the browser only
allows `wss://`. With Caddy that is the whole config (it handles the websocket upgrade and the certificate by itself):

    your-domain.com {
        reverse_proxy localhost:8765
    }

Then in `main.gd` set `OFFICIAL_SERVER := "wss://your-domain.com"`, re-export, upload. Open `https://your-domain.com` in a browser:
"Landgrab relay is running." means it is up. Keep it running with systemd / `pm2` / a Docker restart policy.

No packages needed, Python 3.8+:

    python server/relay.py          # ws://localhost:8765   (another port: python server/relay.py 9000)

## Test on one PC (no browser)
Godot: Debug > Customize Run Instances > enable 2 instances, press F5. In each window click **Play online**
(address `ws://localhost:8765`, same room name). The first one is the host: **Change map**, then **Start match**.

## Test with friends from itch.io
An itch.io page is https, so the browser only allows a **wss://** (TLS) server. Easiest, free, no router setup:

1. Start the relay on your PC: `python server/relay.py`
2. In a second terminal run a tunnel: `cloudflared tunnel --url http://localhost:8765`
   It prints `https://something.trycloudflare.com`. Your address in the game is `wss://something.trycloudflare.com`
   (the address changes every time you restart the tunnel - just type the new one in the game, no re-export needed).
3. Everybody opens the itch page, types the address and the same room name, **Play online**. The first one in is the host.

(Any other way to get TLS in front of port 8765 also works: ngrok, Caddy/nginx on a VPS, ...)

## Export for itch.io (Godot 4.3)
Project > Export > Add... > Web. In the preset turn **Thread Support OFF** (then itch needs no SharedArrayBuffer setting).
Export as `index.html` into an empty folder, zip the folder's contents, upload to itch as "HTML", tick "played in the browser",
size 1280x720. Change `DEFAULT_SERVER` at the top of `main.gd` if you want a fixed address pre-filled.
Re-export + re-upload after EVERY gameplay change and bump `NET_VER` (main.gd) and `PROTO_VERSION` (relay.py) together.

## Protocol (JSON text frames)
client -> relay: `join{name,room,ver}`, `map{idx}` (host), `start{n}` (host), `cmd{c}`, `sum{n,h}`
relay -> client: `joined{you,host}`, `lobby{players,host,map}`, `begin{map,seed,n,players,you}`, `turn{n,c?,d?}`, `desync{n}`, `err{m}`
