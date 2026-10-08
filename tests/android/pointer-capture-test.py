#!/usr/bin/env python3
"""Build the separate pointer dispatch DEX probe against actual ATL classes.

The Java probe uses production dispatch and MotionEvent snapshots. Its capture
state double isolates Java behavior; atl-pointer-capture-test.c tests real X11
capture separately. Neither fixture belongs in the application or runtime.
"""
import argparse
import importlib.util
from pathlib import Path

R8_SHA256 = "900dfbc649519969fc5a4c7520d6b7355338e565fa1249874e0190b8d61b1199"
CORE_SHA256 = "f47736d9d410766a20ae1f60d679607d8e85241e8cdeb5a0c040ab260ba68f42"


_native_spec = importlib.util.spec_from_file_location("vinix_android_native", Path(__file__).resolve().parents[2] / "build-support/android/_native.py")
_native = importlib.util.module_from_spec(_native_spec)
_native_spec.loader.exec_module(_native)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--framework-classes", type=Path, required=True,
                        help="Meson output/src/api-impl/hax.jar, not the installed DEX JAR")
    parser.add_argument("--stub-classes", type=Path, required=True,
                        help="Meson output/src/gstub/gstub.jar")
    parser.add_argument("--core-classes", type=Path, default=Path("/usr/lib/java/core-all_classes.jar"))
    parser.add_argument("--r8", type=Path, required=True)
    parser.add_argument("--javac", default="javac")
    parser.add_argument("--java", default="java")
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    mismatch = _native.command("build_simple_probe", kind="pointer-capture", helper=str(Path(__file__)),
                               **{key: str(value) for key, value in vars(args).items()})
    if mismatch:
        parser.error(f"pinned compiler input checksum mismatch: {mismatch}")



if __name__ == "__main__":
    main()
