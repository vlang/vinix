#!/usr/bin/env python3
"""Cross-build OpenGothic for ARM64/musl and stage an isolated Vulkan runtime."""
from __future__ import annotations

import argparse
import concurrent.futures
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tarfile

ROOT = Path(__file__).resolve().parents[2]
COMMIT = "26b7159230834780fc6a8fc9aa0d060863cb443f"
HEADERS = "3c65a01745e4a1134d32b9c2c456472212dba16d"
REWISE = "c3d3b68903a90ec53ff7b0a4ae704adc6302814b"
MIRROR = "https://dl-cdn.alpinelinux.org/alpine/v3.21"
DEMO_URL = "https://www.worldofgothic.de/download.php?id=122"
DEMO_SHA256 = "380d2ae52e4e2eac3beea55e729eb7eb2ea04ffa13521cd22e9fe22fcbe96353"
# Applied to the pinned Tempest renderer in this order; see README.md.
PATCHES = ("active-descriptors.patch", "sampled-attachments.patch")


def run(*args, **kwargs):
    subprocess.run([str(a) for a in args], check=True, **kwargs)


def apply_patch(source: Path, name: str):
    patch = ROOT / "build-support/opengothic" / name
    clean = subprocess.run(["git", "-C", str(source), "apply", "--check", str(patch)], capture_output=True)
    if clean.returncode == 0:
        run("git", "-C", source, "apply", patch)
    else:
        # Already applied by an earlier build: anything else is an error.
        run("git", "-C", source, "apply", "--reverse", "--check", patch)


def download(url: str, path: Path):
    if path.is_file() and path.stat().st_size:
        return
    temp = path.with_suffix(path.suffix + ".part")
    run("curl", "-fL", "--retry", "3", "-o", temp, url)
    temp.replace(path)


def checkout(url: str, path: Path, commit: str, submodules=False):
    if not path.exists():
        run("git", "clone", "--no-checkout", "--filter=blob:none", url, path)
        run("git", "-C", path, "checkout", "--detach", commit)
    actual = subprocess.check_output(["git", "-C", str(path), "rev-parse", "HEAD"], text=True).strip()
    if actual != commit:
        raise SystemExit(f"Expected {commit} in {path}, found {actual}")
    if submodules:
        run("git", "-C", path, "submodule", "update", "--init", "--recursive")


def copy_file(source: Path, target: Path):
    target.parent.mkdir(parents=True, exist_ok=True)
    if target.exists() or target.is_symlink():
        target.unlink()
    if source.is_symlink():
        target.symlink_to(os.readlink(source))
    else:
        shutil.copy2(source, target)


def stage_game(installation: Path, game: Path):
    """Copy the directories OpenGothic reads from a Gothic II installation."""
    # Windows installations differ in case (System, system, _Work); the
    # launcher looks for Data and _work/Data exactly.
    found = {entry.name.lower(): entry for entry in installation.iterdir() if entry.is_dir()}
    work = found.get("_work")
    inner = {entry.name.lower(): entry for entry in work.iterdir()} if work else {}
    if "data" not in found or "data" not in inner:
        raise SystemExit(f"No Gothic II installation in {installation}: it needs Data and _work/Data")
    if game.exists():
        shutil.rmtree(game)
    shutil.copytree(found["data"], game / "Data")
    for entry in work.iterdir():
        target = game / "_work" / ("Data" if entry.name.lower() == "data" else entry.name)
        if entry.is_dir():
            shutil.copytree(entry, target)
        else:
            copy_file(entry, target)
    if "system" in found:
        shutil.copytree(found["system"], game / "System")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    data = parser.add_mutually_exclusive_group()
    data.add_argument("--demo", action="store_true", help="download and extract the original public Gothic II demo")
    data.add_argument("--game", type=Path, metavar="DIR", help="stage the Gothic II installation in DIR")
    args = parser.parse_args()
    if args.game and not args.game.is_dir():
        raise SystemExit(f"Not a directory: {args.game}")
    build = Path(os.environ.get("VINIX_OPENGOTHIC_BUILD_DIR", ROOT / "build/opengothic")).resolve()
    downloads = build / "downloads"
    sysroot = build / "sysroot"
    staging = build / "staging"
    for path in (downloads, sysroot, staging):
        path.mkdir(parents=True, exist_ok=True)
    source = build / "source"
    headers = build / "vulkan-headers"
    checkout("https://github.com/Try/OpenGothic.git", source, COMMIT, True)
    checkout("https://github.com/KhronosGroup/Vulkan-Headers.git", headers, HEADERS)
    tempest = source / "lib/Tempest"
    for name in PATCHES:
        apply_patch(tempest, name)
    apply_patch(source, "worker-count.patch")

    command = ["python3", str(ROOT / "build-support/alpine-resolve.py")]
    indexes = {}
    for repo in ("main", "community"):
        archive = downloads / f"{repo}-index.tar.gz"
        download(f"{MIRROR}/{repo}/aarch64/APKINDEX.tar.gz", archive)
        index = downloads / f"{repo}-index"
        with tarfile.open(archive) as tar:
            index.write_bytes(tar.extractfile("APKINDEX").read())
        indexes[repo] = index.read_text().split("\n\n")
        command += ["--index", repo, str(index)]
    command += ["mesa-vulkan-swrast", "vulkan-loader", "libx11", "libxcursor", "libstdc++"]
    packages = subprocess.check_output(command, text=True).splitlines()
    (build / "packages.tsv").write_text("\n".join(packages) + "\n")
    development = []
    for name in ("vulkan-loader-dev", "libx11-dev", "libxcursor-dev", "libxfixes-dev", "libxrender-dev", "xorgproto"):
        for repo, records in indexes.items():
            record = next((r for r in records if f"P:{name}\n" in r + "\n"), None)
            if record:
                version = next(line[2:] for line in record.splitlines() if line.startswith("V:"))
                development.append(f"{repo}\t{name}-{version}.apk")
                break
        else:
            raise SystemExit(f"Development package not found: {name}")

    def fetch(line):
        repo, filename = line.split()
        path = downloads / filename
        download(f"{MIRROR}/{repo}/aarch64/{filename}", path)
        return path

    with concurrent.futures.ThreadPoolExecutor(max_workers=6) as pool:
        archives = list(pool.map(fetch, packages + development))
    runtime = build / "runtime"
    if runtime.exists():
        shutil.rmtree(runtime)
    runtime.mkdir()
    for i, archive in enumerate(archives):
        run("tar", "--ignore-zeros", "-xzf", archive, "-C", sysroot, stderr=subprocess.DEVNULL)
        if i < len(packages):
            run("tar", "--ignore-zeros", "-xzf", archive, "-C", runtime, stderr=subprocess.DEVNULL)

    # musl has no execinfo API. Reuse Vinix's GCC-unwinder implementation,
    # compiled separately from OpenGothic's C++-only warning flags.
    cc = os.environ.get("VINIX_OPENGOTHIC_CC", "aarch64-linux-musl-gcc")
    cxx = os.environ.get("VINIX_OPENGOTHIC_CXX", "aarch64-linux-musl-g++")
    run("python3", ROOT / "build-support/compile-v-module.py", ROOT / "desktop/execinfocore",
        build / "execinfo.c", "--arch", "arm64", "--header", sysroot / "usr/include/execinfo.h")
    run(cc, "-D_GNU_SOURCE", "-D__V_HAVE_EXECINFO_H=1", "-O2", "-c", build / "execinfo.c",
        "-o", build / "execinfo.o")
    run(os.environ.get("VINIX_OPENGOTHIC_AR", "aarch64-linux-musl-ar"), "rcs", build / "libexecinfo.a", build / "execinfo.o")
    cmakefile = source / "CMakeLists.txt"
    text = cmakefile.read_text()
    marker = "# Vinix execinfo compatibility"
    if marker in text:
        text = text[:text.index(marker)].rstrip() + "\n"
    text += f'\n{marker}\ntarget_link_libraries(OpenGothic "{build / "libexecinfo.a"}")\n'
    cmakefile.write_text(text)
    validator = os.environ.get("GLSLANGVALIDATOR") or shutil.which("glslangValidator") or shutil.which("glslang")
    if not validator:
        raise SystemExit("Install glslang or set GLSLANGVALIDATOR to its host executable")
    cmake = build / "cmake"
    run("cmake", "-S", source, "-B", cmake, "-G", "Ninja",
        "-DCMAKE_SYSTEM_NAME=Linux", "-DCMAKE_SYSTEM_PROCESSOR=aarch64",
        f"-DCMAKE_C_COMPILER={cc}", f"-DCMAKE_CXX_COMPILER={cxx}",
        "-DCMAKE_BUILD_TYPE=Release", "-DCMAKE_POLICY_VERSION_MINIMUM=3.5",
        f"-DGLSLANGVALIDATOR={validator}",
        f"-DCMAKE_C_FLAGS=-I{sysroot}/usr/include",
        f"-DCMAKE_CXX_FLAGS=-I{sysroot}/usr/include -I{headers}/include -fno-omit-frame-pointer -Wno-error=stringop-overflow",
        f"-DCMAKE_EXE_LINKER_FLAGS=-L{sysroot}/usr/lib -Wl,--allow-shlib-undefined",
        "-DALSOFT_BACKEND_ALSA=OFF", "-DALSOFT_BACKEND_PULSEAUDIO=OFF",
        "-DALSOFT_BACKEND_JACK=OFF", "-DALSOFT_BACKEND_PIPEWIRE=OFF", "-DALSOFT_BACKEND_OSS=OFF")
    run("cmake", "--build", cmake, "--target", "Gothic2Notr", "-j", os.environ.get("VINIX_OPENGOTHIC_JOBS", "8"))
    private = staging / "opt/opengothic"
    if (private / "lib").exists():
        shutil.rmtree(private / "lib")
    for directory in ("lib", "usr/lib"):
        for path in (runtime / directory).glob("*.so*"):
            copy_file(path, private / "lib" / path.name)
    copy_file(cmake / "opengothic/Gothic2Notr", private / "Gothic2Notr")
    copy_file(ROOT / "build-support/opengothic/run-opengothic", staging / "usr/bin/run-opengothic")
    (staging / "usr/bin/run-opengothic").chmod(0o755)
    (private / "icd").mkdir(exist_ok=True)
    icd = json.loads((runtime / "usr/share/vulkan/icd.d/lvp_icd.aarch64.json").read_text())
    icd["ICD"]["library_path"] = "/opt/opengothic/lib/libvulkan_lvp.so"
    (private / "icd/lvp.json").write_text(json.dumps(icd, indent=2) + "\n")
    if args.demo:
        installer = downloads / "Gothic2_Demo_DE.exe"
        download(DEMO_URL, installer)
        if hashlib.sha256(installer.read_bytes()).hexdigest() != DEMO_SHA256:
            raise SystemExit("Gothic II demo checksum mismatch")
        rewise = build / "rewise"
        checkout("https://codeberg.org/CYBERDEV/REWise.git", rewise, REWISE)
        run("make", "-C", rewise, f"CC={os.environ.get('CC', 'cc')}", "CFLAGS=-O2 -Wall -lz")
        extracted = build / "demo"
        extracted.mkdir(exist_ok=True)
        run(rewise / "rewise", "-x", extracted, installer)
        game = staging / "usr/share/games/gothic2"
        if game.exists():
            shutil.rmtree(game)
        shutil.copytree(extracted / "MAINDIR", game)
        (game / ".vinix-demo").write_text(DEMO_SHA256 + "\n")
    elif args.game:
        stage_game(args.game.resolve(), staging / "usr/share/games/gothic2")
    (private / "SOURCES.txt").write_text(f"OpenGothic {COMMIT}\nVulkan-Headers {HEADERS}\nMesa 24.2.8 / LLVM 19.1.4 (Alpine 3.21)\n")
    print(f"Staged OpenGothic: {staging}", flush=True)


if __name__ == "__main__":
    main()
