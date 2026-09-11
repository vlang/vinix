#!/usr/bin/env python3
"""Executable specification of the non-SMR port protocol; DOES NOT execute V.

Checks the adapter's single-lock ownership discipline with an independent
address-set oracle after every operation. Not a concurrency or performance test.
"""
from __future__ import annotations
from dataclasses import dataclass, field
from pathlib import Path
import random
import unittest

N = 32

@dataclass(eq=False)
class Magazine:
    items: list[int] = field(default_factory=list)

@dataclass
class Depot:
    full: list[Magazine] = field(default_factory=list)
    empty: list[Magazine] = field(default_factory=list)

@dataclass
class Cache:
    alloc: Magazine = field(default_factory=Magazine)
    free: Magazine = field(default_factory=Magazine)
    depot: Depot = field(default_factory=lambda: Depot(empty=[Magazine() for _ in range(4)]))
    rr: int = 0

    def pop(self) -> int:
        if not self.alloc.items and self.free.items:
            self.alloc, self.free = self.free, self.alloc
        return self.alloc.items.pop() if self.alloc.items else 0

    def push(self, addr: int) -> bool:
        if len(self.free.items) == N and len(self.alloc.items) < N:
            self.alloc, self.free = self.free, self.alloc
        if len(self.free.items) == N:
            return False
        self.free.items.append(addr)
        return True

class Zone:
    def __init__(self, capacity: int, pages: int, limit: int):
        assert 0 < capacity <= 256 and 0 <= limit <= 4
        self.capacity = capacity
        self.free = [set(range(capacity)) for _ in range(pages)]
        self.empty = list(reversed(range(pages)))
        self.partial: list[int] = []
        self.full: list[int] = []
        self.detached: set[int] = set()
        self.live: set[int] = set()
        self.recirc = Depot()
        self.limit = limit

    def encode(self, page: int, slot: int) -> int:
        return (page + 1) * 4096 + slot * 16

    def decode(self, addr: int) -> tuple[int, int]:
        return addr // 4096 - 1, addr % 4096 // 16

    def available(self) -> int:
        return sum(len(f) for p, f in enumerate(self.free) if p not in self.detached)

    def queue(self, p: int) -> None:
        for q in (self.empty, self.partial, self.full):
            if p in q:
                q.remove(p)
        if len(self.free[p]) == self.capacity:
            self.empty.insert(0, p)
        elif self.free[p]:
            self.partial.insert(0, p)
        else:
            self.full.insert(0, p)

    def reserve(self, n: int, cache: Cache) -> list[int] | None:
        if n > self.available():
            return None
        result = []
        while len(result) < n:
            p = self.partial[0] if self.partial else self.empty[0]
            while len(result) < n and self.free[p]:
                start = (cache.rr + 1) % 256
                after = [s for s in self.free[p] if s >= start]
                s = min(after or self.free[p])
                self.free[p].remove(s)
                cache.rr = s
                result.append(self.encode(p, s))
            self.queue(p)
        return result

    def drop(self, addr: int) -> None:
        p, s = self.decode(addr)
        assert p not in self.detached and addr not in self.live
        assert s not in self.free[p]
        self.free[p].add(s)
        self.queue(p)

    @staticmethod
    def move(src: list[Magazine], dst: list[Magazine], n: int, head: bool) -> None:
        assert 0 < n <= len(src)
        items, src[:n] = src[:n], []
        if head:
            dst[:0] = items
        else:
            dst.extend(items)

    def alloc(self, c: Cache) -> int:
        addr = c.pop()
        if not addr:
            if self.limit:
                if not c.depot.full:
                    if len(c.depot.empty) >= self.limit:
                        self.move(c.depot.empty, self.recirc.empty,
                                  len(c.depot.empty) - self.limit // 2, True)
                    n = min(self.limit - len(c.depot.empty), len(self.recirc.full))
                    if n:
                        self.move(self.recirc.full, c.depot.full, n, False)
                if c.depot.full:
                    old, c.alloc = c.alloc, c.depot.full.pop(0)
                    assert not old.items
                    c.depot.empty.insert(0, old)
            elif self.recirc.full:
                old, c.alloc = c.alloc, self.recirc.full.pop(0)
                assert not old.items
                self.recirc.empty.insert(0, old)
            if not c.alloc.items and self.available():
                c.alloc.items = self.reserve(min(N, self.available()), c) or []
            addr = c.pop()
        if addr:
            assert addr not in self.live
            self.live.add(addr)
        return addr

    def release(self, addr: int, c: Cache | None) -> bool:
        if addr not in self.live:
            return False
        self.live.remove(addr)
        if c is not None:
            if c.push(addr):
                return True
            mag = None
            if self.limit:
                if not c.depot.empty:
                    if len(c.depot.full) >= self.limit:
                        self.move(c.depot.full, self.recirc.full,
                                  len(c.depot.full) - self.limit // 2, False)
                    n = min(self.limit - len(c.depot.full), len(self.recirc.empty))
                    if n:
                        self.move(self.recirc.empty, c.depot.empty, n, True)
                if c.depot.empty:
                    mag = c.depot.empty.pop(0)
                if mag:
                    old, c.free = c.free, mag
                    assert len(old.items) == N and not mag.items
                    c.depot.full.append(old)
            else:
                if self.recirc.empty:
                    mag = self.recirc.empty.pop(0)
                elif c.depot.empty:
                    mag = c.depot.empty.pop(0)
                if mag:
                    old, c.free = c.free, mag
                    assert len(old.items) == N and not mag.items
                    self.recirc.full.append(old)
            if mag:
                assert c.push(addr)
                return True
        self.drop(addr)
        return True

    def drain_mag(self, m: Magazine) -> None:
        for a in m.items:
            self.drop(a)
        m.items.clear()

    def drain(self, c: Cache) -> None:
        self.drain_mag(c.alloc)
        self.drain_mag(c.free)
        while c.depot.full:
            mag = c.depot.full.pop(0)
            self.drain_mag(mag)
            c.depot.empty.insert(0, mag)

    def drain_recirc(self) -> None:
        while self.recirc.full:
            mag = self.recirc.full.pop(0)
            self.drain_mag(mag)
            self.recirc.empty.insert(0, mag)

    def reclaim(self) -> int | None:
        if not self.empty:
            return None
        p = self.empty.pop(0)
        assert len(self.free[p]) == self.capacity
        self.detached.add(p)
        return p

    def check(self, caches: list[Cache]) -> None:
        magazines = list(self.recirc.full) + list(self.recirc.empty)
        for c in caches:
            assert len(c.alloc.items) <= N and len(c.free.items) <= N
            magazines += [c.alloc, c.free] + c.depot.full + c.depot.empty
        assert len(magazines) == len(caches) * 6
        assert len({id(m) for m in magazines}) == len(magazines)
        cached = [a for m in magazines for a in m.items]
        assert len(cached) == len(set(cached))
        assert not (set(cached) & self.live)
        for d in [self.recirc] + [c.depot for c in caches]:
            assert all(len(m.items) == N for m in d.full)
            assert all(not m.items for m in d.empty)
        reserved = {self.encode(p, s) for p, free in enumerate(self.free)
                    if p not in self.detached for s in range(self.capacity) if s not in free}
        assert reserved == set(cached) | self.live
        queue_pages = self.empty + self.partial + self.full
        assert len(queue_pages) == len(set(queue_pages))
        assert set(queue_pages) == set(range(len(self.free))) - self.detached
        assert all(len(self.free[p]) == self.capacity for p in self.empty)
        assert all(0 < len(self.free[p]) < self.capacity for p in self.partial)
        assert all(not self.free[p] for p in self.full)

class ProtocolTests(unittest.TestCase):
    def test_random_migrating_ownership_and_cache_drains(self):
        for limit in (0, 1, 2, 4):
            rng = random.Random(0x584E55 + limit)
            z, caches = Zone(127, 8, limit), [Cache() for _ in range(4)]
            live: list[int] = []
            for step in range(20000):
                c = caches[rng.randrange(4)]
                if not live or (len(live) < 800 and rng.randrange(10) < 6):
                    a = z.alloc(c)
                    if a:
                        self.assertNotIn(a, live)
                        live.append(a)
                else:
                    i = rng.randrange(len(live))
                    a = live.pop(i)
                    self.assertTrue(z.release(a, c))
                    self.assertFalse(z.release(a, c))
                if step % 71 == 0:
                    z.drain(c)
                    z.drain_recirc()
                z.check(caches)
                self.assertEqual(set(live), z.live)
            for a in live:
                self.assertTrue(z.release(a, caches[0]))
            for c in caches:
                z.drain(c)
            z.drain_recirc()
            z.check(caches)
            self.assertEqual(z.available(), 127 * 8)
            while z.reclaim() is not None:
                z.check(caches)
            self.assertEqual(z.available(), 0)

    def test_cached_pages_are_not_reclaimable(self):
        z, c = Zone(64, 1, 2), Cache()
        a = z.alloc(c)
        self.assertTrue(z.release(a, c))
        self.assertIsNone(z.reclaim())
        z.drain(c)
        z.drain_recirc()
        self.assertEqual(z.reclaim(), 0)
        z.check([c])

    def test_live_survivor_pins_backing(self):
        z, c = Zone(64, 1, 2), Cache()
        a = z.alloc(c)
        z.drain(c)
        z.drain_recirc()
        self.assertIsNone(z.reclaim())
        self.assertEqual(z.available(), 63)
        self.assertTrue(z.release(a, None))
        self.assertEqual(z.reclaim(), 0)
        z.check([c])

    def test_failed_batch_does_not_reserve_anything(self):
        z, c = Zone(64, 1, 2), Cache()
        self.assertIsNone(z.reserve(65, c))
        self.assertEqual(z.available(), 64)
        z.check([c])

    def test_partial_allocation_magazine_free_swap(self):
        c = Cache()
        c.alloc.items = [1, 2]
        c.free.items = list(range(3, 35))
        self.assertTrue(c.push(99))
        self.assertEqual(c.free.items, [1, 2, 99])
        self.assertEqual(len(c.alloc.items), N)

    def test_source_integration_contract(self):
        root = Path(__file__).resolve().parents[2]
        zone = (root / 'kernel/modules/xnualloc/zone.v').read_text()
        bridge = (root / 'kernel/modules/memory/xnu_zone_heap.v').read_text()
        physical = (root / 'kernel/modules/memory/physical.v').read_text()
        self.assertNotIn('mut rr u16', zone)
        self.assertIn('heads := [z.full, z.partial, z.empty]!', zone)
        self.assertIn('z.zone_mark_valid(addr)', zone)
        free = bridge.split('fn xnu_heap_free(')[1].split('fn xnu_heap_realloc')[0]
        self.assertLess(free.index('zone_mark_invalid'), free.index('C.memset'))
        self.assertLess(free.index('C.memset'), free.index('zfree_ext'))
        cache = bridge.split('fn (mut h XnuHeapClass) cache_locked')[1].split('fn (mut h XnuHeapClass) grow_locked')[0]
        self.assertLess(cache.index('if count == 0'), cache.index('xnu_heap_cpu_number()'))
        self.assertIn('allow_create && h.zone.elems_free != 0', cache)
        self.assertIn('return xnu_heap_alloc(size)', physical)
        self.assertIn('return xnu_heap_realloc(ptr, new_size)', physical)
        for arch in ('x86', 'aarch64'):
            smp = (root / f'kernel/modules/{arch}/smp/smp.v').read_text()
            self.assertLess(smp.index('for katomic.load(&cpu_local.online)'),
                            smp.index('memory.heap_enable_cpu_caches'))

if __name__ == '__main__':
    unittest.main(verbosity=2)
