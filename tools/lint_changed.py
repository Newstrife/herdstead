"""Lint changed GDScript working files, including staged and untracked paths.

`make lint-changed` compares with HEAD; BASE=<ref> includes a branch's changes.
Checks use the working tree, not a saved copy of the index. Changes to the lint
configuration or tool selection run the full check instead. This is an editing
shortcut, never a replacement for `make lint` before delivery.
"""
from __future__ import annotations

import argparse
import os
import shlex
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
CONFIG = {"gdlintrc", "Makefile", "project.godot", "tools/requirements.txt",
          "tools/requirements-dev.txt", "tools/lint_changed.py"}


def git_paths(root: Path, *args: str) -> set[str]:
    result = subprocess.run(["git", *args], cwd=root, check=True, capture_output=True)
    return {os.fsdecode(path) for path in result.stdout.split(b"\0") if path}


def main(argv: list[str] | None = None, root: Path = ROOT) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--base", default="HEAD", help="compare against this commit (default: HEAD)")
    parser.add_argument("--gdlint", default="gdlint")
    parser.add_argument("--gdformat", default="gdformat")
    args = parser.parse_args(argv)
    try:
        # Resolve a commit first: a misspelt ref must not become an empty green
        # run, and a leading '-' must not turn into a git-diff option.
        base = subprocess.run(["git", "rev-parse", "--verify", "--end-of-options", args.base + "^{commit}"],
                              cwd=root, check=True, capture_output=True, text=True).stdout.strip()
        changed = git_paths(root, "diff", "--name-only", "--no-renames", "-z", base, "--")
        changed |= git_paths(root, "diff", "--cached", "--name-only", "--no-renames", "-z", base, "--")
        changed |= git_paths(root, "ls-files", "--others", "--exclude-standard", "-z")
        if changed & CONFIG:
            print("LINT_CHANGED: configuration changed; checking every GDScript", flush=True)
            files = sorted(str(path.relative_to(root)) for folder in ("scripts", "tools")
                           for path in (root / folder).rglob("*.gd") if path.is_file())
        else:
            files = sorted(path for path in changed
                           if path.startswith(("scripts/", "tools/")) and path.endswith(".gd")
                           and (root / path).is_file())
        if not files:
            print("LINT_CHANGED_OK: no changed GDScript files")
            return 0
        for command in ([args.gdlint, *files], [args.gdformat, "--check", "--line-length=120", *files]):
            print(shlex.join(command), flush=True)
            result = subprocess.run(command, cwd=root)
            if result.returncode:
                return result.returncode if result.returncode > 0 else 1
        print(f"LINT_CHANGED_OK: {len(files)} files")
        return 0
    except subprocess.CalledProcessError as error:
        detail = error.stderr.decode(errors="replace") if isinstance(error.stderr, bytes) else error.stderr
        print("LINT_CHANGED_FAILED: " + (detail or str(error)).strip(), file=sys.stderr)
        return 2
    except OSError as error:
        print(f"LINT_CHANGED_FAILED: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
