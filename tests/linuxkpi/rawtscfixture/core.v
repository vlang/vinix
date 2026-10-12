// SPDX-License-Identifier: GPL-2.0-or-later
// Observable value, type and get_cycles routing checks; all control is V.
@[translated]
module rawtscfixture

import rawtscspy as spy

#include "contract.h"

@[typedef]
struct C.vkt_cycles {}

@[typedef]
struct C.vrt_calls {
	counter fn () C.vkt_cycles
	cycles  fn () C.vkt_cycles
	raw     fn () u64
}

fn C.rdtsc() C.vkt_cycles
fn C.get_cycles() C.vkt_cycles
fn C.vinix_linuxkpi_raw_tsc() u64
fn C.memcpy(voidptr, voidptr, usize) voidptr
fn C.puts(&char) i32

@[c_extern]
__global C.VRT_TSC_CONFIGURED u32

fn bits(value C.vkt_cycles) u64 {
	mut result := u64(0)
	unsafe { C.memcpy(&result, &value, 8) }
	return result
}

@[direct_array_access]
fn check(value u64) {
	calls := C.vrt_calls{ counter: C.rdtsc, cycles: C.get_cycles, raw: C.vinix_linuxkpi_raw_tsc }
	for available in [false, true]! {
		spy.configure(value, available)
		spy.require(calls.raw() == value && spy.read_count() == 1 && spy.query_count() == 0, 1)
		spy.configure(value, available)
		spy.require(bits(calls.counter()) == value && spy.read_count() == 1 && spy.query_count() == 0, 2)
		spy.configure(value, available)
		actual := bits(calls.cycles())
		if C.VRT_TSC_CONFIGURED != 0 {
			spy.require(actual == value && spy.read_count() == 1 && spy.query_count() == 0, 3)
		} else {
			spy.require(spy.query_count() == 1, 4)
			if available {
				spy.require(actual == value && spy.read_count() == 1, 5)
			} else {
				spy.require(actual == 0 && spy.read_count() == 0, 6)
			}
		}
	}
}

@[direct_array_access]
fn boundaries() {
	for value in [u64(0), u64(1), u64(0xffffffff), u64(0x100000000), u64(0xffffffff00000000),
		u64(0x8000000000000000), ~u64(0), u64(0x123456789abcdef0)]! {
		check(value)
	}
	for position in u32(0) .. u32(64) {
		value := u64(1) << position
		check(value)
		check(~value)
	}
	// Repeated borrowed return storage exercises the high/sign bit without
	// assuming an ordering property of the actual unordered instruction.
	for _ in 0 .. 1024 { check(u64(0x80000001ffffffff)) }
}

@[export: 'main']
pub fn run() i32 {
	boundaries()
	C.puts(c'PASS: V raw TSC bridge and ULL facade preserve all 64 bits, call once and follow original get_cycles feature/config routing')
	return 0
}
