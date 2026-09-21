#!/usr/bin/env python3
"""Compile every imported ui2 example as a Vinix application process.

The examples stay in their upstream checkout and are built independently; this
avoids renaming their `module main` models or silently dropping platform demos.
"""

import argparse
import concurrent.futures
import fnmatch
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys

from build_cache import add_hash_field, hash_path, ignored_v_source_entry
from build_cache import ignored_vlib_entry, module_subdirs, new_digest
from build_cache import resolved_tool


CACHE_VERSION = 1
CACHE_STATE_NAME = ".vinix-ui2-build-state.json"
EXCLUDED_MODULE_SUBDIRS = {"appkit"}
EXAMPLE_IGNORE_PATTERNS = ("*_test.v", "*.o", "*.exe", "build_examples")
EXAMPLE_INPUT_SUFFIXES = (
    ".bmp", ".c", ".h", ".jpeg", ".jpg", ".json", ".png", ".qml",
    ".svg", ".ttf", ".txt", ".v", ".vml",
)


def inventory(source: Path):
    return sorted(path.name for path in (source / "examples").iterdir()
                  if path.is_dir() and (path / "main.v").is_file())


def expected_names(repo: Path):
    manifest = repo / "desktop/ui2_examples.txt"
    return [line.strip() for line in manifest.read_text().splitlines()
            if line.strip() and not line.startswith("#")]


def run(command, quiet=False):
    result = subprocess.run(command, text=True,
                            stdout=subprocess.PIPE if quiet else None,
                            stderr=subprocess.STDOUT if quiet else None)
    if result.returncode:
        if quiet and result.stdout:
            sys.stderr.write(result.stdout)
        raise subprocess.CalledProcessError(result.returncode, command)


def ignored_example_entry(path: Path, example_name: str) -> bool:
    patterns = EXAMPLE_IGNORE_PATTERNS + (example_name,)
    if any(fnmatch.fnmatch(path.name, pattern) for pattern in patterns):
        return True
    return path.is_file() and not path.name.endswith(EXAMPLE_INPUT_SUFFIXES)


def shared_build_key(args):
    """Fingerprint everything shared by the independently built examples."""
    digest = new_digest("vinix-ui2-example-cache", CACHE_VERSION)
    v_compiler = resolved_tool(args.v)
    for name, value in (
            ("host", str(args.host)),
            ("arch", args.arch or ""),
            ("target", args.target or "")):
        add_hash_field(digest, name)
        add_hash_field(digest, value)

    for label, path in (
            ("builder", Path(__file__)),
            ("cache-helper", Path(__file__).with_name("build_cache.py")),
            ("manifest", args.repo / "desktop/ui2_examples.txt"),
            ("stager", args.repo / "desktop/tools/stage_ui2.py"),
            ("backend", args.repo / "desktop/tools/ui2_vinix_backend.v"),
            ("ui2-manifest", args.ui2_source / "v.mod"),
            ("v-compiler", v_compiler)):
        hash_path(digest, path, label)
    vlib = v_compiler.parent / "vlib"
    if vlib.is_dir():
        hash_path(digest, vlib, "vlib", metadata_only=True,
                  ignore=ignored_vlib_entry)

    ui2_dirs = [name for name in module_subdirs(args.ui2_source)
                if name not in EXCLUDED_MODULE_SUBDIRS]
    for name in ui2_dirs:
        hash_path(digest, args.ui2_source / name, "ui2/" + name,
                  ignore=ignored_v_source_entry)
    hash_path(digest, args.ui2_source / "assets", "ui2/assets")

    if not args.host:
        # Executables and large sysroot trees use generation metadata. This is
        # fast on warm builds, while inode/ctime/mtime still catches normal
        # package extraction and in-place toolchain updates.
        for label, path in (
                ("clang", resolved_tool(args.clang)),
                ("strip", resolved_tool(args.strip)),
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
                ("libgcc-eh", args.gcclib / "libgcc_eh.a")):
            hash_path(digest, path, label, metadata_only=True)
        if args.cc_shim:
            hash_path(digest, args.cc_shim, "cc-shim")
        if args.llvm_bin:
            hash_path(digest, args.llvm_bin / "ld.lld", "ld.lld",
                      metadata_only=True)
    return digest.hexdigest()


def example_build_key(args, shared_key: str, name: str):
    digest = new_digest("vinix-ui2-example", CACHE_VERSION)
    add_hash_field(digest, shared_key)
    source = args.ui2_source / "examples" / name
    hash_path(digest, source, "example/" + name,
              ignore=lambda path: ignored_example_entry(path, name))
    return digest.hexdigest()


def load_build_state(output: Path):
    try:
        state = json.loads((output / CACHE_STATE_NAME).read_text())
    except (FileNotFoundError, json.JSONDecodeError, OSError):
        return {}
    if state.get("version") != CACHE_VERSION:
        return {}
    if not isinstance(state.get("examples"), dict):
        return {}
    return state


def write_build_state(output: Path, shared_key: str, examples):
    state = {
        "version": CACHE_VERSION,
        "shared_key": shared_key,
        "examples": examples,
    }
    temporary = output / (CACHE_STATE_NAME + ".tmp.%d" % os.getpid())
    temporary.write_text(json.dumps(state, indent=2, sort_keys=True) + "\n")
    os.replace(temporary, output / CACHE_STATE_NAME)


def output_binary(output: Path, name: str) -> Path:
    return output / ("vinix-ui2-" + name)


def usable_cached_binary(output: Path, name: str) -> bool:
    binary = output_binary(output, name)
    try:
        return binary.is_file() and binary.stat().st_size > 0 and os.access(binary, os.X_OK)
    except OSError:
        return False


def reset_directory(path: Path, protected):
    resolved = path.resolve()
    if resolved in protected or resolved == Path(resolved.anchor):
        raise SystemExit("refusing unsafe ui2 build directory: %s" % resolved)
    if path.exists():
        shutil.rmtree(path)
    path.mkdir(parents=True)


def stage_example(args, name: str, work: Path) -> Path:
    source = args.ui2_source / "examples" / name
    staged = work / "source"
    shutil.copytree(source, staged, ignore=shutil.ignore_patterns(
        "*_test.v", "*.o", "*.exe", name, "build_examples"))
    if name == "change_title":
        for platform_source in staged.glob("window_title_*"):
            platform_source.unlink()
        (staged / "vinix_window_title.v").write_text(
            "module main\n\nfn apply_window_title(_title string) {}\n")
    # V's native frontend emits private module-main functions without a C
    # namespace. These two examples intentionally call a helper `truncate`,
    # which otherwise collides with POSIX truncate(2) from unistd.h.
    main_source = staged / "main.v"
    source_text = main_source.read_text()
    if "truncate(" in source_text:
        main_source.write_text(source_text.replace("truncate(",
                                                   "ui2_example_truncate("))
    return staged


def compile_example(args, module_root: Path, name: str):
    work = args.work / name
    work.mkdir(parents=True, exist_ok=True)
    example = stage_example(args, name, work)
    generated = work / (name + ".c")
    # Publish only complete binaries, retaining the previous cached executable
    # if translation or linking fails midway through an incremental rebuild.
    output = work / ("vinix-ui2-" + name)
    common = [str(args.v), "-new-compiler", "-no-memory-limit", "-gc", "none",
              "-enable-globals", "-d", "ui2_headless",
              "-path", "@vlib|%s|@vmodules|%s" %
              (module_root, args.ui2_source)]
    if args.host:
        run(common + ["-o", str(output), str(example)], quiet=True)
        os.replace(output, output_binary(args.output, name))
        return name

    v_command = common[0:3] + ["-os", "linux", "-arch", args.arch] + common[3:]
    v_command += ["-manualfree", "-prod", "-d", "glibc", "-d", "no_backtrace",
                  "-o", str(generated), str(example)]
    run(v_command, quiet=True)

    cc_command = [str(args.clang), "--target=" + args.target, "-static", "-nostdinc",
                  "-nostdlib"]
    if args.cc_shim:
        cc_command += ["-isystem", str(args.cc_shim)]
    cc_command += ["-isystem", str(args.gcclib / "include"),
                   "-isystem", str(args.sysroot / "usr/include"),
                   "-I", str(example), "-O2", "-fno-stack-protector", "-w",
                   str(args.sysroot / "usr/lib/crt1.o"),
                   str(args.sysroot / "usr/lib/crti.o"),
                   str(args.gcclib / "crtbeginT.o"), str(generated),
                   "-L" + str(args.sysroot / "usr/lib"), "-L" + str(args.gcclib),
                   "-lgcc_eh", "-lc", "-lgcc", "-lm",
                   str(args.gcclib / "crtend.o"), str(args.sysroot / "usr/lib/crtn.o"),
                   "-fuse-ld=lld"]
    if args.llvm_bin:
        cc_command += ["-B" + str(args.llvm_bin)]
    cc_command += ["-o", str(output)]
    run(cc_command, quiet=True)
    run([str(args.strip), str(output)], quiet=True)
    os.replace(output, output_binary(args.output, name))
    return name


def parse_args():
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo", type=Path, required=True)
    parser.add_argument("--ui2-source", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--work", type=Path, required=True)
    parser.add_argument("--v", type=Path, required=True)
    parser.add_argument("--host", action="store_true",
                        help="build host-native smoke-test executables")
    parser.add_argument("--arch", choices=("x64", "arm64"))
    parser.add_argument("--clang", type=Path)
    parser.add_argument("--strip", type=Path)
    parser.add_argument("--target")
    parser.add_argument("--sysroot", type=Path)
    parser.add_argument("--gcclib", type=Path)
    parser.add_argument("--cc-shim", type=Path)
    parser.add_argument("--llvm-bin", type=Path)
    parser.add_argument("--jobs", type=int,
                        default=int(os.environ.get("VINIX_UI2_JOBS", "1")))
    parser.add_argument("--only", action="append", default=[],
                        help="build only this named example (repeatable; for validation)")
    return parser.parse_args()


def main():
    args = parse_args()
    if not args.host:
        required = (args.arch, args.clang, args.strip, args.target,
                    args.sysroot, args.gcclib)
        if any(value is None for value in required):
            sys.exit("cross build requires --arch, --clang, --strip, --target, "
                     "--sysroot, and --gcclib")
    names = expected_names(args.repo)
    found = inventory(args.ui2_source)
    if names != found:
        missing = sorted(set(names) - set(found))
        extra = sorted(set(found) - set(names))
        sys.exit("ui2 example inventory mismatch; missing=%s extra=%s" %
                 (",".join(missing) or "none", ",".join(extra) or "none"))
    if args.only:
        unknown = sorted(set(args.only) - set(names))
        if unknown:
            sys.exit("unknown ui2 example(s): " + ",".join(unknown))
        names = [name for name in names if name in set(args.only)]
    protected = {Path.home().resolve(), args.repo.resolve(),
                 args.ui2_source.resolve()}
    if args.output.resolve() == args.work.resolve():
        sys.exit("ui2 output and work directories must be different")
    output_resolved = args.output.resolve()
    if output_resolved in protected or output_resolved == Path(output_resolved.anchor):
        sys.exit("refusing unsafe ui2 output directory: %s" % output_resolved)
    args.output.mkdir(parents=True, exist_ok=True)

    expected_outputs = {"vinix-ui2-" + name for name in found}
    for binary in args.output.glob("vinix-ui2-*"):
        if binary.name not in expected_outputs and binary.is_file():
            binary.unlink()

    shared_key = shared_build_key(args)
    keys = {name: example_build_key(args, shared_key, name) for name in names}
    state = load_build_state(args.output)
    cached_examples = state.get("examples", {})
    cached_examples = {name: key for name, key in cached_examples.items()
                       if name in found}
    if state.get("shared_key") != shared_key:
        cached_examples = {}
    dirty = [name for name in names
             if cached_examples.get(name) != keys[name]
             or not usable_cached_binary(args.output, name)]
    if not dirty:
        print("    reusing %d cached ui2 example applications" % len(names))
        return

    reset_directory(args.work, protected)
    module_root = args.work / "vmodules"
    run([sys.executable, str(args.repo / "desktop/tools/stage_ui2.py"),
         str(module_root / "ui2"), str(args.ui2_source),
         str(args.repo / "desktop/tools/ui2_vinix_backend.v")])
    jobs = max(1, args.jobs)
    with concurrent.futures.ThreadPoolExecutor(max_workers=jobs) as executor:
        futures = {executor.submit(compile_example, args, module_root, name): name
                   for name in dirty}
        completed = 0
        failures = []
        for future in concurrent.futures.as_completed(futures):
            name = futures[future]
            try:
                future.result()
            except Exception:
                sys.stderr.write("FAILED ui2 example: %s\n" % name)
                failures.append(name)
                continue
            completed += 1
            print("    [%d/%d] %s" % (completed, len(dirty), name), flush=True)
    if failures:
        sys.exit("failed ui2 examples: " + ",".join(sorted(failures)))
    if state.get("shared_key") != shared_key:
        cached_examples = {}
    for name in dirty:
        cached_examples[name] = keys[name]
    write_build_state(args.output, shared_key, cached_examples)
    reused = len(names) - len(dirty)
    if reused:
        print("    built %d ui2 example applications; reused %d cached" %
              (len(dirty), reused))
    else:
        print("    built %d ui2 example applications" % len(dirty))


if __name__ == "__main__":
    main()
