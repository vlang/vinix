# SPDX-License-Identifier: GPL-2.0-or-later
import importlib.util
from pathlib import Path
import struct
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[3]
SPEC = importlib.util.spec_from_file_location("dictionary_prepare", ROOT / "build-support/dictionary/prepare.py")
prepare = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(prepare)


class DictionaryDataTests(unittest.TestCase):
    def test_records_are_sorted_and_offsets_cover_both_payloads(self):
        data = prepare.encode({"zebra": "last\nline", "café": "first", "computer": "middle"})
        self.assertEqual(data[:8], b"VNXDICT1")
        count, key_size, definition_size, reserved = struct.unpack_from("<IIII", data, 8)
        self.assertEqual((count, reserved), (3, 0))
        self.assertEqual(len(data), 24 + count * 16 + key_size + definition_size)
        keys = data[24 + count * 16:24 + count * 16 + key_size]
        definitions = data[24 + count * 16 + key_size:]
        actual = []
        for index in range(count):
            key_at, key_len, text_at, text_len = struct.unpack_from("<IIII", data, 24 + index * 16)
            actual.append((keys[key_at:key_at + key_len].decode(), definitions[text_at:text_at + text_len].decode()))
        self.assertEqual(actual, [("café", "first"), ("computer", "middle"), ("zebra", "last\nline")])

    def test_encoding_is_deterministic_and_handles_multibyte_limits(self):
        one = {"é": "emoji 😀", "a": "line\nnext"}
        self.assertEqual(prepare.encode(one), prepare.encode(dict(reversed(list(one.items())))))
        with self.assertRaises(ValueError):
            prepare.encode({"é" * 65: "too long"})

    def test_bounds_and_control_characters_are_rejected(self):
        for entries in ({}, {"": "text"}, {"word": ""}, {"bad\tkey": "text"},
                        {"bad\x85key": "text"}, {"word": "bad\x00text"}, {"word": "bad\x85text"},
                        {"word": "x" * (prepare.MAX_DEFINITION + 1)}):
            with self.subTest(entries=list(entries)):
                with self.assertRaises(ValueError):
                    prepare.encode(entries)

    def test_unverified_archive_is_never_accepted(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "archive.tar.gz"
            self.assertFalse(prepare.verified_archive(path))
            path.write_bytes(b"wrong archive")
            self.assertFalse(prepare.verified_archive(path))

    def test_atomic_write_preserves_complete_data_and_read_only_mode(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "dictionary.vnd"
            prepare.atomic_write(path, b"first")
            prepare.atomic_write(path, b"second")
            self.assertEqual(path.read_bytes(), b"second")
            self.assertEqual(path.stat().st_mode & 0o777, 0o444)
            self.assertEqual(list(path.parent.iterdir()), [path])


if __name__ == "__main__":
    unittest.main()
