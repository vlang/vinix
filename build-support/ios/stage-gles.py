#!/usr/bin/env python3
"""Stage a private ARM64 Mesa runtime, without replacing desktop libraries."""
from pathlib import Path
import argparse
import json
import re
import shutil
import subprocess


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--sysroot", type=Path, required=True)
    parser.add_argument("--mesa-sysroot", type=Path, required=True)
    parser.add_argument("--readelf", required=True)
    args = parser.parse_args()
    library = args.output / "usr/lib/vinix/ios-gles"
    library.mkdir(parents=True, exist_ok=True)
    roots = [args.mesa_sysroot, args.sysroot]
    directories = [root / directory for root in roots for directory in ("usr/lib", "lib")]
    pending = ["libEGL.so.1", "libGLESv2.so.2", "libfreetype.so.6"]
    sources = {}
    while pending:
        name = pending.pop()
        if name in sources:
            continue
        candidates = [directory / name for directory in directories]
        source = next((path.resolve() for path in candidates if path.is_file()), None)
        if source is None:
            raise SystemExit(f"Missing ARM64 graphics dependency {name}; build the X11/userland sysroots")
        header = subprocess.check_output([args.readelf, "-h", str(source)], text=True)
        if "AArch64" not in header or "ELF64" not in header:
            raise SystemExit(f"Not an ARM64 ELF library: {source}")
        dynamic = subprocess.check_output([args.readelf, "-d", str(source)], text=True)
        pending.extend(re.findall(r"\(NEEDED\).*\[(.*?)\]", dynamic))
        sources[name] = str(source)
        shutil.copy2(source, library / name)
    # Mesa's software DRI entry points are in its versioned Gallium library.
    gallium = next((name for name in sources if name.startswith("libgallium-")), None)
    if gallium is None:
        raise SystemExit("Mesa EGL must use the shared Gallium driver build")
    dri = library / "dri"
    dri.mkdir(exist_ok=True)
    swrast = dri / "swrast_dri.so"
    swrast.unlink(missing_ok=True)
    swrast.symlink_to("../" + gallium)
    # Linker aliases stay inside this private directory too.
    for name, target in (("libEGL.so", "libEGL.so.1"), ("libGLESv2.so", "libGLESv2.so.2"), ("libfreetype.so", "libfreetype.so.6"), ("ld-musl-aarch64.so.1", "libc.musl-aarch64.so.1")):
        alias = library / name
        alias.unlink(missing_ok=True)
        alias.symlink_to(target)
    (library / "sources.json").write_text(json.dumps(sources, indent=2) + "\n")
    print(f"Staged {len(sources)} ARM64 graphics libraries in {library}")


if __name__ == "__main__":
    main()
