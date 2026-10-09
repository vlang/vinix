#!/usr/bin/env python3
"""Build and stage Vinix's ABI-compatible Alpine musl with bounded heap reuse."""
from __future__ import annotations

import argparse
import fcntl
import hashlib
import json
import os
import re
from pathlib import Path
import shlex
import shutil
import subprocess
import tarfile
import tempfile
import urllib.request

ROOT = Path(__file__).resolve().parents[2]
SUPPORT = Path(__file__).resolve().parent
RELEASES = {
    "1.2.5": ("a9a118bbe84d8764da0ea0d28b3ab3fae8477fc7e4085d90102b8596fc7c75e4", "musl-1.2.5-r11", "alpine"),
    "1.2.6": ("d585fd3b613c66151fc3249e8ed44f77020cb5e6c1e635a616d3f9f82460512a", "musl-1.2.6-r2", "alpine-1.2.6"),
}


from runpy import run_path as _run_path

_musl_binding = _run_path(str(ROOT / "tools/_package_store_native.py"))
_musl_Popen = subprocess.Popen
_musl_controller = _musl_binding["_host"].Controller(Path(__file__).with_name("stage_query.v"), "VINIX_MUSL_QUERY",
    process=lambda *args, **kwargs: _musl_Popen(*args, start_new_session=True, **kwargs))


def _musl_call(operation, arguments):
    return _musl_binding["call"](operation, arguments, globals(), controller=_musl_controller)


def sha256(path: Path) -> str:
    return _musl_call('sha256', (path,))


def install(source: Path, target: Path, mode: int) -> None:
    return _musl_call('install', (source, target, mode))


def replace_link(target: Path, destination: str) -> None:
    return _musl_call('replace_link', (target, destination))


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--arch", required=True, choices=["x86_64", "aarch64"])
    parser.add_argument("--staging", required=True, type=Path)
    parser.add_argument("--build-dir", type=Path,
                        default=Path(os.environ.get("VINIX_MUSL_BUILD_DIR", ROOT / "build/musl")))
    parser.add_argument("--cc", help="target Linux C compiler command")
    parser.add_argument("--extra-patch", type=Path, action="append", default=[],
                        help="additional source patch for a private runtime, recorded in the build receipt")
    parser.add_argument("--max-page-size", type=int,
                        help="minimum ELF load-segment alignment for a private runtime")
    parser.add_argument("--require-export", action="append", default=[],
                        help="fail if a private runtime API is absent from the rebuilt libc")
    parser.add_argument("--jobs", type=int,
                        default=int(os.environ.get("NPROC", "8")))
    args = parser.parse_args()
    stage = args.staging.resolve()
    if stage == Path("/") or not (stage / f"lib/ld-musl-{args.arch}.so.1").is_file():
        parser.error("staging must be an existing Alpine root for the requested architecture")
    if args.jobs < 1:
        parser.error("jobs must be positive")
    if args.max_page_size is not None and (args.max_page_size < 4096 or
                                          args.max_page_size & (args.max_page_size - 1)):
        parser.error("max-page-size must be a power of two of at least 4096")
    if os.environ.get("VINIX_OPTIMIZED_MUSL", "1") == "0":
        print("    keeping Alpine's packaged musl (VINIX_OPTIMIZED_MUSL=0)")
        return 0
    retain = os.environ.get("VINIX_MUSL_RETAIN", "1")
    if retain not in ("0", "1"):
        parser.error("VINIX_MUSL_RETAIN must be 0 or 1")
    loader = stage / f"lib/ld-musl-{args.arch}.so.1"
    loader_bytes = loader.read_bytes()
    expected_machine = 62 if args.arch == "x86_64" else 183
    if loader_bytes[:6] != b"\x7fELF\x02\x01" or int.from_bytes(loader_bytes[18:20], "little") != expected_machine:
        parser.error("staged loader architecture does not match --arch")
    versions = re.findall(rb"\x00(1\.2\.[56])\x00", loader_bytes)
    if len(set(versions)) != 1:
        parser.error("only the pinned musl 1.2.5 and 1.2.6 loaders are supported")
    VERSION = versions[0].decode()
    # Newer Alpine 1.2.5 packages backport interfaces from 1.2.6. Preserve
    # those interfaces with the compatible 1.2.6 recipe rather than downgrade.
    if VERSION == "1.2.5" and b"posix_getdents\x00" in loader_bytes:
        VERSION = "1.2.6"
    SOURCE_SHA256, package, patch_directory = RELEASES[VERSION]
    SOURCE_URL = f"https://musl.libc.org/releases/musl-{VERSION}.tar.gz"
    cc = shlex.split(args.cc or os.environ.get(f"VINIX_MUSL_CC_{args.arch.upper()}",
                                               f"{args.arch}-linux-musl-gcc"))
    executable = shutil.which(cc[0]) if cc else None
    if not executable:
        parser.error(f"target compiler missing: {shlex.join(cc)}")
    cc[0] = str(Path(executable).resolve())
    machine = subprocess.check_output(cc + ["-dumpmachine"], text=True).strip()
    if not machine.startswith(args.arch + "-") or "linux" not in machine:
        parser.error(f"compiler target must be {args.arch}-linux: {machine}")
    compiler_version = subprocess.check_output(cc + ["--version"], text=True).splitlines()[0]
    ar = subprocess.check_output(cc + ["-print-prog-name=ar"], text=True).strip()
    ranlib = subprocess.check_output(cc + ["-print-prog-name=ranlib"], text=True).strip()
    alpine_manifest = json.loads((SUPPORT / patch_directory / "manifest.json").read_text())
    patches = []
    for record in alpine_manifest:
        patch = SUPPORT / patch_directory / record["name"]
        if hashlib.sha512(patch.read_bytes()).hexdigest() != record["sha512"]:
            raise RuntimeError(f"Alpine musl patch checksum mismatch: {patch}")
        patches.append(patch)
    patches.append(SUPPORT / "malloc-retain.patch")
    patches.extend(path.expanduser().resolve(strict=True) for path in args.extra_patch)
    if len({path.name for path in patches}) != len(patches):
        parser.error("patch filenames must be distinct")
    patch_inputs = [(p.name, p.read_bytes()) for p in patches]
    cflags = f"-fstack-protector-strong -DVINIX_MALLOC_RETAIN={retain}"
    ldflags = f"-Wl,-soname,libc.musl-{args.arch}.so.1"
    if args.max_page_size is not None:
        ldflags += f" -Wl,-z,max-page-size={args.max_page_size}"
    optimization = "internal,malloc,malloc/mallocng/*.c,string"
    manifest = {"version": VERSION, "alpine_package": package,
                "arch": args.arch, "source_url": SOURCE_URL,
                "source_sha256": SOURCE_SHA256,
                "patches": [{"name": name, "sha256": hashlib.sha256(data).hexdigest()}
                            for name, data in patch_inputs],
                "cc": cc, "compiler_version": compiler_version, "compiler_target": machine,
                "cflags": cflags, "ldflags": ldflags,
                "optimize": optimization, "retention": int(retain)}
    key = hashlib.sha256(json.dumps(manifest, sort_keys=True).encode()).hexdigest()
    cache = args.build_dir.resolve()
    if cache in (Path("/"), ROOT):
        parser.error("unsafe build directory")
    cache.mkdir(parents=True, exist_ok=True)
    with (cache / "build.lock").open("w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        build = cache / args.arch / key
        published = build / "build.json"
        if not published.is_file():
            source_archive = cache / f"musl-{VERSION}.tar.gz"
            if not source_archive.is_file():
                fd, download = tempfile.mkstemp(prefix=".musl-download.", dir=cache)
                os.close(fd)
                try:
                    with urllib.request.urlopen(SOURCE_URL, timeout=60) as response, open(download, "wb") as output:
                        shutil.copyfileobj(response, output)
                    if sha256(Path(download)) != SOURCE_SHA256:
                        raise RuntimeError("musl release checksum mismatch")
                    os.replace(download, source_archive)
                finally:
                    Path(download).unlink(missing_ok=True)
            if sha256(source_archive) != SOURCE_SHA256:
                raise RuntimeError("musl release checksum mismatch")
            if build.exists():
                shutil.rmtree(build)  # Private, unpublished build from a failed attempt.
            build.mkdir(parents=True)
            source = build / f"musl-{VERSION}"
            with tarfile.open(source_archive) as archive:
                for entry in archive.getmembers():
                    parts = Path(entry.name).parts
                    if not parts or parts[0] != f"musl-{VERSION}" or ".." in parts or entry.issym() or entry.islnk():
                        raise RuntimeError(f"unsafe musl archive entry: {entry.name}")
                archive.extractall(build)
            with (build / "build.log").open("w") as log:
                snapshots = build / "patches"
                snapshots.mkdir()
                for name, data in patch_inputs:
                    patch = snapshots / name
                    patch.write_bytes(data)
                    subprocess.run(["patch", "--batch", "-p1", "-i", str(patch)],
                                   cwd=source, check=True, stdout=log, stderr=log)
                # Follow Alpine 1.2.6's x86 preparation: compiler-generated
                # C memcpy/memmove replace the legacy assembly variants.
                if VERSION == "1.2.6":
                    for name in ("memcpy.s", "memmove.s"):
                        (source / "src/string/x86_64" / name).unlink()
                objects = build / "objects"
                objects.mkdir()
                env = dict(os.environ, CC=shlex.join(cc), AR=ar, RANLIB=ranlib,
                           CFLAGS=cflags, LDFLAGS=ldflags)
                configure = [str(source / "configure"), f"--target={args.arch}-linux-musl",
                             "--prefix=/usr", "--syslibdir=/lib", "--disable-wrapper",
                             f"--enable-optimize={optimization}"]
                subprocess.run(configure, cwd=objects, env=env, check=True, stdout=log, stderr=log)
                subprocess.run(["make", f"-j{args.jobs}"], cwd=objects, env=env,
                               check=True, stdout=log, stderr=log)
                manifest["configure_argv"] = configure
                manifest["libc_so_sha256"] = sha256(objects / "lib/libc.so")
                manifest["libc_a_sha256"] = sha256(objects / "lib/libc.a")
                published.write_text(json.dumps(manifest, indent=2) + "\n")
        objects = build / "objects"
        cached_manifest = json.loads(published.read_text())
        for field, value in manifest.items():
            if cached_manifest.get(field) != value:
                raise RuntimeError(f"cached musl build inputs do not match: {field}")
        for filename, field in (("libc.so", "libc_so_sha256"), ("libc.a", "libc_a_sha256")):
            library = objects / "lib" / filename
            if sha256(library) != cached_manifest.get(field):
                raise RuntimeError(f"cached musl library checksum mismatch: {library}")
        readelf = subprocess.check_output(cc + ["-print-prog-name=readelf"], text=True).strip()
        def exports(path: Path) -> set[str]:
            table = subprocess.check_output([readelf, "--dyn-syms", "--wide", str(path)], text=True)
            return {parts[7].split("@")[0] for line in table.splitlines()
                    if len(parts := line.split()) >= 8 and parts[4] in ("GLOBAL", "WEAK") and parts[6] != "UND"}
        missing = exports(loader) - exports(objects / "lib/libc.so")
        if missing:
            raise RuntimeError("rebuilt libc would remove existing exports: " + ", ".join(sorted(missing)))
        missing = set(args.require_export) - exports(objects / "lib/libc.so")
        if missing:
            raise RuntimeError("rebuilt libc lacks required runtime exports: " + ", ".join(sorted(missing)))
        install(objects / "lib/libc.so", stage / f"lib/ld-musl-{args.arch}.so.1", 0o755)
        replace_link(stage / f"lib/libc.musl-{args.arch}.so.1", f"ld-musl-{args.arch}.so.1")
        if (stage / "usr/include/stdlib.h").is_file():
            install(objects / "lib/libc.a", stage / "usr/lib/libc.a", 0o644)
            install(build / f"musl-{VERSION}/include/malloc.h", stage / "usr/include/malloc.h", 0o644)
            replace_link(stage / "usr/lib/libc.so", f"../../lib/ld-musl-{args.arch}.so.1")
        install(published, stage / "usr/share/vinix/musl-build.json", 0o644)
        install(build / f"musl-{VERSION}/COPYRIGHT", stage / "usr/share/licenses/musl/COPYRIGHT", 0o644)
    print(f"    staged Vinix musl {VERSION} ({args.arch}, retention={retain}, {key[:12]})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
