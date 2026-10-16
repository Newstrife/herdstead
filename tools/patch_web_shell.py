#!/usr/bin/env python3
"""Relax the web shell's secure-context check, for LAN serving over plain HTTP.

Godot's exported engine refuses to boot unless window.isSecureContext — true
on HTTPS and localhost, false on a LAN IP over HTTP, which is exactly where
tools/herdr_gateway.py serves. The single-threaded build needs nothing the
secure context gates except the clipboard and the audio worklets (both lost
or worked around below); the boot check is the first obstacle, so
`Features.isSecureContext` is patched to true.

Run by `make web-export` after every export (the export rewrites index.js).
Fails loudly when the upstream pattern is not found: a silent no-op would ship
a page that does not boot.

A real loss in an insecure context: the clipboard API, so the terminal
monitor's paste chord (Ctrl+Shift+V / Cmd+V) reads nothing on LAN HTTP and the
office answers its "empty clipboard" refusal — say so in docs/MANUAL.md's LAN
degradations. The chime likewise waits for one user interaction, a browser rule.

Two more patches for the same context, both in the audio chain (AudioWorklet
is another secure-context API, and the shell's feature check looks at the
prototype, not the instance): the position-worklet load becomes a rejected
promise with a silent side-catch instead of a boot-killing throw (the
rejection still reaches its one awaiter, which returns early on it; only the
console's unhandled-rejection noise is swallowed). Sound keeps playing through
the ScriptProcessor fallback the engine picks once the worklet driver reports
unavailable.
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
    # (pattern, replacement): the secure-context check, and the audio
    # chain's two unguarded audioWorklet touches.
    patches = [
        ("return window['isSecureContext'] === true;", "return true; // " + marker),
        (
            "GodotAudio.audioPositionWorkletPromise=ctx.audioWorklet.addModule(path)",
            "GodotAudio.audioPositionWorkletPromise=ctx.audioWorklet?ctx.audioWorklet.addModule(path):"
            '(e=>{e.catch(()=>{});return e})(Promise.reject(new Error("no audioWorklet (insecure context)")))', 
        ),
        (
            "await GodotAudio.audioPositionWorkletPromise;if(this.isCanceled)",
            "try{await GodotAudio.audioPositionWorkletPromise}catch(e){return}if(this.isCanceled)",
        ),
    ]
    if marker in source:
        print(f"PATCH_WEB_SHELL_OK: {path} (already patched)")
        return 0
    # Exactly one hit each, or the upstream shell changed under us: fail
    # loudly rather than silently shipping a page that does not boot.
    for pattern, _ in patches:
        count = source.count(pattern)
        if count != 1:
            print(f"PATCH_WEB_SHELL_ERROR: the shell moved ({count} hits for {pattern[:60]}…); update {__file__}")
            return 1
    for pattern, replacement in patches:
        source = source.replace(pattern, replacement)
    with open(path, "w", encoding="utf-8") as handle:
        handle.write(source)
    print(f"PATCH_WEB_SHELL_OK: {path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
