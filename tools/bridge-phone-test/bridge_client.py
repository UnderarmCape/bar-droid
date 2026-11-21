"""tools/bridge-phone-test.ps1's client: another app on the phone talking to the lobby bridge (LobbyBridge), through
adb's port forward (adbd connects from its own user, as another app would). Asks for what BAR's lobby never does, and
for one thing it does, and prints one line per answer: "<case> <result>".
    python -I bridge_client.py <local port>"""
import json
import socket
import sys
import time

PORT = int(sys.argv[1])
HUB = "https://widget-hub.beyondallreason.dev/manifests.json"


def conn():
    s = socket.create_connection(("127.0.0.1", PORT), timeout=5)
    s.settimeout(1.0)
    return s


def send(s, name, command):
    s.sendall((json.dumps({"name": name, "command": command}) + "\n").encode())


def answers(s, seconds):
    """Every JSON line the bridge sends within seconds."""
    out, buf, end = [], b"", time.time() + seconds
    while time.time() < end:
        try:
            chunk = s.recv(65536)
        except socket.timeout:
            continue
        if not chunk:
            break
        buf += chunk
        while b"\n" in buf:
            line, buf = buf.split(b"\n", 1)
            try:
                out.append(json.loads(line))
            except ValueError:
                pass
    return out


def download(s, dest):
    send(s, "Download", {"name": dest, "type": "resource", "resource": {"url": HUB, "destination": dest, "extract": False}})
    for a in answers(s, 25):
        if a.get("name") == "DownloadFinished" and a.get("command", {}).get("name") == dest:
            return "success" if a["command"].get("isSuccess") else "failed"
    return "no answer"


s = conn()
print("widget", download(s, "LuaUI/Widgets/bardroid_bridge_evil.lua"))
print("devenv", download(s, "dev-env.sh"))
print("manifest", download(s, "LuaUI/Widgets/manifests.json"))
send(s, "ReadReplayInfo", {"relativePath": "../../shared_prefs/bardroid.xml"})
got = [a for a in answers(s, 4) if a.get("name") == "ReplayInfo"]
print("replay", "answered" if got else "no answer")
# (the lobby holds one connection, this test a second: a third is refused)
third = conn()
try:
    third.settimeout(3.0)
    data = third.recv(1)
    print("third", "closed" if data == b"" else "open")
except socket.timeout:
    print("third", "open")
except OSError:
    print("third", "closed")
third.close()
s.close()
