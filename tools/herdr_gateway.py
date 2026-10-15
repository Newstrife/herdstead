#!/usr/bin/env python3
"""The herdr gateway: one LAN port that serves the web office and proxies herdr.

Herdstead's desktop build talks to herdr over Unix sockets, which a browser
cannot open. This gateway bridges the gap, with no logic of its own: it serves
the web export over HTTP and forwards WebSocket connections byte for byte onto
herdr sockets. Everything Herdstead sends stays exactly what it sends on a
socket; the write boundary (scripts/herdr_commands.gd) is unchanged, and this
gateway adds no requests of its own.

Endpoints on the one port (default 8765):

- GET  /                     and any other path under --web: the web export.
- GET  /api/machines         the bytes `herdr machine list --json` printed,
                             so the office's MachineRoster reads machines the
                             same way it does from a child process.
- WS   /ws/local             the local herdr socket (--socket).
- WS   /ws/machine?target=T&session=S
                             herdr on a saved SSH machine. One `ssh -N -L`
                             forward per machine is held for the gateway's
                             lifetime (ssh multiplexes connections onto it);
                             every WebSocket opens its own Unix connection to
                             the forward's local end, so a dead forward is only
                             ever respawned.

A WebSocket message is a chunk, not a request: lines may split across chunks,
as they do across socket reads, and the client's LineReader reassembles them.

LAN only: the port listens on every interface, forwards herdr's whole API
(reads AND writes) to anyone who can reach it, and serves files from --web.
There is no authentication by design.

Stale forwards from a crashed gateway are swept at startup: every hs-gw-*
tempdir carries the owning gateway's pid and its ssh's pid in sidecars, and
only a directory whose owner is dead is touched — a live gateway's tunnels
are left alone, as are directories nothing can vouch for.

Depends on `websockets` (`make setup`); the rest is the standard library.
"""

import argparse
import asyncio
import glob
import json
import mimetypes
import os
import re
import shutil
import signal
import subprocess
import sys
import tempfile
import urllib.parse

import websockets

## Longest a machine list may take before the roster's own timeout wins anyway.
LIST_TIMEOUT = 8
## ssh's connect timeout, as MachineLink's CONNECT_TIMEOUT.
SSH_CONNECT_TIMEOUT = 10
## Bytes per read either way on a bridged connection.
CHUNK = 32768
## A remote $HOME longer than this is refused, as MachineLink's HOME_MAX.
HOME_MAX = 256
## herdr's own session-name rule, as MachineLink's check_session().
SESSION_RE = re.compile(r"^[A-Za-z0-9._-]*$")
## ssh's keepalive, as MachineLink's ALIVE_INTERVAL / ALIVE_COUNT.
ALIVE_INTERVAL = 15
ALIVE_COUNT = 3
## A WebSocket message from a client is a chunk of a request line; the
## boundary's largest payload is a 64 KiB paste, so 1 MiB is generous.
MAX_MESSAGE = 1048576
## Fastest a dead tunnel may be respawned (ssh to a down machine costs seconds).
RESPAWN_MIN = 5.0
## One-shot $HOME lookup on the far side, as MachineLink's HOME_COMMAND.
HOME_COMMAND = "printf '\\nHS_HOME=%s\\nHS_END\\n' \"$HOME\""


def default_socket() -> str:
    """--socket beats HERDR_SOCKET_PATH beats the default session socket."""
    return os.environ.get(
        "HERDR_SOCKET_PATH", os.path.expanduser("~/.config/herdr/herdr.sock")
    )


def _invisible(code: int) -> bool:
    """MachineLink._invisible, code point for code point."""
    return (
        code <= 0x20
        or 0x7F <= code <= 0xA0
        or code == 0x1680
        or 0x2000 <= code <= 0x200F
        or 0x2028 <= code <= 0x202F
        or code == 0x205F
        or code == 0x3000
        or code == 0xFEFF
    )


def check_target(target: str) -> str:
    """Empty when `target` can be handed to ssh, as MachineLink.check_target()."""
    if not target:
        return "empty SSH target"
    if target.startswith("-"):
        return "SSH target must not start with '-'"
    if any(_invisible(ord(c)) for c in target):
        return "SSH target has whitespace or control characters"
    return ""


def check_session(session: str) -> str:
    """Empty when `session` is a herdr session name, as check_session()."""
    if session in (".", "..") or not SESSION_RE.fullmatch(session):
        return "remote session name must be ASCII letters, digits, '.', '_' or '-'"
    return ""


def check_home(home: str) -> str:
    """Empty when a remote $HOME can go into `-L`, as MachineLink.check_home()."""
    if not home.startswith("/"):
        return "remote $HOME is not an absolute path"
    if len(home) > HOME_MAX:
        return f"remote $HOME is longer than {HOME_MAX} characters"
    if any(ord(c) < 0x20 or ord(c) > 0x7E for c in home):
        return "remote $HOME is not one line of printable ASCII"
    if ":" in home or "$" in home:
        return "remote $HOME contains ':' or '$', which ssh -L cannot carry"
    return ""


def remote_socket_path(home: str, session: str) -> str:
    """The remote socket as herdr lays it out, as MachineLink's."""
    base = home.rstrip("/") + "/.config/herdr"
    if session in ("", "default"):
        return base + "/herdr.sock"
    return base + "/sessions/" + session + "/herdr.sock"


def escape_forward(path: str) -> str:
    """ssh expands `%` tokens in `-L` paths on this side; `%%` is a literal."""
    return path.replace("%", "%%")


def ssh_options() -> list[str]:
    """MachineLink's common_options(): our own connection, never a master."""
    return [
        "-n",
        "-T",
        "-o",
        "BatchMode=yes",
        "-o",
        f"ConnectTimeout={SSH_CONNECT_TIMEOUT}",
        "-o",
        "ControlPath=none",
        "-o",
        "LogLevel=ERROR",
    ]


def ssh_forward_options() -> list[str]:
    """MachineLink's forward_argv extras: die with the forward, die when the
    network does (a half-open ssh must not pin a machine offline forever)."""
    return [
        "-o",
        "ExitOnForwardFailure=yes",
        "-o",
        f"ServerAliveInterval={ALIVE_INTERVAL}",
        "-o",
        f"ServerAliveCountMax={ALIVE_COUNT}",
        "-o",
        "StreamLocalBindUnlink=yes",
    ]


class Tunnel:
    """One held `ssh -N -L` forward: its local socket once it is listening.

    The ssh pid is written to a sidecar next to the socket, so a gateway that
    died hard can be swept after the fact (sweep_leftovers()).
    """

    SIDECAR = "ssh.pid"
    ## The owning gateway's own pid, beside the ssh one: a sweep may only reap
    ## a directory whose gateway is dead ("a live owner is left alone").
    OWNER = "gateway.pid"

    def __init__(self, target: str, session: str):
        self.target = target
        self.session = session
        self.local_socket = ""
        self._dir = ""
        self._proc: subprocess.Popen | None = None
        self._lock = asyncio.Lock()
        self._next_spawn = 0.0
        ## Set from outside the lock (a connection that found the socket dead);
        ## the teardown itself always happens inside ensure()'s lock.
        self._dead = False

    async def ensure(self) -> str:
        """The forward's local socket path, respawning ssh as needed."""
        async with self._lock:
            if self._proc is not None and not self._dead and self._proc.poll() is None:
                return self.local_socket
            self._dead = False
            self._teardown()
            left = self._next_spawn - asyncio.get_running_loop().time()
            if left > 0:
                raise RuntimeError(f"respawning the forward in {left:.0f}s")
            self._next_spawn = asyncio.get_running_loop().time() + RESPAWN_MIN
            home = await asyncio.to_thread(self._ask_home)
            problem = check_home(home)
            if problem:
                raise RuntimeError(problem)
            remote = remote_socket_path(home, self.session)
            self._dir = tempfile.mkdtemp(prefix="hs-gw-")
            # The owner marker first: a crash after spawn must still leave a
            # sweepable directory.
            with open(os.path.join(self._dir, self.OWNER), "w") as handle:
                handle.write(str(os.getpid()))
            self.local_socket = os.path.join(self._dir, "herdr.sock")
            forward = escape_forward(self.local_socket) + ":" + escape_forward(remote)
            self._proc = subprocess.Popen(
                ["ssh", *ssh_options(), *ssh_forward_options(), "-N", "-L", forward, "--", self.target],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )
            with open(os.path.join(self._dir, self.SIDECAR), "w") as handle:
                handle.write(str(self._proc.pid))
            for _ in range(2 * SSH_CONNECT_TIMEOUT * 10):
                if os.path.exists(self.local_socket):
                    return self.local_socket
                if self._proc.poll() is not None:
                    break
                await asyncio.sleep(0.05)
            self._teardown()
            raise RuntimeError(f"ssh to {self.target} did not open the forward")

    ## The forward's ssh died or stopped answering: forget it so the next
    ## connection respawns one, as a dead MachineLink is retried. Only marks;
    ## ensure() does the teardown under its lock. A connection that fails on
    ## `local` names the socket it tried: if ensure() already respawned (the
    ## path moved), that failure belongs to the old tunnel and marks nothing.
    def reset(self, local: str) -> None:
        if local == self.local_socket:
            self._dead = True

    def _ask_home(self) -> str:
        try:
            out = subprocess.run(
                ["ssh", *ssh_options(), "--", self.target, HOME_COMMAND],
                capture_output=True,
                text=True,
                timeout=2 * SSH_CONNECT_TIMEOUT,
            ).stdout
        except subprocess.SubprocessError as why:
            raise RuntimeError(f"ssh to {self.target} did not answer") from why
        end = out.rfind("\nHS_END")
        begin = out.rfind("HS_HOME=", 0, end if end >= 0 else None)
        if end < 0 or begin < 0:
            raise RuntimeError(f"ssh to {self.target} gave no remote $HOME")
        return out[begin + 8 : end]

    def _teardown(self) -> None:
        if self._proc is not None:
            if self._proc.poll() is None:
                self._proc.terminate()
                try:
                    self._proc.wait(timeout=3)
                except subprocess.TimeoutExpired:
                    self._proc.kill()
            self._proc = None
        if self._dir:
            shutil.rmtree(self._dir, ignore_errors=True)
            self._dir = ""
            self.local_socket = ""

    def stop(self) -> None:
        self._teardown()


def _pid_alive(pid: int) -> bool:
    try:
        os.kill(pid, 0)
    except OSError:
        return False
    return True


def _pid_is_ssh_holding(pid: int, path: str) -> bool:
    """True when pid is an ssh whose command line names this forward's
    directory. Reads /proc on Linux, `ps` elsewhere; when neither can say, it
    is not its ssh (and nothing is killed)."""
    try:
        with open(f"/proc/{pid}/cmdline", "rb") as handle:
            argv = handle.read().split(b"\0")
            return b"ssh" in argv[0] and path.encode() in argv
    except OSError:
        pass
    try:
        out = subprocess.run(
            ["ps", "-ww", "-p", str(pid), "-o", "command="],
            capture_output=True, text=True, timeout=5,
        ).stdout
        return "ssh" in out.split()[:1] and path in out
    except (OSError, subprocess.SubprocessError):
        return False


def sweep_leftovers() -> list[str]:
    """Kill and remove hs-gw-* forwards a hard-died gateway left, as
    MachineLink.clean_leftovers() sweeps the desktop's: a live owner is left
    alone (its gateway.pid answers), and a directory without one is skipped
    whole. The ssh is killed only when ps / /proc can vouch it is the ssh
    holding this very forward; the directory goes regardless, its owner dead."""
    swept = []
    for path in glob.glob(os.path.join(tempfile.gettempdir(), "hs-gw-*")):
        try:
            with open(os.path.join(path, Tunnel.OWNER)) as handle:
                owner = int(handle.read().strip())
        except (OSError, ValueError):
            continue
        if _pid_alive(owner):
            continue
        try:
            with open(os.path.join(path, Tunnel.SIDECAR)) as handle:
                ssh_pid = int(handle.read().strip())
            if _pid_alive(ssh_pid) and _pid_is_ssh_holding(ssh_pid, path):
                os.kill(ssh_pid, signal.SIGTERM)
        except (OSError, ValueError):
            pass
        shutil.rmtree(path, ignore_errors=True)
        swept.append(path)
    return swept


class Gateway:
    """The one port: the web export, the machine list, and socket bridges."""

    def __init__(self, args: argparse.Namespace):
        self.socket = args.socket
        self.web = os.path.realpath(args.web)
        self.herdr = args.herdr_bin
        self.tunnels: dict[tuple[str, str], Tunnel] = {}

    async def http(self, connection, request) -> "websockets.Response | None":
        """Answer plain HTTP, or None to let the WebSocket upgrade through.

        An endpoint that cannot serve refuses before the handshake, so a bad
        machine ask is a plain HTTP 400, not an open-then-closed socket.
        """
        path = urllib.parse.urlsplit(request.path).path
        if path == "/api/machines":
            body, status = await asyncio.to_thread(self._machine_list)
            return self._respond(status, body, "application/json")
        if path.startswith("/ws/"):
            problem = self._ws_problem(request.path)
            return self._respond(400, (problem + "\n").encode()) if problem else None
        if request.headers.get("Upgrade", "").lower() == "websocket":
            return None
        return await self._static(path)

    @staticmethod
    def _ws_problem(raw_path: str) -> str:
        """Empty when this WebSocket path may upgrade; the refusal otherwise."""
        split = urllib.parse.urlsplit(raw_path)
        if split.path == "/ws/local":
            return ""
        if split.path == "/ws/machine":
            query = urllib.parse.parse_qs(split.query)
            return check_target(query.get("target", [""])[0]) or check_session(
                query.get("session", [""])[0]
            )
        return "unknown endpoint"

    async def _static(self, path: str) -> "websockets.Response":
        if path == "/":
            path = "/index.html"
        root = os.path.realpath(os.path.join(self.web, path.lstrip("/")))
        # commonpath, not a prefix string: a sibling named web2 must not pass.
        try:
            inside = os.path.commonpath([root, self.web]) == self.web
        except ValueError:
            inside = False
        if not inside or not os.path.isfile(root):
            return self._respond(404, b"not found\n")
        # The wasm is tens of MB; reading it must not stall the WS pumps.
        def read_file() -> bytes:
            with open(root, "rb") as handle:
                return handle.read()

        try:
            body = await asyncio.to_thread(read_file)
        except OSError:
            return self._respond(404, b"not found\n")
        kind = mimetypes.guess_type(root)[0] or "application/octet-stream"
        if root.endswith(".wasm"):
            kind = "application/wasm"
        return self._respond(200, body, kind)

    @staticmethod
    def _respond(status: int, body: bytes, kind: str = "text/plain") -> websockets.Response:
        reason = {
            200: "OK", 400: "Bad Request", 404: "Not Found",
            502: "Bad Gateway", 503: "Service Unavailable",
        }.get(status, "?")
        return websockets.Response(status, reason, websockets.Headers({"Content-Type": kind}), body)

    def _machine_list(self) -> tuple[bytes, int]:
        """(body, HTTP status): herdr's stdout verbatim; 503 when herdr cannot
        run at all (the roster's "gone", as a missing binary is on the
        desktop), 502 when it ran and failed (a transient list failure)."""
        try:
            run = subprocess.run(
                [self.herdr, "machine", "list", "--json"],
                capture_output=True,
                timeout=LIST_TIMEOUT,
            )
        except OSError as why:
            return json.dumps({"error": f"herdr machine list failed: {why}"}).encode(), 503
        except subprocess.TimeoutExpired:
            return json.dumps({"error": "herdr machine list timed out"}).encode(), 502
        # The roster's child-process path checks the exit code first; so does
        # this one, and a nonzero exit's stdout is never mistaken for a list.
        if run.returncode != 0:
            detail = run.stderr.decode(errors="replace").strip() or "no answer"
            return json.dumps({"error": detail}).encode(), 502
        return run.stdout, 200

    async def bridge(self, ws) -> None:
        """One WebSocket to one herdr connection; closes propagate both ways."""
        path = urllib.parse.urlsplit(ws.request.path).path
        query = urllib.parse.parse_qs(urllib.parse.urlsplit(ws.request.path).query)
        try:
            if path == "/ws/local":
                reader, writer = await asyncio.open_unix_connection(self.socket)
            elif path == "/ws/machine":
                target = query.get("target", [""])[0]
                session = query.get("session", [""])[0]
                problem = check_target(target) or check_session(session)
                if problem:
                    await ws.close(1008, problem)
                    return
                key = (target, session)
                tunnel = self.tunnels.get(key)
                if tunnel is None:
                    tunnel = Tunnel(target, session)
                    self.tunnels[key] = tunnel
                try:
                    local = await tunnel.ensure()
                except (OSError, RuntimeError) as why:
                    await ws.close(1011, "forward failed")
                    print(f"GATEWAY_FORWARD_FAIL: {target}: {why}")
                    return
                try:
                    reader, writer = await asyncio.open_unix_connection(local)
                except OSError:
                    # The socket file outlived its ssh: drop the tunnel so the
                    # next connection spawns a fresh one.
                    tunnel.reset(local)
                    await ws.close(1011, "forward not listening")
                    return
            else:
                await ws.close(1003, "unknown endpoint")
                return
        except OSError:
            # A fixed phrase, never the exception text: it would carry local
            # paths to anyone on the LAN.
            await ws.close(1011, "herdr unreachable")
            return
        print(f"GATEWAY_OPEN: {path} ({ws.remote_address[0]})")
        await self._pump(ws, reader, writer)

    async def _pump(self, ws, reader, writer) -> None:
        # The first line the client sends names its method; events.subscribe
        # is the one long-lived stream. Anything else is a single request that
        # herdr answers and closes. The head accumulates across messages (a
        # message is a chunk, lines may split), until a newline or 200 bytes —
        # request_line()'s {"id", "method", "params"} order puts the method
        # key well within that. Matching `"method":"events.subscribe"` (JSON
        # escapes a quote inside any string value, so only the envelope's own
        # key can produce those bytes), whitespace stripped.
        is_stream = False
        sniffed = False
        head = b""

        async def ws_to_socket() -> None:
            nonlocal is_stream, sniffed, head
            async for message in ws:
                chunk = message if isinstance(message, bytes) else message.encode()
                if not sniffed:
                    head += chunk
                    if b"\n" in head or len(head) >= 200:
                        sniffed = True
                        flat = head.replace(b" ", b"").replace(b"\t", b"").replace(b"\r", b"")
                        is_stream = b'"method":"events.subscribe"' in flat
                writer.write(chunk)
                await writer.drain()
            writer.close()

        async def socket_to_ws() -> None:
            while True:
                chunk = await reader.read(CHUNK)
                if not chunk:
                    break
                await ws.send(chunk)
            if is_stream:
                # A dead subscription stream must reach the office at once
                # (invariant: a disconnect is never drawn as alive). The
                # close-after-data race risks losing only the dying stream's
                # last events, which a resubscribe would repeat anyway.
                await ws.close()
                return
            # A request's answer, by contrast, must not share a read batch
            # with the close frame (Godot's WebSocketPeer drops buffered
            # packets on close): the client closes once it has its line, so
            # the initiative stays where the data is. The timeout only sweeps
            # a client that never read.
            try:
                await asyncio.wait_for(ws.wait_closed(), timeout=10)
            except asyncio.TimeoutError:
                if ws.state is websockets.State.OPEN:
                    await ws.close()

        tasks = [asyncio.ensure_future(ws_to_socket()), asyncio.ensure_future(socket_to_ws())]
        done, pending = await asyncio.wait(tasks, return_when=asyncio.FIRST_COMPLETED)
        for task in done:
            why = task.exception()
            # A client dropping TCP mid-stream is ordinary; anything else is not.
            if why is not None and not isinstance(why, websockets.ConnectionClosed):
                print(f"GATEWAY_PUMP_ERROR: {why!r}")
        for task in pending:
            task.cancel()
        await asyncio.gather(*pending, return_exceptions=True)
        if not writer.is_closing():
            writer.close()
        if ws.state is websockets.State.OPEN:
            await ws.close()

    async def serve(self, host: str, port: int) -> None:
        async with websockets.serve(
            self.bridge, host, port, process_request=self.http, max_size=MAX_MESSAGE, compression=None
        ):
            print(f"GATEWAY_START: http+ws on {host}:{port} (web: {self.web}, socket: {self.socket})")
            await asyncio.get_running_loop().create_future()

    def stop_tunnels(self) -> None:
        for tunnel in self.tunnels.values():
            tunnel.stop()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--host", default="0.0.0.0", help="listen address (LAN: the default)")
    parser.add_argument("--port", type=int, default=8765)
    parser.add_argument("--socket", default=default_socket(), help="local herdr socket")
    parser.add_argument("--web", default="build/web", help="the web export's directory")
    parser.add_argument("--herdr-bin", default="herdr")
    args = parser.parse_args()
    for leftover in sweep_leftovers():
        print("Removed a stale gateway forward: " + leftover)
    gateway = Gateway(args)
    try:
        asyncio.run(gateway.serve(args.host, args.port))
    except KeyboardInterrupt:
        pass
    finally:
        gateway.stop_tunnels()
    return 0


if __name__ == "__main__":
    sys.exit(main())
