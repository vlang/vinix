// SPDX-License-Identifier: GPL-2.0-or-later
// Independent ACPI gate fixture retaining the original tests and slab equality.
@[translated]
module nativefixture

#include "native-abi.h"
@[typedef]
struct C.pthread_t {}
@[typedef]
struct C.vacpi_ull {}
fn C.memcpy(voidptr, voidptr, usize) voidptr
type WorkerCallback = fn (voidptr) voidptr
fn C.pthread_create(voidptr, voidptr, WorkerCallback, voidptr) i32
fn C.pthread_join(C.pthread_t, voidptr) i32
fn C.pthread_exit(voidptr)
fn C.vinix_acpi_sync_create(bool) voidptr
fn C.vinix_acpi_sync_destroy(voidptr) bool
fn C.vinix_acpi_sync_wait(voidptr, u16) i32
fn C.vinix_acpi_sync_signal(voidptr) bool
fn C.vinix_acpi_sync_reset(voidptr)
fn C.vinix_acpi_sync_sleep(u64)
fn C.vinix_acpi_sync_clock_ns() u64
fn C.vinix_acpi_sync_thread_id() u64
fn C.vinix_acpi_sync_heap_snapshot(&u64)
fn C.vinix_acpi_fixture_mutex_worker(voidptr) voidptr
fn C.vinix_acpi_fixture_event_worker(voidptr) voidptr
fn C.vinix_acpi_fixture_wrong_owner(voidptr) voidptr
fn C.vinix_acpi_fixture_delayed_signal(voidptr) voidptr
fn C.kprintf(&char, ...) i32
fn C.serial__out(i8)
@[c: '__atomic_add_fetch'] fn C.add(&u32, u32, i32) u32
@[c: '__atomic_sub_fetch'] fn C.sub(&u32, u32, i32) u32
@[c: '__atomic_load_n'] fn C.load(&u32, i32) u32

fn log(message &char) {
	C.kprintf(c'%s', message)
	$if amd64 {
		unsafe { for cursor := message; *cursor != 0; cursor++ { C.serial__out(i8(*cursor)) } }
	}
}

fn check(condition bool, original_line u32) bool {
	if !condition {
		C.kprintf(c'FAIL: ACPI sync at line %u\n', original_line)
		log(c'FAIL: ACPI sync native self-test\n')
	}
	return condition
}

fn unsigned_long_long(value u64) C.vacpi_ull {
	mut native := C.vacpi_ull{}
	unsafe { C.memcpy(&native, &value, sizeof(u64)) }
	return native
}

fn counter_and_timeouts() i32 {
	unsafe {
		event := C.vinix_acpi_sync_create(false)
		mutex := C.vinix_acpi_sync_create(true)
		if !check(event != nil && mutex != nil && C.vinix_acpi_sync_thread_id() != 0, 37) { return -1 }
		if !check(C.vinix_acpi_sync_wait(nil, 0) == 7, 38) { return -1 }
		if !check(C.vinix_acpi_sync_wait(event, 0) == 18, 39) { return -1 }
		if !check(C.vinix_acpi_sync_wait(mutex, 0) == 0, 40) { return -1 }
		if !check(C.vinix_acpi_sync_wait(mutex, 0) == 18, 41) { return -1 }
		if !check(!C.vinix_acpi_sync_destroy(mutex), 42) { return -1 }
		if !check(C.vinix_acpi_sync_signal(mutex), 43) { return -1 }
		if !check(!C.vinix_acpi_sync_signal(mutex), 44) { return -1 }
		if !check(C.vinix_acpi_sync_signal(event), 45) { return -1 }
		if !check(C.vinix_acpi_sync_signal(event), 46) { return -1 }
		if !check(C.vinix_acpi_sync_wait(event, 0) == 0, 47) { return -1 }
		if !check(C.vinix_acpi_sync_wait(event, 0) == 0, 48) { return -1 }
		if !check(C.vinix_acpi_sync_wait(event, 0) == 18, 49) { return -1 }
		if !check(C.vinix_acpi_sync_signal(event), 50) { return -1 }
		C.vinix_acpi_sync_reset(event)
		if !check(C.vinix_acpi_sync_wait(event, 0) == 18, 52) { return -1 }
		mut before := C.vinix_acpi_sync_clock_ns()
		if !check(C.vinix_acpi_sync_wait(event, 3) == 18, 54) { return -1 }
		if !check(C.vinix_acpi_sync_clock_ns() - before >= 3000000, 55) { return -1 }
		before = C.vinix_acpi_sync_clock_ns()
		C.vinix_acpi_sync_sleep(2)
		if !check(C.vinix_acpi_sync_clock_ns() - before >= 2000000, 58) { return -1 }
		if !check(C.vinix_acpi_sync_destroy(event), 59) { return -1 }
		if !check(C.vinix_acpi_sync_destroy(mutex), 60) { return -1 }
		return 0
	}
}

@[export: 'vinix_acpi_sync_boot_test']
pub fn boot_test() i32 {
	if !check(counter_and_timeouts() == 0, 66) { return -1 }
	log(c'ACPI-SYNC: bootstrap polling PASS\n')
	return 0
}

struct Workers {
mut:
	mutex voidptr
	event voidptr
	identities [4]u64
	ready u32
	successes u32
	failures u32
	counter u32
	in_section u32
}
struct Worker {
mut:
	shared &Workers = unsafe { nil }
	index u32
}

@[export: 'vinix_acpi_fixture_mutex_worker']
pub fn mutex_worker(argument voidptr) voidptr {
	unsafe {
		worker := &Worker(argument)
		mut shared := worker.shared
		shared.identities[worker.index] = C.vinix_acpi_sync_thread_id()
		C.add(&shared.ready, 1, 3)
		if C.vinix_acpi_sync_wait(shared.event, u16(-1)) != 0 {
			C.add(&shared.failures, 1, 0)
			C.pthread_exit(nil)
		}
		for _ in 0 .. 1000 {
			if C.vinix_acpi_sync_wait(shared.mutex, u16(-1)) != 0 { C.add(&shared.failures, 1, 0); break }
			if C.add(&shared.in_section, 1, 0) != 1 { C.add(&shared.failures, 1, 0) }
			shared.counter++
			C.sub(&shared.in_section, 1, 0)
			if !C.vinix_acpi_sync_signal(shared.mutex) { C.add(&shared.failures, 1, 0) }
		}
		C.pthread_exit(nil)
		return nil
	}
}

@[export: 'vinix_acpi_fixture_event_worker']
pub fn event_worker(argument voidptr) voidptr {
	unsafe {
		worker := &Worker(argument)
		shared := worker.shared
		C.add(&shared.ready, 1, 3)
		result := C.vinix_acpi_sync_wait(shared.event, 200)
		if result == 0 { C.add(&shared.successes, 1, 0) }
		else if result != 18 { C.add(&shared.failures, 1, 0) }
		C.pthread_exit(nil)
		return nil
	}
}

@[export: 'vinix_acpi_fixture_wrong_owner']
pub fn wrong_owner(argument voidptr) voidptr {
	unsafe {
		shared := &Workers(argument)
		if C.vinix_acpi_sync_signal(shared.mutex) { C.add(&shared.failures, 1, 0) }
		C.pthread_exit(nil)
		return nil
	}
}

@[export: 'vinix_acpi_fixture_delayed_signal']
pub fn delayed_signal(argument voidptr) voidptr {
	C.vinix_acpi_sync_sleep(5)
	C.vinix_acpi_sync_signal(argument)
	unsafe { C.pthread_exit(nil); return nil }
}

@[export: 'vinix_acpi_sync_native_test']
pub fn native_test() i32 {
	unsafe {
		if !check(counter_and_timeouts() == 0, 140) { return -1 }
		mut shared := Workers{}
		mut workers := [4]Worker{}
		mut threads := [4]C.pthread_t{}
		shared.mutex = C.vinix_acpi_sync_create(true)
		shared.event = C.vinix_acpi_sync_create(false)
		if !check(shared.mutex != nil && shared.event != nil, 146) { return -1 }
		if !check(C.vinix_acpi_sync_wait(shared.mutex, 0) == 0, 147) { return -1 }
		if !check(C.pthread_create(&threads[0], nil, C.vinix_acpi_fixture_wrong_owner, &shared) == 0, 148) { return -1 }
		if !check(C.pthread_join(threads[0], nil) == 0, 149) { return -1 }
		if !check(shared.failures == 0, 150) { return -1 }
		if !check(C.vinix_acpi_sync_wait(shared.mutex, 0) == 18, 151) { return -1 }
		if !check(C.vinix_acpi_sync_signal(shared.mutex), 152) { return -1 }
		for i in 0 .. 4 {
			workers[i].shared = &shared
			workers[i].index = u32(i)
			if !check(C.pthread_create(&threads[i], nil, C.vinix_acpi_fixture_mutex_worker, &workers[i]) == 0, 156) { return -1 }
		}
		for C.load(&shared.ready, 2) != 4 { C.vinix_acpi_sync_sleep(1) }
		for _ in 0 .. 4 { if !check(C.vinix_acpi_sync_signal(shared.event), 160) { return -1 } }
		for i in 0 .. 4 { if !check(C.pthread_join(threads[i], nil) == 0, 161) { return -1 } }
		if !check(shared.counter == 4000 && shared.failures == 0 && shared.in_section == 0, 162) { return -1 }
		for i in 0 .. 4 {
			if !check(shared.identities[i] != 0 && shared.identities[i] != C.vinix_acpi_sync_thread_id(), 164) { return -1 }
			for j in 0 .. i { if !check(shared.identities[i] != shared.identities[j], 165) { return -1 } }
		}
		log(c'ACPI-SYNC: mutex exclusion and thread identity PASS\n')
		shared.ready = 0
		for i in 0 .. 4 { if !check(C.pthread_create(&threads[i], nil, C.vinix_acpi_fixture_event_worker, &workers[i]) == 0, 172) { return -1 } }
		for C.load(&shared.ready, 2) != 4 { C.vinix_acpi_sync_sleep(1) }
		C.vinix_acpi_sync_sleep(5)
		if !check(!C.vinix_acpi_sync_destroy(shared.event), 175) { return -1 }
		if !check(C.vinix_acpi_sync_signal(shared.event), 176) { return -1 }
		for i in 0 .. 4 { if !check(C.pthread_join(threads[i], nil) == 0, 177) { return -1 } }
		if !check(shared.successes == 1 && shared.failures == 0, 178) { return -1 }
		if !check(C.pthread_create(&threads[0], nil, C.vinix_acpi_fixture_delayed_signal, shared.event) == 0, 179) { return -1 }
		if !check(C.vinix_acpi_sync_wait(shared.event, 100) == 0, 180) { return -1 }
		if !check(C.pthread_join(threads[0], nil) == 0, 181) { return -1 }
		if !check(C.pthread_create(&threads[0], nil, C.vinix_acpi_fixture_delayed_signal, shared.event) == 0, 182) { return -1 }
		if !check(C.vinix_acpi_sync_wait(shared.event, u16(-1)) == 0, 183) { return -1 }
		if !check(C.pthread_join(threads[0], nil) == 0, 184) { return -1 }
		if !check(C.vinix_acpi_sync_wait(shared.event, 0) == 18, 185) { return -1 }
		if !check(C.vinix_acpi_sync_destroy(shared.event), 186) { return -1 }
		if !check(C.vinix_acpi_sync_destroy(shared.mutex), 187) { return -1 }
		log(c'ACPI-SYNC: one permit, reset, finite and infinite waits PASS\n')
		for _ in 0 .. 8 { if !check(counter_and_timeouts() == 0, 192) { return -1 } }
		mut before := [18]u64{}
		mut after := [18]u64{}
		C.vinix_acpi_sync_heap_snapshot(&before[0])
		for _ in 0 .. 200 { if !check(counter_and_timeouts() == 0, 195) { return -1 } }
		C.vinix_acpi_sync_heap_snapshot(&after[0])
		for i in 0 .. 18 {
			if before[i] != after[i] {
				C.kprintf(c'ACPI-SYNC: slab class %u before=%llu after=%llu\n', u32(i), unsigned_long_long(before[i]), unsigned_long_long(after[i]))
			}
			if !check(before[i] == after[i], 201) { return -1 }
		}
		log(c'ACPI-SYNC: 200 repeated gate/timer lifetimes, every slab class flat PASS\n')
		log(c'ACPI-SYNC: ALL PASS\n')
		return 0
	}
}
