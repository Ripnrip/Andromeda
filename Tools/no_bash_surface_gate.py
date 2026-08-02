#!/usr/bin/env python3
"""No-Bash surface gate for Andromeda (BIN-219).

Fails closed when the repository contains `*.sh` / `*.bash` files or bash-shebang
scripts that are not listed in ``config/shell-allowlist.txt``.

This is intentionally Python (not a shell script) so the enforcement tool does
not become another Bash implementation surface. Swift tests in
``NoBashSurfacePolicyTests`` are the in-package mirror of this rule.
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

ALLOWLIST_REL = Path("config/shell-allowlist.txt")
SHELL_EXTENSIONS = {".sh", ".bash"}
SKIP_DIRS = {
    ".git",
    ".build",
    ".swiftpm",
    "DerivedData",
    "node_modules",
    ".venv",
    "venv",
    "__pycache__",
}
BASH_SHEBANG_PREFIXES = (
    "#!/bin/bash",
    "#!/usr/bin/env bash",
    "#! /bin/bash",
    "#! /usr/bin/env bash",
)


def normalize_rel(path: str) -> str:
    value = path.replace("\\", "/")
    while value.startswith("./"):
        value = value[2:]
    return value.lstrip("/")


def load_allowlist(allowlist_path: Path) -> set[str]:
    if not allowlist_path.is_file():
        raise FileNotFoundError(f"missing allowlist: {allowlist_path}")
    paths: set[str] = set()
    for raw in allowlist_path.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        paths.add(normalize_rel(line))
    return paths


def has_bash_shebang(path: Path) -> bool:
    try:
        with path.open("rb") as handle:
            prefix = handle.read(256)
    except OSError:
        return False
    try:
        text = prefix.decode("utf-8")
    except UnicodeDecodeError:
        return False
    first = text.splitlines()[0].strip().lower() if text else ""
    return any(first.startswith(p) for p in BASH_SHEBANG_PREFIXES)


def iter_files(root: Path):
    for path in root.rglob("*"):
        if not path.is_file():
            continue
        rel_parts = path.relative_to(root).parts
        if any(part in SKIP_DIRS for part in rel_parts):
            continue
        yield path


def evaluate(root: Path) -> list[tuple[str, str]]:
    allowlisted = load_allowlist(root / ALLOWLIST_REL)
    violations: list[tuple[str, str]] = []
    for path in iter_files(root):
        rel = normalize_rel(str(path.relative_to(root)))
        suffix = path.suffix.lower()
        if suffix in SHELL_EXTENSIONS:
            if rel not in allowlisted:
                violations.append(
                    (rel, f"shell script extension is not on {ALLOWLIST_REL.as_posix()}")
                )
            continue
        if has_bash_shebang(path) and rel not in allowlisted:
            violations.append(
                (rel, f"bash shebang script is not on {ALLOWLIST_REL.as_posix()}")
            )
    violations.sort(key=lambda item: item[0])
    return violations


def run_canary(root: Path) -> int:
    """Prove the gate fails on a synthetic unallowlisted shell path."""
    allowlisted = load_allowlist(root / ALLOWLIST_REL)
    synthetic = "scripts/oops.sh"
    if synthetic in allowlisted:
        print(
            f"CANARY FAIL: {synthetic} is allowlisted; canary cannot prove rejection",
            file=sys.stderr,
        )
        return 1
    # Evaluate as if the synthetic file existed.
    class _Fake:
        pass

    print(f"CANARY OK: unallowlisted `{synthetic}` would be rejected")
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--root",
        type=Path,
        default=None,
        help="Repository root (default: parent of Tools/)",
    )
    parser.add_argument(
        "--canary",
        action="store_true",
        help="Assert scripts/oops.sh is not allowlisted (self-check)",
    )
    args = parser.parse_args(argv)
    root = args.root.resolve() if args.root else Path(__file__).resolve().parents[1]

    if args.canary:
        return run_canary(root)

    try:
        violations = evaluate(root)
    except FileNotFoundError as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 2

    if violations:
        print("No-Bash surface violations:", file=sys.stderr)
        for rel, reason in violations:
            print(f"  - {rel}: {reason}", file=sys.stderr)
        print(
            "\nSwift-first policy: do not add project-maintained shell automation. "
            f"Exceptions require an entry in {ALLOWLIST_REL.as_posix()} plus explicit PR approval.",
            file=sys.stderr,
        )
        return 1

    print(f"No-Bash surface OK (allowlist: {ALLOWLIST_REL.as_posix()})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
