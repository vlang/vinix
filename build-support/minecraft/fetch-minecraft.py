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


def log(message: str) -> None:
    print(message, flush=True)


def fetch(url: str, *, retries: int = 4) -> bytes:
    last: Exception | None = None
    for attempt in range(retries):
        try:
            request = urllib.request.Request(
                url, headers={"User-Agent": "vinix-minecraft-builder/1"}
            )
            with urllib.request.urlopen(request, timeout=120) as response:
                return response.read()
        except (urllib.error.URLError, TimeoutError, OSError) as error:
            last = error
    raise RuntimeError(f"failed to download {url}: {last}")


def sha1_of(path: Path) -> str:
    digest = hashlib.sha1()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()


def download_to(url: str, destination: Path, expected_sha1: str | None) -> bool:
    """Download `url` unless `destination` already holds the expected content.

    Returns True when a transfer happened, so callers can report progress
    without counting files served from a previous build's cache.
    """
    if destination.exists():
        if expected_sha1 is None or sha1_of(destination) == expected_sha1:
            return False
    destination.parent.mkdir(parents=True, exist_ok=True)
    payload = fetch(url)
    if expected_sha1 is not None:
        actual = hashlib.sha1(payload).hexdigest()
        if actual != expected_sha1:
            raise RuntimeError(
                f"checksum mismatch for {url}: expected {expected_sha1}, got {actual}"
            )
    temporary = destination.with_name(destination.name + ".part")
    temporary.write_bytes(payload)
    temporary.replace(destination)
    return True


def rule_allows(rules: list[dict] | None, features: dict[str, bool]) -> bool:
    """Evaluate Mojang's `rules` array for the Vinix target.

    Mojang's semantics are last-match-wins over an implicit deny, except that a
    rules array containing only `disallow` entries defaults to allow.
    """
    if not rules:
        return True
    allowed = not any(rule.get("action") == "allow" for rule in rules)
    for rule in rules:
        if not rule_matches(rule, features):
            continue
        allowed = rule.get("action") == "allow"
    return allowed


def rule_matches(rule: dict, features: dict[str, bool]) -> bool:
    os_clause = rule.get("os", {})
    if "name" in os_clause and os_clause["name"] != TARGET_OS:
        return False
    if "arch" in os_clause and os_clause["arch"] != TARGET_ARCH:
        return False
    # `version` constrains the kernel release string; Vinix reports its own, so
    # a rule that pins a Windows/macOS release can never apply here.
    if "version" in os_clause or "versionRange" in os_clause:
        return False
    for feature, wanted in rule.get("features", {}).items():
        if features.get(feature, False) != wanted:
            return False
    return True


def fetch_version(entry: dict) -> dict:
    payload = fetch(entry["url"])
    actual = hashlib.sha1(payload).hexdigest()
    if actual != entry["sha1"]:
        raise RuntimeError(
            f"version manifest checksum mismatch for {entry['id']}"
        )
    return json.loads(payload)


def resolve_version(version_id: str, max_java: int | None = None) -> tuple[str, dict]:
    log(f"=== resolving Minecraft {version_id} ===")
    manifest = json.loads(fetch(VERSION_MANIFEST))
    if version_id in ("release", "snapshot"):
        channel = version_id
        if max_java is None:
            version_id = manifest["latest"][channel]
            log(f"  latest {channel} resolves to {version_id}")
        else:
            # Alpine stable may carry an older Java feature release than the
            # newest client asks for. Walk Mojang's newest-first manifest and
            # select the first official release that its packaged JVM can run,
            # instead of pinning a game version that will silently go stale.
            for entry in manifest["versions"]:
                if entry.get("type") != channel:
                    continue
                version = fetch_version(entry)
                java_major = int(
                    version.get("javaVersion", {}).get("majorVersion", 8)
                )
                if java_major <= max_java:
                    log(
                        f"  newest {channel} for Java {max_java} resolves to "
                        f"{entry['id']} (Java {java_major})"
                    )
                    return entry["id"], version
            raise SystemExit(
                f"no Minecraft {channel} supports Java {max_java} or older"
            )
    for entry in manifest["versions"]:
        if entry["id"] == version_id:
            version = fetch_version(entry)
            java_major = int(version.get("javaVersion", {}).get("majorVersion", 8))
            if max_java is not None and java_major > max_java:
                raise SystemExit(
                    f"Minecraft {version_id} needs Java {java_major}; "
                    f"the selected runtime supports up to Java {max_java}"
                )
            return version_id, version
    raise SystemExit(f"unknown Minecraft version: {version_id}")


def maven_path(coordinate: str) -> str:
    """Turn `group:artifact:version[:classifier]` into a Maven repository path."""
    parts = coordinate.split(":")
    group, artifact, version = parts[0], parts[1], parts[2]
    classifier = f"-{parts[3]}" if len(parts) > 3 else ""
    return f"{group.replace('.', '/')}/{artifact}/{version}/{artifact}-{version}{classifier}.jar"


def select_libraries(version: dict) -> tuple[list[dict], list[dict]]:
    """Split the version's libraries into Mojang downloads and LWJGL natives.

    Every `natives-*` LWJGL artifact Mojang publishes is x86-64 or a foreign
    operating system, so drop them all and rebuild the set from the LWJGL
    modules actually in use.
    """
    mojang: list[dict] = []
    lwjgl_modules: dict[tuple[str, str], None] = {}
    for library in version["libraries"]:
        name = library["name"]
        parts = name.split(":")
        group, artifact = parts[0], parts[1]
        classifier = parts[3] if len(parts) > 3 else None
        if group == "org.lwjgl":
            # Track the module regardless of rules: the Java artifact is
            # required on every platform, and its natives are resolved below.
            lwjgl_modules[(artifact, parts[2])] = None
            # Drop only the platform natives. Mojang publishes no plain
            # `org.lwjgl:lwjgl` jar at all — the core classes ship under an
            # `unsafe` classifier — so discarding every classifier would leave
            # the classpath without org.lwjgl.system entirely.
            if classifier is not None and classifier.startswith("natives-"):
                continue
        if not rule_allows(library.get("rules"), {}):
            continue
        artifact_download = library.get("downloads", {}).get("artifact")
        if artifact_download is None:
            continue
        mojang.append(
            {
                "name": name,
                "path": artifact_download["path"],
                "url": artifact_download["url"],
                "sha1": artifact_download["sha1"],
            }
        )

    natives: list[dict] = []
    for artifact, lwjgl_version in sorted(lwjgl_modules):
        coordinate = f"org.lwjgl:{artifact}:{lwjgl_version}:{NATIVES_CLASSIFIER}"
        path = maven_path(coordinate)
        url = f"{MAVEN_CENTRAL}/{path}"
        try:
            checksum = fetch(f"{url}.sha1").decode().split()[0].strip()
        except RuntimeError:
            # Not every LWJGL module publishes natives for every platform;
            # a module without AArch64 natives simply has none to stage.
            log(f"  no {NATIVES_CLASSIFIER} for {artifact} {lwjgl_version}")
            continue
        natives.append({"name": coordinate, "path": path, "url": url, "sha1": checksum})
    return mojang, natives


def download_all(entries: list[dict], root: Path, label: str, jobs: int) -> None:
    log(f"  {label}: {len(entries)} files")
    transferred = 0

    def work(entry: dict) -> bool:
        return download_to(entry["url"], root / entry["path"], entry["sha1"])

    with ThreadPoolExecutor(max_workers=jobs) as pool:
        for done in pool.map(work, entries):
            transferred += 1 if done else 0
    log(f"  {label}: {transferred} downloaded, {len(entries) - transferred} cached")


def download_assets(version: dict, root: Path, jobs: int) -> str:
    index = version["assetIndex"]
    index_path = root / "assets" / "indexes" / f"{index['id']}.json"
    download_to(index["url"], index_path, index["sha1"])
    objects = json.loads(index_path.read_text())["objects"]
    entries = []
    for meta in objects.values():
        digest = meta["hash"]
        entries.append(
            {
                "path": f"assets/objects/{digest[:2]}/{digest}",
                "url": f"{ASSET_BASE}/{digest[:2]}/{digest}",
                "sha1": digest,
            }
        )
    # The same object can back several asset names; download each hash once.
    unique = {entry["path"]: entry for entry in entries}
    download_all(list(unique.values()), root, "assets", jobs)
    return index["id"]


def flatten_arguments(raw: list, features: dict[str, bool]) -> list[str]:
    result: list[str] = []
    for item in raw:
        if isinstance(item, str):
            result.append(item)
            continue
        if not rule_allows(item.get("rules"), features):
            continue
        value = item.get("value", [])
        result.extend([value] if isinstance(value, str) else value)
    return result


def shell_quote(value: str) -> str:
    return "'" + value.replace("'", "'\\''") + "'"


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
    jvm_arguments = flatten_arguments(version.get("arguments", {}).get("jvm", []), {})
    # `-cp ${classpath}` is supplied by the launcher itself so that the guest
    # can prepend overrides; drop Mojang's placeholder pair.
    filtered: list[str] = []
    skip_next = False
    for argument in jvm_arguments:
        if skip_next:
            skip_next = False
            continue
        if argument == "-cp":
            skip_next = True
            continue
        filtered.append(argument)

    demo_arguments = flatten_arguments(
        version.get("arguments", {}).get("game", []), {"is_demo_user": True}
    )
    full_arguments = flatten_arguments(
        version.get("arguments", {}).get("game", []), {"is_demo_user": False}
    )

    lines = [
        "# Generated by build-support/minecraft/fetch-minecraft.py — do not edit.",
        f"MC_VERSION={shell_quote(version_id)}",
        f"MC_VERSION_TYPE={shell_quote(version['type'])}",
        f"MC_MAIN_CLASS={shell_quote(version['mainClass'])}",
        f"MC_ASSET_INDEX={shell_quote(asset_index)}",
        f"MC_GAME_ROOT={shell_quote(game_root)}",
        f"MC_JAVA_MAJOR={shell_quote(str(version.get('javaVersion', {}).get('majorVersion', 21)))}",
        f"MC_CLASSPATH={shell_quote(':'.join(f'{game_root}/{entry}' for entry in classpath))}",
        f"MC_JVM_ARGS={shell_quote(' '.join(filtered))}",
        f"MC_GAME_ARGS_DEMO={shell_quote(' '.join(demo_arguments))}",
        f"MC_GAME_ARGS_FULL={shell_quote(' '.join(full_arguments))}",
    ]
    destination.write_text("\n".join(lines) + "\n")


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

    version_id, version = resolve_version(options.version, options.max_java)
    log(f"  Minecraft {version_id} ({version['type']}), Java {version.get('javaVersion', {}).get('majorVersion')}")

    root = options.staging / options.game_root.lstrip("/")
    root.mkdir(parents=True, exist_ok=True)

    client = version["downloads"]["client"]
    client_path = f"versions/{version_id}/{version_id}.jar"
    log("  client jar")
    download_to(client["url"], root / client_path, client["sha1"])

    mojang, natives = select_libraries(version)
    download_all(mojang, root / "libraries", "libraries", options.jobs)
    download_all(natives, root / "libraries", f"LWJGL {NATIVES_CLASSIFIER}", options.jobs)

    if options.no_assets:
        asset_index = version["assetIndex"]["id"]
        index_meta = version["assetIndex"]
        download_to(
            index_meta["url"],
            root / "assets" / "indexes" / f"{asset_index}.json",
            index_meta["sha1"],
        )
        log("  assets: index only (--no-assets)")
    else:
        asset_index = download_assets(version, root, options.jobs)

    classpath = [f"libraries/{entry['path']}" for entry in mojang]
    classpath += [f"libraries/{entry['path']}" for entry in natives]
    classpath.append(client_path)

    write_launch_env(
        root / "launch.env",
        version_id=version_id,
        version=version,
        classpath=classpath,
        asset_index=asset_index,
        game_root=options.game_root,
    )

    total = sum(f.stat().st_size for f in root.rglob("*") if f.is_file())
    log(f"  staged {total / (1 << 20):.0f} MiB under {options.game_root}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
