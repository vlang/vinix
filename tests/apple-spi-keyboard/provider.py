#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""Copy the unchanged SPI provider and manifest unexecuted hardware entries."""
import hashlib
import re
from pathlib import Path

HARDWARE_ONLY = ("kernel_read32", "kernel_write32", "kernel_now_us", "kernel_delay_us", "vinix_apple_spi_keyboard_init")


def digest(data):
    return hashlib.sha256(data).hexdigest()


def copy_provider(root: Path, destination: Path, *, hardware: bool):
    destination.mkdir(parents=True)
    path = root / "kernel/apple/spi_keyboard/spicore/core.v"
    original = path.read_text()
    spans = []
    omitted = []
    if not hardware:
        for name in HARDWARE_ONLY:
            match = re.search(r"^@\[export: '[^']+'\]\npub fn " + name + r"\(", original, re.M)
            if not match:
                raise RuntimeError("hardware definition changed: " + name)
            export = re.search(r"export: '([^']+)'", match[0])[1]
            begin = original.index("{", match.end())
            depth = 1
            end = begin + 1
            while depth:
                depth += (original[end] == "{") - (original[end] == "}")
                end += 1
            if original[end:end + 1] == "\n":
                end += 1
            spans.append((match.start(), end, name))
            references = [{"line": original.count("\n", 0, hit.start()) + 1,
                           "text": original.splitlines()[original.count("\n", 0, hit.start())],
                           "kind": "comment" if original.splitlines()[original.count("\n", 0, hit.start())].lstrip().startswith("//") else "code"}
                          for hit in re.finditer(r"\b" + name + r"\b", original)
                          if not (match.start() <= hit.start() < end)]
            omitted.append({"name": name, "export": export,
                            "first_line": original.count("\n", 0, match.start()) + 1,
                            "last_line": original.count("\n", 0, end),
                            "sha256": digest(original[match.start():end].encode()),
                            "original_references": references,
                            "reason": "fixture installs exported injected callbacks and invokes vinix_spi_core_start_keyboard directly"})
    parts = []
    cursor = 0
    for start, end, _ in sorted(spans):
        parts.append(original[cursor:start])
        cursor = end
    parts.append(original[cursor:])
    copied = "".join(parts)
    for name in HARDWARE_ONLY if not hardware else ():
        if re.search(r"\b" + name + r"\b", re.sub(r"//[^\n]*", "", copied)):
            raise RuntimeError("retained reference to omitted hardware function: " + name)
    (destination / "core.v").write_text(copied)
    return {"source": str(path.relative_to(root)), "source_sha256": digest(original.encode()),
            "copied_sha256": digest(copied.encode()), "hardware": hardware,
            "excluded_functions": omitted,
            "retained_chunks_sha256": [digest(part.encode()) for part in parts],
            "transform": "remove only listed whole definitions; every retained byte is unchanged"}
