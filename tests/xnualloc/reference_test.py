#!/usr/bin/env python3
# Copyright (c) 2000-2020 Apple Inc. All rights reserved.
#
# @APPLE_OSREFERENCE_LICENSE_HEADER_START@
#
# This file contains Original Code and/or Modifications of Original Code
# as defined in and that are subject to the Apple Public Source License
# Version 2.0 (the 'License'). You may not use this file except in
# compliance with the License. The rights granted to you under the License
# may not be used to create, or enable the creation or redistribution of,
# unlawful or unlicensed copies of an Apple operating system, or to
# circumvent, violate, or enable the circumvention or violation of, any
# terms of an Apple operating system software license agreement.
#
# Please obtain a copy of the License at
# http://www.opensource.apple.com/apsl/ and read it before using this file.
#
# The Original Code and all software distributed under the License are
# distributed on an 'AS IS' basis, WITHOUT WARRANTY OF ANY KIND, EITHER
# EXPRESS OR IMPLIED, AND APPLE HEREBY DISCLAIMS ALL SUCH WARRANTIES,
# INCLUDING WITHOUT LIMITATION, ANY WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE, QUIET ENJOYMENT OR NON-INFRINGEMENT.
# Please see the License for the specific language governing rights and
# limitations under the License.
#
# @APPLE_OSREFERENCE_LICENSE_HEADER_END@
# @OSF_COPYRIGHT@
# Mach Operating System
# Copyright (c) 1991,1990,1989,1988,1987 Carnegie Mellon University
# All Rights Reserved.
#
# Permission to use, copy, modify and distribute this software and its
# documentation is hereby granted, provided that both the copyright
# notice and this permission notice appear in all copies of the
# software, derivative works or modified versions, and any portions
# thereof, and that both notices appear in supporting documentation.
#
# CARNEGIE MELLON ALLOWS FREE USE OF THIS SOFTWARE IN ITS "AS IS"
# CONDITION.  CARNEGIE MELLON DISCLAIMS ANY LIABILITY OF ANY KIND FOR
# ANY DAMAGES WHATSOEVER RESULTING FROM THE USE OF THIS SOFTWARE.
#
# Carnegie Mellon requests users of this software to return to
#
# Software Distribution Coordinator  or  Software.Distribution@CS.CMU.EDU
# School of Computer Science
# Carnegie Mellon University
# Pittsburgh PA 15213-3890
#
# any improvements or extensions that they make and grant Carnegie Mellon
# the rights to redistribute these changes.
# Modified 2026-09-11: Python differential harness and translated buddy model.
# Upstream: apple-oss-distributions/xnu f6217f891ac0bb64f3d375211650a4c1ff8ca1ea,
# osfmk/kern/zalloc.c. See docs/xnualloc/PORT_STATUS.md and
# kernel/modules/xnualloc/APPLE_LICENSE.
# These translations retain APSL 2.0; they are NOT relicensed as GPL.
#

"""Executable C-reference checks, not execution of the V implementation.

Builds the extracted C reference using UBSan. Tests it against a byte-oriented
buddy model and an independent bit-by-bit oracle. V execution is a separate
step (port_test.v); passing this file does not establish V compiler correctness
or kernel/SMP correctness.
"""
from __future__ import annotations

import ctypes as C
import os
from pathlib import Path
import random
import struct
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
MASK = (1 << 64) - 1


class BuddyModel:
    """Test model of the translated relative-index/split-bit representation."""
    def __init__(self, shift: int, chunks: int) -> None:
        self.page = 1 << shift
        self.order = shift - 4
        self.heads = self.order + 1
        self.hdr = self.page // 64
        self.data = bytearray(self.page * chunks)
        self.w32(self.hdr, 1)
        self.w32(self.hdr + 4, chunks)
        self.init_chunk(0, False)

    def r32(self, offset: int) -> int:
        return struct.unpack_from('<I', self.data, offset)[0]

    def w32(self, offset: int, value: int) -> None:
        struct.pack_into('<I', self.data, offset, value)

    def head(self, order: int, extra: bool) -> int:
        return (self.hdr + 8 + ((self.heads if extra else 0) + order) * 8) // 8

    def push(self, index: int, order: int, extra: bool) -> None:
        hd = self.head(order, extra)
        nxt = self.r32(hd * 8)
        if nxt:
            assert self.r32(nxt * 8 + 4) == hd
            self.w32(nxt * 8 + 4, index)
        self.w32(index * 8, nxt)
        self.w32(index * 8 + 4, hd)
        self.w32(hd * 8, index)

    def remove(self, index: int) -> None:
        nxt, prev = self.r32(index * 8), self.r32(index * 8 + 4)
        assert self.r32(prev * 8) == index
        self.w32(prev * 8, nxt)
        if nxt:
            assert self.r32(nxt * 8 + 4) == index
            self.w32(nxt * 8 + 4, prev)

    def pop(self, order: int, extra: bool) -> int:
        index = self.r32(self.head(order, extra) * 8)
        if index:
            self.remove(index)
        return index * 8

    def node(self, address: int, order: int) -> int:
        return ((address % self.page // 8) >> order) + (1 << (self.order - order + 1)) - 1

    def address(self, page: int, node: int, order: int) -> int:
        return page + ((node - (1 << (self.order - order + 1)) + 1) << order) * 8

    def flip(self, page: int, node: int) -> None:
        pos = page + (node // 64) * 8
        word = struct.unpack_from('<Q', self.data, pos)[0]
        struct.pack_into('<Q', self.data, pos, word ^ (1 << (node % 64)))

    def split(self, page: int, node: int) -> bool:
        word = struct.unpack_from('<Q', self.data, page + (node // 64) * 8)[0]
        return bool(word & (1 << (node % 64)))

    def init_chunk(self, index: int, extra: bool) -> None:
        header = self.hdr + (8 + self.heads * 16 if index == 0 else 0)
        page, size = index * self.page, self.page
        for order in range(self.order, -1, -1):
            block = 8 << order
            if size < header + block:
                continue
            size -= block
            node = self.node(page + size, order)
            self.flip(page, (node - 1) // 2)
            self.push(self.address(page, node, order) // 8, order, extra)

    def grow(self, extra: bool) -> bool:
        left, right = self.r32(self.hdr), self.r32(self.hdr + 4)
        if left >= right:
            return False
        index = right - 1 if extra else left
        self.data[index * self.page:(index + 1) * self.page] = bytes(self.page)
        self.w32(self.hdr + (4 if extra else 0), right - 1 if extra else left + 1)
        self.init_chunk(index, extra)
        return True

    def alloc(self, order: int, extra: bool) -> int:
        current = order
        address = self.pop(current, extra)
        while not address:
            if current >= self.order:
                if not self.grow(extra):
                    return 0
                current = order
            else:
                current += 1
            address = self.pop(current, extra)
        page = address & -self.page
        node = self.node(address, current)
        self.flip(page, (node - 1) // 2)
        while current > order:
            current -= 1
            self.flip(page, node)
            node = node * 2 + 1
            self.push(self.address(page, node + 1, current) // 8, current, extra)
        return address

    def free(self, address: int, order: int, extra: bool) -> None:
        page, node = address & -self.page, self.node(address, order)
        while node:
            parent = (node - 1) // 2
            self.flip(page, parent)
            if self.split(page, parent):
                break
            self.remove(self.address(page, ((node - 1) ^ 1) + 1, order) // 8)
            order += 1
            node = parent
        assert order <= self.order
        self.push(self.address(page, node, order) // 8, order, extra)

    def check_lists(self) -> None:
        visited: set[int] = set()
        for extra in (False, True):
            for order in range(self.heads):
                previous = self.head(order, extra)
                index = self.r32(previous * 8)
                while index:
                    assert index not in visited
                    visited.add(index)
                    assert self.r32(index * 8 + 4) == previous
                    assert (index * 8) % (8 << order) == 0
                    assert index * 8 + (8 << order) <= len(self.data)
                    previous, index = index, self.r32(index * 8)


def load_library(shift: int, destination: Path) -> C.CDLL:
    output = destination / f'ref{shift}.so'
    command = [os.environ.get('CC', 'cc'), '-std=c11', '-D_POSIX_C_SOURCE=200809L',
               f'-DPAGE_MAX_SHIFT={shift}', '-O1', '-g', '-Wall', '-Wextra', '-Werror',
               '-fsanitize=undefined', '-fno-sanitize-recover=all', '-shared', '-fPIC',
               str(ROOT / 'tests/xnualloc/reference.c'), '-o', str(output)]
    subprocess.run(command, check=True)
    lib = C.CDLL(str(output))
    lib.ref_buddy_init.argtypes, lib.ref_buddy_init.restype = [C.c_uint32], C.c_int
    lib.ref_buddy_alloc.argtypes, lib.ref_buddy_alloc.restype = [C.c_uint32, C.c_bool], C.c_uint64
    lib.ref_buddy_free.argtypes = [C.c_uint64, C.c_uint32, C.c_bool]
    lib.ref_buddy_snapshot.argtypes = [C.c_void_p]
    lib.ref_scan64.argtypes, lib.ref_scan64.restype = [C.POINTER(C.c_uint64), C.c_uint32, C.c_uint64], C.c_uint64
    lib.ref_merge64.argtypes = [C.POINTER(C.c_uint64), C.c_uint32, C.c_uint32]
    lib.ref_mark_free64.argtypes, lib.ref_mark_free64.restype = [C.POINTER(C.c_uint64), C.c_uint64], C.c_bool
    return lib


class ReferenceTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.temp = tempfile.TemporaryDirectory(prefix='xnu-reference-')
        cls.libs = {s: load_library(s, Path(cls.temp.name)) for s in (12, 14)}

    @classmethod
    def tearDownClass(cls) -> None:
        for lib in cls.libs.values():
            lib.ref_buddy_destroy()
        cls.temp.cleanup()

    def test_rotating_scan_against_bit_by_bit_oracle(self) -> None:
        rng = random.Random(0x584E55)
        lib = self.libs[12]
        for n in range(12000):
            words = 1 << rng.randrange(8)
            values = [rng.getrandbits(64) if n % 3 == 0 else 0 for _ in range(words)]
            if n % 3 == 1:
                slot = rng.randrange(words * 64)
                values[slot // 64] = 1 << (slot % 64)
            start = rng.randrange(words * 64 + 1)
            wanted = MASK
            for step in range(words * 64):
                i = (start + step) % (words * 64)
                if values[i // 64] & (1 << (i % 64)):
                    wanted = i
                    break
            array = (C.c_uint64 * words)(*values)
            actual = lib.ref_scan64(array, words, start)
            self.assertEqual(actual, wanted)
            if wanted != MASK:
                values[wanted // 64] &= ~(1 << (wanted % 64))
            self.assertEqual(list(array), values)

    def test_merge_and_duplicate_free(self) -> None:
        lib = self.libs[12]
        rng = random.Random(7)
        boundaries = [0, 1, 31, 32, 33, 63, 64, 65, 127, 128, 129, 255, 256]
        pairs = [(a, b) for a in boundaries for b in boundaries if a <= b]
        pairs += [tuple(sorted((rng.randrange(257), rng.randrange(257)))) for _ in range(3000)]
        for first, end in pairs:
            array = (C.c_uint64 * 4)()
            lib.ref_merge64(array, first, end)
            expected = ((1 << end) - 1) ^ ((1 << first) - 1)
            self.assertEqual(list(array), [(expected >> (64 * i)) & MASK for i in range(4)])
            slot = rng.randrange(256)
            was_free = bool(expected & (1 << slot))
            self.assertEqual(lib.ref_mark_free64(array, slot), not was_free)
            self.assertFalse(lib.ref_mark_free64(array, slot))

    def test_buddy_mixed_orders_banks_and_exact_arena_state(self) -> None:
        for shift, lib in self.libs.items():
            self.assertEqual(lib.ref_buddy_init(16), 0)
            model = BuddyModel(shift, 16)
            snapshot = (C.c_ubyte * len(model.data))()
            rng = random.Random(shift)
            live: list[tuple[int, int, bool]] = []
            for step in range(20000):
                if not live or (len(live) < 512 and rng.randrange(4)):
                    order = rng.randrange(model.order + 1)
                    extra = bool(rng.randrange(2))
                    actual = lib.ref_buddy_alloc(order, extra)
                    expected = model.alloc(order, extra)
                    self.assertEqual(actual, expected)
                    if actual:
                        size = 8 << order
                        for address, old_order, _ in live:
                            self.assertTrue(actual + size <= address or address + (8 << old_order) <= actual)
                        live.append((actual, order, extra))
                else:
                    idx = rng.randrange(len(live))
                    address, order, extra = live.pop(idx)
                    lib.ref_buddy_free(address, order, extra)
                    model.free(address, order, extra)
                if step % 37 == 0:
                    lib.ref_buddy_snapshot(snapshot)
                    self.assertEqual(bytes(snapshot), model.data)
                    model.check_lists()
            for address, order, extra in live:
                lib.ref_buddy_free(address, order, extra)
                model.free(address, order, extra)
            lib.ref_buddy_snapshot(snapshot)
            self.assertEqual(bytes(snapshot), model.data)
            model.check_lists()
            total = 0
            for extra in (False, True):
                while (address := lib.ref_buddy_alloc(model.order, extra)):
                    self.assertEqual(address, model.alloc(model.order, extra))
                    total += 1
            self.assertEqual(total, 16)

    def test_single_chunk_exhaustion_and_reuse(self) -> None:
        for shift, lib in self.libs.items():
            self.assertEqual(lib.ref_buddy_init(1), 0)
            model = BuddyModel(shift, 1)
            values = []
            while (address := lib.ref_buddy_alloc(0, False)):
                self.assertEqual(address, model.alloc(0, False))
                values.append(address)
            self.assertEqual(model.alloc(0, False), 0)
            expected = ((1 << shift) - model.hdr - 8 - model.heads * 16) // 8
            self.assertEqual(len(values), expected)
            for address in reversed(values):
                lib.ref_buddy_free(address, 0, False)
                model.free(address, 0, False)
            second = []
            while (address := lib.ref_buddy_alloc(0, False)):
                self.assertEqual(address, model.alloc(0, False))
                second.append(address)
            self.assertEqual(len(second), len(values))


if __name__ == '__main__':
    unittest.main(verbosity=2)
