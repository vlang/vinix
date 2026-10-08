"""Exercise firmware patching and setup without downloading or building edk2."""

import atexit
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
_BINARY = None


def _native_case(self):
    global _BINARY
    if _BINARY is None:
        directory = Path(tempfile.mkdtemp(prefix="vinix-ovmf-fixture-controller-"))
        try:
            binary = os.environ.get("VINIX_OVMF_FIXTURE")
            if binary is None:
                binary = str(directory / "fixture")
                subprocess.run([str(ROOT / "build-support/run-v-tool.sh"),
                                str(ROOT / "tests/qemu-ovmf/test_patch.v"),
                                "--install-fixture", binary], check=True)
        except BaseException:
            shutil.rmtree(directory)
            raise
        atexit.register(shutil.rmtree, directory)
        _BINARY = binary
    result = subprocess.run([_BINARY, self.id().split(".")[-1]],
                            capture_output=True, text=True)
    if result.returncode and "Firmware fixture check failed:" in result.stderr:
        self.fail(result.stdout + result.stderr)
    result.check_returncode()


@unittest.skipUnless(shutil.which("git"), "git is not installed")
class FirmwarePatchTests(unittest.TestCase):
    pass


for _name in json.loads((ROOT / "tests/qemu-ovmf/ovmffixture/cases.json").read_text())["cases"]:
    setattr(FirmwarePatchTests, _name, _native_case)


if __name__ == "__main__":
    unittest.main()
