#!/usr/bin/env python3

import importlib.util
import os
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "build-support" / "desktop-build-key.py"
SPEC = importlib.util.spec_from_file_location("desktop_build_key", SCRIPT)
assert SPEC is not None and SPEC.loader is not None
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


def write(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")


class DesktopBuildKeyTests(unittest.TestCase):
    def fixture(self, root: Path) -> tuple[Path, dict[str, str]]:
        v = root / "tools/v"
        write(v, "compiler\n")
        v.chmod(0o755)

        llvm = root / "tools/llvm"
        for name in ("clang", "llvm-strip"):
            tool = llvm / name
            write(tool, name + "\n")
            tool.chmod(0o755)
        for name in ("ld.lld", "host-clang", "ld64.lld"):
            tool = root / "tools" / name
            write(tool, name + "\n")
            tool.chmod(0o755)

        write(root / "desktop/main.v", "module main\n")
        write(root / "third_party/ui2/v.mod", "Module { name: 'ui2' }\n")
        write(root / "build-aarch64-x11/staging/usr/lib/libx.so", "one\n")
        write(root / "build-aarch64-x11/sysroot/usr/lib/Scrt1.o", "crt\n")
        write(root / "build-aarch64-userland/staging/usr/lib/libc.a", "libc\n")
        write(root / "build-support/init-aarch64/initramfs.tar", "base\n")
        write(root / "build-aarch64-minecraft/staging/usr/bin/minecraft", "game\n")

        env = dict(os.environ)
        env.update(
            {
                "LLVM_BIN": str(llvm),
                "LD_LLD": str(root / "tools/ld.lld"),
                "CLANG": str(root / "tools/host-clang"),
                "LD64_LLD": str(root / "tools/ld64.lld"),
                "VINIX_AARCH64_USERLAND_BUILD_DIR": str(
                    root / "build-aarch64-userland"
                ),
                "VINIX_X11_STAGING": str(root / "build-aarch64-x11/staging"),
                "VINIX_GPU_SYSROOT": str(root / "build-aarch64-x11/sysroot"),
            }
        )
        return v, env

    def test_source_content_change_invalidates(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            v, env = self.fixture(root)
            first = MODULE.compute_key(root, v, env)
            write(root / "desktop/main.v", "module main\nconst changed = true\n")
            self.assertNotEqual(first, MODULE.compute_key(root, v, env))

    def test_nested_x11_rewrite_invalidates_in_place(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            v, env = self.fixture(root)
            library = root / "build-aarch64-x11/staging/usr/lib/libx.so"
            first = MODULE.compute_key(root, v, env)
            old_stat = library.stat()
            write(library, "two\n")
            os.utime(library, ns=(old_stat.st_atime_ns, old_stat.st_mtime_ns))
            self.assertNotEqual(first, MODULE.compute_key(root, v, env))

    def test_replaced_layer_root_invalidates(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            v, env = self.fixture(root)
            staging = root / "build-aarch64-minecraft/staging"
            first = MODULE.compute_key(root, v, env)
            old = root / "old-staging"
            staging.rename(old)
            staging.mkdir(parents=True)
            write(staging / "usr/bin/minecraft", "game\n")
            self.assertNotEqual(first, MODULE.compute_key(root, v, env))

    def test_replaced_v_layer_invalidates(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            v, env = self.fixture(root)
            staging = root / "build-aarch64-v/staging"
            write(staging / "usr/bin/v", "first compiler\n")
            first = MODULE.compute_key(root, v, env)
            old = root / "old-v-staging"
            staging.rename(old)
            write(staging / "usr/bin/v", "second compiler\n")
            self.assertNotEqual(first, MODULE.compute_key(root, v, env))

    def test_guest_compatibility_module_change_invalidates(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            v, env = self.fixture(root)
            module = root / "compat/macos/macho/macho.v"
            write(module, "module macho\n")
            first = MODULE.compute_key(root, v, env)
            write(module, "module macho\nconst changed = true\n")
            self.assertNotEqual(first, MODULE.compute_key(root, v, env))

    def test_compiler_generation_invalidates(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            v, env = self.fixture(root)
            first = MODULE.compute_key(root, v, env)
            replacement = root / "tools/v-new"
            write(replacement, "compiler two\n")
            replacement.chmod(0o755)
            replacement.replace(v)
            self.assertNotEqual(first, MODULE.compute_key(root, v, env))


if __name__ == "__main__":
    unittest.main()
