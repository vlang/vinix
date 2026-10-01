#!/usr/bin/env python3
"""Build one ARM64/musl dhewm3 binary for Vinix and the Linux comparison."""
from __future__ import annotations

import concurrent.futures
import hashlib
import os
from pathlib import Path
import shutil
import subprocess
import tarfile

ROOT = Path(__file__).resolve().parents[2]
BUILD = Path(os.environ.get("VINIX_DHEWM3_BUILD_DIR", ROOT / "build-aarch64-dhewm3")).resolve()
X11 = Path(os.environ.get("VINIX_X11_BUILD_DIR", ROOT / "build-aarch64-x11")).resolve()
TAG = "1.5.5"
COMMIT = "455b88e8dff2be822f08eb498f51b383e851fa38"
MIRROR = "https://dl-cdn.alpinelinux.org/alpine/v3.21"
DEMO_URL = "https://files.holarse-linuxgaming.de/native/Spiele/Doom%203/Demo/doom3-linux-1.1.1286-demo.x86.run"
DEMO_MD5 = "70c2c63ef1190158f1ebd6c255b22d8e"


def download(url: str, path: Path) -> None:
    if path.is_file() and path.stat().st_size:
        return
    temp = path.with_suffix(path.suffix + ".part")
    subprocess.run(["curl", "-fL", "--retry", "3", "-o", str(temp), url], check=True)
    temp.replace(path)


def main() -> None:
    downloads = BUILD / "downloads"
    sysroot = BUILD / "sysroot"
    runtime = BUILD / "runtime"
    stage = BUILD / "staging"
    if runtime.exists():
        shutil.rmtree(runtime)
    for path in (downloads, sysroot, runtime):
        path.mkdir(parents=True, exist_ok=True)
    source = BUILD / "source"
    if not source.exists():
        subprocess.run(["git", "clone", "--depth", "1", "--branch", TAG,
                        "https://github.com/dhewm/dhewm3.git", str(source)], check=True)
    if subprocess.check_output(["git", "-C", str(source), "rev-parse", "HEAD"], text=True).strip() != COMMIT:
        raise SystemExit("dhewm3 source is not the pinned 1.5.5 commit")
    if not (X11 / "sysroot/usr/include/GL/gl.h").is_file():
        raise SystemExit("Build the X11 layer first with build-x11-aarch64.sh")
    command = ["python3", str(ROOT / "build-support/alpine-resolve.py")]
    for repo in ("main", "community"):
        archive = downloads / f"{repo}_APKINDEX.tar.gz"
        download(f"{MIRROR}/{repo}/aarch64/APKINDEX.tar.gz", archive)
        index = downloads / f"{repo}_APKINDEX"
        with tarfile.open(archive, "r:gz") as tar:
            index.write_bytes(tar.extractfile("APKINDEX").read())
        command += ["--index", repo, str(index)]
    # The X11 staging layer expects these small dependencies from userland.
    # In particular, LLVM's libxml2 needs liblzma when dlopen loads swrast.
    command += ["sdl2", "openal-soft-libs", "libcurl", "libstdc++", "libbsd",
                "xz-libs", "gmp", "libuuid", "libpciaccess", "wayland-libs-client"]
    packages = subprocess.check_output(command, text=True)
    (BUILD / "packages.tsv").write_text(packages)
    headers = []
    for repo, names in (("main", ("curl-dev",)), ("community", ("sdl2-dev", "openal-soft-dev"))):
        records = (downloads / f"{repo}_APKINDEX").read_text().split("\n\n")
        for name in names:
            record = next(r for r in records if f"P:{name}\n" in r + "\n")
            version = next(line[2:] for line in record.splitlines() if line.startswith("V:"))
            headers.append(f"{repo}\t{name}-{version}.apk")

    def fetch(line: str) -> Path:
        repo, filename = line.split()
        path = downloads / filename
        download(f"{MIRROR}/{repo}/aarch64/{filename}", path)
        return path

    with concurrent.futures.ThreadPoolExecutor(max_workers=6) as pool:
        archives = list(pool.map(fetch, packages.splitlines() + headers))
    for i, archive in enumerate(archives):
        subprocess.run(["tar", "--ignore-zeros", "-xzf", str(archive), "-C", str(sysroot)],
                       stderr=subprocess.DEVNULL, check=True)
        if i < len(packages.splitlines()):
            subprocess.run(["tar", "--ignore-zeros", "-xzf", str(archive), "-C", str(runtime)],
                           stderr=subprocess.DEVNULL, check=True)
    cmake = BUILD / "cmake"
    subprocess.run([
        "cmake", "-S", str(source / "neo"), "-B", str(cmake), "-G", "Ninja",
        "-DCMAKE_SYSTEM_NAME=Linux", "-DCMAKE_SYSTEM_PROCESSOR=aarch64",
        f"-DCMAKE_C_COMPILER={os.environ.get('VINIX_DHEWM3_CC', 'aarch64-linux-musl-gcc')}",
        f"-DCMAKE_CXX_COMPILER={os.environ.get('VINIX_DHEWM3_CXX', 'aarch64-linux-musl-g++')}",
        "-DCMAKE_BUILD_TYPE=Release", "-DD3XP=OFF", "-DREPRODUCIBLE_BUILD=ON",
        f"-DOPENAL_INCLUDE_DIR={sysroot}/usr/include",
        f"-DOPENAL_LIBRARY={sysroot}/usr/lib/libopenal.so",
        f"-DSDL2_INCLUDE_DIR={sysroot}/usr/include/SDL2",
        f"-DSDL2_LIBRARY={sysroot}/usr/lib/libSDL2.so",
        f"-DCURL_INCLUDE_DIR={sysroot}/usr/include",
        f"-DCURL_LIBRARY={sysroot}/usr/lib/libcurl.so",
        f"-DCMAKE_CXX_FLAGS=-I{X11}/sysroot/usr/include -g -fno-omit-frame-pointer",
        "-DCMAKE_EXE_LINKER_FLAGS=-Wl,--allow-shlib-undefined",
    ], check=True)
    subprocess.run(["cmake", "--build", str(cmake), "-j",
                    os.environ.get("VINIX_DHEWM3_JOBS", "8")], check=True)
    # This directory is generated output. Recreate the library directories so
    # a previous dependency closure cannot leave unused libraries in the image.
    for folder in ("lib", "usr/lib"):
        if (stage / folder).exists():
            shutil.rmtree(stage / folder)
    for path in (stage / "usr/bin", stage / "usr/lib/dhewm3", stage / "lib",
                 stage / "usr/share/games/dhewm3/demo"):
        path.mkdir(parents=True, exist_ok=True)
    shutil.copy2(cmake / "dhewm3", stage / "usr/bin/dhewm3")
    shutil.copy2(cmake / "base.so", stage / "usr/lib/dhewm3/base.so")
    shutil.copy2(ROOT / "build-support/dhewm3/run-dhewm3", stage / "usr/bin/run-dhewm3")
    gui = stage / "usr/share/games/dhewm3/demo/guis/map/loading.gui"
    gui.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(ROOT / "build-support/dhewm3/loading.gui", gui)
    # Include the full runtime closure; development archives and headers stay
    # in the sysroot. The X11 layer supplies Mesa and its matching LLVM.
    for folder in ("lib", "usr/lib"):
        for path in (runtime / folder).glob("*.so*"):
            dest = stage / folder / path.name
            dest.parent.mkdir(parents=True, exist_ok=True)
            if dest.exists() or dest.is_symlink():
                dest.unlink()
            if path.is_symlink():
                dest.symlink_to(os.readlink(path))
            else:
                shutil.copy2(path, dest)
    demo = stage / "usr/share/games/dhewm3/demo/demo00.pk4"
    if not demo.exists():
        installer = downloads / "doom3-linux-1.1.1286-demo.x86.run"
        download(DEMO_URL, installer)
        # Makeself's 373-line shell header precedes a gzip tar. Extract only
        # the data file, without executing the installer or its setup scripts.
        with installer.open("rb") as stream:
            for _ in range(373):
                stream.readline()
            with tarfile.open(fileobj=stream, mode="r|gz") as tar:
                for member in tar:
                    if member.name == "demo/demo00.pk4":
                        demo.write_bytes(tar.extractfile(member).read())
                        break
    if demo.stat().st_size != 483535485 or hashlib.md5(demo.read_bytes()).hexdigest() != DEMO_MD5:
        raise SystemExit("Doom 3 Linux demo checksum mismatch")
    (stage / "usr/share/games/dhewm3/SOURCES.txt").write_text(
        f"dhewm3 {TAG} {COMMIT}\n{DEMO_URL}\ndemo00.pk4 MD5 {DEMO_MD5}\n")
    print(f"Staged dhewm3 and verified demo: {stage}")


if __name__ == "__main__":
    main()
