#!/usr/bin/env python3
"""Relax the web shell's secure-context check, for LAN serving over plain HTTP.

Godot's exported engine refuses to boot unless window.isSecureContext — true
on HTTPS and localhost, false on a LAN IP over HTTP, which is exactly where
tools/herdr_gateway.py serves. The single-threaded build needs nothing the
secure context gates except the clipboard (SharedArrayBuffer is the threads
build's; the clipboard loss is named below); the check is the only obstacle,
so `Features.isSecureContext` is patched to true.

Run by `make web-export` after every export (the export rewrites index.js).
Fails loudly when the upstream pattern is not found: a silent no-op would ship
a page that does not boot.

A real loss in an insecure context: the clipboard API, so the terminal
monitor's paste chord (Ctrl+Shift+V / Cmd+V) reads nothing on LAN HTTP and the
office answers its "empty clipboard" refusal — say so in docs/MANUAL.md's LAN
degradations. The chime likewise waits for one user interaction, a browser rule.
"""

import sys


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: patch_web_shell.py <exported index.js>")
        return 2
    path = sys.argv[1]
    with open(path, encoding="utf-8") as handle:
        source = handle.read()
    marker = "patched for LAN HTTP (tools/patch_web_shell.py)"
    pattern = "return window['isSecureContext'] === true;"
    if marker in source:
        print(f"PATCH_WEB_SHELL_OK: {path} (already patched)")
        return 0
    # Exactly one, or the upstream shell changed under us: fail loudly either
    # way rather than silently shipping a page that does not boot.
    count = source.count(pattern)
    if count != 1:
        print(f"PATCH_WEB_SHELL_ERROR: the secure-context check moved ({count} hits); update {__file__}")
        return 1
    with open(path, "w", encoding="utf-8") as handle:
        handle.write(source.replace(pattern, "return true; // " + marker))
    print(f"PATCH_WEB_SHELL_OK: {path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
