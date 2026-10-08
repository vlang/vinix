#!/usr/bin/env python3
"""Resolve and download Minecraft: Java Edition for the Vinix aarch64 image.

The client, its libraries and its assets are fetched from Mojang's own
distribution endpoints, exactly as every third-party launcher does; nothing
about the game is redistributed with Vinix. Mojang publishes no AArch64 Linux
natives, so the LWJGL natives are taken from the same LWJGL release on Maven
Central, which is the substitution Prism Launcher performs on ARM as well.

The output is a self-contained game directory plus `launch.env`, a
shell-sourceable description of the launch the in-guest `minecraft` script
performs. Resolving the version manifest here keeps JSON parsing, rule
evaluation and hash verification on the build host instead of requiring any of
it from Vinix at boot.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import shutil
import sys
import urllib.error
import urllib.request
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

VERSION_MANIFEST = "https://piston-meta.mojang.com/mc/game/version_manifest_v2.json"
MAVEN_CENTRAL = "https://repo1.maven.org/maven2"
ASSET_BASE = "https://resources.download.minecraft.net"

# Vinix runs the game on 64-bit ARM under musl. Mojang's rules are written in
# terms of these two values, so evaluate every rule against them.
TARGET_OS = "linux"
TARGET_ARCH = "arm64"

# Mojang ships `natives-linux` only for x86-64. These are the modules whose
# AArch64 natives come from Maven Central instead.
NATIVES_CLASSIFIER = "natives-linux-arm64"


_NATIVE = None


def _invoke(operation, *arguments):
    global _NATIVE
    if _NATIVE is None:
        import importlib.util
        spec = importlib.util.spec_from_file_location("minecraft_fetch_native", Path(__file__).with_name("_native_fetcher.py"))
        _NATIVE = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(_NATIVE)
    return _NATIVE.call(operation, list(arguments), globals())


def log(message: str) -> None:
    print(message, flush=True)


def fetch(url: str, *, retries: int = 4) -> bytes:
    return bytes.fromhex(_invoke("fetch", url, retries))


def sha1_of(path: Path) -> str:
    return _invoke("sha1_of", str(path))


def download_to(url: str, destination: Path, expected_sha1: str | None) -> bool:
    """Download `url` unless `destination` already holds the expected content.

    Returns True when a transfer happened, so callers can report progress
    without counting files served from a previous build's cache.
    """
    return _invoke("download_to", url, str(destination), expected_sha1)


def rule_allows(rules: list[dict] | None, features: dict[str, bool]) -> bool:
    """Evaluate Mojang's `rules` array for the Vinix target.

    Mojang's semantics are last-match-wins over an implicit deny, except that a
    rules array containing only `disallow` entries defaults to allow.
    """
    return _invoke("rule_allows", rules, features)


def rule_matches(rule: dict, features: dict[str, bool]) -> bool:
    return _invoke("rule_matches", rule, features)


def fetch_version(entry: dict) -> dict:
    return _invoke("fetch_version", entry)


def resolve_version(version_id: str, max_java: int | None = None) -> tuple[str, dict]:
    return tuple(_invoke("resolve_version", version_id, max_java))


def maven_path(coordinate: str) -> str:
    """Turn `group:artifact:version[:classifier]` into a Maven repository path."""
    return _invoke("maven_path", coordinate)


def select_libraries(version: dict) -> tuple[list[dict], list[dict]]:
    """Split the version's libraries into Mojang downloads and LWJGL natives.

    Every `natives-*` LWJGL artifact Mojang publishes is x86-64 or a foreign
    operating system, so drop them all and rebuild the set from the LWJGL
    modules actually in use.
    """
    return tuple(_invoke("select_libraries", version))


def download_all(entries: list[dict], root: Path, label: str, jobs: int) -> None:
    return _invoke("download_all", entries, str(root), label, jobs)


def download_assets(version: dict, root: Path, jobs: int) -> str:
    return _invoke("download_assets", version, str(root), jobs)


def flatten_arguments(raw: list, features: dict[str, bool]) -> list[str]:
    return _invoke("flatten_arguments", raw, features)


def shell_quote(value: str) -> str:
    return _invoke("shell_quote", value)


def write_launch_env(
    destination: Path,
    *,
    version_id: str,
    version: dict,
    classpath: list[str],
    asset_index: str,
    game_root: str,
) -> None:
    """Emit the launch description the in-guest shell launcher sources.

    Rule evaluation and JSON parsing both happen here so that `/usr/bin/minecraft`
    stays a plain POSIX script with no dependency on a JSON tool in the guest.
    """
    return _invoke("write_launch_env", str(destination), dict(version_id=version_id, version=version, classpath=classpath, asset_index=asset_index, game_root=game_root))


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--version", default="release", help="version id, or release/snapshot")
    parser.add_argument(
        "--max-java",
        type=int,
        help="for a release/snapshot channel, select its newest version supported by this Java feature release",
    )
    parser.add_argument("--staging", required=True, type=Path)
    parser.add_argument("--game-root", default="/usr/share/minecraft")
    parser.add_argument("--jobs", type=int, default=16)
    parser.add_argument(
        "--no-assets",
        action="store_true",
        help="stage the code but not the ~500 MiB asset objects",
    )
    options = parser.parse_args()

    return _invoke("stage", {**vars(options), "staging": str(options.staging)})


if __name__ == "__main__":
    sys.exit(main())
