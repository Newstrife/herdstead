#!/usr/bin/env python3
"""Unit tests for tools/herdr_gateway.py: the checks, the paths, the bridges.

Runs a real gateway on an ephemeral port against a fake unix socket, and
checks the wire: a ping through /ws/local answers and closes, a machine
endpoint without ssh refuses the WebSocket politely, /api/machines proxies
whatever the herdr binary printed, static files serve and stay inside --web,
and a request's WebSocket stays open after the answer until the client closes
(a close frame read in the same batch as the answer can eat it; subscription
streams close at once so a dead stream reaches the office immediately).

Pure checks cover the target/session/home rules (mirroring MachineLink),
remote_socket_path() and escape_forward().

Run: python3 tools/test_gateway.py (needs .venv: make setup).
"""

import asyncio
import os
import socket
import subprocess
import sys
import tempfile
import unittest
import urllib.request

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import websockets

import herdr_gateway as gw


class TestChecks(unittest.TestCase):
    def test_targets(self):
        self.assertEqual(gw.check_target("box"), "")
        self.assertEqual(gw.check_target("me@box.lan"), "")
        self.assertNotEqual(gw.check_target(""), "")
        self.assertNotEqual(gw.check_target("-oProxyCommand=x"), "")
        self.assertNotEqual(gw.check_target("a b"), "")
        self.assertNotEqual(gw.check_target("a\tb"), "")

    def test_targets_reject_every_invisible_codepoint(self):
        # The whole MachineLink._invisible table, code point for code point.
        for code in list(range(0x21)) + list(range(0x7F, 0xA1)):
            self.assertNotEqual(gw.check_target("a" + chr(code) + "b"), "", hex(code))
        for code in (0x1680, 0x2000, 0x200F, 0x2028, 0x202F, 0x205F, 0x3000, 0xFEFF):
            self.assertNotEqual(gw.check_target("a" + chr(code) + "b"), "", hex(code))
        # And the visible neighbours stay legal.
        for code in (0x21, 0x7E, 0xA1, 0x2010, 0x2027, 0x2030, 0x3001):
            self.assertEqual(gw.check_target("a" + chr(code) + "b"), "", hex(code))

    def test_sessions(self):
        for good in ("", "default", "work-2", "a.b_c"):
            self.assertEqual(gw.check_session(good), "")
        for bad in (".", "..", "a b", "a/b", "å"):
            self.assertNotEqual(gw.check_session(bad), "")

    def test_homes(self):
        self.assertEqual(gw.check_home("/home/ed"), "")
        for bad in ("", "home/ed", "/a:b", "/a$b", "/a\nb", "/" + "a" * gw.HOME_MAX):
            self.assertNotEqual(gw.check_home(bad), "")

    def test_remote_socket_path(self):
        self.assertEqual(
            gw.remote_socket_path("/home/ed", ""), "/home/ed/.config/herdr/herdr.sock"
        )
        self.assertEqual(
            gw.remote_socket_path("/home/ed", "default"),
            "/home/ed/.config/herdr/herdr.sock",
        )
        self.assertEqual(
            gw.remote_socket_path("/home/ed/", "work"),
            "/home/ed/.config/herdr/sessions/work/herdr.sock",
        )

    def test_escape_forward(self):
        self.assertEqual(gw.escape_forward("/a/b.sock"), "/a/b.sock")
        self.assertEqual(gw.escape_forward("/a%b"), "/a%%b")


class FakeHerdr:
    """A unix socket that answers one NDJSON line per connection, then closes."""

    def __init__(self, path: str):
        self.path = path
        self.requests: list[bytes] = []
        self._server = None

    async def __aenter__(self):
        self._server = await asyncio.start_unix_server(self._handle, self.path)
        return self

    async def __aexit__(self, *exc):
        self._server.close()
        await self._server.wait_closed()

    async def _handle(self, reader, writer):
        line = await reader.readline()
        self.requests.append(line)
        writer.write(b'{"id":"1","result":{"type":"pong"}}\n')
        await writer.drain()
        writer.close()


class GatewayFixture(unittest.IsolatedAsyncioTestCase):
    """A real gateway on 127.0.0.1:0 against a fake herdr socket."""

    async def asyncSetUp(self):
        self.tmp = tempfile.mkdtemp(prefix="hs-gwtest-")
        self.sock_path = os.path.join(self.tmp, "herdr.sock")
        self.web = os.path.join(self.tmp, "web")
        os.makedirs(self.web)
        with open(os.path.join(self.web, "index.html"), "w") as handle:
            handle.write("<title>herdstead</title>\n")
        self.fake = await FakeHerdr(self.sock_path).__aenter__()
        args = gw.argparse.Namespace(
            socket=self.sock_path, web=self.web, herdr_bin="false"
        )
        self.gateway = gw.Gateway(args)
        self.server = await websockets.serve(
            self.gateway.bridge, "127.0.0.1", 0,
            process_request=self.gateway.http, max_size=None, compression=None,
        )
        self.port = self.server.sockets[0].getsockname()[1]

    async def asyncTearDown(self):
        self.server.close()
        await self.server.wait_closed()
        self.gateway.stop_tunnels()
        await self.fake.__aexit__()
        gw.shutil.rmtree(self.tmp, ignore_errors=True)

    async def test_ws_local_answers_and_closes(self):
        uri = f"ws://127.0.0.1:{self.port}/ws/local"
        async with websockets.connect(uri, max_size=None) as ws:
            await ws.send(b'{"id":"1","method":"ping","params":{}}\n')
            answer = b""
            while b"\n" not in answer:
                answer += await asyncio.wait_for(ws.recv(), 5)
            self.assertIn(b"pong", answer)
            # herdr closed its side after answering; the gateway deliberately
            # does NOT close the WebSocket (a close frame can eat the answer):
            # the client closes once it has its line, as HerdrClient does.
            await ws.close()
        self.assertEqual(len(self.fake.requests), 1)

    async def test_ws_machine_refuses_a_bad_target(self):
        uri = f"ws://127.0.0.1:{self.port}/ws/machine?target=-oProxyCommand%3Dx"
        with self.assertRaises(websockets.InvalidStatus) as raised:
            async with websockets.connect(uri):
                pass
        self.assertEqual(raised.exception.response.status_code, 400)

    async def test_unknown_endpoint_refused(self):
        uri = f"ws://127.0.0.1:{self.port}/ws/elsewhere"
        with self.assertRaises(websockets.InvalidStatus) as raised:
            async with websockets.connect(uri):
                pass
        self.assertEqual(raised.exception.response.status_code, 400)

    async def test_api_machines_proxies_stderr_on_failure(self):
        # urllib blocks; the gateway shares this test's event loop.
        def fetch():
            try:
                with urllib.request.urlopen(
                    f"http://127.0.0.1:{self.port}/api/machines", timeout=5
                ) as response:
                    return response.status, response.read()
            except urllib.error.HTTPError as why:
                try:
                    return why.code, why.read()
                finally:
                    why.close()

        # `false` exits 1 with nothing: the proxy answers 502, never the
        # empty stdout as if it were a list.
        code, body = await asyncio.to_thread(fetch)
        self.assertEqual(code, 502)
        self.assertIn(b"error", body)

    async def test_static_prefix_collision_stays_out(self):
        # A sibling whose name starts with the web dir's own is not served:
        # the classic startswith() prefix bug.
        sibling = self.web + "2"
        os.makedirs(sibling)
        secret = os.path.join(sibling, "secret.txt")
        with open(secret, "w") as handle:
            handle.write("not for the LAN\n")
        link = os.path.join(self.web, "linked")
        os.symlink(secret, link)

        def code_of(path: str) -> int:
            try:
                with urllib.request.urlopen(f"http://127.0.0.1:{self.port}{path}", timeout=5):
                    return 200
            except urllib.error.HTTPError as why:
                code = why.code
                why.close()
                return code

        self.assertEqual(await asyncio.to_thread(code_of, "/linked"), 404)
        gw.shutil.rmtree(sibling, ignore_errors=True)

    async def test_api_machines_503_when_herdr_cannot_run(self):
        # herdr 二进制不存在 → 503(对应 roster 的 _gone 回退),与"跑了但失败
        # → 502"成对。
        self.gateway.herdr = "/nonexistent/herdr"
        def fetch():
            try:
                with urllib.request.urlopen(
                    f"http://127.0.0.1:{self.port}/api/machines", timeout=5
                ) as response:
                    return response.status
            except urllib.error.HTTPError as why:
                code = why.code
                why.close()
                return code
        self.assertEqual(await asyncio.to_thread(fetch), 503)

    async def test_static_serves_and_stays_inside_web(self):
        def get(path: str) -> bytes:
            return urllib.request.urlopen(
                f"http://127.0.0.1:{self.port}{path}", timeout=5
            ).read()

        self.assertIn(b"herdstead", await asyncio.to_thread(get, "/"))

        def code_of(path: str) -> int:
            try:
                with urllib.request.urlopen(f"http://127.0.0.1:{self.port}{path}", timeout=5):
                    return 200
            except urllib.error.HTTPError as why:
                code = why.code
                why.close()
                return code

        self.assertEqual(await asyncio.to_thread(code_of, "/../herdr_gateway.py"), 404)
        self.assertEqual(
            await asyncio.to_thread(code_of, "/%2e%2e/%2e%2e/etc/passwd"), 404
        )


class TestSniff(unittest.IsolatedAsyncioTestCase):
    """The stream sniff: events.subscribe closes at once, anything else waits
    for the client — and a payload merely NAMING it is not a stream."""

    async def test_request_waits_for_the_client_close(self):
        line = b'{"id":"1","method":"ping","params":{}}\n'
        # A request's answer arrives; the WS stays open for the client.
        tmp = tempfile.mkdtemp(prefix="hs-gwtest-")
        sock_path = os.path.join(tmp, "herdr.sock")
        async with FakeHerdr(sock_path):
            args = gw.argparse.Namespace(socket=sock_path, web=tmp, herdr_bin="false")
            gateway = gw.Gateway(args)
            server = await websockets.serve(
                gateway.bridge, "127.0.0.1", 0,
                process_request=gateway.http, max_size=gw.MAX_MESSAGE, compression=None,
            )
            port = server.sockets[0].getsockname()[1]
            async with websockets.connect(f"ws://127.0.0.1:{port}/ws/local") as ws:
                await ws.send(line)
                answer = b""
                while b"\n" not in answer:
                    answer += await asyncio.wait_for(ws.recv(), 5)
                self.assertIn(b"pong", answer)
                self.assertEqual(ws.state.name, "OPEN")
            server.close()
            await server.wait_closed()
        gw.shutil.rmtree(tmp, ignore_errors=True)

    async def test_a_payload_naming_subscribe_is_not_a_stream(self):
        # pane.send_text of the literal text events.subscribe: the value's
        # bytes must not mark the connection a stream (the answer would race
        # the close). The sniff reads only the envelope's own method key.
        line = (
            b'{"id":"1","method":"pane.send_text",'
            b'"params":{"text":"events.subscribe"}}\n'
        )
        tmp = tempfile.mkdtemp(prefix="hs-gwtest-")
        sock_path = os.path.join(tmp, "herdr.sock")
        async with FakeHerdr(sock_path):
            args = gw.argparse.Namespace(socket=sock_path, web=tmp, herdr_bin="false")
            gateway = gw.Gateway(args)
            server = await websockets.serve(
                gateway.bridge, "127.0.0.1", 0,
                process_request=gateway.http, max_size=gw.MAX_MESSAGE, compression=None,
            )
            port = server.sockets[0].getsockname()[1]
            async with websockets.connect(f"ws://127.0.0.1:{port}/ws/local") as ws:
                await ws.send(line)
                answer = b""
                while b"\n" not in answer:
                    answer += await asyncio.wait_for(ws.recv(), 5)
                self.assertIn(b"pong", answer)
                # 非流:服务端不主动关。
                self.assertEqual(ws.state.name, "OPEN")
            server.close()
            await server.wait_closed()
        gw.shutil.rmtree(tmp, ignore_errors=True)

    async def test_a_stream_is_closed_by_the_server_at_once(self):
        # events.subscribe 判成流:herdr EOF 后网关立即关 WS(断线毫秒级传达,
        # 不变量 4),不等客户端。
        line = b'{"id":"1","method":"events.subscribe","params":{"subscriptions":[]}}\n'
        tmp = tempfile.mkdtemp(prefix="hs-gwtest-")
        sock_path = os.path.join(tmp, "herdr.sock")
        async with FakeHerdr(sock_path):
            args = gw.argparse.Namespace(socket=sock_path, web=tmp, herdr_bin="false")
            gateway = gw.Gateway(args)
            server = await websockets.serve(
                gateway.bridge, "127.0.0.1", 0,
                process_request=gateway.http, max_size=gw.MAX_MESSAGE, compression=None,
            )
            port = server.sockets[0].getsockname()[1]
            async with websockets.connect(f"ws://127.0.0.1:{port}/ws/local") as ws:
                await ws.send(line)
                answer = b""
                while b"\n" not in answer:
                    answer += await asyncio.wait_for(ws.recv(), 5)
                self.assertIn(b"pong", answer)
                with self.assertRaises(websockets.ConnectionClosed):
                    await asyncio.wait_for(ws.recv(), 5)
            server.close()
            await server.wait_closed()
        gw.shutil.rmtree(tmp, ignore_errors=True)

    async def test_text_frame_first_message_is_forwarded(self):
        # A text (not binary) first message must not crash the pump.
        tmp = tempfile.mkdtemp(prefix="hs-gwtest-")
        sock_path = os.path.join(tmp, "herdr.sock")
        async with FakeHerdr(sock_path):
            args = gw.argparse.Namespace(socket=sock_path, web=tmp, herdr_bin="false")
            gateway = gw.Gateway(args)
            server = await websockets.serve(
                gateway.bridge, "127.0.0.1", 0,
                process_request=gateway.http, max_size=gw.MAX_MESSAGE, compression=None,
            )
            port = server.sockets[0].getsockname()[1]
            async with websockets.connect(f"ws://127.0.0.1:{port}/ws/local") as ws:
                await ws.send('{"id":"1","method":"ping","params":{}}\n')  # str: text frame
                answer = b""
                while b"\n" not in answer:
                    answer += await asyncio.wait_for(ws.recv(), 5)
                self.assertIn(b"pong", answer)
            server.close()
            await server.wait_closed()
        gw.shutil.rmtree(tmp, ignore_errors=True)


class TestGodotClient(unittest.IsolatedAsyncioTestCase):
    """The real client (HerdrPeer) over a real gateway to a fake herdr."""

    async def test_godot_peer_over_ws(self):
        godot = gw.shutil.which("godot")
        if godot is None:
            self.skipTest("godot not on PATH")
        tmp = tempfile.mkdtemp(prefix="hs-gwtest-")
        sock_path = os.path.join(tmp, "herdr.sock")
        async with FakeHerdr(sock_path):
            args = gw.argparse.Namespace(socket=sock_path, web=tmp, herdr_bin="false")
            gateway = gw.Gateway(args)
            server = await websockets.serve(
                gateway.bridge, "127.0.0.1", 0,
                process_request=gateway.http, max_size=gw.MAX_MESSAGE, compression=None,
            )
            port = server.sockets[0].getsockname()[1]
            repo = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
            run = await asyncio.to_thread(
                subprocess.run,
                [godot, "--headless", "--path", repo, "--script", "tools/probe_ws.gd",
                 "--", f"--url=ws://127.0.0.1:{port}/ws/local"],
                capture_output=True, text=True, timeout=60,
            )
            server.close()
            await server.wait_closed()
        gw.shutil.rmtree(tmp, ignore_errors=True)
        self.assertEqual(run.returncode, 0, run.stdout[-500:] + run.stderr[-500:])
        self.assertIn("GOT LINE", run.stdout)


if __name__ == "__main__":
    unittest.main(verbosity=2)
