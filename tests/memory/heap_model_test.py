#!/usr/bin/env python3
"""Executable specification, NOT a test of compiled V or kernel concurrency.

Models the slab.v list/bitmap transitions with an abstract PMM. Source checks
keep geometry and size classes aligned with the implementation. The separate
V boot self-test exercises actual kernel code when a kernel can be built.
"""
from __future__ import annotations

import ctypes
from dataclasses import dataclass, field
from pathlib import Path
import random
import re
import unittest

PAGE = 4096
MASK = (1 << 64) - 1
CLASSES = (16, 32, 48, 64, 96, 128, 192, 256, 384, 512, 768, 1024, 1536, 2048)


class HeaderLayout(ctypes.Structure):
    _fields_ = [(name, ctypes.c_uint64) for name in
                ('slab', 'magic', 'prev', 'next', 'capacity', 'in_use')]
    _fields_.append(('used', ctypes.c_uint64 * 4))


OFFSET = (ctypes.sizeof(HeaderLayout) + 15) & ~15


def first_zero(word: int) -> int:
    bits = (~word) & MASK
    if not bits:
        raise ValueError('requires a zero bit')
    index = 0
    for shift in (32, 16, 8, 4, 2):
        if bits & ((1 << shift) - 1) == 0:
            index += shift
            bits >>= shift
    if bits & 1 == 0:
        index += 1
    return index


@dataclass
class Page:
    base: int
    size: int
    prev: int = 0
    next: int = 0
    count: int = 0
    bits: list[int] = field(default_factory=lambda: [MASK] * 4)
    payload: bytearray = field(default_factory=lambda: bytearray([0xAA] * PAGE))

    @property
    def capacity(self) -> int:
        return (PAGE - OFFSET) // self.size

    def __post_init__(self) -> None:
        for slot in range(self.capacity):
            self.bits[slot // 64] &= ~(1 << (slot % 64))


class PMM:
    def __init__(self) -> None:
        self.pages: dict[int, Page] = {}
        self.returned: list[int] = []
        self.next_base = PAGE
        self.allocations = 0
        self.frees = 0

    def alloc(self, size: int) -> Page:
        if self.returned:
            base = self.returned.pop()
        else:
            base = self.next_base
            self.next_base += PAGE
        page = Page(base, size)
        self.pages[base] = page
        self.allocations += 1
        return page

    def free(self, page: Page) -> None:
        assert page.count == 0
        assert self.pages.pop(page.base) is page
        self.returned.append(page.base)
        self.frees += 1


class Slab:
    def __init__(self, pmm: PMM, size: int) -> None:
        self.pmm, self.size = pmm, size
        self.partial = self.spare = 0
        self.owned: set[int] = set()
        self.live: set[int] = set()

    def add(self, page: Page) -> None:
        page.prev, page.next = 0, self.partial
        if self.partial:
            self.pmm.pages[self.partial].prev = page.base
        self.partial = page.base

    def remove(self, page: Page) -> None:
        if page.prev == 0:
            self.partial = page.next
        else:
            self.pmm.pages[page.prev].next = page.next
        if page.next:
            self.pmm.pages[page.next].prev = page.prev
        page.prev = page.next = 0

    def alloc(self) -> int:
        if not self.partial:
            if self.spare:
                page = self.pmm.pages[self.spare]
                self.spare = 0
            else:
                page = self.pmm.alloc(self.size)
                self.owned.add(page.base)
            self.add(page)
        page = self.pmm.pages[self.partial]
        for i, word in enumerate(page.bits):
            if word != MASK:
                bit = first_zero(word)
                page.bits[i] |= 1 << bit
                slot = i * 64 + bit
                break
        else:
            raise AssertionError('no slot on a partial page')
        assert slot < page.capacity
        page.count += 1
        if page.count == page.capacity:
            self.remove(page)
        address = page.base + OFFSET + slot * self.size
        assert address not in self.live and address % 16 == 0
        self.live.add(address)
        offset = address - page.base
        page.payload[offset:offset + self.size] = bytes(self.size)
        return address

    def free(self, address: int) -> None:
        if not address:
            return
        base, offset = address & ~(PAGE - 1), address & (PAGE - 1)
        if base not in self.owned or offset < OFFSET:
            raise ValueError('invalid header')
        page = self.pmm.pages[base]
        slot, remainder = divmod(offset - OFFSET, self.size)
        if remainder or slot >= page.capacity:
            raise ValueError('invalid alignment')
        word, bit = slot // 64, 1 << (slot % 64)
        if page.bits[word] & bit == 0 or page.count == 0:
            raise ValueError('double free')
        full = page.count == page.capacity
        page.payload[offset:offset + self.size] = bytes([0xAA]) * self.size
        page.bits[word] &= ~bit
        page.count -= 1
        self.live.remove(address)
        if page.count == 0:
            if not full:
                self.remove(page)
            if not self.spare:
                self.spare = base
            else:
                self.owned.remove(base)
                self.pmm.free(page)
        elif full:
            self.add(page)

    def trim(self) -> int:
        if not self.spare:
            return 0
        base, self.spare = self.spare, 0
        self.owned.remove(base)
        self.pmm.free(self.pmm.pages[base])
        return PAGE

    def check(self) -> None:
        linked: set[int] = set()
        base, prev = self.partial, 0
        while base:
            assert base not in linked
            linked.add(base)
            page = self.pmm.pages[base]
            assert page.prev == prev and 0 < page.count < page.capacity
            prev, base = base, page.next
        expected_partial: set[int] = set()
        expected_live: set[int] = set()
        for base in self.owned:
            page = self.pmm.pages[base]
            assert 0 <= page.count <= page.capacity
            active = 0
            for slot in range(256):
                used = bool(page.bits[slot // 64] & (1 << (slot % 64)))
                if slot >= page.capacity:
                    assert used, 'tail slot became available'
                elif used:
                    active += 1
                    expected_live.add(base + OFFSET + slot * self.size)
            assert active == page.count
            if page.count == 0:
                assert base == self.spare and page.prev == page.next == 0
            elif page.count < page.capacity:
                expected_partial.add(base)
            else:
                assert page.prev == page.next == 0
        assert linked == expected_partial
        assert self.live == expected_live
        if self.spare:
            assert self.spare in self.owned


class HeapModelTests(unittest.TestCase):
    def test_source_geometry_and_classes(self) -> None:
        root = Path(__file__).resolve().parents[2]
        source = (root / 'kernel/modules/memory/physical.v').read_text()
        sizes = tuple(map(int, re.findall(r'slabs\[\d+\]\.init\((\d+)\)', source)))
        self.assertEqual(sizes, CLASSES)
        self.assertEqual(OFFSET, 80)
        slab = (root / 'kernel/modules/memory/slab.v').read_text()
        self.assertRegex(slab, r'used\s+\[4\]u64')
        self.assertIn('const slab_alignment = u64(16)', slab)
        for size in CLASSES:
            self.assertEqual(size % 16, 0)
            self.assertTrue(1 <= (PAGE - OFFSET) // size <= 256)

    def test_bit_search_all_positions_and_random_words(self) -> None:
        for bit in range(64):
            self.assertEqual(first_zero(MASK ^ (1 << bit)), bit)
        rng = random.Random(12345)
        for _ in range(20000):
            word = rng.getrandbits(64)
            if word != MASK:
                free = (~word) & MASK
                self.assertEqual(first_zero(word), (free & -free).bit_length() - 1)

    def test_all_classes_multi_page_lifecycle(self) -> None:
        for size in CLASSES:
            with self.subTest(size=size):
                pmm = PMM()
                slab = Slab(pmm, size)
                capacity = (PAGE - OFFSET) // size
                objects = [slab.alloc() for _ in range(3 * capacity + 1)]
                self.assertEqual(len(pmm.pages), 4)
                slab.check()
                for address in objects[::2] + objects[1::2]:
                    slab.free(address)
                    slab.check()
                self.assertEqual(len(pmm.pages), 1)
                self.assertEqual(slab.trim(), PAGE)
                self.assertEqual(slab.trim(), 0)
                slab.check()
                self.assertFalse(pmm.pages)
                self.assertEqual(pmm.allocations, pmm.frees)

    def test_single_slot_full_to_empty(self) -> None:
        pmm, size = PMM(), 2048
        slab = Slab(pmm, size)
        a, b = slab.alloc(), slab.alloc()
        slab.free(a)
        slab.free(b)
        slab.check()
        self.assertEqual(len(pmm.pages), 1)
        self.assertEqual(slab.alloc(), a)
        slab.check()

    def test_partial_preferred_to_spare(self) -> None:
        pmm = PMM()
        slab = Slab(pmm, 1024)
        objects = [slab.alloc() for _ in range(7)]
        slab.free(objects[6])  # third page becomes spare
        slab.free(objects[1])  # first page becomes partial
        self.assertEqual(slab.alloc(), objects[1])
        self.assertNotEqual(slab.spare, 0)
        slab.check()

    def test_payload_poison_and_zero_on_reuse(self) -> None:
        pmm = PMM()
        slab = Slab(pmm, 64)
        a, keeper = slab.alloc(), slab.alloc()
        page = pmm.pages[a & ~(PAGE - 1)]
        offset = a % PAGE
        page.payload[offset:offset + 64] = bytes([0x13]) * 64
        slab.free(a)
        self.assertEqual(page.payload[offset:offset + 64], bytes([0xAA]) * 64)
        self.assertEqual(slab.alloc(), a)
        self.assertEqual(page.payload[offset:offset + 64], bytes(64))
        slab.free(a)
        slab.free(keeper)
        slab.check()

    def test_invalid_and_double_free_on_resident_page(self) -> None:
        slab = Slab(PMM(), 64)
        a, keeper = slab.alloc(), slab.alloc()
        for bad in (a + 1, a - 1, a & ~(PAGE - 1)):
            with self.assertRaises(ValueError):
                slab.free(bad)
        slab.free(a)
        with self.assertRaises(ValueError):
            slab.free(a)
        slab.free(keeper)
        slab.check()

    def test_random_mixed_size_churn(self) -> None:
        rng, pmm = random.Random(0x584E55), PMM()
        slabs = [Slab(pmm, size) for size in CLASSES]
        live: list[tuple[Slab, int]] = []
        for i in range(100000):
            if not live or (len(live) < 2048 and rng.random() < .52):
                slab = rng.choice(slabs)
                live.append((slab, slab.alloc()))
            else:
                index = rng.randrange(len(live))
                slab, address = live[index]
                live[index] = live[-1]
                live.pop()
                slab.free(address)
            if i % 251 == 0:
                rng.choice(slabs).trim()
                for slab in slabs:
                    slab.check()
        rng.shuffle(live)
        for slab, address in live:
            slab.free(address)
        self.assertLessEqual(len(pmm.pages), len(CLASSES))
        for slab in slabs:
            slab.trim()
            slab.check()
        self.assertFalse(pmm.pages)
        self.assertEqual(pmm.allocations, pmm.frees)

    def test_arithmetic_guards(self) -> None:
        def checked_product(a: int, b: int) -> int | None:
            return None if b and a > MASK // b else a * b
        self.assertIsNone(checked_product(1 << 63, 2))
        self.assertEqual(checked_product(MASK, 0), 0)
        self.assertEqual(checked_product(7, 13), 91)
        maximum = (MASK // PAGE - 1) * PAGE
        for value in (0, 1, 2049, maximum - 1, maximum):
            pages = (value + PAGE - 1) // PAGE
            self.assertLessEqual((pages + 1) * PAGE, MASK)
        self.assertGreater(((maximum + 1 + PAGE - 1) // PAGE + 1) * PAGE, MASK)
        root = Path(__file__).resolve().parents[2]
        source = (root / 'kernel/modules/memory/physical.v').read_text()
        self.assertIn('if b != 0 && a > u64(-1) / b', source)
        self.assertIn('if new_ptr == unsafe { nil }', source)
        self.assertEqual(source.count('(u64(-1) / page_size - 1) * page_size'), 2)

    def test_irq_snapshot_source_order(self) -> None:
        root = Path(__file__).resolve().parents[2]
        source = (root / 'kernel/modules/klock/klock_amd64.v').read_text()
        release = source.split('pub fn (mut l Lock) release() {', 1)[1].split('\n}', 1)[0]
        self.assertLess(release.index('ints := l.ints'), release.index('katomic.store'))
        self.assertIn('cpu.interrupt_toggle(ints)', release)


if __name__ == '__main__':
    unittest.main(verbosity=2)
