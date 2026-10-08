#!/usr/bin/env python3
"""Cross-compile VOffice Calc and Writer as native Vinix ui2 clients."""

import argparse
import concurrent.futures
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys

from build_cache import _native


APPS = {
    "calc": "cmd/excel",
    "writer": "cmd/word",
}
CACHE_VERSION = 2
CACHE_STATE_NAME = ".vinix-voffice-build-state.json"
EXCLUDED_UI2_SUBDIRS = {"appkit"}
OFFICE_SOURCE_SUFFIXES = (".c", ".h", ".m", ".v")
OFFICE_IMPORT_RE = re.compile(r"\boffice\.([a-zA-Z_][a-zA-Z0-9_]*)")


def run(command, quiet=False):
    result = subprocess.run(
        [str(part) for part in command],
        text=True,
        stdout=subprocess.PIPE if quiet else None,
        stderr=subprocess.STDOUT if quiet else None,
    )
    if result.returncode:
        if quiet and result.stdout:
            sys.stderr.write(result.stdout)
        raise subprocess.CalledProcessError(result.returncode, command)


def ignored_office_source(path: Path) -> bool:
    return _native.request("ignored_source", path=_native.wire(path), policy="office")


def office_source_files(source: Path):
    return [Path(os.fsdecode(bytes.fromhex(path))) for path in
            _native.request("office_source_files", path=_native.wire(source))]


def imported_office_modules(args, app_name: str):
    APPS[app_name]
    return _native.request("office_modules", office=_native.wire(args.office_source),
                           app=_native.wire(app_name))


def shared_build_key(args, vroot: Path):
    return _native.request("office_shared", repo=_native.wire(args.repo),
                           builder=_native.wire(Path(__file__)),
                           office=_native.wire(args.office_source), ui2=_native.wire(args.ui2_source),
                           v=_native.wire(args.v), vroot=_native.wire(vroot),
                           arch=_native.wire(args.arch), target=_native.wire(args.target),
                           clang=_native.wire(args.clang), strip=_native.wire(args.strip),
                           clang_headers=_native.wire(args.clang_resource_include),
                           sysroot=_native.wire(args.sysroot), gcclib=_native.wire(args.gcclib),
                           cc_shim=_native.wire(args.cc_shim) if args.cc_shim else "",
                           llvm=_native.wire(args.llvm_bin) if args.llvm_bin else "")


def app_build_key(args, shared_key: str, name: str):
    APPS[name]
    return _native.request("office_key", office=_native.wire(args.office_source),
                           shared=_native.wire(shared_key), app=_native.wire(name))


def load_build_state(output: Path):
    try:
        state = json.loads((output / CACHE_STATE_NAME).read_text())
    except (FileNotFoundError, json.JSONDecodeError, OSError):
        return {}
    if state.get("version") != CACHE_VERSION:
        return {}
    if not isinstance(state.get("apps"), dict):
        return {}
    return state


def write_build_state(output: Path, shared_key: str, apps):
    state = {
        "version": CACHE_VERSION,
        "shared_key": shared_key,
        "apps": apps,
    }
    temporary = output / (CACHE_STATE_NAME + ".tmp.%d" % os.getpid())
    temporary.write_text(json.dumps(state, indent=2, sort_keys=True) + "\n")
    os.replace(temporary, output / CACHE_STATE_NAME)


def output_binary(output: Path, name: str) -> Path:
    return output / ("voffice-" + name)


def usable_cached_binary(output: Path, name: str) -> bool:
    binary = output_binary(output, name)
    try:
        return binary.is_file() and binary.stat().st_size > 0 and os.access(
            binary, os.X_OK
        )
    except OSError:
        return False


def reset_directory(path: Path, protected):
    resolved = path.resolve()
    if resolved in protected or resolved == Path(resolved.anchor):
        raise RuntimeError("refusing unsafe VOffice build directory: %s" % resolved)
    if path.exists():
        shutil.rmtree(path)
    path.mkdir(parents=True)


def compiler_root(v: Path):
    root = v.resolve().parent
    required = [root / "vlib", root / "thirdparty/mbedtls"]
    if not all(path.is_dir() for path in required):
        raise RuntimeError(
            "%s must be an executable in a V source checkout with bundled mbedTLS"
            % v
        )
    return root


def cc_base(args, vroot: Path):
    mbedtls = vroot / "thirdparty/mbedtls"
    command = [
        args.clang,
        "--target=" + args.target,
        "-nostdinc",
    ]
    if args.cc_shim:
        command += ["-isystem", args.cc_shim]
    if args.target.startswith("aarch64-"):
        # mbedTLS enables NEON on AArch64. Clang must see its own intrinsic
        # header before Alpine GCC's target-private copy; the latter names GCC
        # builtin vector types that Clang does not provide. The explicit shim
        # above remains first so Vinix's stdatomic compatibility header wins.
        command += ["-isystem", args.clang_resource_include]
    command += [
        "-isystem",
        args.gcclib / "include",
        "-isystem",
        args.sysroot / "usr/include",
        "-I",
        mbedtls / "include",
        "-I",
        mbedtls / "library",
        "-I",
        mbedtls / "3rdparty/everest/include",
        "-I",
        mbedtls / "3rdparty/everest/include/everest",
        "-I",
        mbedtls / "3rdparty/everest/include/everest/kremlib",
        "-O2",
        "-fno-stack-protector",
        "-w",
    ]
    return command


def mbedtls_sources(vroot: Path):
    manifest = vroot / "vlib/net/mbedtls/mbedtls.c.v"
    text = manifest.read_text()
    names = re.findall(
        r"^#flag @VEXEROOT/thirdparty/mbedtls/(.+)\.o$", text, re.MULTILINE
    )
    if not names:
        raise RuntimeError("could not find bundled mbedTLS object inventory")
    return [Path(name + ".c") for name in names]


def compile_mbedtls_source(args, vroot: Path, objects: Path, source: Path):
    mbedtls = vroot / "thirdparty/mbedtls"
    output = objects / ("_".join(source.parts[:-1] + (source.stem,)) + ".o")
    run(cc_base(args, vroot) + ["-c", mbedtls / source, "-o", output], quiet=True)
    return output


def build_mbedtls(args, vroot: Path):
    objects = args.work / "mbedtls"
    objects.mkdir(parents=True)
    sources = mbedtls_sources(vroot)
    workers = max(1, args.jobs)
    with concurrent.futures.ThreadPoolExecutor(max_workers=workers) as executor:
        futures = [
            executor.submit(compile_mbedtls_source, args, vroot, objects, source)
            for source in sources
        ]
        outputs = [future.result() for future in futures]
    print("    built %d bundled mbedTLS objects" % len(outputs), flush=True)
    return outputs


def compile_app(args, vroot: Path, module_root: Path, tls_objects, name: str):
    source = args.office_source / APPS[name]
    generated = args.work / (name + ".c")
    output = args.work / ("voffice-" + name)
    v_command = [
        args.v,
        "-new-compiler",
        "--no-parallel",
        "-no-memory-limit",
        "-os",
        "linux",
        "-arch",
        args.arch,
        "-gc",
        "none",
        "-manualfree",
        "-enable-globals",
        "-prod",
        "-d",
        "glibc",
        "-d",
        "no_backtrace",
        "-d",
        "ui2_headless",
        "-path",
        "@vlib|%s" % module_root,
        "-o",
        generated,
        source,
    ]
    run(v_command, quiet=True)

    command = cc_base(args, vroot)
    command[1:1] = ["-static", "-nostdlib"]
    command += [
        "-I",
        args.office_source,
        "-Wno-error=incompatible-function-pointer-types",
        args.sysroot / "usr/lib/crt1.o",
        args.sysroot / "usr/lib/crti.o",
        args.gcclib / "crtbeginT.o",
        generated,
        *tls_objects,
        "-L" + str(args.sysroot / "usr/lib"),
        "-L" + str(args.gcclib),
        "-lgcc_eh",
        "-lc",
        "-lgcc",
        "-lm",
        args.gcclib / "crtend.o",
        args.sysroot / "usr/lib/crtn.o",
        "-fuse-ld=lld",
    ]
    if args.llvm_bin:
        command += ["-B" + str(args.llvm_bin)]
    command += ["-o", output]
    run(command, quiet=True)
    run([args.strip, output], quiet=True)
    os.replace(output, output_binary(args.output, name))
    print("    built VOffice %s" % name.capitalize(), flush=True)


def parse_args():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", type=Path, required=True)
    parser.add_argument("--office-source", type=Path, required=True)
    parser.add_argument("--ui2-source", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--work", type=Path, required=True)
    parser.add_argument("--v", type=Path, required=True)
    parser.add_argument("--arch", choices=("x64", "arm64"), required=True)
    parser.add_argument("--clang", type=Path, required=True)
    parser.add_argument("--strip", type=Path, required=True)
    parser.add_argument("--target", required=True)
    parser.add_argument("--sysroot", type=Path, required=True)
    parser.add_argument("--gcclib", type=Path, required=True)
    parser.add_argument("--cc-shim", type=Path)
    parser.add_argument("--llvm-bin", type=Path)
    parser.add_argument(
        "--jobs", type=int, default=int(os.environ.get("VINIX_OFFICE_JOBS", "4"))
    )
    parser.add_argument(
        "--only",
        action="append",
        choices=tuple(APPS),
        default=[],
        help="build only one application (repeatable; for validation)",
    )
    return parser.parse_args()


def validate_inputs(args):
    required = [
        args.office_source / "v.mod",
        args.office_source / "cmd/excel/main.v",
        args.office_source / "cmd/word/main.v",
        args.office_source / "assets/logo.png",
        args.ui2_source / "v.mod",
    ]
    missing = [str(path) for path in required if not path.is_file()]
    if missing:
        raise RuntimeError("missing VOffice/ui2 input: " + ", ".join(missing))


def main():
    args = parse_args()
    validate_inputs(args)
    resource_dir = subprocess.check_output(
        [str(args.clang), "--print-resource-dir"], text=True
    ).strip()
    args.clang_resource_include = Path(resource_dir) / "include"
    if not args.clang_resource_include.is_dir():
        raise RuntimeError(
            "Clang resource headers not found at %s" % args.clang_resource_include
        )
    vroot = compiler_root(args.v)
    protected = {
        Path.home().resolve(),
        args.repo.resolve(),
        args.office_source.resolve(),
        args.ui2_source.resolve(),
        vroot.resolve(),
    }
    if args.output.resolve() == args.work.resolve():
        raise RuntimeError("VOffice output and work directories must be different")
    output_resolved = args.output.resolve()
    if output_resolved in protected or output_resolved == Path(output_resolved.anchor):
        raise RuntimeError("refusing unsafe VOffice output directory: %s" % output_resolved)
    args.output.mkdir(parents=True, exist_ok=True)

    expected_outputs = {"voffice-" + name for name in APPS}
    for binary in args.output.glob("voffice-*"):
        if binary.name not in expected_outputs and binary.is_file():
            binary.unlink()

    names = args.only or list(APPS)
    shared_key = shared_build_key(args, vroot)
    keys = {name: app_build_key(args, shared_key, name) for name in names}
    state = load_build_state(args.output)
    cached_apps = {
        name: key for name, key in state.get("apps", {}).items() if name in APPS
    }
    if state.get("shared_key") != shared_key:
        cached_apps = {}
    dirty = [
        name
        for name in names
        if cached_apps.get(name) != keys[name]
        or not usable_cached_binary(args.output, name)
    ]
    if not dirty:
        print("    reusing %d cached VOffice applications" % len(names))
        return

    reset_directory(args.work, protected)

    module_root = args.work / "vmodules"
    run(
        [
            sys.executable,
            args.repo / "desktop/tools/stage_ui2.py",
            module_root / "ui2",
            args.ui2_source,
            args.repo / "desktop/tools/ui2_vinix_backend.v",
        ]
    )
    os.symlink(args.office_source.resolve(), module_root / "office")

    tls_objects = build_mbedtls(args, vroot)
    for name in dirty:
        compile_app(args, vroot, module_root, tls_objects, name)
    if state.get("shared_key") != shared_key:
        cached_apps = {}
    for name in dirty:
        cached_apps[name] = keys[name]
    write_build_state(args.output, shared_key, cached_apps)
    reused = len(names) - len(dirty)
    if reused:
        print(
            "    built %d VOffice applications; reused %d cached"
            % (len(dirty), reused)
        )
    else:
        print("    built %d VOffice applications" % len(dirty))


if __name__ == "__main__":
    try:
        main()
    except (RuntimeError, subprocess.CalledProcessError) as error:
        sys.exit("VOffice build failed: %s" % error)
