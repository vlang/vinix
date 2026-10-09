#!/usr/bin/env python3
"""Cross-build Dota's amd64 Lavapipe from Debian's pinned Mesa source and patches."""
from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tarfile

from runpy import run_path

_native = run_path(str(Path(__file__).resolve().parents[2] / "tests/dota2/_native.py"))
_native_request, _policy_value = _native["request"], _native["policy_value"]

REPO = Path(__file__).resolve().parents[2]
SUPPORT = Path(__file__).with_name("mesa")
LIBRARY = "usr/lib/x86_64-linux-gnu/libvulkan_lvp.so"
TARGET = "src/gallium/targets/lavapipe/libvulkan_lvp.so"
PYTHON_PACKAGES = ("meson==1.11.2", "Mako==1.3.12", "MarkupSafe==3.0.4")
# Debian's amd64 Vulkan options, reduced to the software driver Dota uses.
MESON_OPTIONS = (
    "--prefix=/usr", "--libdir=lib/x86_64-linux-gnu", "--buildtype=release", "-Db_ndebug=true",
    "-Dplatforms=x11", "-Dvulkan-drivers=swrast", "-Dgallium-drivers=swrast",
    "-Dglx=disabled", "-Degl=disabled", "-Dgbm=disabled", "-Dopengl=false",
    "-Dgles1=disabled", "-Dgles2=disabled", "-Dllvm=enabled", "-Dshared-llvm=enabled",
    "-Dbuild-tests=false", "-Dtools=", "-Dvulkan-layers=",
    "-Dvalgrind=disabled", "-Dlibunwind=disabled", "-Dlmsensors=disabled",
    "-Dgallium-vdpau=disabled", "-Dgallium-va=disabled", "-Dgallium-xa=disabled",
    "-Dgallium-omx=disabled", "-Dgallium-nine=false",
)
# Only headers and metadata come from llvm-15-dev. Lavapipe links the base
# root's own libLLVM-15.so.1, which inputs.json pins by hash.
LLVM_CONFIG = '''#!/usr/bin/env python3
from pathlib import Path
import sys
root = Path(__file__).resolve().parent / "sysroot"
base = root / "usr/lib/llvm-15"
args = sys.argv[1:]
components = {"bitwriter": "BitWriter", "engine": "ExecutionEngine",
              "mcdisassembler": "MCDisassembler", "mcjit": "MCJIT", "core": "Core",
              "executionengine": "ExecutionEngine", "scalaropts": "ScalarOpts",
              "transformutils": "TransformUtils", "instcombine": "InstCombine",
              "native": "X86CodeGen", "coroutines": "Coroutines", "lto": "LTO"}
if "--version" in args:
    print("%(version)s")
elif "--components" in args:
    print(" ".join(name for name, library in components.items()
                   if (base / "lib" / ("libLLVM" + library + ".a")).is_file()))
elif "--cppflags" in args:
    print("-I" + str(base / "include") + " -D_GNU_SOURCE -D__STDC_CONSTANT_MACROS"
          " -D__STDC_FORMAT_MACROS -D__STDC_LIMIT_MACROS")
elif "--shared-mode" in args:
    print("shared")
elif "--libs" in args or "--ldflags" in args:
    print("-L" + str(root / "usr/lib/x86_64-linux-gnu") + " -lLLVM-15")
elif "--libdir" in args:
    print(root / "usr/lib/x86_64-linux-gnu")
elif "--has-rtti" in args:
    print("YES")
else:
    raise SystemExit("unsupported LLVM 15 cross query: " + repr(args))
'''


_builder_binding = run_path(str(REPO / "tools/_package_store_native.py"))
_builder_Popen = subprocess.Popen
_builder_controller = _builder_binding["_host"].Controller(Path(__file__).with_name("mesa_query.v"), "VINIX_MESA_QUERY",
    process=lambda *args, **kwargs: _builder_Popen(*args, start_new_session=True, **kwargs))


def _mesa_call(operation, arguments):
    return _builder_binding["call"](operation, arguments, globals(), controller=_builder_controller)


def _mesa_reader(owner, name, arguments):
    return lambda: _builder_binding["builtins"].getattr(owner, name)(*arguments)


def _mesa_mapping(value):
    return {**value}


def digest(path: Path) -> str:
    return _mesa_call('digest', (path,))


def tool(name: str) -> str:
    return _mesa_call('tool', (name,))


def load_resolver():
    return _mesa_call('load_resolver', ())


def load_inputs(path: Path = SUPPORT / "inputs.json") -> dict:
    return _mesa_call('load_inputs', (path,))


def llvm_bin() -> Path:
    # Homebrew's LLVM provides clang, lld and llvm-ar together on macOS.
    return _mesa_call('llvm_bin', ())


def base_identity(base: Path) -> str:
    # Lavapipe links against the base root's libraries. Their names, sizes and
    # link targets change with any package update; hashing all of them is slow.
    return _mesa_call('base_identity', (base,))


def logged(command: list[str], directory: Path, log: Path, environment=None) -> None:
    return _mesa_call('logged', (command, directory, log, environment))


def apply_patch(source: Path, patch: bytes, label: str) -> None:
    return _mesa_call('apply_patch', (source, patch, label))


def check_sources(source: Path, expected: dict, label: str) -> None:
    return _mesa_call('check_sources', (source, expected, label))


def prepare_source(resolver, inputs: dict, downloads: Path, source: Path) -> None:
    return _mesa_call('prepare_source', (resolver, inputs, downloads, source))


def prepare_sysroot(resolver, inputs: dict, base: Path, downloads: Path, sysroot: Path) -> None:
    return _mesa_call('prepare_sysroot', (resolver, inputs, base, downloads, sysroot))


def write_configuration(work: Path, inputs: dict, tools: Path) -> Path:
    return _mesa_call('write_configuration', (work, inputs, tools))


def verify_library(path: Path, base: Path, tools: Path) -> None:
    return _mesa_call('verify_library', (path, base, tools))


def build(base: Path, work: Path, jobs: int = os.cpu_count() or 1, refresh: bool = False) -> Path:
    """Return a patched libvulkan_lvp.so linked against base's runtime libraries."""
    return _mesa_call('build', (base, work, jobs, refresh))


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--base-root", type=Path, required=True,
                        help="amd64 root with Steam's libraries and the Vulkan runtime packages")
    parser.add_argument("--work", type=Path, default=REPO / "build/dota2-runtime/mesa")
    parser.add_argument("--jobs", type=int, default=os.cpu_count() or 1)
    parser.add_argument("--refresh", action="store_true", help="prepare the source and sysroot again")
    args = parser.parse_args()
    if args.jobs < 1:
        parser.error("--jobs must be positive")
    print(build(args.base_root, args.work, args.jobs, args.refresh))


if __name__ == "__main__":
    main()
