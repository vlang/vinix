// SPDX-License-Identifier: GPL-2.0-or-later
// Independent membership, atomics and fatal transport; no feature reduction.
@[has_globals]
@[translated]
module policytransport

#include "contract.h"

@[typedef]
struct C.vpp_array {
mut:
	data voidptr
	len i64
	cap i64
	element_size i64
}
@[typedef]
struct C.vpp_string { str &u8 len i64 }
@[typedef]
pub struct C.vpp_jump {}
@[typedef]
pub struct C.vpp_thread {}
fn C.memset(voidptr, int, usize) voidptr
fn C.memcpy(voidptr, voidptr, usize) voidptr
fn C.memcmp(voidptr, voidptr, usize) int
fn C.strstr(&char, &char) &char
fn C.printf(&char, ...)
@[noreturn]
fn C.exit(int)
fn C.vpp_longjmp(voidptr)
@[c: '__atomic_load_n']
fn C.load32(&u32, int) u32
@[c: '__atomic_load_n']
fn C.load64(&u64, int) u64
@[c: '__atomic_store_n']
fn C.store32(&u32, u32, int)
@[c: '__atomic_fetch_add']
fn C.add32(&u32, u32, int) u32

pub struct Local {
pub mut:
	cpu_number u64
	online u64
	directstore_ecx u32
	linuxkpi_shstk_supported bool
	linuxkpi_la57_active bool
}

__global (
	records [257]Local
	members [257]&Local
	baseline [257]Local
	slots [6]&u32
	prior [6]u32
	load_count u32
	store_count u32
	cpuid_count u32
	array_count u32
	geometry_count u32
	dynamic_count u32
	geometry_limit u64
	leaf_ecx u32
	leaf_edx u32
	leaf_available bool
	prior_store u32
	prior_cpuid u32
	expected_message &char
	jump_target voidptr
	sampling bool
	sample_one_available bool
	sample_xsaves_available bool
	sample_one_ecx u32
	sample_one_edx u32
	sample_xsaves_eax u32
	sample_cr4 u64
	sample_phase u32
)

@[direct_array_access]
pub fn configure(descriptor voidptr, count i64, direct u32, shstk bool, la57 bool) {
	for i in 0 .. 257 {
		records[i] = Local{cpu_number: u64(i), online: 1, directstore_ecx: direct,
			linuxkpi_shstk_supported: shstk, linuxkpi_la57_active: la57}
		members[i] = unsafe { &records[i] }
	}
	mut value := unsafe { &C.vpp_array(descriptor) }
	unsafe { C.memset(value, 0, sizeof(C.vpp_array)) }
	value.data = unsafe { &members[0] }
	value.len = count
	value.cap = count
	value.element_size = sizeof(&Local)
	geometry_limit = if la57 { u64(1) << 56 } else { u64(1) << 47 }
	leaf_available = true
	sampling = false
	load_count = 0; store_count = 0; cpuid_count = 0; array_count = 0; geometry_count = 0; dynamic_count = 0
}

@[direct_array_access]
pub fn register_slots(a &u32, b &u32, c &u32, d &u32, e &u32, f &u32) {
	slots[0] = a; slots[1] = b; slots[2] = c; slots[3] = d; slots[4] = e; slots[5] = f
}

@[direct_array_access]
pub fn set_member(position int, kind int, value u64) {
	require(position >= 0 && position < 257, 1)
	match kind {
		0 { members[position] = unsafe { nil } }
		1 { records[position].online = value }
		2 { records[position].cpu_number = value }
		3 { records[position].directstore_ecx = u32(value) }
		4 { records[position].linuxkpi_shstk_supported = value != 0 }
		5 { records[position].linuxkpi_la57_active = value != 0 }
		else { require(false, 2) }
	}
}

pub fn set_geometry(value bool) { geometry_limit = if value { u64(1) << 56 } else { u64(1) << 47 } }
pub fn set_leaf(available bool, ecx u32, edx u32) { leaf_available = available; leaf_ecx = ecx; leaf_edx = edx }
pub fn geometry() u64 { geometry_count++; return geometry_limit }
pub fn cpuid(leaf u32, subleaf u32) (bool, u32, u32, u32, u32) {
	if sampling {
		if sample_phase == 0 {
			require(leaf == 1 && subleaf == 0, 31)
			sample_phase = 1
			return sample_one_available, 0, 0, sample_one_ecx, sample_one_edx
		}
		require(sample_phase == 1 && leaf == 0xd && subleaf == 1, 32)
		sample_phase = 2
		return sample_xsaves_available, sample_xsaves_eax, 0, 0, 0
	}
	require(leaf == 1 && subleaf == 0, 3)
	unsafe { C.add32(&cpuid_count, 1, 0) }
	return leaf_available, 0, 0, leaf_ecx, leaf_edx
}
pub fn configure_sampler(one_available bool, ecx u32, edx u32, xsaves_available bool, eax u32, cr4 u64) {
	require(!sampling, 33)
	sample_one_available = one_available; sample_one_ecx = ecx; sample_one_edx = edx
	sample_xsaves_available = xsaves_available; sample_xsaves_eax = eax; sample_cr4 = cr4
	sample_phase = 0
	sampling = true
}
pub fn read_cr4() u64 {
	require(sampling && sample_phase == 2, 34)
	sample_phase = 3
	return sample_cr4
}
pub fn finish_sampler() {
	require(sampling && sample_phase == 3, 35)
	sampling = false
}
pub fn load[T](value &T) T {
	unsafe { C.add32(&load_count, 1, 0) }
	if sizeof(T) == 8 { return T(unsafe { C.load64(&u64(value), 2) }) }
	return T(unsafe { C.load32(&u32(value), 2) })
}
@[direct_array_access]
pub fn store(value &u32, item u32) {
	require(item == 1, 4)
	// Observe the real release boundary: both immutable values precede readiness.
	if value == slots[2] {
		require(unsafe { C.load32(slots[1], 2) } >= 1 && unsafe { C.load32(slots[1], 2) } <= 256
			&& unsafe { C.load32(slots[0], 2) } & ~((u32(1) << 27) | (u32(1) << 28)) == 0, 29)
	} else {
		require(value == slots[5] && unsafe { C.load32(slots[4], 2) } >= 1 && unsafe { C.load32(slots[4], 2) } <= 256
			&& unsafe { C.load32(slots[3], 2) } & ~((u32(1) << 7) | (u32(1) << 16)) == 0, 30)
	}
	unsafe { C.add32(&store_count, 1, 0); C.store32(value, item, 3) }
}
pub fn metrics(which int) u32 {
	return match which { 0 { store_count } 1 { cpuid_count } 2 { geometry_count } 3 { dynamic_count } else { load_count } }
}
pub fn once(value u32) u32 { dynamic_count++; return value }

@[direct_array_access]
pub fn capture() {
	unsafe { C.memcpy(&baseline[0], &records[0], sizeof(baseline)) }
	for i in 0 .. 6 { prior[i] = unsafe { C.load32(slots[i], 2) } }
	prior_store = store_count; prior_cpuid = cpuid_count
}
@[direct_array_access]
pub fn same_records() bool { return unsafe { C.memcmp(&baseline[0], &records[0], sizeof(baseline)) } == 0 }
@[direct_array_access]
pub fn same_state() bool {
	for i in 0 .. 6 { if prior[i] != unsafe { C.load32(slots[i], 2) } { return false } }
	return same_records() && prior_store == store_count && prior_cpuid == cpuid_count
}
pub fn arm(target voidptr, message &char) { capture(); expected_message = message; jump_target = target }
pub fn disarm() { jump_target = unsafe { nil }; expected_message = unsafe { nil } }

@[noreturn]
pub fn fatal(message &char) {
	if jump_target != unsafe { nil } {
		require(same_state(), 5)
		require(unsafe { C.strstr(message, expected_message) } != unsafe { nil }, 6)
		C.vpp_longjmp(jump_target)
	}
	C.printf(c'FAIL: unexpected CPU policy panic: %s\n', message)
	C.exit(1)
}
pub fn require(condition bool, code int) {
	if !condition { C.printf(c'FAIL: CPU policy condition %d\n', code); C.exit(1) }
}

@[export: 'array_get']
pub fn borrowed_index(value C.vpp_array, index i64) voidptr {
	require(index >= 0 && index < value.len && value.data != unsafe { nil }
		&& value.element_size == sizeof(&Local), 7)
	array_count++
	return unsafe { voidptr(usize(value.data) + usize(index) * usize(value.element_size)) }
}
@[export: 'v_panic']
@[noreturn]
pub fn unexpected_v_panic(message C.vpp_string) { fatal(unsafe { &char(message.str) }) }
