#!/usr/bin/env python3
"""Compile every imported ui2 example as a Vinix application process.

The examples stay in their upstream checkout and are built independently; this
avoids renaming their `module main` models or silently dropping platform demos.
"""

import argparse
import concurrent.futures
import os
from pathlib import Path
import shutil
import subprocess
import sys


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
    output = args.output / ("vinix-ui2-" + name)
    common = [str(args.v), "-new-compiler", "-no-memory-limit", "-gc", "none",
              "-enable-globals", "-d", "ui2_headless",
              "-path", "@vlib|%s|@vmodules|%s" %
              (module_root, args.ui2_source)]
    if args.host:
        run(common + ["-o", str(output), str(example)], quiet=True)
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
    reset_directory(args.output, protected)
    reset_directory(args.work, protected)
    module_root = args.work / "vmodules"
    run([sys.executable, str(args.repo / "desktop/tools/stage_ui2.py"),
         str(module_root / "ui2"), str(args.ui2_source),
         str(args.repo / "desktop/tools/ui2_vinix_backend.v")])
    jobs = max(1, args.jobs)
    with concurrent.futures.ThreadPoolExecutor(max_workers=jobs) as executor:
        futures = {executor.submit(compile_example, args, module_root, name): name
                   for name in names}
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
            print("    [%d/%d] %s" % (completed, len(names), name), flush=True)
    if failures:
        sys.exit("failed ui2 examples: " + ",".join(sorted(failures)))
    print("    built %d ui2 example applications" % len(names))


if __name__ == "__main__":
    main()
