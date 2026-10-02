#!/usr/bin/env python3
"""Check Dota's architecture and runtime isolation without running the game."""
import json
import os
from pathlib import Path
import struct
import subprocess
import tempfile
import unittest


LAUNCHER = Path(__file__).resolve().parents[2] / "build-support/dota2/run-dota2"


class LauncherTest(unittest.TestCase):
    def setUp(self):
        self.work = tempfile.TemporaryDirectory(prefix="vinix-dota2-test-")
        self.addCleanup(self.work.cleanup)
        self.base = Path(self.work.name).resolve()
        self.runtime = self.base / "glibc runtime"
        self.game_dir = self.base / "dota 2 beta"
        self.game_root = self.game_dir / "game"
        self.game = self.game_root / "bin/linuxsteamrt64/dota2"
        self.icd = self.runtime / "usr/share/vulkan/icd.d/lvp_icd.x86_64.json"
        for relative in (
            "lib64/ld-linux-x86-64.so.2",
            "usr/lib/x86_64-linux-gnu/libvulkan.so.1",
            "usr/lib/x86_64-linux-gnu/libvulkan_lvp.so",
            "usr/share/vulkan/icd.d/lvp_icd.x86_64.json",
        ):
            path = self.runtime / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text("fixture\n")
        for relative in ("dota/gameinfo.gi", "dota/pak01_dir.vpk", "core/pak01_dir.vpk"):
            path = self.game_root / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text("fixture\n")
        self.game.parent.mkdir(parents=True)
        header = bytearray(64)
        header[:7] = b"\x7fELF\x02\x01\x01"
        struct.pack_into("<HH", header, 16, 3, 62)
        self.game.write_bytes(header)
        self.game.chmod(0o755)
        self.output = self.base / "launch.json"
        self.emulator = self.base / "fake-qemu-x86_64"
        self.emulator.write_text(
            "#!/usr/bin/env python3\n"
            "import json, os, resource, sys\n"
            "with open(os.environ['VINIX_DOTA_TEST_LOG'], 'w') as stream:\n"
            "    json.dump({'args': sys.argv[1:], 'env': dict(os.environ), 'cwd': os.getcwd(),\n"
            "               'nofile': resource.getrlimit(resource.RLIMIT_NOFILE)[0],\n"
            "               'stack': resource.getrlimit(resource.RLIMIT_STACK)[0]}, stream)\n"
            "sys.exit(int(os.environ.get('VINIX_DOTA_TEST_STATUS', '0')))\n"
        )
        self.emulator.chmod(0o755)
        self.env = os.environ.copy()
        for key in (
            "VK_DRIVER_FILES", "VK_ICD_FILENAMES", "VK_LOADER_DRIVERS_SELECT",
            "QEMU_CPU", "VINIX_X86_64_PRELOAD", "VINIX_DOTA2_LD_LIBRARY_PATH",
            "VINIX_DOTA2_WIDTH", "VINIX_DOTA2_HEIGHT", "VINIX_X86_64_GUEST_BASE",
            "VINIX_DOTA2_ROOT", "SDL_VIDEO_DRIVER", "VINIX_DOTA_TEST_STATUS",
        ):
            self.env.pop(key, None)
        self.env.update(
            DISPLAY=":73",
            VINIX_DOTA2_DIR=str(self.game_dir),
            VINIX_STEAM_ROOT=str(self.runtime),
            VINIX_X86_64_EMULATOR=str(self.emulator),
            VINIX_DOTA_TEST_LOG=str(self.output),
        )

    def run_launcher(self, *arguments):
        result = subprocess.run(
            [str(LAUNCHER), *arguments], env=self.env,
            text=True, capture_output=True, check=False,
        )
        if result.returncode == 0 and self.output.exists():
            return json.loads(self.output.read_text())
        return result

    def assert_rejected(self, message):
        result = self.run_launcher()
        self.assertIsInstance(result, subprocess.CompletedProcess)
        self.assertEqual(result.returncode, 127)
        self.assertIn(message, result.stderr)
        self.assertFalse(self.output.exists(), "an invalid install reached the translator")

    def test_translator_isolated_and_arguments_preserved(self):
        # Poison inherited loader settings: none may reach native QEMU.
        self.env.update(
            LD_LIBRARY_PATH="/foreign/x86/libraries",
            LD_PRELOAD="/foreign/x86/preload.so",
            QEMU_LD_PREFIX="/unrelated/runtime",
            QEMU_SET_ENV="LD_LIBRARY_PATH=/unrelated/libraries",
            VINIX_X86_64_PRELOAD="/guest/only/preload.so",
        )
        launch = self.run_launcher("+map", "path with spaces", "-w", "960")
        libraries = (
            f"{self.game.parent}:{self.runtime}/usr/lib/x86_64-linux-gnu:"
            f"{self.runtime}/lib/x86_64-linux-gnu"
        )
        self.assertEqual(launch["args"], [
            "-B", "0x100000000", "-L", str(self.runtime),
            "-E", f"LD_LIBRARY_PATH={libraries}",
            "-E", "LD_PRELOAD=/guest/only/preload.so",
            str(self.game), "-windowed", "-w", "1280", "-h", "720",
            "+map", "path with spaces", "-w", "960",
        ])
        self.assertEqual(launch["cwd"], str(self.game_root))
        self.assertEqual(launch["nofile"], 2048)
        self.assertEqual(launch["stack"], 2048 * 1024)
        for key in ("LD_LIBRARY_PATH", "LD_PRELOAD", "QEMU_LD_PREFIX", "QEMU_SET_ENV"):
            self.assertNotIn(key, launch["env"])
        for key, value in {
            "VINIX_I386_ROOT": str(self.runtime),
            "VINIX_X86_64_ROOT": str(self.runtime),
            "VINIX_X86_MULTIARCH": "1", "VINIX_ALLOW_WX": "1",
            "QEMU_CPU": "Haswell", "SteamAppId": "570", "SteamGameId": "570",
            "ENABLE_PATHMATCH": "1", "SDL_VIDEO_DRIVER": "x11",
            "VK_ICD_FILENAMES": str(self.icd),
        }.items():
            self.assertEqual(launch["env"][key], value)

    def test_explicit_vulkan_selection_is_preserved(self):
        self.icd.unlink()
        for key in ("VK_DRIVER_FILES", "VK_ICD_FILENAMES", "VK_LOADER_DRIVERS_SELECT"):
            with self.subTest(key=key):
                self.env[key] = "/custom/driver selection"
                launch = self.run_launcher()
                self.assertEqual(launch["env"][key], self.env[key])
                if key != "VK_ICD_FILENAMES":
                    self.assertNotIn("VK_ICD_FILENAMES", launch["env"])
                del self.env[key]

    def test_explicit_empty_vulkan_selection_is_preserved(self):
        self.icd.unlink()
        self.env["VK_DRIVER_FILES"] = ""
        launch = self.run_launcher()
        self.assertEqual(launch["env"]["VK_DRIVER_FILES"], "")
        self.assertNotIn("VK_ICD_FILENAMES", launch["env"])

    def test_dedicated_runtime_override_takes_priority(self):
        self.env["VINIX_DOTA2_ROOT"] = str(self.runtime)
        self.env["VINIX_STEAM_ROOT"] = "/missing/steam/runtime"
        launch = self.run_launcher()
        self.assertEqual(launch["env"]["VINIX_X86_64_ROOT"], str(self.runtime))

    def test_missing_content_is_rejected(self):
        (self.game_root / "core/pak01_dir.vpk").unlink()
        self.assert_rejected("game content is missing")

    def test_wrong_architecture_is_rejected(self):
        self.game.write_bytes(b"MZ" + bytes(62))
        self.assert_rejected("Linux x86-64 ELF")

    def test_aarch64_elf_is_rejected(self):
        header = bytearray(self.game.read_bytes())
        struct.pack_into("<H", header, 18, 183)
        self.game.write_bytes(header)
        self.assert_rejected("Linux x86-64 ELF")

    def test_truncated_elf_is_rejected(self):
        self.game.write_bytes(self.game.read_bytes()[:20])
        self.assert_rejected("Linux x86-64 ELF")

    def test_missing_glibc_loader_is_rejected(self):
        (self.runtime / "lib64/ld-linux-x86-64.so.2").unlink()
        self.assert_rejected("x86-64 glibc loader is missing")

    def test_missing_software_vulkan_is_rejected(self):
        self.icd.unlink()
        self.assert_rejected("x86-64 Lavapipe ICD is missing")

    def test_emulator_exit_status_is_preserved(self):
        self.env["VINIX_DOTA_TEST_STATUS"] = "42"
        result = self.run_launcher()
        self.assertEqual(result.returncode, 42)


if __name__ == "__main__":
    unittest.main()
