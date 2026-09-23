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

from build_cache import add_hash_field, hash_path, ignored_v_source_entry
from build_cache import ignored_vlib_entry, module_subdirs, new_digest
from build_cache import resolved_tool


APPS = {
    "calc": "cmd/excel",
    "writer": "cmd/word",
}
CACHE_VERSION = 1
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
    """Match the files V ignores when compiling one directory as a module."""
    if path.is_dir():
        return True
    return path.name.endswith("_test.v") or not path.name.endswith(
        OFFICE_SOURCE_SUFFIXES
    )


def office_source_files(source: Path):
    return sorted(
        (
            path
            for path in source.iterdir()
            if path.is_file() and not ignored_office_source(path)
        ),
        key=lambda path: os.fsencode(path.name),
    )


def imported_office_modules(args, app_name: str):
    """Find the app's transitive office.* modules from its production source."""
    pending = [args.office_source / APPS[app_name]]
    visited = set()
    modules = set()
    while pending:
        source = pending.pop()
        source_id = source.resolve()
        if source_id in visited:
            continue
        visited.add(source_id)
        for path in office_source_files(source):
            if not path.name.endswith(".v"):
                continue
            for name in OFFICE_IMPORT_RE.findall(path.read_text()):
                if name in modules:
                    continue
                module_source = args.office_source / name
                if module_source.is_dir():
                    modules.add(name)
                    pending.append(module_source)
    return sorted(modules)


def shared_build_key(args, vroot: Path):
    """Fingerprint inputs shared by both independently built Office apps."""
    digest = new_digest("vinix-voffice-cache", CACHE_VERSION)
    v_compiler = resolved_tool(args.v)
    for name, value in (("arch", args.arch), ("target", args.target)):
        add_hash_field(digest, name)
        add_hash_field(digest, value)

    for label, path in (
        ("builder", Path(__file__)),
        ("cache-helper", Path(__file__).with_name("build_cache.py")),
        ("stager", args.repo / "desktop/tools/stage_ui2.py"),
        ("backend", args.repo / "desktop/tools/ui2_vinix_backend.v"),
        ("ui2-manifest", args.ui2_source / "v.mod"),
        ("office-manifest", args.office_source / "v.mod"),
        ("office-version", args.office_source / "VERSION"),
        ("v-compiler", v_compiler),
    ):
        hash_path(digest, path, label)

    # Compiler libraries and bundled TLS sources are large but change in place
    # during V development. Metadata fingerprints make repeat checks cheap
    # while still noticing normal edits, compiler rebuilds and checkouts.
    hash_path(
        digest,
        vroot / "vlib",
        "vlib",
        metadata_only=True,
        ignore=ignored_vlib_entry,
    )
    hash_path(
        digest,
        vroot / "thirdparty/mbedtls",
        "mbedtls",
        metadata_only=True,
        ignore=ignored_v_source_entry,
    )

    ui2_dirs = [
        name
        for name in module_subdirs(args.ui2_source)
        if name not in EXCLUDED_UI2_SUBDIRS
    ]
    for name in ui2_dirs:
        hash_path(
            digest,
            args.ui2_source / name,
            "ui2/" + name,
            ignore=ignored_v_source_entry,
        )
    hash_path(digest, args.ui2_source / "assets", "ui2/assets")

    for label, path in (
        ("clang", resolved_tool(args.clang)),
        ("strip", resolved_tool(args.strip)),
        ("clang-resource-headers", args.clang_resource_include),
        ("sysroot-headers", args.sysroot / "usr/include"),
        ("gcc-headers", args.gcclib / "include"),
        ("crt1", args.sysroot / "usr/lib/crt1.o"),
        ("crti", args.sysroot / "usr/lib/crti.o"),
        ("crtn", args.sysroot / "usr/lib/crtn.o"),
        ("libc", args.sysroot / "usr/lib/libc.a"),
        ("libm", args.sysroot / "usr/lib/libm.a"),
        ("crtbegin", args.gcclib / "crtbeginT.o"),
        ("crtend", args.gcclib / "crtend.o"),
        ("libgcc", args.gcclib / "libgcc.a"),
        ("libgcc-eh", args.gcclib / "libgcc_eh.a"),
    ):
        hash_path(digest, path, label, metadata_only=True)
    if args.cc_shim:
        hash_path(digest, args.cc_shim, "cc-shim")
    if args.llvm_bin:
        hash_path(
            digest,
            args.llvm_bin / "ld.lld",
            "ld.lld",
            metadata_only=True,
        )
    return digest.hexdigest()


def app_build_key(args, shared_key: str, name: str):
    digest = new_digest("vinix-voffice-app", CACHE_VERSION)
    add_hash_field(digest, shared_key)
    hash_path(
        digest,
        args.office_source / APPS[name],
        "office/" + APPS[name],
        ignore=ignored_office_source,
    )
    for module_name in imported_office_modules(args, name):
        hash_path(
            digest,
            args.office_source / module_name,
            "office/" + module_name,
            ignore=ignored_office_source,
        )
    return digest.hexdigest()


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
