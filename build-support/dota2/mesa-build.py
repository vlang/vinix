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


def digest(path: Path) -> str:
    result = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            result.update(block)
    return result.hexdigest()


def tool(name: str) -> str:
    value = shutil.which(name)
    if not value:
        raise SystemExit(f"missing build tool: {name}")
    return value


def load_resolver():
    spec = importlib.util.spec_from_file_location("vinix_debian_root", REPO / "build-support/debian-root.py")
    resolver = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = resolver
    spec.loader.exec_module(resolver)
    return resolver


def load_inputs(path: Path = SUPPORT / "inputs.json") -> dict:
    inputs = json.loads(path.read_text())
    files = [inputs.get("source", {}), inputs.get("debian_diff", {})]
    if (inputs.get("format") != 2 or not isinstance(inputs.get("debian_version"), str) or
            not inputs.get("mirror", "").startswith("https://") or
            any(not isinstance(f.get("filename"), str) or Path(f["filename"]).is_absolute() or
                ".." in Path(f["filename"]).parts or len(f.get("sha256", "")) != 64
                for f in files) or
            not isinstance(inputs.get("patches"), dict) or not inputs["patches"] or
            any("/" in name or len(value) != 64 for name, value in inputs["patches"].items()) or
            not isinstance(inputs.get("packages"), list)):
        raise SystemExit(f"invalid pinned Mesa inputs: {path}")
    return inputs


def llvm_bin() -> Path:
    # Homebrew's LLVM provides clang, lld and llvm-ar together on macOS.
    configured = os.environ.get("VINIX_DOTA2_LLVM_BIN")
    if configured:
        return Path(configured)
    homebrew = Path("/opt/homebrew/opt/llvm/bin")
    return homebrew if (homebrew / "clang").is_file() else Path(tool("clang")).parent


def base_identity(base: Path) -> str:
    # Lavapipe links against the base root's libraries. Their names, sizes and
    # link targets change with any package update; hashing all of them is slow.
    result = hashlib.sha256()
    for directory in ("lib/x86_64-linux-gnu", "usr/lib/x86_64-linux-gnu", "usr/lib/gcc/x86_64-linux-gnu"):
        root = base / directory
        if not root.is_dir():
            continue
        for entry in sorted(root.rglob("*")):
            relative = entry.relative_to(base).as_posix()
            if entry.is_symlink():
                result.update(f"{relative} -> {os.readlink(entry)}\n".encode())
            elif entry.is_file():
                result.update(f"{relative} {entry.stat().st_size}\n".encode())
    return result.hexdigest()


def logged(command: list[str], directory: Path, log: Path, environment=None) -> None:
    with log.open("w") as output:
        result = subprocess.run(command, cwd=directory, env=environment,
                                stdout=output, stderr=subprocess.STDOUT)
    if result.returncode:
        print("\n".join(log.read_text(errors="replace").splitlines()[-35:]), file=sys.stderr)
        raise SystemExit(f"Lavapipe build failed; see {log}")


def apply_patch(source: Path, patch: bytes, label: str) -> None:
    result = subprocess.run([tool("patch"), "-p1", "--batch", "--forward"], cwd=source, input=patch,
                            stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    if result.returncode:
        print(result.stdout.decode(errors="replace"), file=sys.stderr)
        raise SystemExit(f"patch does not apply to the pinned Mesa source: {label}")


def check_sources(source: Path, expected: dict, label: str) -> None:
    for relative, value in expected.items():
        path = source / relative
        if not path.is_file() or digest(path) != value:
            raise SystemExit(f"{label} Mesa source has an unexpected hash: {relative}")


def prepare_source(resolver, inputs: dict, downloads: Path, source: Path) -> None:
    archives = {}
    for key in ("source", "debian_diff"):
        pin = inputs[key]
        package = resolver.Package(key, inputs["debian_version"], "source", pin["filename"],
                                   pin["sha256"], 0, (), ())
        archives[key] = resolver.download(inputs["mirror"], package, downloads)
    pending = source.with_name(source.name + ".pending")
    if pending.exists():
        shutil.rmtree(pending)
    pending.mkdir(parents=True)
    subprocess.run([tool("tar"), "xzf", str(archives["source"]), "-C", str(pending),
                    "--strip-components=1"], check=True)
    apply_patch(pending, subprocess.check_output([tool("gzip"), "-dc", str(archives["debian_diff"])]),
                Path(inputs["debian_diff"]["filename"]).name)
    patches = pending / "debian/patches"
    series = [line.split()[0] for line in (patches / "series").read_text().splitlines()
              if line.strip() and not line.lstrip().startswith("#")]
    if series != list(inputs["debian_patches"]):
        raise SystemExit("Debian's Mesa patch series differs from the pinned series")
    for name in series:
        if digest(patches / name) != inputs["debian_patches"][name]:
            raise SystemExit(f"Debian Mesa patch has an unexpected hash: {name}")
        apply_patch(pending, (patches / name).read_bytes(), name)
    check_sources(pending, inputs["debian_source_sha256"], "Debian-patched")
    for name, expected in inputs["patches"].items():
        patch = SUPPORT / name
        if digest(patch) != expected:
            raise SystemExit(f"Lavapipe patch has an unexpected hash: {patch}")
        apply_patch(pending, patch.read_bytes(), name)
    check_sources(pending, inputs["patched_source_sha256"], "patched")
    if source.exists():
        shutil.rmtree(source)
    pending.rename(source)


def prepare_sysroot(resolver, inputs: dict, base: Path, downloads: Path, sysroot: Path) -> None:
    pending = sysroot.with_name(sysroot.name + ".pending")
    if pending.exists():
        shutil.rmtree(pending)
    if sys.platform == "darwin":
        subprocess.run(["/bin/cp", "-cRp", str(base), str(pending)], check=True)
    else:
        shutil.copytree(base, pending, symlinks=True)
    for row in inputs["packages"]:
        package = resolver.Package(row["name"], row["version"], row["architecture"],
                                   row["filename"], row["sha256"], row["size"], (), ())
        resolver.extract_deb(resolver.download(inputs["mirror"], package, downloads), pending)
    if sysroot.exists():
        shutil.rmtree(sysroot)
    pending.rename(sysroot)


def write_configuration(work: Path, inputs: dict, tools: Path) -> Path:
    sysroot = work / "sysroot"
    config = work / "llvm-config"
    config.write_text(LLVM_CONFIG % {"version": inputs["llvm_version"]})
    config.chmod(0o755)
    gcc = sorted((sysroot / "usr/lib/gcc/x86_64-linux-gnu").iterdir())[-1]
    flags = ["--target=x86_64-linux-gnu", f"--sysroot={sysroot}", f"--gcc-install-dir={gcc}"]
    links = ["-fuse-ld=lld", f"-Wl,-rpath-link,{sysroot / 'usr/lib/x86_64-linux-gnu'}",
             f"-Wl,-rpath-link,{sysroot / 'lib/x86_64-linux-gnu'}"]
    cross = work / "cross.ini"
    cross.write_text(f"""[binaries]
c = {[str(tools / 'clang'), *flags]!r}
cpp = {[str(tools / 'clang++'), *flags]!r}
ar = '{tools / 'llvm-ar'}'
strip = '{tools / 'llvm-strip'}'
pkg-config = '{tool('pkg-config')}'
llvm-config = '{config}'
[host_machine]
system = 'linux'
cpu_family = 'x86_64'
cpu = 'x86_64'
endian = 'little'
[properties]
needs_exe_wrapper = true
sys_root = '{sysroot}'
pkg_config_libdir = ['{sysroot / 'usr/lib/x86_64-linux-gnu/pkgconfig'}', '{sysroot / 'usr/share/pkgconfig'}']
[built-in options]
c_link_args = {links!r}
cpp_link_args = {links!r}
""")
    return cross


def verify_library(path: Path, base: Path, tools: Path) -> None:
    header = path.read_bytes()[:20]
    if header[:6] != b"\x7fELF\x02\x01" or header[16:20] != b"\x03\x00\x3e\x00":
        raise SystemExit(f"Lavapipe must be an x86-64 shared library: {path}")
    dynamic = subprocess.check_output([str(tools / "llvm-readelf"), "-d", "--dyn-syms", str(path)], text=True)
    if "vk_icdNegotiateLoaderICDInterfaceVersion" not in dynamic:
        raise SystemExit("built Lavapipe lacks the Vulkan ICD entry point")
    for name in re.findall(r"\(NEEDED\).*\[([^]]+)\]", dynamic):
        if not any((base / directory / name).exists()
                   for directory in ("lib/x86_64-linux-gnu", "usr/lib/x86_64-linux-gnu")):
            raise SystemExit(f"built Lavapipe needs a library the runtime lacks: {name}")


def build(base: Path, work: Path, jobs: int = os.cpu_count() or 1, refresh: bool = False) -> Path:
    """Return a patched libvulkan_lvp.so linked against base's runtime libraries."""
    base, work = base.resolve(), work.resolve()
    if work == base or work in base.parents or base in work.parents:
        raise SystemExit("the Lavapipe work directory must be separate from its base root")
    inputs = load_inputs()
    llvm = base / "usr/lib/x86_64-linux-gnu/libLLVM-15.so.1"
    if not llvm.is_file() or digest(llvm) != inputs["llvm_runtime_sha256"]:
        raise SystemExit(f"the base root lacks the pinned LLVM 15 runtime: {llvm}")
    tools = llvm_bin()
    for name in ("clang", "clang++", "llvm-ar", "llvm-strip", "llvm-readelf"):
        if not (tools / name).is_file():
            raise SystemExit(f"missing LLVM tool {name} in {tools}; set VINIX_DOTA2_LLVM_BIN")
    generation = hashlib.sha256(json.dumps({
        "inputs": inputs, "builder": digest(Path(__file__)),
        "patches": {name: digest(SUPPORT / name) for name in inputs["patches"]},
        "options": MESON_OPTIONS, "python_packages": PYTHON_PACKAGES,
        "clang": subprocess.check_output([str(tools / "clang"), "--version"], text=True),
        "base": base_identity(base),
    }, sort_keys=True).encode()).hexdigest()
    output = work / "out/libvulkan_lvp.so"
    marker = work / "out/generation"
    if (not refresh and output.is_file() and marker.is_file() and
            marker.read_text().strip() == f"{generation} {digest(output)}"):
        return output
    resolver = load_resolver()
    downloads = work / "downloads"
    downloads.mkdir(parents=True, exist_ok=True)
    source, objects = work / "source", work / "obj"
    stamp = work / ".prepared-generation"
    if refresh or not stamp.is_file() or stamp.read_text().strip() != generation:
        print("Preparing pinned Mesa source and amd64 development libraries", flush=True)
        prepare_source(resolver, inputs, downloads, source)
        prepare_sysroot(resolver, inputs, base, downloads, work / "sysroot")
        if objects.exists():
            shutil.rmtree(objects)
        stamp.write_text(generation + "\n")
    check_sources(source, inputs["patched_source_sha256"], "prepared")
    venv = work / "host-venv"
    python = venv / "bin/python3"
    if not python.exists():
        subprocess.run([sys.executable, "-m", "venv", str(venv)], check=True)
    package_stamp = venv / ".dota2-packages"
    if not package_stamp.is_file() or package_stamp.read_text().splitlines() != list(PYTHON_PACKAGES):
        subprocess.run([str(python), "-m", "pip", "install", "--quiet", *PYTHON_PACKAGES], check=True)
        package_stamp.write_text("\n".join(PYTHON_PACKAGES) + "\n")
    # Mesa's generators run "python3"; the venv supplies Mako to them.
    environment = {**os.environ, "PATH": f"{venv / 'bin'}:{os.environ['PATH']}"}
    if not (objects / "build.ninja").is_file():
        print("Configuring amd64 Lavapipe", flush=True)
        cross = write_configuration(work, inputs, tools)
        logged([str(venv / "bin/meson"), "setup", str(objects), str(source),
                "--cross-file", str(cross), *MESON_OPTIONS], work, work / "configure.log", environment)
    print("Building amd64 Lavapipe", flush=True)
    logged([tool("ninja"), "-C", str(objects), "-j", str(jobs), TARGET], work, work / "build.log", environment)
    built = objects / TARGET
    verify_library(built, base, tools)
    output.parent.mkdir(exist_ok=True)
    partial = output.with_name(".libvulkan_lvp.so.partial")
    shutil.copy2(built, partial)
    partial.replace(output)
    marker.write_text(f"{generation} {digest(output)}\n")
    return output


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
