# Hosting the relay - what must be true, and how to find what is wrong

The relay is ONE file (`relay.py`, Python 3.8+, no packages). The game only connects if ALL of these are true:

1. `relay.py` is running right now (it prints "Landgrab relay SERVER ... listening on port ...").
2. There is an **https / wss** address that reaches that port (itch.io pages are https, so the browser refuses plain `ws://`).
3. `OFFICIAL_SERVER` in `main.gd` is **exactly that address** and the game was **re-exported and re-uploaded** after you changed it.
4. `NET_VER` in `main.gd` equals `PROTO_VERSION` in `relay.py` (both are **17** in this folder). If they differ the lobby shows "Version mismatch".

## Test it in 10 seconds (no Godot, no browser)
    python check_server.py https://your-address        # prints OK, or exactly what is wrong (not running / TLS / not a relay / version)
Also open `https://your-address` in a browser: it must say "Landgrab relay is running."

## The most likely problem: a quick tunnel address
`main.gd` currently contains a `https://....trycloudflare.com` address. That is a **quick tunnel** (`cloudflared tunnel --url http://localhost:8765`):
it only works while that cloudflared window AND `relay.py` are running on your PC, and **the address is different every time you restart it**.
So the exported game points at a dead address as soon as either one is restarted. Fix: use a permanent address (below), put it in `OFFICIAL_SERVER`, re-export.

## Permanent options (pick one)
**A. A hosting service that gives you https (easiest).** Create a "Web Service" from this `server` folder (Render, Railway, Fly.io, ...):
- Start command: `python relay.py` (it listens on the `PORT` the service gives it), or use the included `Dockerfile`.
- The service's address (e.g. `https://landgrab-relay.onrender.com`) is your `OFFICIAL_SERVER`. WebSockets work on these services.
- Free plans put the service to sleep when idle: the first connection then takes up to ~30-50 s (the game keeps trying quietly for ~20 s and shows the practice lobby meanwhile; a paid plan / "always on" avoids that).
**B. Your own VPS + Caddy** (see README.md in this folder): `your-domain.com { reverse_proxy localhost:8765 }`, relay kept alive with systemd / pm2 / docker `--restart always`.
**C. Cloudflare NAMED tunnel** (free, permanent address on your own domain): `cloudflared tunnel login`, `cloudflared tunnel create landgrab`, route a hostname to `http://localhost:8765`, run it as a service. Your PC (and relay.py) must stay on.

## Other things that break it
- Wrong scheme: `OFFICIAL_SERVER` may be written `https://x`, `wss://x` or `x` (the game turns it into wss://). `http://` / `ws://` only work for local tests, never from an itch.io page.
- A proxy that does not pass WebSockets (turn WebSocket support on) - `check_server.py` says "upgrade refused".
- Old relay still deployed: it answers "Version mismatch" (or, with a relay older than 16, silently ignores bomb commands). Re-deploy `relay.py` whenever `PROTO_VERSION` changes.
- Only one relay may serve a lobby: two copies behind one address = players land in different lobbies (the server id shown by `check_server.py` tells you which one answered).
