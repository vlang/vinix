#!/usr/bin/env python3
"""Offline regressions for the private Dota libc family and staging cache."""
import hashlib
import importlib.util
import io
import json
from pathlib import Path
import sys
import tarfile
import tempfile
import unittest
from contextlib import redirect_stdout
from unittest.mock import patch
from types import SimpleNamespace

REPO = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("dota2_vulkan_stage", REPO / "build-support/dota2/vulkan-stage.py")
stage = importlib.util.module_from_spec(spec)
spec.loader.exec_module(stage)


_fixture_spec = importlib.util.spec_from_file_location("dota2_vulkan_fixture_native", Path(__file__).with_name("_vulkan_fixture_native.py"))
_fixture = importlib.util.module_from_spec(_fixture_spec)
_fixture_spec.loader.exec_module(_fixture)


def deb_bytes(files, links=None):
    return bytes.fromhex(_fixture.query("deb_bytes", {"files": {name: data.hex() for name, data in files.items()},
                                                 "links": links or {}}, globals()))


class StageTests(unittest.TestCase):
    def setUp(self):
        _fixture.query("setup", {}, globals(), self)

    @staticmethod
    def write(path, contents):
        _fixture.query("write", {"path": path, "contents": contents.hex()}, globals())

    def run_stage(self, extra=()):
        _fixture.query("run_stage", {"extra": list(extra)}, globals(), self)

    def test_full_package_and_legacy_paths_share_one_libc_family(self):
        _fixture.query("case", {"name": "test_full_package_and_legacy_paths_share_one_libc_family"}, globals(), self)

    def test_cached_mixed_loader_is_rebuilt_and_restores_alias(self):
        _fixture.query("case", {"name": "test_cached_mixed_loader_is_rebuilt_and_restores_alias"}, globals(), self)

    def test_changed_libm_and_gconv_invalidate_cached_full_package(self):
        _fixture.query("case", {"name": "test_changed_libm_and_gconv_invalidate_cached_full_package"}, globals(), self)

    def test_wrong_legacy_libc_and_missing_marker_are_not_cache_hits(self):
        _fixture.query("case", {"name": "test_wrong_legacy_libc_and_missing_marker_are_not_cache_hits"}, globals(), self)

    def test_generation_tracks_alias_policy_package_pin_and_builder(self):
        _fixture.query("case", {"name": "test_generation_tracks_alias_policy_package_pin_and_builder"}, globals(), self)

    def test_early_v_abi_and_generator_invalidate_cache(self):
        _fixture.query("case", {"name": "test_early_v_abi_and_generator_invalidate_cache"}, globals(), self)

    def test_mmap_v_abi_and_export_policy_invalidate_cache(self):
        _fixture.query("case", {"name": "test_mmap_v_abi_and_export_policy_invalidate_cache"}, globals(), self)

    def test_baseline_option_keeps_the_steam_libc_without_overlay(self):
        _fixture.query("case", {"name": "test_baseline_option_keeps_the_steam_libc_without_overlay"}, globals(), self)

    def test_patched_lavapipe_links_bookworm_libc_and_replaces_only_its_driver(self):
        _fixture.query("case", {"name": "test_patched_lavapipe_links_bookworm_libc_and_replaces_only_its_driver"}, globals(), self)

    def test_replaced_lavapipe_is_not_a_cache_hit(self):
        _fixture.query("case", {"name": "test_replaced_lavapipe_is_not_a_cache_hit"}, globals(), self)

    def test_baseline_option_keeps_debian_lavapipe(self):
        _fixture.query("case", {"name": "test_baseline_option_keeps_debian_lavapipe"}, globals(), self)

    def test_other_debian_mesa_version_is_rejected(self):
        _fixture.query("case", {"name": "test_other_debian_mesa_version_is_rejected"}, globals(), self)

    def test_venus_is_staged_for_the_guest_root_with_bookworm_libc(self):
        _fixture.query("case", {"name": "test_venus_is_staged_for_the_guest_root_with_bookworm_libc"}, globals(), self)

    def test_replaced_venus_is_not_a_cache_hit(self):
        _fixture.query("case", {"name": "test_replaced_venus_is_not_a_cache_hit"}, globals(), self)

    def test_option_omits_venus(self):
        _fixture.query("case", {"name": "test_option_omits_venus"}, globals(), self)

    def test_corrupt_cached_package_fails_before_cloning_payload_into_root(self):
        _fixture.query("case", {"name": "test_corrupt_cached_package_fails_before_cloning_payload_into_root"}, globals(), self)

    def test_pin_rejects_wrong_architecture(self):
        _fixture.query("case", {"name": "test_pin_rejects_wrong_architecture"}, globals(), self)

    def test_partial_libc_family_fails_before_changing_the_source(self):
        _fixture.query("case", {"name": "test_partial_libc_family_fails_before_changing_the_source"}, globals(), self)


if __name__ == "__main__":
    unittest.main()
