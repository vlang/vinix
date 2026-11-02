// SPDX-License-Identifier: GPL-2.0-or-later
// Typed native stack borrows only; these records perform no page-table operation.
@[translated]
module aggregatefixture

#include "linuxkpi_aggregate_fixture_v_contract.h"

fn C.memcpy(voidptr, voidptr, uint) voidptr

@[typedef]
struct C.vaf_record1 {}

@[c: 'xchg']
fn C.vaf_x_record1(&C.vaf_record1, C.vaf_record1) C.vaf_record1
@[c: 'cmpxchg']
fn C.vaf_c_record1(&C.vaf_record1, C.vaf_record1, C.vaf_record1) C.vaf_record1

@[typedef]
struct C.vaf_record2 {}

@[c: 'xchg']
fn C.vaf_x_record2(&C.vaf_record2, C.vaf_record2) C.vaf_record2
@[c: 'cmpxchg']
fn C.vaf_c_record2(&C.vaf_record2, C.vaf_record2, C.vaf_record2) C.vaf_record2

@[typedef]
struct C.vaf_record4 {}

@[c: 'xchg']
fn C.vaf_x_record4(&C.vaf_record4, C.vaf_record4) C.vaf_record4
@[c: 'cmpxchg']
fn C.vaf_c_record4(&C.vaf_record4, C.vaf_record4, C.vaf_record4) C.vaf_record4

@[typedef]
struct C.vaf_record8 {}

@[c: 'xchg']
fn C.vaf_x_record8(&C.vaf_record8, C.vaf_record8) C.vaf_record8
@[c: 'cmpxchg']
fn C.vaf_c_record8(&C.vaf_record8, C.vaf_record8, C.vaf_record8) C.vaf_record8

@[typedef]
struct C.vaf_union1 {}

@[c: 'xchg']
fn C.vaf_x_union1(&C.vaf_union1, C.vaf_union1) C.vaf_union1
@[c: 'cmpxchg']
fn C.vaf_c_union1(&C.vaf_union1, C.vaf_union1, C.vaf_union1) C.vaf_union1

@[typedef]
struct C.vaf_union2 {}

@[c: 'xchg']
fn C.vaf_x_union2(&C.vaf_union2, C.vaf_union2) C.vaf_union2
@[c: 'cmpxchg']
fn C.vaf_c_union2(&C.vaf_union2, C.vaf_union2, C.vaf_union2) C.vaf_union2

@[typedef]
struct C.vaf_union4 {}

@[c: 'xchg']
fn C.vaf_x_union4(&C.vaf_union4, C.vaf_union4) C.vaf_union4
@[c: 'cmpxchg']
fn C.vaf_c_union4(&C.vaf_union4, C.vaf_union4, C.vaf_union4) C.vaf_union4

@[typedef]
struct C.vaf_union8 {}

@[c: 'xchg']
fn C.vaf_x_union8(&C.vaf_union8, C.vaf_union8) C.vaf_union8
@[c: 'cmpxchg']
fn C.vaf_c_union8(&C.vaf_union8, C.vaf_union8, C.vaf_union8) C.vaf_union8

@[typedef]
struct C.pte_t {}

@[c: 'xchg']
fn C.vaf_x_pte(&C.pte_t, C.pte_t) C.pte_t
@[c: 'cmpxchg']
fn C.vaf_c_pte(&C.pte_t, C.pte_t, C.pte_t) C.pte_t

@[typedef]
struct C.pmd_t {}

@[c: 'xchg']
fn C.vaf_x_pmd(&C.pmd_t, C.pmd_t) C.pmd_t
@[c: 'cmpxchg']
fn C.vaf_c_pmd(&C.pmd_t, C.pmd_t, C.pmd_t) C.pmd_t

fn bits(storage voidptr, width uint) u64 {
	mut value := u64(0)
	unsafe { C.memcpy(&value, storage, width) }
	return value
}

fn check_record1() bool {
	seed := (u64(1) << (1 * 8 - 1)) | 1
	next := (u64(1) << (1 * 8)) - 2
	mut initial := C.vaf_record1{}
	mut replacement := C.vaf_record1{}
	zero := C.vaf_record1{}
	unsafe { C.memcpy(&initial, &seed, 1); C.memcpy(&replacement, &next, 1) }
	mut storage := initial
	mut prior := C.vaf_x_record1(unsafe { &storage }, replacement)
	if bits(unsafe { &prior }, 1) != seed || bits(unsafe { &storage }, 1) != next { return false }
	prior = C.vaf_c_record1(unsafe { &storage }, zero, initial)
	if bits(unsafe { &prior }, 1) != next || bits(unsafe { &storage }, 1) != next { return false }
	prior = C.vaf_c_record1(unsafe { &storage }, replacement, initial)
	return bits(unsafe { &prior }, 1) == next && bits(unsafe { &storage }, 1) == seed
}

fn check_record2() bool {
	seed := (u64(1) << (2 * 8 - 1)) | 1
	next := (u64(1) << (2 * 8)) - 2
	mut initial := C.vaf_record2{}
	mut replacement := C.vaf_record2{}
	zero := C.vaf_record2{}
	unsafe { C.memcpy(&initial, &seed, 2); C.memcpy(&replacement, &next, 2) }
	mut storage := initial
	mut prior := C.vaf_x_record2(unsafe { &storage }, replacement)
	if bits(unsafe { &prior }, 2) != seed || bits(unsafe { &storage }, 2) != next { return false }
	prior = C.vaf_c_record2(unsafe { &storage }, zero, initial)
	if bits(unsafe { &prior }, 2) != next || bits(unsafe { &storage }, 2) != next { return false }
	prior = C.vaf_c_record2(unsafe { &storage }, replacement, initial)
	return bits(unsafe { &prior }, 2) == next && bits(unsafe { &storage }, 2) == seed
}

fn check_record4() bool {
	seed := (u64(1) << (4 * 8 - 1)) | 1
	next := (u64(1) << (4 * 8)) - 2
	mut initial := C.vaf_record4{}
	mut replacement := C.vaf_record4{}
	zero := C.vaf_record4{}
	unsafe { C.memcpy(&initial, &seed, 4); C.memcpy(&replacement, &next, 4) }
	mut storage := initial
	mut prior := C.vaf_x_record4(unsafe { &storage }, replacement)
	if bits(unsafe { &prior }, 4) != seed || bits(unsafe { &storage }, 4) != next { return false }
	prior = C.vaf_c_record4(unsafe { &storage }, zero, initial)
	if bits(unsafe { &prior }, 4) != next || bits(unsafe { &storage }, 4) != next { return false }
	prior = C.vaf_c_record4(unsafe { &storage }, replacement, initial)
	return bits(unsafe { &prior }, 4) == next && bits(unsafe { &storage }, 4) == seed
}

fn check_record8() bool {
	seed := (u64(1) << (8 * 8 - 1)) | 1
	next := ~u64(1)
	mut initial := C.vaf_record8{}
	mut replacement := C.vaf_record8{}
	zero := C.vaf_record8{}
	unsafe { C.memcpy(&initial, &seed, 8); C.memcpy(&replacement, &next, 8) }
	mut storage := initial
	mut prior := C.vaf_x_record8(unsafe { &storage }, replacement)
	if bits(unsafe { &prior }, 8) != seed || bits(unsafe { &storage }, 8) != next { return false }
	prior = C.vaf_c_record8(unsafe { &storage }, zero, initial)
	if bits(unsafe { &prior }, 8) != next || bits(unsafe { &storage }, 8) != next { return false }
	prior = C.vaf_c_record8(unsafe { &storage }, replacement, initial)
	return bits(unsafe { &prior }, 8) == next && bits(unsafe { &storage }, 8) == seed
}

fn check_union1() bool {
	seed := (u64(1) << (1 * 8 - 1)) | 1
	next := (u64(1) << (1 * 8)) - 2
	mut initial := C.vaf_union1{}
	mut replacement := C.vaf_union1{}
	zero := C.vaf_union1{}
	unsafe { C.memcpy(&initial, &seed, 1); C.memcpy(&replacement, &next, 1) }
	mut storage := initial
	mut prior := C.vaf_x_union1(unsafe { &storage }, replacement)
	if bits(unsafe { &prior }, 1) != seed || bits(unsafe { &storage }, 1) != next { return false }
	prior = C.vaf_c_union1(unsafe { &storage }, zero, initial)
	if bits(unsafe { &prior }, 1) != next || bits(unsafe { &storage }, 1) != next { return false }
	prior = C.vaf_c_union1(unsafe { &storage }, replacement, initial)
	return bits(unsafe { &prior }, 1) == next && bits(unsafe { &storage }, 1) == seed
}

fn check_union2() bool {
	seed := (u64(1) << (2 * 8 - 1)) | 1
	next := (u64(1) << (2 * 8)) - 2
	mut initial := C.vaf_union2{}
	mut replacement := C.vaf_union2{}
	zero := C.vaf_union2{}
	unsafe { C.memcpy(&initial, &seed, 2); C.memcpy(&replacement, &next, 2) }
	mut storage := initial
	mut prior := C.vaf_x_union2(unsafe { &storage }, replacement)
	if bits(unsafe { &prior }, 2) != seed || bits(unsafe { &storage }, 2) != next { return false }
	prior = C.vaf_c_union2(unsafe { &storage }, zero, initial)
	if bits(unsafe { &prior }, 2) != next || bits(unsafe { &storage }, 2) != next { return false }
	prior = C.vaf_c_union2(unsafe { &storage }, replacement, initial)
	return bits(unsafe { &prior }, 2) == next && bits(unsafe { &storage }, 2) == seed
}

fn check_union4() bool {
	seed := (u64(1) << (4 * 8 - 1)) | 1
	next := (u64(1) << (4 * 8)) - 2
	mut initial := C.vaf_union4{}
	mut replacement := C.vaf_union4{}
	zero := C.vaf_union4{}
	unsafe { C.memcpy(&initial, &seed, 4); C.memcpy(&replacement, &next, 4) }
	mut storage := initial
	mut prior := C.vaf_x_union4(unsafe { &storage }, replacement)
	if bits(unsafe { &prior }, 4) != seed || bits(unsafe { &storage }, 4) != next { return false }
	prior = C.vaf_c_union4(unsafe { &storage }, zero, initial)
	if bits(unsafe { &prior }, 4) != next || bits(unsafe { &storage }, 4) != next { return false }
	prior = C.vaf_c_union4(unsafe { &storage }, replacement, initial)
	return bits(unsafe { &prior }, 4) == next && bits(unsafe { &storage }, 4) == seed
}

fn check_union8() bool {
	seed := (u64(1) << (8 * 8 - 1)) | 1
	next := ~u64(1)
	mut initial := C.vaf_union8{}
	mut replacement := C.vaf_union8{}
	zero := C.vaf_union8{}
	unsafe { C.memcpy(&initial, &seed, 8); C.memcpy(&replacement, &next, 8) }
	mut storage := initial
	mut prior := C.vaf_x_union8(unsafe { &storage }, replacement)
	if bits(unsafe { &prior }, 8) != seed || bits(unsafe { &storage }, 8) != next { return false }
	prior = C.vaf_c_union8(unsafe { &storage }, zero, initial)
	if bits(unsafe { &prior }, 8) != next || bits(unsafe { &storage }, 8) != next { return false }
	prior = C.vaf_c_union8(unsafe { &storage }, replacement, initial)
	return bits(unsafe { &prior }, 8) == next && bits(unsafe { &storage }, 8) == seed
}

fn check_pte() bool {
	seed := (u64(1) << (8 * 8 - 1)) | 1
	next := ~u64(1)
	mut initial := C.pte_t{}
	mut replacement := C.pte_t{}
	zero := C.pte_t{}
	unsafe { C.memcpy(&initial, &seed, 8); C.memcpy(&replacement, &next, 8) }
	mut storage := initial
	mut prior := C.vaf_x_pte(unsafe { &storage }, replacement)
	if bits(unsafe { &prior }, 8) != seed || bits(unsafe { &storage }, 8) != next { return false }
	prior = C.vaf_c_pte(unsafe { &storage }, zero, initial)
	if bits(unsafe { &prior }, 8) != next || bits(unsafe { &storage }, 8) != next { return false }
	prior = C.vaf_c_pte(unsafe { &storage }, replacement, initial)
	return bits(unsafe { &prior }, 8) == next && bits(unsafe { &storage }, 8) == seed
}

fn check_pmd() bool {
	seed := (u64(1) << (8 * 8 - 1)) | 1
	next := ~u64(1)
	mut initial := C.pmd_t{}
	mut replacement := C.pmd_t{}
	zero := C.pmd_t{}
	unsafe { C.memcpy(&initial, &seed, 8); C.memcpy(&replacement, &next, 8) }
	mut storage := initial
	mut prior := C.vaf_x_pmd(unsafe { &storage }, replacement)
	if bits(unsafe { &prior }, 8) != seed || bits(unsafe { &storage }, 8) != next { return false }
	prior = C.vaf_c_pmd(unsafe { &storage }, zero, initial)
	if bits(unsafe { &prior }, 8) != next || bits(unsafe { &storage }, 8) != next { return false }
	prior = C.vaf_c_pmd(unsafe { &storage }, replacement, initial)
	return bits(unsafe { &prior }, 8) == next && bits(unsafe { &storage }, 8) == seed
}

@[export: 'vinix_linuxkpi_aggregate_fixture_queries']
pub fn queries() i32 {
	if !check_record1() { return 1 }
	if !check_record2() { return 2 }
	if !check_record4() { return 3 }
	if !check_record8() { return 4 }
	if !check_union1() { return 5 }
	if !check_union2() { return 6 }
	if !check_union4() { return 7 }
	if !check_union8() { return 8 }
	if !check_pte() { return 9 }
	if !check_pmd() { return 10 }
	return 0
}
