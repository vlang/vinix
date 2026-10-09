#!/usr/bin/env python3
"""Run real iOS-targeted Mach-O instructions in an isolated Vinix ARM64 VM."""
from pathlib import Path
import argparse
import gzip
import importlib.util
import os
import shutil
import struct
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
FEATURES = (
    b"iOS PASS: Mach-O arithmetic and libSystem imports",
    b"iOS PASS: legacy dyld imports and image/TLS lifecycle",
    b"iOS PASS: native chained and legacy pointer tags",
    b"iOS PASS: native CoreFoundation conversion, data and collection ownership",
    b"iOS PASS: native framework constants match installed Apple libraries",
    b"iOS PASS: native accessibility metadata and weak container lifecycle",
    b"iOS PASS: native Objective-C reflection, replacement and dynamic classes",
    b"iOS PASS: native register-specific ARC calling conventions and ownership",
    b"iOS PASS: import audit reports missing dependencies without executing app code",
    b"iOS PASS: lazy function imports defer unsupported calls",
    b"iOS PASS: Darwin stdio, varargs and system queries",
    b"iOS PASS: native UIKit scene and application launch",
    b"iOS PASS: native file launch and scene URL ownership",
    b"iOS PASS: thread-safe ARC and autorelease pools",
    b"iOS PASS: native Mach VM aliases and mapping lifetime",
    b"iOS PASS: return status and unsupported imports",
    b"iOS PASS: universal executable selects ARM64",
    b"iOS PASS: ARM64e and malformed images rejected",
    b"iOS PASS: UIKit Mach-O 27 button/action cases",
    b"iOS PASS: UIKit resize, keyboard, 1000 updates and ARC teardown",
)


def prepare_images(fixtures: Path, destination: Path) -> None:
    original = (fixtures / "calculator").read_bytes()
    arm64e = bytearray(original)
    struct.pack_into("<I", arm64e, 8, 2)
    (destination / "calculator-arm64e").write_bytes(arm64e)
    (destination / "truncated").write_bytes(original[:31])
    second = (4096 + len(original) + 4095) & ~4095
    fat = bytearray(second + len(original))
    struct.pack_into(">II", fat, 0, 0xCAFEBABE, 2)
    struct.pack_into(">IIIII", fat, 8, 0x100000C, 2, 4096, len(arm64e), 12)
    struct.pack_into(">IIIII", fat, 28, 0x100000C, 0, second, len(original), 12)
    fat[4096:4096 + len(arm64e)] = arm64e
    fat[second:] = original
    (destination / "calculator-fat").write_bytes(fat)


def stage_game_asset(source: str, destination: str) -> None:
    # The host only archives these files; all game writes happen in guest RAM.
    # Share the verified assets until then, saving a 98 MB temporary copy.
    try:
        os.link(source, destination)
    except OSError:
        shutil.copy2(source, destination)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--no-build", action="store_true", help="reuse build/ios/staging/usr/bin/run-ios")
    parser.add_argument("--with-2048", action="store_true", help="also build and run pinned upstream iOS-2048")
    parser.add_argument("--with-cxx", action="store_true", help="also build and execute native iOS C++ ABI fixtures")
    parser.add_argument("--with-gles", action="store_true", help="run with the optional Mesa GLES backend and native graphics fixture")
    parser.add_argument("--with-ppsspp", action="store_true", help="probe native PPSSPP scene startup and report its unsupported API")
    parser.add_argument("--ppsspp-muted", action="store_true", help="test PPSSPP with its ordinary Sound/Enable=False preference")
    parser.add_argument("--ppsspp-cube", action="store_true", help="boot the pinned upstream PSP rotating-cube demo in the unchanged iOS app")
    parser.add_argument("--ppsspp-nzp", action="store_true", help="play the pinned NZ:P 3D PSP shooter in the unchanged iOS app")
    parser.add_argument("--ppsspp-gow", action="store_true", help="run Sony's God of War: Chains of Olympus PSP demo in the unchanged iOS app")
    parser.add_argument("--timeout", type=int, default=180)
    arguments = parser.parse_args()
    if arguments.timeout <= 0:
        parser.error("timeout must be positive")
    if arguments.with_ppsspp and not arguments.with_cxx:
        parser.error("--with-ppsspp requires --with-cxx for PPSSPP's native C++ runtime")
    if arguments.ppsspp_muted and not (arguments.with_ppsspp and arguments.with_gles):
        parser.error("--ppsspp-muted requires --with-ppsspp and --with-gles")
    if arguments.ppsspp_cube and not arguments.ppsspp_muted:
        parser.error("--ppsspp-cube requires --ppsspp-muted")
    if arguments.ppsspp_nzp and (not arguments.ppsspp_muted or arguments.ppsspp_cube):
        parser.error("--ppsspp-nzp requires --ppsspp-muted and cannot be combined with --ppsspp-cube")
    if arguments.ppsspp_gow and (not arguments.ppsspp_muted or arguments.ppsspp_cube or arguments.ppsspp_nzp):
        parser.error("--ppsspp-gow requires --ppsspp-muted and cannot be combined with another PSP game")
    build = Path(os.environ.get("VINIX_IOS_BUILD_DIR", ROOT / "build/ios"))
    if not arguments.no_build:
        subprocess.run(["bash", str(ROOT / "scripts/build-ios-aarch64.sh")]
            + (["--with-cxx"] if arguments.with_cxx else [])
            + (["--with-gles"] if arguments.with_gles else []), check=True)
    subprocess.run(["sh", str(ROOT / "tests/ios/build-fixture.sh"), str(build / "fixtures")], check=True)
    if arguments.with_cxx:
        subprocess.run(["bash", str(ROOT / "tests/ios/build-cxx-fixture.sh"), str(build / "fixtures")], check=True)
    if arguments.with_gles:
        subprocess.run(["bash", str(ROOT / "tests/ios/build-gles-fixture.sh"), str(build / "fixtures")], check=True)
    subprocess.run(["bash", str(ROOT / "examples/ios-calculator/build.sh")],
        env={**os.environ, "VINIX_IOS_CALCULATOR_BUILD_DIR": str(build / "objc")}, check=True)
    if arguments.with_2048:
        env = {**os.environ, "VINIX_IOS_2048_BUILD_DIR": str(build / "2048")}
        subprocess.run(["bash", str(ROOT / "examples/ios-2048/build.sh")], env=env, check=True)
        subprocess.run(["bash", str(ROOT / "tests/ios/build-2048-model.sh")], env=env, check=True)
    if arguments.with_ppsspp or arguments.with_gles:
        subprocess.run(["python3", str(ROOT / "examples/ios-ppsspp/download.py"),
            "--output", str(build / "ppsspp")], check=True)
    if arguments.ppsspp_cube:
        subprocess.run(["python3", str(ROOT / "examples/ios-ppsspp/download-cube.py"),
            "--output", str(build / "ppsspp/cube.pbp")], check=True)
    if arguments.ppsspp_nzp:
        subprocess.run(["python3", str(ROOT / "examples/ios-ppsspp/download-nzp.py"),
            "--output", str(build / "nzportable")], check=True)
    if arguments.ppsspp_gow:
        subprocess.run(["python3", str(ROOT / "examples/ios-ppsspp/download-gow.py"),
            "--output", str(build / "god-of-war")], check=True)
    runner_root = Path(os.environ.get("VINIX_VM_RUNNER_ROOT", ROOT))
    spec = importlib.util.spec_from_file_location("ios_vm", runner_root / "tests/realtime/run_vm.py")
    runner = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(runner)
    runner.PASS_MARKER = b"VINIX iOS GUEST: PASS"
    runner.FAIL_MARKERS = (b"iOS FAIL:", b"FATAL EXCEPTION", b"KERNEL PANIC")
    runner.FEATURE_MARKERS = FEATURES + ((
        b"iOS PASS: upstream 2048 eight model merge tests",
        b"iOS PASS: upstream 2048 launch, swipes, merges, timers and ARC teardown",
    ) if arguments.with_2048 else ())
    if arguments.with_ppsspp:
        runner.FEATURE_MARKERS += (b"iOS PASS: upstream PPSSPP native framebuffer and process lifecycle (muted)",) if arguments.ppsspp_muted else (b"iOS BLOCKED: upstream PPSSPP unsupported API reached at runtime",)
    if arguments.ppsspp_cube:
        runner.FEATURE_MARKERS += (b"iOS PASS: unchanged PPSSPP iOS binary executes PSP cube homebrew",)
    if arguments.ppsspp_nzp:
        runner.FEATURE_MARKERS += (b"iOS PASS: unchanged PPSSPP iOS binary plays NZP PSP shooter",)
    if arguments.ppsspp_gow:
        runner.FEATURE_MARKERS += (b"iOS PASS: unchanged PPSSPP iOS binary runs God of War PSP demo",)
    if arguments.with_cxx:
        runner.FEATURE_MARKERS += (b"iOS PASS: native C++ strings, streams, regex and lifetime",)
        runner.FEATURE_MARKERS += (b"iOS PASS: Objective-C image startup and C++ ivars",)
    if arguments.with_gles:
        runner.FEATURE_MARKERS += (b"iOS PASS: native OpenGL ES shader rendering and GLKView lifecycle",)
        runner.FEATURE_MARKERS += (b"iOS PASS: display links, main queue and desktop shared-surface presentation",)
        runner.FEATURE_MARKERS += (b"iOS PASS: native CoreText fonts and bitmap glyph rendering",)
        runner.FEATURE_MARKERS += (b"iOS PASS: native zlib and Mach-O callbacks",)
    with tempfile.TemporaryDirectory(prefix="vinix-ios-vm-") as directory:
        work = Path(directory)
        rootfs = work / "rootfs"
        for name in ("root", "sbin", "proc", "sys", "dev", "tmp", "opt/ios"):
            (rootfs / name).mkdir(parents=True)
        destination = rootfs / "opt/ios"
        (destination / "launch name#é%?.bin").write_bytes(b"native file launch fixture\n")
        shutil.copy2(build / "staging/usr/bin" / ("run-ios-gles" if arguments.with_gles else "run-ios"), destination / "run-ios")
        if arguments.with_gles:
            shutil.copytree(build / "staging/usr/lib/vinix/ios-gles", rootfs / "usr/lib/vinix/ios-gles", symlinks=True)
            shutil.copy2(build / "fixtures/gles", destination / "gles")
            shutil.copy2(build / "fixtures/gles-app", destination / "gles-app")
            shutil.copy2(build / "fixtures/compression", destination / "compression")
            shutil.copytree(build / "fixtures/TextFixture.app", destination / "TextFixture.app")
            shutil.copy2(build / "ppsspp/unpacked/Payload/PPSSPP.app/assets/Roboto_Condensed-Regular.ttf", destination / "TextFixture.app/font.ttf")
        for name in ("calculator", "calculator-legacy", "unsupported", "lifecycle", "pointer-tags", "pointer-tags-legacy", "core-foundation", "framework-constants", "accessibility", "objc-runtime", "arc-registers", "lazy", "stdio", "arc-threads", "mach-memory"):
            shutil.copy2(build / "fixtures" / name, destination / name)
        shutil.copytree(build / "fixtures/SceneFixture.app", destination / "SceneFixture.app")
        if arguments.with_cxx:
            shutil.copy2(build / "fixtures/cxx", destination / "cxx")
            shutil.copy2(build / "fixtures/startup", destination / "startup")
        shutil.copy2(build / "objc/Calculator.app/Calculator", destination / "UIKitCalculator")
        if arguments.with_2048:
            shutil.copytree(build / "2048/NumberTileGame.app", destination / "NumberTileGame.app")
            shutil.copy2(build / "2048/model-tests", destination / "model-tests")
        if arguments.with_ppsspp:
            if arguments.ppsspp_muted:
                installed = rootfs / "usr/share/vinix/ios/PPSSPP.app"
                shutil.copytree(build / "ppsspp/unpacked/Payload/PPSSPP.app", installed)
                (destination / "PPSSPP").symlink_to("/usr/share/vinix/ios/PPSSPP.app/PPSSPP")
                binary = rootfs / "usr/bin"
                binary.mkdir(parents=True)
                shutil.copy2(build / "staging/usr/bin/run-ios-gles", binary / "run-ios-gles")
                (binary / "vinix-ios-ppsspp").symlink_to("run-ios-gles")
                (destination / "ppsspp-muted").touch()
                if arguments.ppsspp_cube:
                    shutil.copy2(build / "ppsspp/cube.pbp", destination / "cube.pbp")
                    (destination / "ppsspp-cube").touch()
                if arguments.ppsspp_nzp:
                    game = destination / "ppsspp-documents/PSP/GAME/nzportable"
                    shutil.copytree(build / "nzportable/unpacked/nzportable", game, copy_function=stage_game_asset)
                    # Ordinary engine arguments/configuration expose the real
                    # player state without changing its executable or assets.
                    (game / "setup.ini").write_text("-condebug +developer 1 +exec vinix-input.cfg\n")
                    (game / "nzp/vinix-input.cfg").write_text('bind "SELECT" "edict 1; echo VINIX-NZP-STATE-DONE"\nbinddt "SELECT" ""\n')
                    (destination / "ppsspp-nzp").touch()
                if arguments.ppsspp_gow:
                    game = destination / "ppsspp-documents/PSP/GAME/UCUS98713"
                    shutil.copytree(build / "god-of-war/unpacked/PSP/GAME/UCUS98713", game, copy_function=stage_game_asset)
                    system = destination / "ppsspp-documents/PSP/SYSTEM"
                    system.mkdir(parents=True)
                    # Ordinary PPSSPP settings: software GLES does not need
                    # the iOS default's 2x internal render resolution.
                    (system / "ppsspp.ini").write_text("[Sound]\nEnable=False\n[Graphics]\nInternalResolution=1\n")
                    (destination / "ppsspp-gow").touch()
            else:
                shutil.copytree(build / "ppsspp/unpacked/Payload/PPSSPP.app", destination / "PPSSPP.app")
                (destination / "PPSSPP").symlink_to("PPSSPP.app/PPSSPP")
        prepare_images(build / "fixtures", destination)
        # Same small static musl sysroot used by the existing syscall tests.
        sysroot = Path(os.environ.get("VINIX_IOS_TEST_SYSROOT", ROOT / "build-aarch64-userland/sysroot"))
        subprocess.run([
            os.environ.get("CC", "clang"), "--target=aarch64-linux-musl", f"--sysroot={sysroot}",
            "-static", "-O2", "-fno-stack-protector", "-Wall", "-Wextra", "-Werror",
            str(ROOT / "tests/ios/guest.c"), str(ROOT / "tests/ios/uikit-guest.c"),
            str(ROOT / "tests/ios/gles-guest.c"), f"-L{sysroot / 'lib'}", "-fuse-ld=lld",
            "-o", str(work / "init"),
        ], check=True)
        archive = work / ("initramfs.tar.gz" if arguments.with_gles else "initramfs.tar")
        if arguments.with_gles:
            # LLVM/Mesa's dependency closure is large. Stream compression so a
            # disposable VM does not need two extra uncompressed copies.
            with gzip.open(archive, "wb", compresslevel=1) as compressed:
                with subprocess.Popen(["tar", "--format=ustar", "-cf", "-", "-C", str(rootfs), "."],
                        env={**os.environ, "COPYFILE_DISABLE": "1"}, stdout=subprocess.PIPE) as tar:
                    shutil.copyfileobj(tar.stdout, compressed)
                    if tar.wait():
                        raise RuntimeError("could not archive GLES guest root")
        else:
            subprocess.run(["tar", "--format=ustar", "-cf", str(archive),
                "-C", str(rootfs), "."], env={**os.environ, "COPYFILE_DISABLE": "1"}, check=True)
        # No kernel changes are needed. Reuse the existing kernel, and keep
        # every boot disk, package store and persistent volume disposable.
        os.environ["VINIX_QEMU_RT_NO_BUILD"] = "1"
        os.environ["VINIX_QEMU_HOST_SOURCE"] = "0"
        os.environ["VINIX_QEMU_CLIPBOARD"] = "0"
        os.environ["VINIX_QEMU_AUDIO"] = "off"
        os.environ["VINIX_QEMU_NETWORK"] = "0"
        return runner.run_vm(runner_root, work / "init", archive, work / "vm", arguments.timeout)


if __name__ == "__main__":
    raise SystemExit(main())
