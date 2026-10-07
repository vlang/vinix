#!/usr/bin/env python3
"""Build pinned paraLLEl-N64 with interpreters and synchronous software RDP."""
# SPDX-License-Identifier: MIT
import argparse
from concurrent.futures import ThreadPoolExecutor
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import shlex
import shutil
import subprocess
import tarfile
import tempfile
import urllib.request

ROOT = Path(__file__).resolve().parents[2]
SUPPORT = Path(__file__).resolve().parent
REVISION = "ef73c7e6fa356262f88e05f85cdfad092f8f90e0"
SOURCE_URL = f"https://codeload.github.com/libretro/parallel-n64/tar.gz/{REVISION}"
SOURCE_SHA256 = "0be08e52bb9a759253b802a546a699dc5cc8e2799f9234e45e64550b09ffc396"
ZLIB_REVISION = "51b7f2abdade71cd9bb0e7a373ef2610ec6f9daf"
ZLIB_URL = f"https://codeload.github.com/madler/zlib/tar.gz/{ZLIB_REVISION}"
ZLIB_SHA256 = "d9e270d46252734aa49770fbc544125391617956266f220bd63216c834f3a522"
PATCH_VERSION = "vinix-interpreter-5"


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        while chunk := stream.read(1024 * 1024):
            digest.update(chunk)
    return digest.hexdigest()


def fetch(path: Path, url: str = SOURCE_URL, digest: str = SOURCE_SHA256) -> None:
    if not path.exists():
        request = urllib.request.Request(url, headers={"User-Agent": "Vinix-N64-build"})
        with tempfile.NamedTemporaryFile(dir=path.parent, delete=False) as stream:
            temporary = Path(stream.name)
            try:
                with urllib.request.urlopen(request, timeout=120) as response:
                    count = 0
                    while chunk := response.read(1024 * 1024):
                        count += len(chunk)
                        if count > 16 * 1024 * 1024:
                            raise ValueError("source download exceeds size limit")
                        stream.write(chunk)
                stream.flush()
                if sha256(temporary) != digest:
                    raise ValueError("emulator dependency source checksum mismatch")
                temporary.replace(path)
            finally:
                temporary.unlink(missing_ok=True)
    if path.stat().st_size > 16 * 1024 * 1024 or sha256(path) != digest:
        raise ValueError(f"cached source checksum mismatch: {path}")


def unpack(archive: Path, destination: Path) -> None:
    with tarfile.open(archive, "r:gz") as stream:
        for member in stream:
            path = PurePosixPath(member.name)
            if path.is_absolute() or ".." in path.parts or "\\" in member.name:
                raise ValueError(f"unsafe archive path: {member.name}")
            if member.isdir():
                continue
            if not member.isfile() or len(path.parts) < 2 or member.size > 16 * 1024 * 1024:
                raise ValueError(f"unsupported archive member: {member.name}")
            target = destination.joinpath(*path.parts[1:])
            target.parent.mkdir(parents=True, exist_ok=True)
            with stream.extractfile(member) as data:
                target.write_bytes(data.read())
            target.chmod(0o755 if member.mode & 0o111 else 0o644)


def replace(path: Path, before: str, after: str) -> None:
    text = path.read_text()
    if text.count(before) != 1:
        raise ValueError(f"pinned source patch did not match once: {path}")
    path.write_text(text.replace(before, after))


def patch(source: Path) -> None:
    memory = source / "mupen64plus-core/src/device/memory/m64p_memory.c"
    text = memory.read_text()
    first = text.index("void* init_mem_base(void)")
    last = text.index("void release_mem_base", first)
    memory.write_text(text[:first] + """/* Vinix uses the upstream compact mapping: 76 MiB rather than 512 MiB.
 * No JIT or external-memory GPU backend needs a full physical-address map. */
void* init_mem_base(void)
{
    void* mem_base = malloc(MB_MAX_SIZE);
    if (mem_base != NULL) SET_MEM_BASE_MODE(mem_base);
    return mem_base;
}

""" + text[last:])
    replace(source / "mupen64plus-core/src/device/r4300/pure_interp.c",
            "void InterpretOpcode(struct r4300_core* r4300)\n{",
            "void InterpretOpcode(struct r4300_core* r4300)\n{\n"
            "    if (vinix_n64_cpu_budget && !--vinix_n64_cpu_budget) {\n"
            "        vinix_n64_budget_exhausted(); return;\n    }")
    # Static-PC branches dispatch their delay slot with goto EX, bypassing
    # the outer loop. Count at the shared execution entry so those instructions
    # cannot evade the per-frame limit.
    replace(source / "mupen64plus-rsp-cxd4/su.c",
            "EX:\n#endif\n#ifdef SP_EXECUTE_LOG",
            "EX:\n#endif\n"
            "        if (vinix_n64_rsp_budget && !--vinix_n64_rsp_budget) {\n"
            "            vinix_n64_budget_exhausted(); goto RSP_halted_CPU_exit_point;\n        }\n"
            "#ifdef SP_EXECUTE_LOG")
    # Cartridge-only frontend never mounts 64DD disks. Avoid clearing 67 MiB
    # of unused global disk storage on each ROM load.
    replace(source / "libretro/libretro.c", "   format_disk(saved_memory.disk);", "   /* Vinix: no 64DD disk. */")
    replace(source / "libretro/libretro.c", '#include <glsm/glsm.h>',
            '#if defined(HAVE_OPENGL) || defined(HAVE_OPENGLES)\n#include <glsm/glsm.h>\n'
            '#else\nenum glsm_state_ctl { GLSM_CTL_STATE_CONTEXT_DESTROY };\n#endif')
    replace(source / "libretro-common/vfs/vfs_implementation.c", '#if defined(__linux__)\n#include <linux/falloc.h>',
            '#if defined(__linux__) && !defined(VINIX_NO_FALLOC)\n#include <linux/falloc.h>')
    replace(source / "mupen64plus-core/src/device/r4300/r4300.h",
            '#if !defined(__arm64__) && !defined(__aarch64__)',
            '#if (!defined(__arm64__) && !defined(__aarch64__)) || !defined(NEW_DYNAREC)')
    # Upstream's reentrant interpreter/run setup uses local static flags that
    # must be cleared when the singleton starts a different cartridge.
    replace(source / "mupen64plus-core/src/device/r4300/pure_interp.c",
            '   static int l_pi_started = 0;', '   extern int vinix_n64_pi_started;\n#define l_pi_started vinix_n64_pi_started')
    replace(source / "mupen64plus-core/src/main/main.c",
            '    static int l_setup_done = 0;',
            '    extern int vinix_n64_setup_done;\n#define l_setup_done vinix_n64_setup_done')
    replace(source / "libretro/libretro.c", '    first_time = 1;\n\n    EmuThreadStep();',
            '    first_time = 1;\n\n    /* Vinix closes devices between frame slices; do not execute another frame. */')


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=ROOT / "build/n64")
    parser.add_argument("--sysroot", type=Path, default=ROOT / "build-aarch64-userland/staging")
    parser.add_argument("--linux-headers", type=Path,
                        default=Path(os.environ.get("VINIX_AARCH64_LINUX_HEADERS",
                                                    str(ROOT / "build-aarch64-userland/sysroot/include"))))
    parser.add_argument("--llvm-bin", type=Path, default=Path(os.environ.get("LLVM_BIN", "/opt/homebrew/opt/llvm/bin")))
    parser.add_argument("--jobs", type=int, default=min(os.cpu_count() or 2, 8))
    parser.add_argument("--host", action="store_true", help="build a native host archive for emulator smoke tests")
    args = parser.parse_args()
    output, sysroot, llvm = args.output.resolve(), args.sysroot.resolve(), args.llvm_bin.resolve()
    if args.jobs < 1:
        parser.error("--jobs must be positive")
    common = ["-O2", "-DNDEBUG", "-D_GNU_SOURCE", "-DNO_ASM", "-DVINIX_NO_FALLOC", "-fcommon", "-fno-stack-protector",
              "-ffunction-sections", "-fdata-sections", "-Wno-everything"]
    cxx = []
    if not args.host:
        versions = sorted((sysroot / "usr/lib/gcc/aarch64-alpine-linux-musl").glob("*"))
        if not versions or not (sysroot / "usr/lib/libc.a").is_file():
            parser.error("ARM64 musl sysroot missing; run scripts/build-userland-aarch64.sh")
        gcc = versions[-1]
        cpp = sysroot / "usr/include/c++" / gcc.name
        for path in (cpp / "vector", sysroot / "usr/lib/libstdc++.a"):
            if not path.is_file():
                parser.error(f"build input missing: {path}")
        common += ["--target=aarch64-linux-musl", f"--sysroot={sysroot}", f"--gcc-install-dir={gcc}"]
        linux_headers = args.linux_headers.resolve()
        if not (linux_headers / "linux/futex.h").is_file():
            parser.error("Linux headers missing; run scripts/build-userland-aarch64.sh")
        common += ["-idirafter", str(linux_headers)]
        cxx = ["-nostdinc++", f"-isystem{cpp}", f"-isystem{cpp / 'aarch64-alpine-linux-musl'}", f"-isystem{cpp / 'backward'}"]
    for path in (llvm / "clang", llvm / "clang++", llvm / "llvm-ar"):
        if not path.is_file():
            parser.error(f"build input missing: {path}")
    output.mkdir(parents=True, exist_ok=True)
    archive, source = output / "parallel-source.tar.gz", output / "source"
    fetch(archive)
    source_stamp = SOURCE_SHA256 + PATCH_VERSION
    stamp = source / ".vinix-source"
    if not stamp.is_file() or stamp.read_text() != source_stamp:
        temporary = Path(tempfile.mkdtemp(prefix="n64-source-", dir=output))
        try:
            unpack(archive, temporary)
            patch(temporary)
            (temporary / ".vinix-source").write_text(source_stamp)
            if source.exists():
                shutil.rmtree(source)
            temporary.replace(source)
        finally:
            if temporary.exists():
                shutil.rmtree(temporary)
    manifest = output / "manifest.mk"
    manifest.write_text("vinix-manifest:\n\t@echo C_SOURCES=$(SOURCES_C)\n\t@echo CXX_SOURCES=$(SOURCES_CXX)\n"
                        "\t@echo C_FLAGS=$(CFLAGS)\n\t@echo CXX_FLAGS=$(CXXFLAGS)\n")
    command = ["make", "--no-print-directory", "-s", "-f", "Makefile", "-f", str(manifest), "vinix-manifest",
               "platform=unix", "WITH_DYNAREC=", "HAVE_OPENGL=0", "HAVE_THR_AL=1", "HAVE_PARALLEL=0",
               "HAVE_PARALLEL_RSP=0", "HAVE_LTCG=0", "STATIC_LINKING=0", "UNAME=Linux", "ARCH=aarch64",
               "CPUOPTS=-O2", f"GIT_VERSION={REVISION[:7]}", f"CC={llvm / 'clang'}"]
    lines = subprocess.check_output(command, cwd=source).decode().splitlines()
    values = dict(line.split("=", 1) for line in lines if "=" in line)
    files = [(source / name, False) for name in values["C_SOURCES"].split()]
    files += [(source / name, True) for name in values["CXX_SOURCES"].split()]
    files += [(SUPPORT / "bridge.c", False)]
    zlib_archive, zlib_source = output / "zlib-source.tar.gz", output / "zlib-source"
    fetch(zlib_archive, ZLIB_URL, ZLIB_SHA256)
    zlib_stamp = zlib_source / ".vinix-source"
    if not zlib_stamp.is_file() or zlib_stamp.read_text() != ZLIB_SHA256:
        temporary = Path(tempfile.mkdtemp(prefix="zlib-source-", dir=output))
        try:
            unpack(zlib_archive, temporary)
            (temporary / ".vinix-source").write_text(ZLIB_SHA256)
            if zlib_source.exists():
                shutil.rmtree(zlib_source)
            temporary.replace(zlib_source)
        finally:
            if temporary.exists():
                shutil.rmtree(temporary)
    zlib_files = ("adler32", "compress", "crc32", "deflate", "gzclose", "gzlib", "gzread", "gzwrite",
                  "inflate", "infback", "inftrees", "inffast", "trees", "uncompr", "zutil")
    files += [(zlib_source / (name + ".c"), False) for name in zlib_files]
    common += [f"-I{zlib_source}"]
    obj = output / "obj"
    obj.mkdir(exist_ok=True)
    compiler = subprocess.check_output([str(llvm / "clang"), "--version"]).decode()
    headers = SOURCE_SHA256 + PATCH_VERSION + ZLIB_SHA256 + sha256(SUPPORT / "bridge.h") + sha256(SUPPORT / "budget.h")
    libc = "host" if args.host else sha256(sysroot / "usr/lib/libc.a")

    def compile_one(item: tuple[Path, bool]) -> tuple[Path, bytes]:
        path, is_cpp = item
        relative = path.relative_to(source) if source in path.parents else Path(path.name)
        target = obj / (str(relative).replace("/", "_") + ".o")
        flags = shlex.split(values["CXX_FLAGS" if is_cpp else "C_FLAGS"])
        flags = [flag for flag in flags if flag != "-MMD" and not flag.startswith("-DGIT_VERSION=")]
        flags += [f'-DGIT_VERSION=" {REVISION[:7]}"']
        command = [str(llvm / ("clang++" if is_cpp else "clang"))] + flags + common
        if is_cpp:
            command += cxx
        if path.name in ("pure_interp.c", "rsp.c"):
            command += ["-include", str(SUPPORT / "budget.h")]
        command += ["-c", str(path), "-o", str(target)]
        fingerprint = json.dumps({"command": command, "source": sha256(path), "headers": headers,
                                  "compiler": compiler, "libc": libc}, sort_keys=True)
        stamp = target.with_suffix(".stamp")
        if target.exists() and stamp.exists() and stamp.read_text() == fingerprint:
            return target, b""
        process = subprocess.run(command, cwd=source, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        if process.returncode:
            raise RuntimeError(f"compile failed: {path}\n{process.stdout.decode(errors='replace')}")
        stamp.write_text(fingerprint)
        return target, process.stdout

    log = output / "core-build.log"
    try:
        with ThreadPoolExecutor(max_workers=args.jobs) as pool:
            results = list(pool.map(compile_one, files))
    except Exception as error:
        log.write_text(str(error))
        raise
    log.write_bytes(b"".join(data for _, data in results))
    library = output / "libvinix_n64.a"
    temporary = output / "libvinix_n64.new.a"
    temporary.unlink(missing_ok=True)
    subprocess.run([str(llvm / "llvm-ar"), "rcs", str(temporary)] + [str(path) for path, _ in results], check=True)
    temporary.replace(library)
    notices = output / "staging/usr/share/licenses/vinix-n64"
    notices.mkdir(parents=True, exist_ok=True)
    for name in ("README.md", "THIRD-PARTY-NOTICES", "GPL-2.0", "MAME-LICENSE", "CXD4-CC0", "ZLIB-LICENSE"):
        shutil.copyfile(SUPPORT / name, notices / name)
    corresponding = output / "staging/usr/share/vinix/n64/source"
    if corresponding.exists():
        shutil.rmtree(corresponding)
    corresponding.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(archive, corresponding / archive.name)
    shutil.copyfile(zlib_archive, corresponding / zlib_archive.name)
    for directory, relative in ((SUPPORT, "build-support/n64"),
                                (ROOT / "games/n64", "games/n64"),
                                (ROOT / "build-support/n64-homebrew", "build-support/n64-homebrew")):
        if directory.exists():
            shutil.copytree(directory, corresponding / relative, dirs_exist_ok=True,
                            ignore=shutil.ignore_patterns("__pycache__", "*.pyc"))
    for name in ("build-n64-aarch64.sh", "build-support/find-v.sh", "build-support/aarch64-cc-shim"):
        relative = Path(name) if name.startswith("build-support/") else Path("scripts") / name
        original = ROOT / relative
        if original.is_dir():
            shutil.copytree(original, corresponding / relative, dirs_exist_ok=True)
        elif original.exists():
            destination = corresponding / relative
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(original, destination)
    print(f"Built paraLLEl-N64 {REVISION[:7]} (pure CPU/LLE RSP/synchronous Angrylion): {library}")


if __name__ == "__main__":
    main()
