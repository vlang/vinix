#!/usr/bin/env python3
"""Small, dependency-free helpers for content-keyed desktop build caches."""

import hashlib
import os
from pathlib import Path
import re
import shutil
import stat


V_SOURCE_SUFFIXES = (".c", ".cc", ".cpp", ".h", ".m", ".S", ".v", ".vsh")
IGNORED_SOURCE_DIRECTORIES = {".git", "__pycache__", "testdata", "tests"}
V_COMPILER_SOURCE_DIRECTORIES = {"v", "v3"}


def ignored_v_source_entry(path: Path) -> bool:
    """Exclude tests and generated binaries from a production V source tree."""
    if path.is_dir():
        return path.name in IGNORED_SOURCE_DIRECTORIES
    return path.name.endswith("_test.v") or not path.name.endswith(
        V_SOURCE_SUFFIXES
    )


def ignored_vlib_entry(path: Path) -> bool:
    """Exclude compiler sources; the compiler executable fingerprints those."""
    if (
        path.is_dir()
        and path.parent.name == "vlib"
        and path.name in V_COMPILER_SOURCE_DIRECTORIES
    ):
        return True
    return ignored_v_source_entry(path)


def add_hash_field(digest, value):
    if isinstance(value, str):
        value = value.encode("utf-8", "surrogateescape")
    digest.update(len(value).to_bytes(8, "big"))
    digest.update(value)


def hash_path(digest, path: Path, label: str, metadata_only=False,
              ignore=None, active_directories=None):
    """Hash a build input without making its absolute location significant."""
    if active_directories is None:
        active_directories = set()
    add_hash_field(digest, label)
    try:
        info = path.lstat()
    except FileNotFoundError:
        add_hash_field(digest, "missing")
        return

    add_hash_field(digest, oct(stat.S_IMODE(info.st_mode)))
    # Directory mtimes change when an ignored build artifact is created or
    # removed. The included descendants already describe meaningful tree
    # changes, so only fingerprint leaf metadata in metadata mode.
    if metadata_only and not stat.S_ISDIR(info.st_mode):
        for value in (info.st_dev, info.st_ino, info.st_size,
                      info.st_mtime_ns, info.st_ctime_ns):
            add_hash_field(digest, str(value))

    if stat.S_ISLNK(info.st_mode):
        add_hash_field(digest, "symlink")
        add_hash_field(digest, os.readlink(path))
        resolved = path.resolve()
        if resolved != path and resolved.exists():
            hash_path(digest, resolved, label + "/target", metadata_only,
                      ignore, active_directories)
        return
    if stat.S_ISREG(info.st_mode):
        add_hash_field(digest, "file")
        add_hash_field(digest, str(info.st_size))
        if not metadata_only:
            with path.open("rb") as handle:
                while True:
                    chunk = handle.read(1024 * 1024)
                    if not chunk:
                        break
                    digest.update(chunk)
        return
    if stat.S_ISDIR(info.st_mode):
        add_hash_field(digest, "directory")
        identity = (info.st_dev, info.st_ino)
        if identity in active_directories:
            add_hash_field(digest, "symlink-cycle")
            return
        active_directories.add(identity)
        for child in sorted(path.iterdir(), key=lambda item: os.fsencode(item.name)):
            if ignore is not None and ignore(child):
                continue
            hash_path(digest, child, label + "/" + child.name,
                      metadata_only, ignore, active_directories)
        active_directories.remove(identity)
        return
    add_hash_field(digest, "special")
    add_hash_field(digest, str(stat.S_IFMT(info.st_mode)))


def module_subdirs(module_source: Path):
    text = (module_source / "v.mod").read_text()
    match = re.search(r"\bsubdirs\s*:\s*\[([^]]*)\]", text, re.DOTALL)
    if not match:
        return []
    return re.findall(r"['\"]([^'\"]+)['\"]", match.group(1))


def resolved_tool(path: Path) -> Path:
    if not path.is_absolute() and path.parent == Path("."):
        found = shutil.which(str(path))
        if found:
            return Path(found).resolve()
    return path.resolve()


def new_digest(namespace: str, version: int):
    digest = hashlib.sha256()
    add_hash_field(digest, "%s-v%d" % (namespace, version))
    return digest
