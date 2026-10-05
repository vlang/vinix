#!/usr/bin/env python3
"""Copy the filtered kernel sources and missing project-local imports."""

from pathlib import Path
import re
import shutil
import sys


IMPORT = re.compile(r"^\s*import\s+([A-Za-z_][A-Za-z_0-9.]*)", re.MULTILINE)


def copy_sources(kernel: Path, files: Path, destination: Path) -> list[str]:
    copied: set[str] = set()
    pending: list[str] = []

    def copy(relative: str) -> None:
        if relative in copied:
            return
        target = destination / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(kernel / relative, target)
        copied.add(relative)
        pending.append(relative)

    for relative in files.read_text().splitlines():
        copy(relative)

    while pending:
        relative = pending.pop()
        for module in IMPORT.findall((destination / relative).read_text()):
            module_path = Path(*module.split("."))
            original = kernel / module_path
            # An existing module keeps the GNUmakefile's architecture filtering.
            # Missing modules are normally found through the build's source
            # symlinks, but a copied scratch tree has no such fallback.
            if not original.is_dir() or any((destination / module_path).glob("*.v")):
                continue
            for source in sorted(original.glob("*.v")):
                copy(str(source.relative_to(kernel)))

    shutil.copy2(kernel / "v.mod", destination / "v.mod")
    return sorted(copied)


if __name__ == "__main__":
    for relative in copy_sources(*(Path(value) for value in sys.argv[1:])):
        print(relative)
