// SPDX-License-Identifier: GPL-2.0-or-later
// Observable queries and native production entry points, with V-only checks.
@[translated]
module cpupolicyfixture

import policytransport as model

#include "contract.h"
@[typedef]
struct C.vpp_volatile_u32 {}
@[typedef]
struct C.vpp_jump {}
@[typedef]
struct C.vpp_thread {}
fn C.vpp_setjmp(voidptr) int
fn C.pthread_create(voidptr, voidptr, fn(voidptr) voidptr, voidptr) int
fn C.pthread_join(C.vpp_thread, voidptr) int
fn C.sched_yield() int
fn C.puts(&char) int
fn C.cpu_feature_enabled(...) bool
fn C.boot_cpu_has(...) bool
fn C.static_cpu_has(...) bool
fn C.vinix_linuxkpi_cpu_has(u32) bool
fn C.policy_configure(i64, u32, bool, bool)
fn C.policy_initialize(u32)
fn C.policy_state(int) u32
fn C.policy_seed_ready(u32)
fn C.policy_sample(voidptr, bool, u32)
fn C.__atomic_store_n(voidptr, ...)
@[c_extern] __global C.X86_FEATURE_SHSTK u32
@[c_extern] __global C.X86_FEATURE_LA57 u32
@[c_extern] __global C.X86_FEATURE_MOVDIRI u32
@[c_extern] __global C.X86_FEATURE_MOVDIR64B u32
@[c_extern] __global C.X86_FEATURE_OSPKE u32
@[c_extern] __global C.X86_FEATURE_PKU u32
@[c_extern] __global C.X86_FEATURE_USER_SHSTK u32
@[c_extern] __global C.X86_FEATURE_IBT u32

const direct_mask = (u32(1) << 27) | (u32(1) << 28)

@[direct_array_access]
fn actual_sampler() {
	// Five independent raw flags and three leaf acknowledgements. The oracle
	// uses the exhaustive all-present row, not a second feature predicate.
	for flags in u32(0) .. u32(32) {
		for available in u32(0) .. u32(8) {
			for active in [false, true]! {
				seven_ecx := if flags & 1 != 0 { u32(1) << 7 } else { u32(0) }
				xsaves_eax := if flags & 2 != 0 { u32(1) << 3 } else { u32(0) }
				one_ecx := if flags & 4 != 0 { u32(1) << 26 } else { u32(0) }
				one_edx := (if flags & 8 != 0 { u32(1) << 24 } else { u32(0) })
					| (if flags & 16 != 0 { u32(1) } else { u32(0) })
				cr4 := (u64(0x12345) & ~(u64(1) << 12)) | if active { u64(1) << 12 } else { u64(0) }
				mut local := model.Local{cpu_number: 0x100000001, online: ~u64(0), directstore_ecx: 0xa593,
					linuxkpi_shstk_supported: true, linuxkpi_la57_active: !active}
				model.configure_sampler(available & 2 != 0, one_ecx, one_edx, available & 4 != 0, xsaves_eax, cr4)
				C.policy_sample(unsafe { &local }, available & 1 != 0, seven_ecx)
				model.finish_sampler()
				model.require(local.linuxkpi_shstk_supported == (flags == 31 && available == 7), 36)
				model.require(local.linuxkpi_la57_active == active && local.cpu_number == 0x100000001
					&& local.online == ~u64(0) && local.directstore_ecx == 0xa593, 37)
			}
		}
	}
	// Original XSAVE -> FXSR -> FPU prerequisites do not require SSE. The
	// all-present exhaustive row has SSE clear; setting it changes no result.
	mut local := model.Local{}
	model.configure_sampler(true, u32(1) << 26, (u32(1) << 24) | (u32(1) << 25) | 1, true, u32(1) << 3, 0)
	C.policy_sample(unsafe { &local }, true, u32(1) << 7)
	model.finish_sampler()
	model.require(local.linuxkpi_shstk_supported && !local.linuxkpi_la57_active, 38)
}

fn failure(kind u32, bit u32, text &char) {
	mut target := C.vpp_jump{}
	model.arm(unsafe { &target }, text)
	if C.vpp_setjmp(unsafe { &target }) == 0 {
		match kind {
			0 { C.policy_initialize(0) }
			1 { C.policy_initialize(1) }
			2 { C.vinix_linuxkpi_cpu_has(bit) }
			3 {
				mut dynamic := C.vpp_volatile_u32{}
				unsafe { C.__atomic_store_n(&dynamic, bit, 0) }
				C.cpu_feature_enabled(dynamic)
			}
			4 { C.cpu_feature_enabled(model.once(bit)) }
			else { model.require(false, 8) }
		}
		model.require(false, 9)
	}
	model.disarm()
}

fn check_queries(direct u32, shstk bool, la57 bool) {
	model.require(C.boot_cpu_has(C.X86_FEATURE_MOVDIRI) == (direct & (u32(1) << 27) != 0), 10)
	model.require(C.static_cpu_has(C.X86_FEATURE_MOVDIR64B) == (direct & (u32(1) << 28) != 0), 11)
	model.require(C.cpu_feature_enabled(C.X86_FEATURE_SHSTK) == shstk, 12)
	model.require(C.cpu_feature_enabled(C.X86_FEATURE_LA57) == la57, 13)
	model.require(!C.cpu_feature_enabled(C.X86_FEATURE_OSPKE)
		&& !C.cpu_feature_enabled(C.X86_FEATURE_PKU)
		&& !C.cpu_feature_enabled(C.X86_FEATURE_USER_SHSTK)
		&& !C.cpu_feature_enabled(C.X86_FEATURE_IBT), 14)
}

@[direct_array_access]
fn memberships() {
	for count in [1, 2, 4, 64, 65, 128, 256]! {
		for pattern in u32(0) .. u32(4) {
			for shstk in [false, true]! {
				for la57 in [false, true]! {
					C.policy_configure(i64(count), direct_mask, true, la57)
					expected := (if pattern & 1 != 0 { u32(1) << 27 } else { u32(0) })
						| (if pattern & 2 != 0 { u32(1) << 28 } else { u32(0) })
					model.set_member(count - 1, 3, u64(expected | ~direct_mask))
					model.set_member(count - 1, 4, u64(shstk))
					model.capture()
					C.policy_initialize(0); C.policy_initialize(1)
					model.require(model.same_records(), 15)
					model.require(C.policy_state(0) == expected && C.policy_state(1) == u32(count)
						&& C.policy_state(2) == 1 && C.policy_state(4) == u32(count) && C.policy_state(5) == 1, 16)
					model.require(model.metrics(0) == 2 && model.metrics(1) == 0 && model.metrics(2) == 1, 17)
					check_queries(expected, shstk, la57)
					for i in 0 .. count { model.set_member(i, 3, u64(~expected)); model.set_member(i, 4, u64(!shstk)) }
					model.set_geometry(!la57)
					check_queries(expected, shstk, la57)
					model.require(model.metrics(0) == 2 && model.metrics(1) == 0 && model.metrics(2) == 1, 18)
					failure(0, 0, c'initialized twice'); failure(1, 0, c'initialized twice')
				}
			}
		}
	}
	C.policy_configure(256, direct_mask, true, false)
	model.set_member(17, 3, u64(u32(1) << 28)); model.set_member(255, 3, u64(u32(1) << 27))
	model.set_member(169, 4, 0)
	C.policy_initialize(0); C.policy_initialize(1)
	check_queries(0, false, false)
}

@[direct_array_access]
fn invalid_memberships() {
	for kind in u32(0) .. u32(2) {
		for count in [i64(-1), i64(0), i64(257), i64(2147483647), i64(9223372036854775807), i64(0x100000001)]! {
			C.policy_configure(count, direct_mask, true, false)
			failure(kind, 0, if kind == 0 { c'invalid CPU feature policy membership' } else { c'invalid CPU infrastructure membership' })
		}
		for position in 0 .. 256 {
			for variant in 0 .. 7 {
				C.policy_configure(256, direct_mask, true, false)
				match variant {
					0 { model.set_member(position, 0, 0) }
					1 { model.set_member(position, 1, 0) }
					2 { model.set_member(position, 1, 2) }
					3 { model.set_member(position, 1, 0x100000001) }
					4 { model.set_member(position, 1, ~u64(0)) }
					5 { model.set_member(position, 2, u64(position + 1)) }
					else { model.set_member(position, 2, u64(position) + 0x100000000) }
				}
				failure(kind, 0, c'not acknowledged')
			}
			for active in [false, true]! {
				C.policy_configure(256, direct_mask, true, active)
				model.set_member(position, 5, u64(!active))
				failure(1, 0, c'paging mode disagrees')
			}
		}
		// An empty intersection never bypasses validation of later members.
		C.policy_configure(256, direct_mask, true, false)
		model.set_member(0, 3, 0); model.set_member(0, 4, 0); model.set_member(255, 1, 0)
		failure(kind, 0, c'not acknowledged')
	}
}

@[direct_array_access]
fn cold_and_unknown_queries() {
	C.policy_configure(4, direct_mask, true, false)
	model.require(!C.cpu_feature_enabled(C.X86_FEATURE_OSPKE)
		&& !C.cpu_feature_enabled(C.X86_FEATURE_PKU)
		&& !C.cpu_feature_enabled(C.X86_FEATURE_USER_SHSTK)
		&& !C.cpu_feature_enabled(C.X86_FEATURE_IBT), 19)
	model.require(model.metrics(1) == 0 && model.metrics(4) == 0, 20)
	for bit in [C.X86_FEATURE_MOVDIRI, C.X86_FEATURE_MOVDIR64B, C.X86_FEATURE_SHSTK, C.X86_FEATURE_LA57]! {
		failure(2, bit, c'not initialized')
	}
	C.policy_seed_ready(2)
	for bit in [C.X86_FEATURE_MOVDIRI, C.X86_FEATURE_MOVDIR64B, C.X86_FEATURE_SHSTK, C.X86_FEATURE_LA57]! {
		failure(2, bit, c'not initialized')
	}
	failure(0, 0, c'initialized twice'); failure(1, 0, c'initialized twice')
	C.policy_configure(4, direct_mask, true, false)
	for bit in u32(0) .. u32(32) {
		if bit !in [u32(7), u32(16), u32(27), u32(28)]! { failure(2, 16 * 32 + bit, c'unsupported') }
	}
	C.policy_initialize(0); C.policy_initialize(1)
	for bit in u32(0) .. u32(32) {
		if bit !in [u32(7), u32(16), u32(27), u32(28)]! { failure(2, 16 * 32 + bit, c'unsupported') }
	}
	for available in [false, true]! {
		model.set_leaf(available, 0, 0)
		for word in u32(0) .. u32(23) {
			if word !in [u32(0), u32(4), u32(16)]! { failure(2, word * 32, c'unsupported') }
		}
	}
	model.set_leaf(true, 0, 0)
	for bit in [C.X86_FEATURE_OSPKE, C.X86_FEATURE_PKU, C.X86_FEATURE_USER_SHSTK, C.X86_FEATURE_IBT]! {
		failure(3, bit, c'unsupported')
		before := model.metrics(3)
		failure(4, bit, c'unsupported')
		model.require(model.metrics(3) == before + 1, 21)
	}
	model.set_leaf(true, 0xa5a536e9, 0x693bc157)
	before := model.metrics(1)
	for bit in u32(0) .. u32(32) {
		model.require(C.vinix_linuxkpi_cpu_has(bit) == (u32(0x693bc157) & (u32(1) << bit) != 0), 22)
		model.require(C.vinix_linuxkpi_cpu_has(4 * 32 + bit) == (u32(0xa5a536e9) & (u32(1) << bit) != 0), 23)
	}
	model.require(model.metrics(1) == before + 64, 24)
	model.set_leaf(false, 0, 0)
	model.require(!C.vinix_linuxkpi_cpu_has(0) && !C.vinix_linuxkpi_cpu_has(4 * 32), 25)
}

fn query_actor(_argument voidptr) voidptr {
	for round in 0 .. 20000 {
		check_queries(u32(1) << 28, true, true)
		if round % 1024 == 0 { C.sched_yield() }
	}
	return unsafe { nil }
}

@[direct_array_access]
fn concurrent_queries() {
	C.policy_configure(256, direct_mask, true, true)
	model.set_member(169, 3, u64(u32(1) << 28))
	C.policy_initialize(0); C.policy_initialize(1)
	// Warm public/compiler wrappers before the observers start concurrently.
	check_queries(u32(1) << 28, true, true)
	model.capture()
	mut threads := [8]C.vpp_thread{}
	for i in 0 .. 8 { model.require(C.pthread_create(unsafe { &threads[i] }, unsafe { nil }, query_actor, unsafe { nil }) == 0, 26) }
	for i in 0 .. 8 { model.require(C.pthread_join(threads[i], unsafe { nil }) == 0, 27) }
	model.require(model.same_state() && model.metrics(2) == 1, 28)
}

@[export: 'main']
pub fn run() int {
	actual_sampler(); memberships(); invalid_memberships(); cold_and_unknown_queries(); concurrent_queries()
	C.puts(c'PASS: V CPU policy membership, immutable MOVDIR/SHSTK/LA57, exact configured feature macros and concurrent query lifetimes')
	return 0
}
