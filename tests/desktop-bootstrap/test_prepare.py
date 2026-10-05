#!/usr/bin/env python3
"""Exercise the fresh-checkout workflow without downloading binary layers."""

import json
import os
from pathlib import Path
import shutil
import subprocess
import tarfile
import tempfile
import unittest


HELPER = Path(__file__).resolve().parents[2] / "build-support/prepare-desktop-aarch64.sh"

FIXTURE_BUILDER = r'''
import json
import os
from pathlib import Path
import shutil
import sys
import tarfile

root = Path(__file__).resolve().parent
label = sys.argv[1]
with (root / "events.jsonl").open("a") as events:
    events.write(json.dumps({"builder": label,
                            "base_only": os.environ.get("VINIX_ALPINE_BASE_ONLY"),
                            "args": sys.argv[2:]}) + "\n")

def write(path, executable=False):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("fixture\n")
    if executable:
        path.chmod(0o755)

def ui2(path):
    for name in ["v.mod", "ui/vml_compiled.v", "examples/calculator/calculator.vml"]:
        write(path / name)

if label == "git":
    assert sys.argv[2:-1] == ["clone", "--depth", "1", "https://github.com/vlang/ui2"]
    ui2(Path(sys.argv[-1]))
elif label == "userland":
    build = Path(os.environ.get("VINIX_AARCH64_USERLAND_BUILD_DIR", root / "build-aarch64-userland"))
    stage = build / "staging"
    shutil.rmtree(stage, ignore_errors=True)
    write(stage / "usr/bin/vim", True)
    write(stage / "usr/lib/libc.a")
    write(stage / "usr/lib/gcc/aarch64-alpine-linux-musl/14/libgcc.a")
    write(stage / "usr/include/stdio.h")
    if os.environ["VINIX_ALPINE_BASE_ONLY"] == "0":
        for variable, default in [("VINIX_NETWORK_TOOLS_STAGING", "network-tools"),
                                  ("VINIX_X11_STAGING", "x11"),
                                  ("VINIX_FIREFOX_STAGING", "firefox")]:
            overlay = Path(os.environ.get(variable, root / ("build-aarch64-" + default) / "staging"))
            if overlay.exists():
                shutil.copytree(overlay, stage, dirs_exist_ok=True)
    archive = Path(os.environ["VINIX_AARCH64_INITRAMFS"])
    archive.parent.mkdir(parents=True, exist_ok=True)
    with tarfile.open(archive, "w", format=tarfile.USTAR_FORMAT) as output:
        output.add(stage, arcname=".")
else:
    layer = {"network": "network-tools", "x11": "x11", "firefox": "firefox"}[label]
    stage = root / ("build-aarch64-" + layer) / "staging"
    files = {
        "network": ["usr/bin/pkg", "sbin/apk", "usr/bin/curl"],
        "x11": ["usr/bin/Xorg", "usr/bin/Xvfb", "usr/bin/startx",
                "usr/bin/vinix-xinput", "usr/bin/vinix-wine-host"],
        "firefox": ["usr/bin/run-firefox", "usr/lib/firefox-esr/firefox-esr", "usr/bin/firefox-esr"],
    }[label]
    if os.environ.get("TEST_BROKEN_LAYER") == label:
        sys.exit(0)
    for path in files:
        write(stage / path, True)
    if label == "network":
        write(stage / "etc/vinix-pkg/base-world")
'''


class PrepareDesktopTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="vinix-desktop-bootstrap-")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name) / "checkout"
        (self.root / "build-support").mkdir(parents=True)
        self.helper = self.root / "build-support" / HELPER.name
        shutil.copy2(HELPER, self.helper)
        (self.root / "fixture_builder.py").write_text(FIXTURE_BUILDER)
        (self.root / "scripts").mkdir()
        for label, name in [("userland", "build-userland-aarch64.sh"),
                            ("network", "build-network-tools-aarch64.sh"),
                            ("x11", "build-x11-aarch64.sh"),
                            ("firefox", "build-firefox-aarch64.sh")]:
            self.write_builder(self.root / "scripts" / name, label)
        (self.root / "fake-bin").mkdir()
        self.write_builder(self.root / "fake-bin/git", "git")
        self.environment = {key: value for key, value in os.environ.items()
                            if not key.startswith(("VINIX_", "ALPINE_"))}
        self.environment["PATH"] = str(self.root / "fake-bin") + os.pathsep + os.environ["PATH"]

    def write_builder(self, path, label):
        path.write_text('#!/bin/sh\nexec python3 "' + str(self.root / "fixture_builder.py") +
                        '" ' + label + ' "$@"\n')
        path.chmod(0o755)

    def run_helper(self, **overrides):
        return subprocess.run(["bash", str(self.helper)], cwd=self.root,
                              env={**self.environment, **overrides}, text=True,
                              stdout=subprocess.PIPE, stderr=subprocess.PIPE)

    def events(self):
        log = self.root / "events.jsonl"
        return [json.loads(line) for line in log.read_text().splitlines()] if log.exists() else []

    def clear_events(self):
        (self.root / "events.jsonl").unlink(missing_ok=True)

    def bootstrap(self):
        result = self.run_helper()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_fresh_checkout_builds_runtime_before_assembling_image(self):
        self.bootstrap()
        self.assertEqual([(event["builder"], event["base_only"]) for event in self.events()],
                         [("git", None), ("userland", "1"), ("network", None),
                          ("x11", None), ("firefox", None), ("userland", "0")])
        with tarfile.open(self.root / "build-support/init-aarch64/initramfs.tar") as image:
            for path in ["./usr/bin/vim", "./usr/bin/Xorg", "./usr/bin/Xvfb", "./usr/bin/pkg",
                         "./usr/lib/firefox-esr/firefox-esr"]:
                self.assertTrue(image.getmember(path).isfile(), path)

    def test_warm_checkout_reuses_sources_and_layers(self):
        self.bootstrap()
        self.clear_events()
        image = self.root / "build-support/init-aarch64/initramfs.tar"
        before = image.read_bytes()
        self.bootstrap()
        self.assertEqual(self.events(), [])
        self.assertEqual(image.read_bytes(), before)

    def test_base_missing_x11_is_reassembled_from_existing_layers(self):
        self.bootstrap()
        self.clear_events()
        image = self.root / "build-support/init-aarch64/initramfs.tar"
        replacement = image.with_suffix(".tmp")
        with tarfile.open(image) as old, tarfile.open(replacement, "w") as output:
            for member in old:
                if member.name != "./usr/bin/Xorg":
                    output.addfile(member, old.extractfile(member) if member.isfile() else None)
        replacement.replace(image)
        self.bootstrap()
        self.assertEqual([(event["builder"], event["base_only"]) for event in self.events()],
                         [("userland", "0")])

    def test_incomplete_custom_staging_is_not_overwritten(self):
        for variable in ["VINIX_AARCH64_SYSROOT", "VINIX_NETWORK_TOOLS_STAGING",
                         "VINIX_X11_STAGING", "VINIX_FIREFOX_STAGING"]:
            with self.subTest(variable=variable):
                custom = self.root / variable
                custom.mkdir()
                marker = custom / "keep"
                marker.write_text("caller owned")
                result = self.run_helper(**{variable: str(custom)})
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("custom", result.stderr)
                self.assertEqual(marker.read_text(), "caller owned")
                self.assertEqual(self.events(), [])

    def test_explicit_ui2_is_validated_without_fetching_default(self):
        custom = self.root / "custom-ui2"
        custom.mkdir()
        result = self.run_helper(VINIX_UI2_SOURCE=str(custom))
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("ui2", result.stderr)
        self.assertEqual(self.events(), [])
        self.assertFalse((self.root / "third_party/ui2").exists())

    def test_complete_custom_layer_is_reused(self):
        self.bootstrap()
        self.clear_events()
        custom = self.root / "custom-x11"
        (self.root / "build-aarch64-x11/staging").rename(custom)
        result = self.run_helper(VINIX_X11_STAGING=str(custom))
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(self.events(), [])
        self.assertTrue((custom / "usr/bin/Xorg").is_file())

    def test_reassembling_other_layers_preserves_base_firefox(self):
        self.bootstrap()
        self.clear_events()
        shutil.rmtree(self.root / "build-aarch64-network-tools/staging")
        shutil.rmtree(self.root / "build-aarch64-firefox/staging")
        self.bootstrap()
        self.assertEqual([event["builder"] for event in self.events()],
                         ["network", "firefox", "userland"])
        with tarfile.open(self.root / "build-support/init-aarch64/initramfs.tar") as image:
            self.assertTrue(image.getmember("./usr/lib/firefox-esr/firefox-esr").isfile())

    def test_successful_builder_with_incomplete_output_stops_bootstrap(self):
        result = self.run_helper(TEST_BROKEN_LAYER="x11")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("X11 builder left incomplete staging", result.stderr)
        self.assertEqual([event["builder"] for event in self.events()],
                         ["git", "userland", "network", "x11"])


if __name__ == "__main__":
    unittest.main()
