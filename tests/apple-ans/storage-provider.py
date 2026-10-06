#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Copy storage providers; record hardware-only omissions for injected models."""
import hashlib
import re
from pathlib import Path

HARDWARE_ONLY = (
    "a_kernel_read32", "a_kernel_read64", "a_kernel_write32",
    "a_kernel_write64", "a_kernel_now", "a_kernel_delay", "a_kernel_sync",
    "vinix_ans_init",
)


def digest(data):
    return hashlib.sha256(data).hexdigest()


def copy_provider(root: Path, destination: Path, *, ans: bool, hardware: bool):
    destination.mkdir(parents=True)
    ext2_path = root / "kernel/apple/ans/ext2core/core.v"
    ext2 = ext2_path.read_bytes()
    receipt = {"ext2_source": str(ext2_path.relative_to(root)), "ext2_sha256": digest(ext2),
               "ans": ans, "hardware": hardware, "excluded_functions": []}
    if ans:
        source_path = root / "kernel/apple/ans/anscore/core.v"
        original = source_path.read_text()
        spans = []
        if not hardware:
            for name in HARDWARE_ONLY:
                match = re.search(r"^@\[export: '" + name + r"'\]\npub fn " + name + r"\(", original, re.M)
                if not match:
                    raise RuntimeError("hardware definition changed: " + name)
                begin = original.index("{", match.end())
                depth = 1
                end = begin + 1
                while depth:
                    depth += (original[end] == "{") - (original[end] == "}")
                    end += 1
                if original[end:end + 1] == "\n":
                    end += 1
                spans.append((match.start(), end, name))
                receipt["excluded_functions"].append({
                    "name": name, "first_line": original.count("\n", 0, match.start()) + 1,
                    "last_line": original.count("\n", 0, end),
                    "sha256": digest(original[match.start():end].encode()),
                    "reason": "injected fixture installs its own callbacks and invokes a_start directly",
                })
        parts = []
        cursor = 0
        for start, end, _ in sorted(spans):
            parts.append(original[cursor:start])
            cursor = end
        parts.append(original[cursor:])
        copied = "".join(parts)
        for name in HARDWARE_ONLY if not hardware else ():
            if re.search(r"\b" + name + r"\b", copied):
                raise RuntimeError("retained reference to omitted hardware function: " + name)
        submodule = destination / "anscore"
        submodule.mkdir()
        (submodule / "core.v").write_text(copied)
        receipt.update({"ans_source": str(source_path.relative_to(root)),
                        "ans_source_sha256": digest(original.encode()),
                        "ans_copied_sha256": digest(copied.encode()),
                        "retained_chunks_sha256": [digest(part.encode()) for part in parts],
                        "transform": "remove only listed whole definitions; all retained text is byte-identical"})
        ext2 = ext2.replace(b"module ext2core", b"module ext2core\nimport ext2core.anscore as _", 1)
    (destination / "core.v").write_bytes(ext2)
    return receipt
