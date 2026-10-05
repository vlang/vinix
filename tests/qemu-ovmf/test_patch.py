"""Exercise firmware patching and setup without downloading or building edk2."""

import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]
BUILDER = ROOT / "build-qemu-ovmf-aarch64.sh"
PATCH = Path("patches/edk2/qemu-ramfb-2048x1536.patch")
DRIVER = Path("OvmfPkg/QemuRamfbDxe/QemuRamfb.c")
BUILD_SENTINEL = 73

# Mode table from edk2-stable202511. The upstream file uses CRLF; generate
# both byte representations explicitly so the host's newline rules do not
# conceal a failure to apply our LF patch to a fresh upstream checkout.
UPSTREAM = b"""STATIC EFI_GRAPHICS_OUTPUT_MODE_INFORMATION  mQemuRamfbModeInfo[] = {
  {
    0,    // Version
    640,  // HorizontalResolution
    480,  // VerticalResolution
  },{
    0,    // Version
    800,  // HorizontalResolution
    600,  // VerticalResolution
  },{
    0,    // Version
    1024, // HorizontalResolution
    768,  // VerticalResolution
  }
};

STATIC EFI_GRAPHICS_OUTPUT_PROTOCOL_MODE  mQemuRamfbMode = {
  ARRAY_SIZE (mQemuRamfbModeInfo),                // MaxMode
  0,                                              // Mode
  mQemuRamfbModeInfo,                             // Info
  sizeof (EFI_GRAPHICS_OUTPUT_MODE_INFORMATION),  // SizeOfInfo
};
"""


@unittest.skipUnless(shutil.which("git"), "git is not installed")
class FirmwarePatchTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="vinix-ovmf-patch.")
        self.addCleanup(self.temporary.cleanup)
        self.checkout = Path(self.temporary.name) / "vinix"
        self.checkout.mkdir()
        shutil.copyfile(BUILDER, self.checkout / BUILDER.name)
        (self.checkout / PATCH.parent).mkdir(parents=True)
        shutil.copyfile(ROOT / PATCH, self.checkout / PATCH)

        self.source = self.checkout / "boot-image/edk2-edk2-stable202511"
        (self.source / DRIVER.parent).mkdir(parents=True)
        (self.source / "BaseTools").mkdir()
        self.driver = self.source / DRIVER
        subprocess.run(
            ["git", "init", "-q", str(self.source)], check=True, capture_output=True
        )

        commands = self.checkout / "test-bin"
        commands.mkdir()
        for name, body in {
            "make": f"echo 'test: reached BaseTools build'\nexit {BUILD_SENTINEL}\n",
            "clang": "exit 0\n",
            "llvm-ar": "exit 0\n",
            "sysctl": "echo 2\n",
            "nproc": "echo 2\n",
        }.items():
            executable = commands / name
            executable.write_text("#!/bin/sh\n" + body)
            executable.chmod(0o755)

        self.environment = os.environ.copy()
        self.environment.update(
            PATH=str(commands) + os.pathsep + os.environ.get("PATH", ""),
            VINIX_EDK2_SOURCE=str(self.source),
            GIT_CONFIG_GLOBAL=os.devnull,
            GIT_CONFIG_NOSYSTEM="1",
            LC_ALL="C",
        )

    def run_builder(self):
        return subprocess.run(
            ["bash", str(self.checkout / BUILDER.name)],
            cwd=self.checkout,
            env=self.environment,
            capture_output=True,
            text=True,
            timeout=10,
        )

    def assert_reached_build(self, result):
        self.assertEqual(
            result.returncode, BUILD_SENTINEL, result.stdout + result.stderr
        )
        self.assertIn("Building edk2 BaseTools", result.stdout)
        self.assertIn("test: reached BaseTools build", result.stdout)

    def assert_rejected(self, result):
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn("ERROR: cannot apply", result.stderr)
        self.assertIn("error: patch failed:", result.stderr)
        self.assertIn(str(DRIVER), result.stderr)
        self.assertNotIn("Building edk2 BaseTools", result.stdout)

    def prepare_setup(self, script):
        self.driver.write_bytes(UPSTREAM)
        (self.checkout / "test-bin/make").write_text("#!/bin/sh\nexit 0\n")
        (self.source / "edksetup.sh").write_text(script)
        for name in (
            "PYTHON_COMMAND", "WORKSPACE", "EDK_TOOLS_PATH", "PACKAGES_PATH", "CONF_PATH"
        ):
            self.environment.pop(name, None)

    def test_fresh_and_already_patched_checkouts(self):
        for newline in (b"\n", b"\r\n"):
            with self.subTest(newline=newline):
                self.driver.write_bytes(UPSTREAM.replace(b"\n", newline))
                self.assert_reached_build(self.run_builder())
                patched = self.driver.read_bytes()
                self.assertEqual(patched.count(b"2048, // HorizontalResolution"), 1)
                self.assertEqual(patched.count(b"1536, // VerticalResolution"), 1)

                rerun = self.run_builder()
                self.assert_reached_build(rerun)
                self.assertIn("patch is already applied", rerun.stdout)
                self.assertEqual(self.driver.read_bytes(), patched)

    def test_incomplete_mode_is_rejected(self):
        self.driver.write_bytes(UPSTREAM)
        self.assert_reached_build(self.run_builder())
        incomplete = self.driver.read_bytes().replace(
            b"1536, // VerticalResolution", b"1535, // VerticalResolution"
        )
        self.driver.write_bytes(incomplete)
        self.assert_rejected(self.run_builder())
        self.assertEqual(self.driver.read_bytes(), incomplete)

    def test_incompatible_source_reports_git_diagnostic(self):
        incompatible = UPSTREAM.replace(
            b"1024, // HorizontalResolution", b"1280, // HorizontalResolution"
        )
        self.driver.write_bytes(incompatible)
        self.assert_rejected(self.run_builder())
        self.assertEqual(self.driver.read_bytes(), incompatible)

    def test_setup_accepts_unset_variables_and_restores_strict_mode(self):
        # These optional-variable reads match edk2-stable202511's edksetup.sh
        # and BaseTools/BuildEnv. They run before the build command is defined.
        self.prepare_setup(f"""
SetupPythonCommand() {{
    if [ -n "$PYTHON_COMMAND" ]; then
        return 0
    fi
    export PYTHON_COMMAND=python3
}}
SetupPythonCommand
if [ -z "$WORKSPACE" ]; then
    export WORKSPACE="$PWD"
fi
if [ -z "$EDK_TOOLS_PATH" ]; then
    export EDK_TOOLS_PATH="$WORKSPACE/BaseTools"
fi
if [ -z "$CONF_PATH" ]; then
    export CONF_PATH="$WORKSPACE/Conf"
fi
if [ -n "$PACKAGES_PATH" ]; then
    echo 'test: unexpected packages path' >&2
    return 72
fi
build() {{
    case "$-" in
        *u*) ;;
        *) echo 'test: nounset was not restored' >&2; return 72 ;;
    esac
    case "$-" in
        *e*) ;;
        *) echo 'test: errexit was disabled' >&2; return 72 ;;
    esac
    echo "test: ramfb build $*"
    return {BUILD_SENTINEL}
}}
""")
        result = self.run_builder()
        self.assertEqual(
            result.returncode, BUILD_SENTINEL, result.stdout + result.stderr
        )
        self.assertIn("Building the AArch64 2048x1536 ramfb driver", result.stdout)
        self.assertIn(
            "test: ramfb build -a AARCH64 -b RELEASE -t CLANGDWARF "
            "-p ArmVirtPkg/ArmVirtQemu.dsc "
            "-m OvmfPkg/QemuRamfbDxe/QemuRamfbDxe.inf -n 2",
            result.stdout,
        )

    def test_setup_failure_stops_before_driver_build(self):
        self.prepare_setup("""
build() {
    echo 'test: unexpected ramfb build'
    return 73
}
echo 'test: setup failed' >&2
return 61
""")
        result = self.run_builder()
        self.assertEqual(result.returncode, 61, result.stdout + result.stderr)
        self.assertIn("test: setup failed", result.stderr)
        self.assertNotIn("test: unexpected ramfb build", result.stdout)


if __name__ == "__main__":
    unittest.main()
