#!/usr/bin/env python3
"""Exercise the build verifier against the actual linked kernel and bad copies."""
from pathlib import Path
import struct
import sys
import unittest
from verify_build import KERNEL_FILE_REQUEST_ID, elf_symbols, verify_hooks

elf = Path(sys.argv.pop(1)).read_bytes()
source = Path(sys.argv.pop(1)).read_text()


class BuildVerifierTests(unittest.TestCase):
    def reject_field(self, offset, fmt, value):
        changed = bytearray(elf)
        struct.pack_into(fmt, changed, offset, value)
        with self.assertRaises(ValueError):
            elf_symbols(changed)

    def test_actual_kernel(self):
        elf_symbols(elf)
        verify_hooks(source)

    def test_truncated(self):
        for length in (0, 63, len(elf) // 2):
            with self.assertRaises(ValueError):
                elf_symbols(elf[:length])

    def test_wrong_machine(self):
        self.reject_field(18, '<H', 62)

    def test_relocatable_object(self):
        self.reject_field(16, '<H', 1)

    def test_missing_symbols(self):
        changed = bytearray(elf)
        offset = struct.unpack_from('<Q', elf, 40)[0]
        count = struct.unpack_from('<H', elf, 60)[0]
        for i in range(count):
            if struct.unpack_from('<I', elf, offset + i * 64 + 4)[0] == 2:
                struct.pack_into('<I', changed, offset + i * 64 + 4, 0)
        with self.assertRaisesRegex(ValueError, 'missing linked Wi-Fi symbols'):
            elf_symbols(changed)

    def test_duplicate_kernel_file_request(self):
        with self.assertRaisesRegex(ValueError, 'exactly one Limine kernel-file request'):
            elf_symbols(elf + KERNEL_FILE_REQUEST_ID)

    def test_dynamic_loader(self):
        offset = struct.unpack_from('<Q', elf, 32)[0]
        self.reject_field(offset, '<I', 3)

    def test_bad_entry(self):
        self.reject_field(24, '<Q', 0)

    def test_missing_init(self):
        with self.assertRaisesRegex(ValueError, 'initialization'):
            verify_hooks(source.replace('apple__wifi__initialise();', ''))

    def test_missing_poll(self):
        with self.assertRaisesRegex(ValueError, 'polling'):
            verify_hooks(source.replace('apple__wifi__poll();', ''))

    def test_duplicate_poll(self):
        with self.assertRaisesRegex(ValueError, 'polling'):
            verify_hooks(source.replace('apple__wifi__poll();', 'apple__wifi__poll(); apple__wifi__poll();'))


if __name__ == '__main__':
    unittest.main()
