// SPDX-License-Identifier: GPL-2.0-or-later
// Independent source-derived truth matrix and explicit native transports.
@[has_globals; translated]
module cpubugfixture

#include "contract.h"

@[typedef]
struct C.cbh_array {
mut:
	data         voidptr
	len          i64
	cap          i64
	element_size i64
}

@[typedef]
struct C.cbh_string {
	str &u8
	len i64
}

@[typedef]
struct C.cbh_jump {}

@[typedef]
struct C.cbh_thread {}

fn C.memcpy(voidptr, voidptr, usize) voidptr
fn C.memset(voidptr, int, usize) voidptr
fn C.memcmp(voidptr, voidptr, usize) int
fn C.strstr(&char, &char) &char
fn C.printf(&char, ...)
fn C.puts(&char) int

@[noreturn]
fn C.exit(int)

fn C.cbh_setjmp(voidptr) int

@[noreturn]
fn C.cbh_longjmp(voidptr)

fn C.pthread_create(voidptr, voidptr, fn (voidptr) voidptr, voidptr) int
fn C.pthread_join(C.cbh_thread, voidptr) int
fn C.sched_yield() int

@[c: '__atomic_load_n']
fn C.load32(&u32, int) u32

@[c: '__atomic_load_n']
fn C.load64(&u64, int) u64

@[c: '__atomic_store_n']
fn C.store32(&u32, u32, int)

@[c: '__atomic_fetch_add']
fn C.add32(&u32, u32, int) u32

fn C.cpu__linuxkpi_classify_l1tf(u32, u32, u32, u32, u64) bool
fn C.cpu__linuxkpi_sample_l1tf() u32
fn C.cpubug_configure(i64, u32)
fn C.cpubug_initialize()
fn C.cpubug_state(int) u32
fn C.cpubug_seed_ready(u32)
fn C.vinix_linuxkpi_boot_cpu_has_bug(u32) bool
fn C.boot_cpu_has_bug(...) bool

@[c_extern]
__global C.X86_BUG_L1TF u32

pub struct Local {
pub mut:
	cpu_number           u64
	online               u64
	linuxkpi_l1tf_sample u32
}

struct OracleEntry {
	vendor int
	family int
	model  int
	flags  u32
}

struct Vendor {
	b        u32
	d        u32
	c        u32
	identity int
}

__global (
	records          [257]Local
	members          [257]&Local
	baseline         [257]Local
	slots            [3]&u32
	prior            [3]u32
	load_count       u32
	store_count      u32
	array_count      u32
	cpuid_count      u32
	msr_count        u32
	prior_store      u32
	prior_cpuid      u32
	prior_msr        u32
	expected_message &char
	jump_target      voidptr
	sampler_irq      bool
	sample_available u32
	sample_max       u32
	sample_vendor    Vendor
	sample_signature u32
	sample_edx       u32
	sample_caps      u64
	sample_msr_ok    bool
	sample_phase     u32
	dynamic_count    u32
	matrix_cases     u64
	sampler_cases    u32
	fatal_cases      u32
)

pub fn require(condition bool, code int) {
	if !condition {
		C.printf(c'FAIL: CPU bug condition %d, matrix=%llu sampler=%u fatal=%u\n', code, matrix_cases, sampler_cases, fatal_cases)
		C.exit(1)
	}
}

@[direct_array_access]
pub fn configure(descriptor voidptr, count i64, sample u32) {
	for i in 0 .. 257 {
		records[i] = Local{ cpu_number: u64(i), online: 1, linuxkpi_l1tf_sample: sample }
		members[i] = unsafe { &records[i] }
	}
	mut value := unsafe { &C.cbh_array(descriptor) }
	unsafe { C.memset(value, 0, sizeof(C.cbh_array)) }
	value.data = unsafe { &members[0] }
	value.len = count
	value.cap = count
	value.element_size = sizeof(&Local)
	load_count = 0
	store_count = 0
	array_count = 0
	cpuid_count = 0
	msr_count = 0
}

@[direct_array_access]
pub fn register_slots(a &u32, b &u32, c &u32) {
	slots[0] = a
	slots[1] = b
	slots[2] = c
}

@[direct_array_access]
pub fn set_member(position int, field int, value u64) {
	require(position >= 0 && position < 257, 1)
	match field {
		0 { members[position] = unsafe { nil } }
		1 { records[position].online = value }
		2 { records[position].cpu_number = value }
		3 { records[position].linuxkpi_l1tf_sample = u32(value) }
		else { require(false, 2) }
	}
}

pub fn load[T](value &T) T {
	unsafe { C.add32(&load_count, 1, 0) }
	if sizeof(T) == 8 { return T(unsafe { C.load64(&u64(value), 2) }) }
	return T(unsafe { C.load32(&u32(value), 2) })
}

@[direct_array_access]
pub fn store(value &u32, item u32) {
	require(value == slots[2] && item == 1, 3)
	require((unsafe { C.load32(slots[0], 2) } == 1 || unsafe { C.load32(slots[0], 2) } == 2) && unsafe { C.load32(slots[1], 2) } >= 1 && unsafe { C.load32(slots[1], 2) } <= 256, 4)
	unsafe {
		C.add32(&store_count, 1, 0)
		C.store32(value, item, 3)
	}
}

@[direct_array_access]
pub fn capture() {
	unsafe { C.memcpy(&baseline[0], &records[0], sizeof(baseline)) }
	for i in 0 .. 3 { prior[i] = unsafe { C.load32(slots[i], 2) } }
	prior_store = store_count
	prior_cpuid = cpuid_count
	prior_msr = msr_count
}

@[direct_array_access]
pub fn same_records() bool {
	return unsafe { C.memcmp(&baseline[0], &records[0], sizeof(baseline)) } == 0
}

@[direct_array_access]
pub fn same_state() bool {
	for i in 0 .. 3 { if prior[i] != unsafe { C.load32(slots[i], 2) } { return false } }
	return same_records() && prior_store == store_count && prior_cpuid == cpuid_count && prior_msr == msr_count
}

@[noreturn]
pub fn fatal(message &char) {
	if jump_target != unsafe { nil } {
		require(same_state(), 5)
		require(unsafe { C.strstr(message, expected_message) } != unsafe { nil }, 6)
		C.cbh_longjmp(jump_target)
	}
	C.printf(c'FAIL: unexpected CPU bug panic: %s\n', message)
	C.exit(1)
}

@[export:'array_get']
pub fn borrowed_index(value C.cbh_array, index i64) voidptr {
	require(index >= 0 && index < value.len && value.data != unsafe { nil } && value.element_size == sizeof(&Local), 7)
	array_count++
	return unsafe { voidptr(usize(value.data) + usize(index) * usize(value.element_size)) }
}

@[export:'v_panic']
@[noreturn]
pub fn unexpected_v_panic(message C.cbh_string) { fatal(unsafe { &char(message.str) }) }

pub fn interrupt_state() bool { return sampler_irq }

pub fn cpuid(leaf u32, subleaf u32) (bool, u32, u32, u32, u32) {
	require(!sampler_irq && subleaf == 0, 8)
	cpuid_count++
	match sample_phase {
		0 {
			require(leaf == 0, 9)
			sample_phase = 1
			return sample_available & 1 != 0, sample_max, sample_vendor.b, sample_vendor.c, sample_vendor.d
		}
		1 {
			require(leaf == 1, 10)
			sample_phase = 2
			return sample_available & 2 != 0, sample_signature, 0, 0, 0
		}
		else {
			require(sample_phase == 2 && leaf == 7 && sample_max >= 7, 11)
			sample_phase = 3
			return sample_available & 4 != 0, 0, 0, 0, sample_edx
		}
	}
}

@[export:'x86_rdmsr_safe']
pub fn safe_msr(index u32, value &u64) bool {
	require(!sampler_irq && sample_phase == 3 && sample_available & 4 != 0 && sample_edx & (u32(1) << 29) != 0 && index == 0x10a, 12)
	msr_count++
	sample_phase = 4
	unsafe { *value = sample_caps }
	return sample_msr_ok
}

fn signature(base u32, extended u32, model u32) u32 {
	return (base << 8) | (extended << 20) | ((model & 15) << 4) | ((model >> 4) << 16)
}

// This generic interpreter consumes all source-derived whitelist entries in
// their original order. It does not reproduce the new classifier's branches.
@[direct_array_access]
fn oracle(vendor int, raw u32, caps u64) bool {
	mut family := (raw >> 8) & 15
	if family == 15 { family += (raw >> 20) & 255 }
	model := ((raw >> 4) & 15) + (if family >= 6 { ((raw >> 16) & 15) << 4 } else { u32(0) })
	stored_family := int(u8(family))
	mut flags := u32(0)
	for row in 0 .. oracle_entry_count {
		entry := original_entry(row)
		if (entry.vendor == -1 || entry.vendor == vendor) && (entry.family == 0 || entry.family == stored_family) && (entry.model == 0 || entry.model == int(model)) {
			flags = entry.flags
			break
		}
	}
	return flags & 1 == 0 && flags & 2 == 0 && caps & 1 == 0 && flags & 8 == 0
}

@[direct_array_access]
fn compare(vendor Vendor, raw u32, caps u64) {
	expected := oracle(vendor.identity, raw, caps)
	actual := C.cpu__linuxkpi_classify_l1tf(vendor.b, vendor.d, vendor.c, raw, caps)
	if actual != expected {
		C.printf(c'FAIL: L1TF matrix vendor=%d signature=%x caps=%llx expected=%d actual=%d\n', vendor.identity, raw, caps, expected, actual)
		C.exit(1)
	}
	matrix_cases++
}

@[direct_array_access]
fn classifier_matrix() {
	for vendor_index in 0 .. oracle_vendor_count {
		vendor := original_vendor(vendor_index)
		for base in u32(0) .. u32(16) {
			for model in u32(0) .. u32(256) {
				for extended in [u32(0), u32(1), u32(244), u32(245), u32(246), u32(247), u32(255)]! {
					raw := signature(base, extended, model)
					for caps in [u64(0), u64(1), u64(0xfffffffffffffe), ~u64(0)]! {
						compare(vendor, raw, caps)
						// Stepping, processor type and reserved high/low holes must not alter it.
						compare(vendor, raw | 0xf000f00f, caps)
					}
				}
			}
		}
		// Every extended-family value and full-model boundary, including u8 aliases.
		for extended in u32(0) .. u32(256) {
			for model in [u32(0), u32(0x1c), u32(0x5c), u32(0x8c), u32(0xff)]! {
				compare(vendor, signature(15, extended, model), 0)
			}
		}
		// Each corrupted vendor word is unknown, rather than a partial-name alias.
		for word in 0 .. 3 {
			mut altered := vendor
			altered.identity = 255
			match word {
				0 { altered.b ^= 1 }
				1 { altered.d ^= 1 }
				else { altered.c ^= 1 }
			}
			for family in [u32(4), u32(5), u32(6), u32(15)]! {
				for model in [u32(0x1c), u32(0x37), u32(0x5c), u32(0x8c)]! {
					compare(altered, signature(family, 0, model), 0)
				}
			}
		}
	}
}

@[direct_array_access]
fn sampler_matrix() {
	for vendor_index in 0 .. oracle_vendor_count {
		vendor := original_vendor(vendor_index)
		for raw in [signature(6, 0, 0x8c), signature(6, 0, 0x5c), signature(4, 0, 0),
			signature(15, 245, 0x1c)]! {
			for max_leaf in [u32(0), u32(1), u32(6), u32(7), u32(0xffffffff)]! {
				for available in u32(0) .. u32(8) {
					for advertised in [false, true]! {
						for okay in [false, true]! {
							for caps in [u64(0), u64(1), u64(0xfffffffffffffffe)]! {
								for irq in [false, true]! {
									sample_vendor = vendor
									sample_signature = raw
									sample_max = max_leaf
									sample_available = available
									sample_edx = (if advertised { u32(1) << 29 } else { u32(0) }) | 0x84214681
									sample_caps = caps
									sample_msr_ok = okay
									sample_phase = 0
									sampler_irq = irq
									cpuid_count = 0
									msr_count = 0
									result := C.cpu__linuxkpi_sample_l1tf()
									mut expected := u32(0)
									mut probes := u32(0)
									mut reads := u32(0)
									if !irq {
										probes = 1
										if available & 1 != 0 && max_leaf >= 1 {
											probes = 2
											if available & 2 != 0 {
												if max_leaf >= 7 { probes = 3 }
												if max_leaf < 7 || available & 4 != 0 {
													if max_leaf >= 7 && advertised { reads = 1 }
													if reads == 0 || okay {
														expected = if oracle(vendor.identity, raw, if reads == 1 {
															caps
														} else {
															u64(0)
														}) {
															u32(2)
														} else {
															u32(1)
														}
													}
												}
											}
										}
									}
									require(result == expected && cpuid_count == probes && msr_count == reads && sampler_irq == irq, 13)
									sampler_cases++
								}
							}
						}
					}
				}
			}
		}
	}
	sampler_irq = false
}

fn failure(kind int, bit u32, text &char) {
	mut target := C.cbh_jump{}
	capture()
	expected_message = text
	jump_target = unsafe { &target }
	if C.cbh_setjmp(unsafe { &target }) == 0 {
		match kind {
			0 { C.cpubug_initialize() }
			1 { C.vinix_linuxkpi_boot_cpu_has_bug(bit) }
			2 { C.boot_cpu_has_bug(once(bit)) }
			else { require(false, 14) }
		}
		require(false, 15)
	}
	jump_target = unsafe { nil }
	expected_message = unsafe { nil }
	fatal_cases++
}

fn once(value u32) u32 {
	dynamic_count++
	return value
}

@[direct_array_access]
fn membership_matrix() {
	for count in [1, 2, 4, 64, 65, 128, 256]! {
		for boot in [u32(1), u32(2)]! {
			for ap in [u32(1), u32(2)]! {
				C.cpubug_configure(i64(count), ap)
				set_member(0, 3, boot)
				capture()
				C.cpubug_initialize()
				require(same_records() && C.cpubug_state(0) == boot && C.cpubug_state(1) == u32(count) && C.cpubug_state(2) == 1 && store_count == 1, 16)
				require(C.boot_cpu_has_bug(C.X86_BUG_L1TF) == (boot == 2), 17)
				before_dynamic := dynamic_count
				require(C.boot_cpu_has_bug(once(722)) == (boot == 2) && dynamic_count == before_dynamic + 1, 25)
				for i in 0 .. count { set_member(i, 3, if boot == 2 { u64(1) } else { u64(2) }) }
				before_cpuid := cpuid_count
				before_msr := msr_count
				for irq in [false, true]! {
					sampler_irq = irq
					for _ in 0 .. 1000 {
						require(C.vinix_linuxkpi_boot_cpu_has_bug(722) == (boot == 2), 18)
					}
				}
				require(cpuid_count == before_cpuid && msr_count == before_msr && store_count == 1, 19)
				failure(0, 0, c'initialized twice')
			}
		}
	}
	for count in [i64(-1), i64(0), i64(257), i64(2147483647), i64(9223372036854775807),
		i64(0x100000001)]! {
		C.cpubug_configure(count, 1)
		failure(0, 0, c'invalid CPU bug policy membership')
	}
	for index in 0 .. 256 {
		for variant in 0 .. 9 {
			C.cpubug_configure(256, 1)
			match variant {
				0 { set_member(index, 0, 0) }
				1 { set_member(index, 1, 0) }
				2 { set_member(index, 1, 2) }
				3 { set_member(index, 1, 0x100000001) }
				4 { set_member(index, 2, u64(index + 1)) }
				5 { set_member(index, 2, u64(index) + 0x100000000) }
				6 { set_member(index, 3, 0) }
				7 { set_member(index, 3, 3) }
				else { set_member(index, 3, 0xffffffff) }
			}
			failure(0, 0, if variant < 6 {
				c'not acknowledged'
			} else {
				c'unresolved CPU L1TF observation'
			})
		}
	}
	C.cpubug_configure(256, 1)
	set_member(0, 3, 2)
	set_member(255, 3, 0)
	failure(0, 0, c'unresolved CPU L1TF observation')
	for ready in [u32(0), u32(2), u32(0xffffffff)]! {
		C.cpubug_configure(4, 1)
		C.cpubug_seed_ready(ready)
		failure(1, 722, c'not initialized')
		if ready != 0 { failure(0, 0, c'initialized twice') }
	}
	for initialized in [false, true]! {
		C.cpubug_configure(4, 2)
		if initialized { C.cpubug_initialize() }
		for bit in [u32(0), u32(18), u32(519), u32(704), u32(721), u32(723), u32(735), u32(1024),
			~u32(0)]! {
			failure(1, bit, c'unsupported CPU bug query')
			before := dynamic_count
			failure(2, bit, c'unsupported CPU bug query')
			require(dynamic_count == before + 1, 20)
		}
	}
}

fn query_actor(_argument voidptr) voidptr {
	for round in 0 .. 20000 {
		require(C.boot_cpu_has_bug(once_concurrent()) && C.vinix_linuxkpi_boot_cpu_has_bug(722), 21)
		if round % 1024 == 0 { C.sched_yield() }
	}
	return unsafe { nil }
}

fn once_concurrent() u32 { return 722 }

@[direct_array_access]
fn concurrent_queries() {
	C.cpubug_configure(256, 1)
	set_member(0, 3, 2)
	C.cpubug_initialize()
	capture()
	mut actors := [8]C.cbh_thread{}
	for i in 0 .. 8 {
		require(C.pthread_create(unsafe { &actors[i] }, unsafe { nil }, query_actor, unsafe { nil }) == 0, 22)
	}
	for i in 0 .. 8 { require(C.pthread_join(actors[i], unsafe { nil }) == 0, 23) }
	require(same_state(), 24)
}

@[export:'main']
pub fn run() int {
	classifier_matrix()
	sampler_matrix()
	membership_matrix()
	concurrent_queries()
	C.printf(c'PASS: V L1TF source-derived matrix=%llu sampler=%u fatal=%u; BSP-only immutable query and concurrent readers\n', matrix_cases, sampler_cases, fatal_cases)
	return 0
}
