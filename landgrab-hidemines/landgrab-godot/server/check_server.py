#!/usr/bin/env python3
"""Checks a hosted Landgrab relay from your PC (Python 3.8+, no packages).

    python check_server.py https://your-domain.com        (or wss://..., ws://localhost:8765, or just your-domain.com)
    python check_server.py https://your-domain.com 16     (second argument = the NET_VER of your game build, default = this folder's PROTO_VERSION)

It does what the game does: opens the address, upgrades to a WebSocket, says "watch" and prints what the server answers.
"""
import base64, json, os, socket, ssl, struct, sys
from urllib.parse import urlparse

def main():
    raw = sys.argv[1] if len(sys.argv) > 1 else "ws://localhost:8765"
    ver = int(sys.argv[2]) if len(sys.argv) > 2 else None
    if ver is None:
        try:
            src = open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "relay.py"), encoding="utf-8").read()
            ver = int(src.split("PROTO_VERSION = ")[1].split()[0])
        except Exception:
            ver = 17
    if "://" not in raw:
        raw = "wss://" + raw
    u = urlparse(raw)
    tls = u.scheme in ("wss", "https")
    host = u.hostname
    port = u.port or (443 if tls else 80)
    print("address: %s   host=%s port=%d tls=%s   game protocol to test: %d" % (raw, host, port, tls, ver))
    try:
        s = socket.create_connection((host, port), timeout=10)
    except OSError as e:
        print("FAIL: cannot open a connection:", e, "\n -> wrong address, the server / tunnel is not running, or the port is blocked.")
        return 1
    if tls:
        try:
            s = ssl.create_default_context().wrap_socket(s, server_hostname=host)
        except ssl.SSLError as e:
            print("FAIL: TLS problem:", e, "\n -> the address needs a valid https certificate (use Caddy / your host's HTTPS / a Cloudflare tunnel).")
            return 1
    s.settimeout(10)
    key = base64.b64encode(os.urandom(16)).decode()
    s.sendall(("GET / HTTP/1.1\r\nHost: %s\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Key: %s\r\nSec-WebSocket-Version: 13\r\nOrigin: https://itch.io\r\n\r\n" % (host, key)).encode())
    buf = b""
    try:
        while b"\r\n\r\n" not in buf:
            chunk = s.recv(4096)
            if not chunk:
                break
            buf += chunk
    except socket.timeout:
        pass
    status = buf.split(b"\r\n")[0].decode("latin-1") if buf else "(no answer)"
    print("HTTP upgrade answer:", status)
    if "101" not in status:
        print("FAIL: the WebSocket upgrade was refused. -> this is not the relay, or a proxy in front does not pass WebSockets (turn WebSocket support on).")
        print(buf[:300].decode("latin-1"))
        return 1
    rest = buf.split(b"\r\n\r\n", 1)[1]
    data = json.dumps({"t": "watch", "ver": ver}).encode()
    mask = os.urandom(4)
    s.sendall(bytes([0x81, 0x80 | len(data)]) + mask + bytes(b ^ mask[i % 4] for i, b in enumerate(data)))
    def need(n):
        nonlocal rest
        while len(rest) < n:
            c = s.recv(65536)
            if not c:
                raise ConnectionError("closed")
            rest += c
        out, rest = rest[:n], rest[n:]
        return out
    try:
        b0, b1 = need(2)
        ln = b1 & 0x7F
        if ln == 126: ln = struct.unpack("!H", need(2))[0]
        elif ln == 127: ln = struct.unpack("!Q", need(8))[0]
        msg = json.loads(need(ln).decode())
    except Exception as e:
        print("FAIL: connected but no usable answer:", repr(e))
        return 1
    if msg.get("t") == "pub":
        print("OK: the relay answered. map %s, %s s left in the public lobby, server id %s, %s watching." % (msg.get("map"), msg.get("left"), msg.get("srv"), msg.get("online")))
        print("Public lobby player slots on this server: %s  (must be 100 for the World map, 65 for the continents - 2 means an OLD relay.py is still running)" % msg.get("open"))
        print("Now make sure OFFICIAL_SERVER in main.gd is this address and the game build was re-exported.")
        return 0
    if msg.get("t") == "err":
        print("SERVER SAYS:", msg.get("m"))
        return 1
    print("unexpected answer:", msg)
    return 1

if __name__ == "__main__":
    sys.exit(main())
