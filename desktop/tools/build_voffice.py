#!/usr/bin/env python3
"""Cross-compile VOffice Calc and Writer as native Vinix ui2 clients."""

import argparse
import concurrent.futures
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys


APPS = {
    "calc": "cmd/excel",
    "writer": "cmd/word",
}


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
    output = args.output / ("voffice-" + name)
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
    if args.output.exists():
        shutil.rmtree(args.output)
    if args.work.exists():
        shutil.rmtree(args.work)
    args.output.mkdir(parents=True)
    args.work.mkdir(parents=True)

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
    names = args.only or list(APPS)
    for name in names:
        compile_app(args, vroot, module_root, tls_objects, name)


if __name__ == "__main__":
    try:
        main()
    except (RuntimeError, subprocess.CalledProcessError) as error:
        sys.exit("VOffice build failed: %s" % error)
