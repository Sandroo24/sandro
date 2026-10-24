#!/usr/bin/env python3
"""
Landgrab relay server  -  Python 3.8+, NO extra packages (plain asyncio + a tiny WebSocket implementation).

    python relay.py            # listens on 0.0.0.0:8765  (or:  python relay.py 9000   /   PORT=9000 python relay.py)

What it does
------------
It does NOT run the game. Every player's game runs the same deterministic simulation. The relay only:
  * keeps rooms (a room name is chosen by the players), the lobby and who is the host,
  * on "start" gives everybody the same match (map, random seed, who is human, their final slot number),
  * then sends one numbered TURN every 0.1 s containing the commands players sent during that turn (in arrival order),
  * tells everybody when a player left (their country turns into a bot),
  * compares the state checksums the clients send and warns everybody on a mismatch ("desync").

Messages are JSON text frames (see MULTIPLAYER_PROGRESS.md for the list). The sender of a command is always taken from the
connection, never from the message. This is a relay: it cannot know whether a command is legal (every client re-validates it),
so it is for friendly testing, not for a public game against cheaters.
"""
import asyncio
import base64
import hashlib
import json
import os
import random
import ssl
import struct
import sys
import time

GUID = b"258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
PROTO_VERSION = 20
SERVER_ID = "%04X" % random.randint(0, 0xFFFF)   # new on every start of the relay: players who see the same id are on the same server
MAX_MSG = 64 * 1024            # biggest message a client may send
MAX_HUMANS = 8                 # per room
TURN_SECS = 0.1                # one turn = one attack step in the game
MAX_NAME = 16
MAX_ROOM = 16
CMD_BURST = 20                 # commands a client may send in a burst ...
CMD_PER_SEC = 12.0             # ... and per second on average
MAX_ROOM_SECS = 6 * 3600       # a running match is closed after this long
PING_EVERY = 25.0              # websocket ping, keeps tunnels / proxies from closing an idle lobby

# ---- the OFFICIAL PUBLIC LOBBY (the big "Join game" button in the game) ----
# One public lobby at a time: the server owns the map rotation, the countdown and the open player slots. The rest of the
# nations are bots (placeholders) that every client runs itself. When the countdown ends the lobby becomes a normal match
# (a room called "!pubN") for whoever joined, and the next lobby opens with the next map. No humans joined = it just rolls over.
LOBBY_SECS = float(os.environ.get("LANDGRAB_LOBBY_SECS", "120"))   # same as LOBBY_SECS in main.gd
# Real players per public lobby = the nations of the map (World 100, the others 65): tribes (bots) never take a lobby place, they only fill land the players do not.
# (map index in main.gd's MAPS, nations on that map). Delete a line to take a map out of the public rotation.
PUBLIC_MAPS = [(0, 100), (1, 65), (2, 65), (3, 65), (4, 65)]
MAX_CONNS = 600                # connections (watchers + players) the server accepts at once

INT_FIELDS = {
    "attack": ["target"], "boat": ["tile"], "build": ["tile"], "sea": ["tile"], "ship": ["ship", "tile"], "shipatk": ["ship", "tgt"],
    "cancel": ["id"], "ally_ask": ["target"], "ally_cancel": ["target"], "trade_off": ["target"], "trade_on": ["target"], "pick": ["tile"],
    "nuke": ["tile"],      # Small Bomb / Nuke / Mega Bomb (this type was MISSING before: every bomb command was silently dropped online)
}
STR_FIELDS = {"build": ["kind"], "sea": ["kind"], "nuke": ["kind"]}
FRAC_TYPES = {"attack", "boat"}


def log(*a):
    print(time.strftime("%H:%M:%S"), *a, flush=True)


def is_int(v):
    return isinstance(v, int) and not isinstance(v, bool) and -2**31 < v < 2**31


def is_num(v):
    return isinstance(v, (int, float)) and not isinstance(v, bool) and v == v and abs(v) < 1e9


def clean_command(raw):
    """Returns a command dict that only contains known fields of the right type, or None."""
    if not isinstance(raw, dict):
        return None
    typ = raw.get("type")
    if typ not in INT_FIELDS:
        return None
    out = {"type": typ}
    for k in INT_FIELDS[typ]:
        if not is_int(raw.get(k)):
            return None
        out[k] = raw[k]
    for k in STR_FIELDS.get(typ, []):
        v = raw.get(k)
        if not isinstance(v, str) or len(v) > 16:
            return None
        out[k] = v
    if typ in FRAC_TYPES:
        f = raw.get("frac")
        if not is_num(f) or not (0.0 < f <= 1.0):
            return None
        out["frac"] = float(f)
    if typ == "attack" and "focus" in raw:
        fo = raw["focus"]
        if not (isinstance(fo, list) and len(fo) == 2 and is_num(fo[0]) and is_num(fo[1])):
            return None
        out["focus"] = [float(fo[0]), float(fo[1])]
    return out


# ----------------------------------------------------------------------------- minimal WebSocket (RFC 6455)

class Conn:
    def __init__(self, reader, writer):
        self.r = reader
        self.w = writer
        self.open = True
        # game state
        self.name = "Player"
        self.room = None
        self.slot = 0
        self.joined = False
        self.pub_watch = False     # watching the public lobby
        self.pub_in = False        # has taken one of the public player slots
        self.alive = True
        self.tokens = float(CMD_BURST)
        self.tok_t = time.monotonic()

    def _frame(self, opcode, payload=b""):
        n = len(payload)
        if n < 126:
            head = struct.pack("!BB", 0x80 | opcode, n)
        elif n < 65536:
            head = struct.pack("!BBH", 0x80 | opcode, 126, n)
        else:
            head = struct.pack("!BBQ", 0x80 | opcode, 127, n)
        return head + payload

    def send(self, obj):
        """Queue a JSON message. Never blocks: a client that cannot keep up is dropped."""
        if not self.open:
            return
        data = obj if isinstance(obj, str) else json.dumps(obj, separators=(",", ":"))
        try:
            self.w.write(self._frame(0x1, data.encode("utf-8")))
            if self.w.transport.get_write_buffer_size() > 2_000_000:
                log("dropping slow client", self.name)
                self.close()
        except Exception:
            self.close()

    def ping(self):
        if self.open:
            try:
                self.w.write(self._frame(0x9, b""))
            except Exception:
                self.close()

    def close(self):
        if self.open:
            self.open = False
            try:
                self.w.write(self._frame(0x8, struct.pack("!H", 1000)))
                self.w.close()
            except Exception:
                pass

    async def recv(self):
        """Returns the next text message, or None when the connection is over."""
        msg = bytearray()
        started = False
        while True:
            try:
                b0, b1 = await self.r.readexactly(2)
                fin = bool(b0 & 0x80)
                op = b0 & 0x0F
                masked = bool(b1 & 0x80)
                ln = b1 & 0x7F
                if ln == 126:
                    (ln,) = struct.unpack("!H", await self.r.readexactly(2))
                elif ln == 127:
                    (ln,) = struct.unpack("!Q", await self.r.readexactly(8))
                if ln > MAX_MSG or not masked:   # clients must mask; oversize = abuse
                    return None
                mask = await self.r.readexactly(4)
                data = bytearray(await self.r.readexactly(ln))
            except (asyncio.IncompleteReadError, ConnectionError, OSError):
                return None
            for i in range(ln):
                data[i] ^= mask[i & 3]
            if op == 0x8:
                return None
            if op == 0x9:      # ping -> pong
                try:
                    self.w.write(self._frame(0xA, bytes(data)))
                except Exception:
                    return None
                continue
            if op == 0xA:
                continue
            if op in (0x1, 0x2):
                msg = bytearray(data)
                started = True
            elif op == 0x0 and started:
                msg += data
                if len(msg) > MAX_MSG:
                    return None
            else:
                return None
            if fin:
                try:
                    return bytes(msg).decode("utf-8")
                except UnicodeDecodeError:
                    return None


async def handshake(reader, writer):
    """Reads the HTTP request. Returns True when upgraded to a WebSocket; answers plain HTTP itself (health check)."""
    try:
        raw = await asyncio.wait_for(reader.readuntil(b"\r\n\r\n"), 10)
    except Exception:
        return False
    head = raw.decode("latin-1").split("\r\n")
    hdr = {}
    for line in head[1:]:
        if ":" in line:
            k, v = line.split(":", 1)
            hdr[k.strip().lower()] = v.strip()
    key = hdr.get("sec-websocket-key")
    if "websocket" not in hdr.get("upgrade", "").lower() or not key:
        body = b"Landgrab relay is running.\n"
        writer.write(b"HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nContent-Length: %d\r\nConnection: close\r\n\r\n" % len(body) + body)
        try:
            await writer.drain()
        except Exception:
            pass
        writer.close()
        return False
    acc = base64.b64encode(hashlib.sha1(key.encode() + GUID).digest()).decode()
    writer.write(("HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n"
                  "Sec-WebSocket-Accept: %s\r\n\r\n" % acc).encode())
    await writer.drain()
    return True


# ----------------------------------------------------------------------------- rooms

class Room:
    def __init__(self, name):
        self.name = name
        self.clients = {}          # slot -> Conn  (lobby slots; renumbered 1..H when the match starts)
        self.host = 0
        self.map_idx = 0
        self.started = False
        self.pending = []          # commands for the next turn
        self.drops = []            # slots that left during the match
        self.sums = {}             # turn -> {slot: checksum}
        self.desync_sent = False
        self.task = None
        self.turn = 0

    def humans(self):
        return [c for c in self.clients.values() if c.alive]

    def broadcast(self, obj):
        data = json.dumps(obj, separators=(",", ":"))
        for c in list(self.clients.values()):
            if c.alive:
                c.send(data)

    def lobby_msg(self):
        return {"t": "lobby", "map": self.map_idx, "host": self.host, "started": self.started,
                "players": [{"slot": s, "name": c.name} for s, c in sorted(self.clients.items())]}

    def free_slot(self):
        for s in range(1, MAX_HUMANS + 1):
            if s not in self.clients:
                return s
        return 0

    def pick_host(self):
        self.host = min(self.clients) if self.clients else 0

    async def run(self):
        """The turn clock of a running match."""
        n = 0
        t0 = time.monotonic()
        next_t = t0
        try:
            while self.humans() and time.monotonic() - t0 < MAX_ROOM_SECS:
                next_t += TURN_SECS
                n += 1
                self.turn = n
                msg = {"t": "turn", "n": n}
                if self.pending:
                    msg["c"] = self.pending
                    self.pending = []
                if self.drops:
                    msg["d"] = self.drops
                    self.drops = []
                data = json.dumps(msg, separators=(",", ":"))
                for c in list(self.clients.values()):
                    if c.alive:
                        c.send(data)
                delay = next_t - time.monotonic()
                if delay < -1.0:       # the machine stalled: do not send a burst of turns, just carry on
                    next_t = time.monotonic()
                    delay = 0.0
                await asyncio.sleep(max(0.0, delay))
        finally:
            for c in list(self.clients.values()):
                c.close()
            ROOMS.pop(self.name, None)
            log("room", self.name, "closed after", n, "turns")


ROOMS = {}
PUB = None
CONNS = 0


def sanitize_name(v):
    if not isinstance(v, str):
        return "Player"
    s = "".join(ch for ch in v if ch.isprintable())[:MAX_NAME].strip()
    return s or "Player"


def sanitize_room(v):
    if not isinstance(v, str):
        return "main"
    s = "".join(ch for ch in v if ch.isalnum() or ch in "-_")[:MAX_ROOM].lower()
    return s or "main"


class PublicLobby:
    def __init__(self):
        self.seq = 0
        self.watchers = set()      # every connection looking at the lobby (players included)
        self.players = []          # connections that took a player slot, in join order
        self.match_no = 0
        self.last = None           # what happened to the previous lobby: {"map": idx, "humans": n}
        self.map_idx, self.cap = random.choice(PUBLIC_MAPS)
        self.next_idx, self.next_cap = self._other(self.map_idx)
        self.left = LOBBY_SECS

    @staticmethod
    def _other(cur):
        opts = [m for m in PUBLIC_MAPS if m[0] != cur] or PUBLIC_MAPS
        return random.choice(opts)

    def msg(self, c):
        return {"t": "pub", "seq": self.seq, "map": self.map_idx, "cap": self.cap, "next": self.next_idx,
                "next_cap": self.next_cap, "left": int(self.left + 0.999), "open": self.cap,
                "humans": [p.name for p in self.players], "in": c in self.players, "srv": SERVER_ID, "online": len(self.watchers),
                "me": self.players.index(c) if c in self.players else -1, "last": self.last}

    def broadcast(self):
        for c in list(self.watchers):
            c.send(self.msg(c))

    def watch(self, c):
        c.pub_watch = True
        self.watchers.add(c)
        c.send(self.msg(c))

    def join(self, c, name):
        if c in self.players or c not in self.watchers:
            return
        if len(self.players) >= self.cap:
            c.send({"t": "pnote", "m": "This lobby is full - the next one opens when the timer ends."})
            return
        c.name = sanitize_name(name)
        c.pub_in = True
        self.players.append(c)
        log("public: +", c.name, "(%d/%d players, map %d)" % (len(self.players), self.cap, self.map_idx))
        if len(self.players) >= self.cap:
            # every player slot is taken: the match starts this very second, the next lobby opens right away
            self.start_match()
            self.roll()
        else:
            self.broadcast()

    def drop(self, c):
        """Leave the player slot (stays a watcher)."""
        if c in self.players:
            self.players.remove(c)
            c.pub_in = False
            self.broadcast()

    def remove(self, c):
        """The connection is gone."""
        self.watchers.discard(c)
        self.drop(c)
        c.pub_watch = False

    def start_match(self):
        humans = [c for c in self.players if c.open]
        if not humans:
            self.last = {"map": self.map_idx, "humans": 0}
            return
        self.match_no += 1
        room = Room("!pub%d" % self.match_no)      # "!" can never be typed as a private room name
        ROOMS[room.name] = room
        roster = []
        for i, c in enumerate(humans, start=1):
            c.slot, c.room, c.joined, c.alive = i, room, True, True
            c.pub_in = False
            c.pub_watch = False
            self.watchers.discard(c)
            room.clients[i] = c
            roster.append({"slot": i, "name": c.name})
        room.started = True
        room.host = 0
        room.map_idx = self.map_idx
        seed = random.randint(1, 2**31 - 1)
        for i, c in room.clients.items():
            c.send({"t": "begin", "map": self.map_idx, "seed": seed, "n": self.cap, "players": roster, "you": i})
        log("public match", room.name, "STARTED map", self.map_idx, "nations", self.cap, "humans", [p["name"] for p in roster], "seed", seed)
        room.task = asyncio.ensure_future(room.run())
        self.last = {"map": self.map_idx, "humans": len(humans)}

    def roll(self):
        self.seq += 1
        self.players = []
        for c in self.watchers:
            c.pub_in = False
        self.map_idx, self.cap = self.next_idx, self.next_cap
        self.next_idx, self.next_cap = self._other(self.map_idx)
        self.left = LOBBY_SECS
        self.broadcast()

    async def run(self):
        last = time.monotonic()
        while True:
            await asyncio.sleep(1.0)
            now = time.monotonic()
            self.left -= now - last
            last = now
            if self.left <= 0:
                try:
                    self.start_match()
                except Exception as e:      # a bug here must never stop the lobby from rolling over
                    log("public start error:", repr(e))
                self.roll()
            else:
                self.broadcast()


def leave(c):
    if PUB is not None:
        PUB.remove(c)
    room = c.room
    if room is None or not c.joined:
        return
    c.alive = False
    c.joined = False
    if not room.started:
        room.clients.pop(c.slot, None)
        if not room.clients:
            ROOMS.pop(room.name, None)
            log("room", room.name, "empty, removed")
            return
        if room.host == c.slot:
            room.pick_host()
        room.broadcast(room.lobby_msg())
    else:
        room.drops.append(c.slot)
        log("room", room.name, "slot", c.slot, c.name, "left the match")


def handle(c, text):
    try:
        d = json.loads(text)
    except ValueError:
        return
    if not isinstance(d, dict):
        return
    t = d.get("t")
    if t == "watch":
        if c.joined or c.pub_watch or PUB is None:
            return
        if d.get("ver") != PROTO_VERSION:
            c.send({"t": "err", "m": "Version mismatch: the server speaks protocol %d, this game build speaks %s. The older one must be updated: re-export the game, or re-deploy relay.py." % (PROTO_VERSION, d.get("ver"))})
            c.close()
            return
        PUB.watch(c)
        return
    if t == "pjoin":
        if c.pub_watch and PUB is not None:
            PUB.join(c, d.get("name"))
        return
    if t == "pleave":
        if c.pub_watch and PUB is not None:
            PUB.drop(c)
        return
    if t == "join":
        if c.joined or c.pub_watch:
            return
        if d.get("ver") != PROTO_VERSION:
            c.send({"t": "err", "m": "Version mismatch: the server speaks protocol %d, this game build speaks %s. The older one must be updated: re-export the game, or re-deploy relay.py." % (PROTO_VERSION, d.get("ver"))})
            c.close()
            return
        name = sanitize_room(d.get("room"))
        room = ROOMS.get(name)
        if room is None:
            room = ROOMS[name] = Room(name)
            log("room", name, "created")
        if room.started:
            c.send({"t": "err", "m": "That room's match already started. Use another room name."})
            c.close()
            return
        slot = room.free_slot()
        if slot == 0:
            c.send({"t": "err", "m": "Room is full (%d players)." % MAX_HUMANS})
            c.close()
            return
        c.name = sanitize_name(d.get("name"))
        c.room = room
        c.slot = slot
        c.joined = True
        room.clients[slot] = c
        if room.host == 0 or room.host not in room.clients:
            room.pick_host()
        log("room", name, "+", c.name, "slot", slot, "(%d in room)" % len(room.clients))
        c.send({"t": "joined", "you": slot, "host": room.host == slot})
        room.broadcast(room.lobby_msg())
        return
    room = c.room
    if room is None or not c.joined:
        return
    if t == "map" and not room.started and c.slot == room.host:
        idx = d.get("idx")
        if is_int(idx) and 0 <= idx <= 20:
            room.map_idx = idx
            room.broadcast(room.lobby_msg())
    elif t == "start" and not room.started and c.slot == room.host:
        n = d.get("n")
        n = n if is_int(n) else 24
        humans = sorted(room.clients.items())
        n = max(len(humans) + 1, min(n, 120))
        seed = random.randint(1, 2**31 - 1)
        # final slot numbers 1..H in join order; every client gets its own number in "you"
        final = {}
        roster = []
        for i, (old, cl) in enumerate(humans, start=1):
            final[old] = i
            roster.append({"slot": i, "name": cl.name})
        newmap = {}
        for old, cl in humans:
            cl.slot = final[old]
            newmap[cl.slot] = cl
        room.clients = newmap
        room.started = True
        room.host = 0
        for s, cl in newmap.items():
            cl.send({"t": "begin", "map": room.map_idx, "seed": seed, "n": n, "players": roster, "you": s})
        log("room", room.name, "STARTED map", room.map_idx, "nations", n, "humans", [p["name"] for p in roster], "seed", seed)
        room.task = asyncio.ensure_future(room.run())
    elif t == "cmd" and room.started:
        now = time.monotonic()
        c.tokens = min(float(CMD_BURST), c.tokens + (now - c.tok_t) * CMD_PER_SEC)
        c.tok_t = now
        if c.tokens < 1.0:
            return
        cmd = clean_command(d.get("c"))
        if cmd is None:
            return
        c.tokens -= 1.0
        cmd["slot"] = c.slot            # the sender is the connection, whatever the message says
        room.pending.append(cmd)
    elif t == "sum" and room.started:
        n, h = d.get("n"), d.get("h")
        if not (is_int(n) and is_int(h)):
            return
        bucket = room.sums.setdefault(n, {})
        bucket[c.slot] = h
        if len(set(bucket.values())) > 1 and not room.desync_sent:
            room.desync_sent = True
            log("room", room.name, "DESYNC at turn", n, bucket)
            room.broadcast({"t": "desync", "n": n})
        for old in [k for k in room.sums if k < n - 200]:
            del room.sums[old]


async def on_client(reader, writer):
    global CONNS
    c = Conn(reader, writer)
    if CONNS >= MAX_CONNS:
        writer.close()
        return
    CONNS += 1
    try:
        if not await handshake(reader, writer):
            return
        while True:
            text = await c.recv()
            if text is None:
                break
            handle(c, text)
    except Exception as e:      # one bad client must never stop the server
        log("client error:", repr(e))
    finally:
        CONNS -= 1
        leave(c)
        c.close()


async def pinger():
    while True:
        await asyncio.sleep(PING_EVERY)
        for room in list(ROOMS.values()):
            for cl in list(room.clients.values()):
                cl.ping()
        if PUB is not None:
            for cl in list(PUB.watchers):
                cl.ping()


async def main():
    global PUB
    PUB = PublicLobby()
    asyncio.ensure_future(PUB.run())
    port = int(sys.argv[1]) if len(sys.argv) > 1 else int(os.environ.get("PORT", "8765"))
    host = os.environ.get("HOST", "0.0.0.0")
    # Your own domain + fixed IP: set TLS_CERT and TLS_KEY (paths to the certificate chain and private key, e.g. from Let's Encrypt)
    # and this process serves wss:// by itself. Without them it serves plain ws:// (put Caddy / nginx in front for wss://, see DEPLOY.md).
    ssl_ctx = None
    cert, key = os.environ.get("TLS_CERT"), os.environ.get("TLS_KEY")
    if cert and key:
        ssl_ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        ssl_ctx.load_cert_chain(cert, key)
        log("TLS on: this relay speaks wss:// directly on port", port)
    server = await asyncio.start_server(on_client, host, port, limit=2 ** 17, ssl=ssl_ctx)
    asyncio.ensure_future(pinger())
    log("Hosting checklist: (1) this process keeps running, (2) a wss:// address points at port %d, (3) OFFICIAL_SERVER in main.gd is exactly that address, (4) NET_VER in main.gd == %d. Test: python check_server.py <address>" % (port, PROTO_VERSION))
    log("Landgrab relay SERVER", SERVER_ID, "protocol", PROTO_VERSION, "listening on port", port, "(%s://localhost:%d)" % ("wss" if ssl_ctx else "ws", port),
        "- public lobby: map", PUB.map_idx, "next", PUB.next_idx, "every", int(LOBBY_SECS), "s")
    async with server:
        await server.serve_forever()


if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        pass
