// SPDX-License-Identifier: GPL-2.0-or-later
// Independent bit and token-ownership observations through original Linux APIs.
@[translated]
module aggregatefixture

#include "contract.h"

@[typedef]
struct C.vag_record1 {}

@[typedef]
struct C.vag_record2 {}

@[typedef]
struct C.vag_record4 {}

@[typedef]
struct C.vag_record8 {}

@[typedef]
struct C.vag_union1 {}

@[typedef]
struct C.vag_union2 {}

@[typedef]
struct C.vag_union4 {}

@[typedef]
struct C.vag_union8 {}

@[typedef]
struct C.vag_volatile_record8 {}

@[typedef]
struct C.pmd_t {}

@[typedef]
struct C.pte_t {}

@[typedef]
struct C.vag_thread {}

@[typedef]
struct C.vag_actor {
	ordinal u32
}

fn C.memcpy(voidptr, voidptr, usize) voidptr
fn C.printf(&char, ...) i32
fn C.abort()
fn C.pthread_create(voidptr, voidptr, fn (voidptr) voidptr, voidptr) i32
fn C.pthread_join(C.vag_thread, voidptr) i32

@[c: '__atomic_fetch_add']
fn C.vag_mark(&u32, u32, i32) u32

@[c: 'xchg']
fn C.vag_x1(&C.vag_record1, C.vag_record1) C.vag_record1

@[c: 'cmpxchg']
fn C.vag_c1(&C.vag_record1, C.vag_record1, C.vag_record1) C.vag_record1

@[c: 'xchg']
fn C.vag_x2(&C.vag_record2, C.vag_record2) C.vag_record2

@[c: 'cmpxchg']
fn C.vag_c2(&C.vag_record2, C.vag_record2, C.vag_record2) C.vag_record2

@[c: 'xchg']
fn C.vag_x4(&C.vag_record4, C.vag_record4) C.vag_record4

@[c: 'cmpxchg']
fn C.vag_c4(&C.vag_record4, C.vag_record4, C.vag_record4) C.vag_record4

@[c: 'xchg']
fn C.vag_x8(&C.vag_record8, C.vag_record8) C.vag_record8

@[c: 'cmpxchg']
fn C.vag_c8(&C.vag_record8, C.vag_record8, C.vag_record8) C.vag_record8

@[c: 'xchg']
fn C.vag_xu1(&C.vag_union1, C.vag_union1) C.vag_union1

@[c: 'cmpxchg']
fn C.vag_cu1(&C.vag_union1, C.vag_union1, C.vag_union1) C.vag_union1

@[c: 'xchg']
fn C.vag_xu2(&C.vag_union2, C.vag_union2) C.vag_union2

@[c: 'cmpxchg']
fn C.vag_cu2(&C.vag_union2, C.vag_union2, C.vag_union2) C.vag_union2

@[c: 'xchg']
fn C.vag_xu4(&C.vag_union4, C.vag_union4) C.vag_union4

@[c: 'cmpxchg']
fn C.vag_cu4(&C.vag_union4, C.vag_union4, C.vag_union4) C.vag_union4

@[c: 'xchg']
fn C.vag_xu8(&C.vag_union8, C.vag_union8) C.vag_union8

@[c: 'cmpxchg']
fn C.vag_cu8(&C.vag_union8, C.vag_union8, C.vag_union8) C.vag_union8

@[c: 'xchg']
fn C.vag_xpmd(&C.pmd_t, C.pmd_t) C.pmd_t

@[c: 'cmpxchg']
fn C.vag_cpmd(&C.pmd_t, C.pmd_t, C.pmd_t) C.pmd_t

@[c: 'xchg']
fn C.vag_xpte(&C.pte_t, C.pte_t) C.pte_t

@[c: 'cmpxchg']
fn C.vag_cpte(&C.pte_t, C.pte_t, C.pte_t) C.pte_t

@[c: 'xchg']
fn C.vag_xvolatile(&C.vag_volatile_record8, C.vag_record8) C.vag_record8

@[c: 'cmpxchg']
fn C.vag_cvolatile(&C.vag_volatile_record8, C.vag_record8, C.vag_record8) C.vag_record8

@[c: 'xchg']
fn C.vag_xscalar(&u64, u64) u64

@[c: 'cmpxchg']
fn C.vag_cscalar(&u64, u64, u64) u64

@[c: 'xchg']
fn C.vag_xpointer(&voidptr, voidptr) voidptr

@[c: 'cmpxchg']
fn C.vag_cpointer(&voidptr, voidptr, voidptr) voidptr

__global (
	vag_spy_cell           C.pmd_t
	vag_spy_pointer_calls  u32
	vag_spy_expected_calls u32
	vag_spy_value_calls    u32
	vag_token_cell         C.pmd_t
	vag_token_seen         [4001]u32
	vag_cas_cell           C.pmd_t
)

fn check(ok bool, code i32) {
	if !ok {
		C.printf(c'FAIL: V aggregate exchange code=%d\n', code)
		C.abort()
	}
}

fn bits_at(pointer voidptr, width usize) u64 {
	mut scalar := u64(0)
	unsafe { C.memcpy(&scalar, pointer, width) }
	return scalar
}

fn pmd(bits u64) C.pmd_t {
	mut page := C.pmd_t{}
	unsafe { C.memcpy(&page, &bits, 8) }
	return page
}

fn pointer_operand() &C.pmd_t {
	unsafe {
		vag_spy_pointer_calls++
		return &vag_spy_cell
	}
}

fn expected_operand() C.pmd_t {
	unsafe { vag_spy_expected_calls++ }
	return pmd(0x8000000000000081)
}

fn value_operand() C.pmd_t {
	unsafe { vag_spy_value_calls++ }
	return pmd(0xFFFFFFFFFFFFFFFE)
}

// These branches invoke the real typed macros; the shared raw buffer has word
// alignment. Native build flags deliberately disable C strict alias analysis.
fn exchange(pointer voidptr, bits u64, kind i32, width usize) u64 {
	unsafe {
		match kind {
			0 {
				mut operand := C.vag_record1{}
				C.memcpy(&operand, &bits, width)
				mut observed := C.vag_x1(&C.vag_record1(pointer), operand)
				return bits_at(&observed, width)
			}
			1 {
				mut operand := C.vag_record2{}
				C.memcpy(&operand, &bits, width)
				mut observed := C.vag_x2(&C.vag_record2(pointer), operand)
				return bits_at(&observed, width)
			}
			2 {
				mut operand := C.vag_record4{}
				C.memcpy(&operand, &bits, width)
				mut observed := C.vag_x4(&C.vag_record4(pointer), operand)
				return bits_at(&observed, width)
			}
			3 {
				mut operand := C.vag_record8{}
				C.memcpy(&operand, &bits, width)
				mut observed := C.vag_x8(&C.vag_record8(pointer), operand)
				return bits_at(&observed, width)
			}
			4 {
				mut operand := C.vag_union1{}
				C.memcpy(&operand, &bits, width)
				mut observed := C.vag_xu1(&C.vag_union1(pointer), operand)
				return bits_at(&observed, width)
			}
			5 {
				mut operand := C.vag_union2{}
				C.memcpy(&operand, &bits, width)
				mut observed := C.vag_xu2(&C.vag_union2(pointer), operand)
				return bits_at(&observed, width)
			}
			6 {
				mut operand := C.vag_union4{}
				C.memcpy(&operand, &bits, width)
				mut observed := C.vag_xu4(&C.vag_union4(pointer), operand)
				return bits_at(&observed, width)
			}
			7 {
				mut operand := C.vag_union8{}
				C.memcpy(&operand, &bits, width)
				mut observed := C.vag_xu8(&C.vag_union8(pointer), operand)
				return bits_at(&observed, width)
			}
			8 {
				mut operand := C.pmd_t{}
				C.memcpy(&operand, &bits, width)
				mut observed := C.vag_xpmd(&C.pmd_t(pointer), operand)
				return bits_at(&observed, width)
			}
			9 {
				mut operand := C.pte_t{}
				C.memcpy(&operand, &bits, width)
				mut observed := C.vag_xpte(&C.pte_t(pointer), operand)
				return bits_at(&observed, width)
			}
			else {
				mut operand := C.vag_record8{}
				C.memcpy(&operand, &bits, width)
				mut observed := C.vag_xvolatile(&C.vag_volatile_record8(pointer), operand)
				return bits_at(&observed, width)
			}
		}
	}
}

fn compare(pointer voidptr, expected u64, bits u64, kind i32, width usize) u64 {
	unsafe {
		match kind {
			0 {
				mut operand := C.vag_record1{}
				mut previous := C.vag_record1{}
				C.memcpy(&operand, &bits, width)
				C.memcpy(&previous, &expected, width)
				mut observed := C.vag_c1(&C.vag_record1(pointer), previous, operand)
				return bits_at(&observed, width)
			}
			1 {
				mut operand := C.vag_record2{}
				mut previous := C.vag_record2{}
				C.memcpy(&operand, &bits, width)
				C.memcpy(&previous, &expected, width)
				mut observed := C.vag_c2(&C.vag_record2(pointer), previous, operand)
				return bits_at(&observed, width)
			}
			2 {
				mut operand := C.vag_record4{}
				mut previous := C.vag_record4{}
				C.memcpy(&operand, &bits, width)
				C.memcpy(&previous, &expected, width)
				mut observed := C.vag_c4(&C.vag_record4(pointer), previous, operand)
				return bits_at(&observed, width)
			}
			3 {
				mut operand := C.vag_record8{}
				mut previous := C.vag_record8{}
				C.memcpy(&operand, &bits, width)
				C.memcpy(&previous, &expected, width)
				mut observed := C.vag_c8(&C.vag_record8(pointer), previous, operand)
				return bits_at(&observed, width)
			}
			4 {
				mut operand := C.vag_union1{}
				mut previous := C.vag_union1{}
				C.memcpy(&operand, &bits, width)
				C.memcpy(&previous, &expected, width)
				mut observed := C.vag_cu1(&C.vag_union1(pointer), previous, operand)
				return bits_at(&observed, width)
			}
			5 {
				mut operand := C.vag_union2{}
				mut previous := C.vag_union2{}
				C.memcpy(&operand, &bits, width)
				C.memcpy(&previous, &expected, width)
				mut observed := C.vag_cu2(&C.vag_union2(pointer), previous, operand)
				return bits_at(&observed, width)
			}
			6 {
				mut operand := C.vag_union4{}
				mut previous := C.vag_union4{}
				C.memcpy(&operand, &bits, width)
				C.memcpy(&previous, &expected, width)
				mut observed := C.vag_cu4(&C.vag_union4(pointer), previous, operand)
				return bits_at(&observed, width)
			}
			7 {
				mut operand := C.vag_union8{}
				mut previous := C.vag_union8{}
				C.memcpy(&operand, &bits, width)
				C.memcpy(&previous, &expected, width)
				mut observed := C.vag_cu8(&C.vag_union8(pointer), previous, operand)
				return bits_at(&observed, width)
			}
			8 {
				mut operand := C.pmd_t{}
				mut previous := C.pmd_t{}
				C.memcpy(&operand, &bits, width)
				C.memcpy(&previous, &expected, width)
				mut observed := C.vag_cpmd(&C.pmd_t(pointer), previous, operand)
				return bits_at(&observed, width)
			}
			9 {
				mut operand := C.pte_t{}
				mut previous := C.pte_t{}
				C.memcpy(&operand, &bits, width)
				C.memcpy(&previous, &expected, width)
				mut observed := C.vag_cpte(&C.pte_t(pointer), previous, operand)
				return bits_at(&observed, width)
			}
			else {
				mut operand := C.vag_record8{}
				mut previous := C.vag_record8{}
				C.memcpy(&operand, &bits, width)
				C.memcpy(&previous, &expected, width)
				mut observed := C.vag_cvolatile(&C.vag_volatile_record8(pointer), previous, operand)
				return bits_at(&observed, width)
			}
		}
	}
}

fn pattern(kind i32, width usize, bits u64, next u64) {
	mask := if width == 8 { ~u64(0) } else { (u64(1) << (width * 8)) - 1 }
	mut storage := bits & mask
	replacement := next & mask
	unsafe {
		check(exchange(&storage, replacement, kind, width) == (bits & mask) && storage == replacement, 10 + kind)
		check(compare(&storage, replacement ^ 1, bits & mask, kind, width) == replacement && storage == replacement, 30 + kind)
		check(compare(&storage, replacement, bits & mask, kind, width) == replacement && storage == (bits & mask), 50 + kind)
	}
}

@[direct_array_access]
fn token_actor(argument voidptr) voidptr {
	unsafe {
		actor := &C.vag_actor(argument)
		for step in 0 .. 1000 {
			identifier := u64(actor.ordinal * 1000 + u32(step) + 1)
			mut observed := C.vag_xpmd(&vag_token_cell, pmd(identifier))
			old_identifier := bits_at(&observed, 8)
			check(old_identifier <= 4000, 90)
			check(C.vag_mark(&vag_token_seen[old_identifier], 1, 0) == 0, 91)
		}
		return nil
	}
}

fn cas_actor(argument voidptr) voidptr {
	unsafe {
		for _ in 0 .. 1000 {
			mut expected := u64(0)
			for {
				mut observed := C.vag_cpmd(&vag_cas_cell, pmd(expected), pmd(expected + 1))
				actual := bits_at(&observed, 8)
				if actual == expected { break }
				expected = actual
			}
		}
		return nil
	}
}

@[direct_array_access]
fn ownership() {
	unsafe {
		mut actors := [4]C.vag_actor{}
		mut threads := [4]C.vag_thread{}
		for i in 0 .. 4001 { vag_token_seen[i] = 0 }
		vag_token_cell = pmd(0)
		for i in 0 .. 4 {
			actors[i] = C.vag_actor{ ordinal: u32(i) }
			check(C.pthread_create(&threads[i], nil, token_actor, &actors[i]) == 0, 92)
		}
		for i in 0 .. 4 { check(C.pthread_join(threads[i], nil) == 0, 93) }
		last := bits_at(&vag_token_cell, 8)
		check(last <= 4000 && C.vag_mark(&vag_token_seen[last], 1, 0) == 0, 94)
		for i in 0 .. 4001 { check(vag_token_seen[i] == 1, 95) }
		vag_cas_cell = pmd(0)
		for i in 0 .. 4 { check(C.pthread_create(&threads[i], nil, cas_actor, nil) == 0, 96) }
		for i in 0 .. 4 { check(C.pthread_join(threads[i], nil) == 0, 97) }
		check(bits_at(&vag_cas_cell, 8) == 4000, 98)
	}
}

@[export: 'main']
@[direct_array_access]
pub fn run() i32 {
	unsafe {
		boundaries := [u64(0), 1, 0xFFFFFFFFFFFFFFFF, 0x8000000000000000, 0x0123456789ABCDEF,
			0xFEDCBA9876543210, 0xAAAAAAAAAAAAAAAA, 0x5555555555555555]!
		widths := [usize(1), 2, 4, 8, 1, 2, 4, 8, 8, 8, 8]!
		for kind in 0 .. 11 {
			for item in boundaries { pattern(kind, widths[kind], item, ~item) }
			for bit in 0 .. 64 { pattern(kind, widths[kind], u64(1) << bit, ~(u64(1) << bit)) }
		}
		// Genuine original page-table typed locals, not only raw-buffer views.
		mut page := pmd(0x8000000000000081)
		mut observed := C.vag_xpmd(&page, pmd(0xFFFFFFFFFFFFFFFE))
		check(bits_at(&observed, 8) == 0x8000000000000081 && bits_at(&page, 8) == 0xFFFFFFFFFFFFFFFE, 100)
		mut entry := C.pte_t{}
		mut operand := C.pte_t{}
		seed := u64(0x8000000000000001)
		replacement := u64(0xFEDCBA9876543210)
		C.memcpy(&entry, &seed, 8)
		C.memcpy(&operand, &replacement, 8)
		mut prior_entry := C.vag_xpte(&entry, operand)
		check(bits_at(&prior_entry, 8) == seed && bits_at(&entry, 8) == replacement, 101)
		vag_spy_cell = pmd(0x8000000000000081)
		vag_spy_pointer_calls = 0
		vag_spy_expected_calls = 0
		vag_spy_value_calls = 0
		observed = C.vag_xpmd(pointer_operand(), value_operand())
		check(bits_at(&observed, 8) == 0x8000000000000081 && vag_spy_pointer_calls == 1 && vag_spy_expected_calls == 0 && vag_spy_value_calls == 1, 102)
		vag_spy_cell = pmd(0x8000000000000081)
		vag_spy_pointer_calls = 0
		vag_spy_expected_calls = 0
		vag_spy_value_calls = 0
		observed = C.vag_cpmd(pointer_operand(), expected_operand(), value_operand())
		check(bits_at(&observed, 8) == 0x8000000000000081 && bits_at(&vag_spy_cell, 8) == 0xFFFFFFFFFFFFFFFE && vag_spy_pointer_calls == 1 && vag_spy_expected_calls == 1 && vag_spy_value_calls == 1, 103)
		vag_spy_cell = pmd(0x0123456789ABCDEF)
		vag_spy_pointer_calls = 0
		vag_spy_expected_calls = 0
		vag_spy_value_calls = 0
		observed = C.vag_cpmd(pointer_operand(), expected_operand(), value_operand())
		check(bits_at(&observed, 8) == 0x0123456789ABCDEF && bits_at(&vag_spy_cell, 8) == 0x0123456789ABCDEF && vag_spy_pointer_calls == 1 && vag_spy_expected_calls == 1 && vag_spy_value_calls == 1, 106)
		mut scalar := u64(0x8000000000000001)
		check(C.vag_xscalar(&scalar, 7) == 0x8000000000000001 && C.vag_cscalar(&scalar, 6, 8) == 7 && scalar == 7, 104)
		mut pointee := u64(9)
		mut address := voidptr(nil)
		check(C.vag_xpointer(&address, &pointee) == nil && C.vag_cpointer(&address, nil, nil) == &pointee && address == &pointee, 105)
		for _ in 0 .. 4 { ownership() }
		C.printf(c'PASS: V aggregate exchange records/unions=1,2,4,8 pmd/pte volatile cases=792 ownership=16000 CAS=16000\n')
		return 0
	}
}
