// SPDX-License-Identifier: GPL-2.0-or-later
// Single-threaded diagnostic for V-managed allocations, not libc/kernel heap.
module main

import os
import tools.packages.wineadapter

#include <sys/resource.h>
#include <fcntl.h>
#include <unistd.h>
#include <errno.h>
struct C.rlimit { mut: rlim_cur u64 rlim_max u64 }
fn C.getrlimit(i32, &C.rlimit) i32
fn C.setrlimit(i32, &C.rlimit) i32
fn C.open(&char, i32, ...i32) i32
fn C.close(i32) i32

struct HeapSlot { mut: pointer u64 bytes u64 }
__global (
	heap_slots [65536]HeapSlot
	heap_enabled bool
	heap_failed bool
	heap_bytes u64
	heap_objects u64
)

// Fixed storage and integer operations only: allocation hooks cannot allocate.
@[export: 'vheap_alloc']
fn heap_alloc(pointer voidptr, bytes u64) {
	if !heap_enabled || pointer == unsafe { nil } { return }
	key := u64(pointer)
	mut slot := int((key >> 4) & 65535)
	for _ in 0 .. 65536 {
		if heap_slots[slot].pointer <= 1 {
			heap_slots[slot] = HeapSlot{pointer: key, bytes: bytes}
			heap_bytes += bytes; heap_objects++
			return
		}
		if heap_slots[slot].pointer == key { heap_failed = true; return }
		slot = (slot + 1) & 65535
	}
	heap_failed = true
}

@[export: 'vheap_free']
fn heap_free(pointer voidptr) {
	if !heap_enabled || pointer == unsafe { nil } { return }
	key := u64(pointer)
	mut slot := int((key >> 4) & 65535)
	for _ in 0 .. 65536 {
		if heap_slots[slot].pointer == 0 { return }
		if heap_slots[slot].pointer == key {
			heap_bytes -= heap_slots[slot].bytes; heap_objects--
			heap_slots[slot] = HeapSlot{pointer: 1}
			return
		}
		slot = (slot + 1) & 65535
	}
}

fn verify_hooks() ! {
	heap_enabled = true
	block := unsafe { malloc(37) }
	allocated := heap_bytes == 37 && heap_objects == 1
	unsafe { free(block) }
	freed := heap_bytes == 0 && heap_objects == 0
	heap_enabled = false
	if !allocated || !freed || heap_failed { return error('allocation/free hook control failed') }
}

fn require_empty(label string, cycles int) ! {
	heap_enabled = false
	println('WINE BINDING HEAP phase=${label} cycles=${cycles} live_objects=${heap_objects} live_bytes=${heap_bytes}')
	if heap_failed { return error('allocation tracker overflow or duplicate allocation') }
	if heap_objects != 0 || heap_bytes != 0 { return error('binding phase retains V-managed allocations: ' + label) }
}

fn sample(data string, builtins string, store string, cycles int) ! {
	heap_enabled = true
	for _ in 0 .. cycles {
		mut review := wineadapter.review_prefix_bindings(data, builtins, store) or {
			heap_enabled = false
			return err
		}
		review.close()
	}
	require_empty('review', cycles)!
	mut idle := wineadapter.capture_idle_binding_review(data, builtins, store)!
	defer { idle.close() }
	heap_enabled = true
	for _ in 0 .. cycles {
		idle.recheck() or { heap_enabled = false; return err }
	}
	require_empty('idle-recheck', cycles)!
	idle.close()
	heap_enabled = true
	for _ in 0 .. cycles {
		mut current := wineadapter.capture_idle_binding_review(data, builtins, store) or {
			heap_enabled = false
			return err
		}
		current.migrate_bindings() or { current.close(); heap_enabled = false; return err }
		current.close()
	}
	require_empty('capture-repeat-close', cycles)!
}

fn refused_capture(data string, builtins string, store string, expected string) ! {
	if mut unexpected := wineadapter.capture_idle_binding_review(data, builtins, store) {
		unexpected.close()
		return error('unsafe capture unexpectedly succeeded')
	} else {
		matches := err.msg().contains(expected)
		unsafe { err.free() }
		if !matches { return error('capture refusal reason differs') }
	}
}

// Count available descriptors without /proc or allocation. The process has a
// verified soft limit of 32. Always close only the descriptors opened here.
fn spare_descriptors() !int {
	mut fds := [32]i32{}
	mut count := 0
	defer { for index in 0 .. count { C.close(fds[index]) } }
	for count < fds.len {
		fd := C.open(c'/dev/null', C.O_RDONLY | C.O_CLOEXEC)
		if fd < 0 {
			if C.errno != C.EMFILE { return error('descriptor probe failed before the soft limit') }
			return count
		}
		fds[count] = fd
		count++
	}
	return error('descriptor probe did not reach the soft limit')
}

fn require_descriptors(expected int) ! {
	if spare_descriptors()! != expected { return error('refusal phase retained descriptors') }
}

fn verify_descriptor_probe() ! {
	before := spare_descriptors()!
	fd := C.open(c'/dev/null', C.O_RDONLY | C.O_CLOEXEC)
	if fd < 0 { return error('cannot create descriptor control') }
	defer { C.close(fd) }
	require_descriptors(before - 1)!
}

fn sample_refusals(data string, builtins string, store string, cycles int) ! {
	link := data + '/wine/drive_c/windows/system32/0.dll'
	os.rm(link)!
	os.write_file(link, 'personal DLL')!
	initial_fds := spare_descriptors()!
	heap_enabled = true
	for _ in 0 .. cycles {
		refused_capture(data, builtins, store, 'requires existing bounded symlinks') or { heap_enabled = false; return err }
	}
	require_empty('personal-file-refusal', cycles)!
	require_descriptors(initial_fds)!
	if os.read_file(link)! != 'personal DLL' { return error('refusal changed personal DLL') }
	os.rm(link)!; os.symlink(builtins + '/0.dll', link)!
	os.write_file(builtins + '/0.dll', '')!
	heap_enabled = true
	for _ in 0 .. cycles {
		refused_capture(data, builtins, store, 'between 1 byte and 64 MiB') or { heap_enabled = false; return err }
	}
	require_empty('empty-asset-refusal', cycles)!
	require_descriptors(initial_fds)!
	if os.file_size(builtins + '/0.dll') != 0 || os.readlink(link)! != builtins + '/0.dll' {
		return error('refusal changed empty asset or prefix link')
	}
	os.write_file(builtins + '/0.dll', 'marker')!
	mut owner := wineadapter.capture_idle_binding_review(data, builtins, store)!
	defer { owner.close() }
	held_fds := spare_descriptors()!
	heap_enabled = true
	for _ in 0 .. cycles {
		refused_capture(data, builtins, store, 'already has a managed launch') or { heap_enabled = false; return err }
	}
	require_empty('competing-capture-refusal', cycles)!
	require_descriptors(held_fds)!
	owner.recheck()!
	stage := data + '/wine/.vinix-builtin-next'
	os.write_file(stage, 'personal stage')!
	heap_enabled = true
	for _ in 0 .. cycles {
		mut refused := false
		owner.migrate_bindings() or {
			refused = err.msg().contains('stage must be a bounded symlink')
			unsafe { err.free() }
		}
		if !refused { heap_enabled = false; return error('personal stage migration refusal differs') }
	}
	require_empty('personal-stage-refusal', cycles)!
	require_descriptors(held_fds)!
	if os.read_file(stage)! != 'personal stage' { return error('refusal changed personal stage') }
	os.rm(stage)!
	owner.close()
	mut recovered := wineadapter.capture_idle_binding_review(data, builtins, store)!
	recovered.migrate_bindings() or { recovered.close(); return err }
	recovered.close()
	require_descriptors(initial_fds)!
	println('WINE BINDING REFUSALS PASS four phases; heap and descriptor release; preserved personal data; recapture')
}

fn pressure_capture(data string, builtins string, store string, headroom int) !bool {
	available := spare_descriptors()!
	if headroom < 0 || headroom > available { return error('invalid descriptor headroom') }
	mut held := [32]i32{}
	mut count := 0
	defer { for index in 0 .. count { C.close(held[index]) } }
	for count < available - headroom {
		fd := C.open(c'/dev/null', C.O_RDONLY | C.O_CLOEXEC)
		if fd < 0 { return error('cannot establish descriptor pressure') }
		held[count] = fd
		count++
	}
	require_descriptors(headroom)!
	mut accepted := false
	mut saved_errno := i32(0)
	C.errno = 0
	heap_enabled = true
	if mut owner := wineadapter.capture_idle_binding_review(data, builtins, store) {
		accepted = true
		owner.close()
	} else {
		saved_errno = C.errno
		unsafe { err.free() }
	}
	heap_enabled = false
	if !accepted && saved_errno != C.EMFILE { return error('pressured capture failed without EMFILE: ' + saved_errno.str()) }
	require_empty('capture-headroom-' + headroom.str(), 1)!
	require_descriptors(headroom)!
	println('WINE BINDING PRESSURE headroom=${headroom} accepted=${accepted}')
	return accepted
}

fn sample_descriptor_exhaustion(data string, builtins string, store string) ! {
	available := spare_descriptors()!
	mut failures := 0
	mut successes := 0
	for headroom in 0 .. available + 1 {
		if pressure_capture(data, builtins, store, headroom)! { successes++ } else { failures++ }
		require_descriptors(available)!
		// Restoring the budget must make the same prefix admissible after every
		// failed or successful construction, proving guard release too.
		mut recovered := wineadapter.capture_idle_binding_review(data, builtins, store)!
		valid := recovered.review.prior_generation == 0 && recovered.review.bindings.all(it.operation == .keep)
		recovered.close()
		if !valid { return error('descriptor pressure changed prefix bindings') }
		require_descriptors(available)!
	}
	if failures == 0 || successes == 0 { return error('descriptor sweep requires refusal and success controls') }
	println('WINE BINDING EXHAUSTION PASS failures=${failures} successes=${successes}; heap and descriptors released; fresh capture')
}

fn pressure_recheck(owner &wineadapter.IdleBindingReview, headroom int) !bool {
	available := spare_descriptors()!
	if headroom < 0 || headroom > available { return error('invalid recheck descriptor headroom') }
	mut held := [32]i32{}
	mut count := 0
	defer { for index in 0 .. count { C.close(held[index]) } }
	for count < available - headroom {
		fd := C.open(c'/dev/null', C.O_RDONLY | C.O_CLOEXEC)
		if fd < 0 { return error('cannot establish recheck descriptor pressure') }
		held[count] = fd
		count++
	}
	require_descriptors(headroom)!
	mut accepted := true
	mut saved_errno := i32(0)
	C.errno = 0
	heap_enabled = true
	owner.recheck() or {
		accepted = false
		saved_errno = C.errno
		unsafe { err.free() }
	}
	heap_enabled = false
	if !accepted && saved_errno != C.EMFILE { return error('pressured recheck failed without EMFILE: ' + saved_errno.str()) }
	require_empty('recheck-headroom-' + headroom.str(), 1)!
	require_descriptors(headroom)!
	println('WINE BINDING RECHECK PRESSURE headroom=${headroom} accepted=${accepted}')
	return accepted
}

fn sample_recheck_exhaustion(data string, builtins string, store string) ! {
	initial := spare_descriptors()!
	mut owner := wineadapter.capture_idle_binding_review(data, builtins, store)!
	defer { owner.close() }
	available := spare_descriptors()!
	mut failures := 0
	mut successes := 0
	for headroom in 0 .. available + 1 {
		if pressure_recheck(unsafe { &owner }, headroom)! { successes++ } else { failures++ }
		require_descriptors(available)!
		owner.recheck()!
		refused_capture(data, builtins, store, 'already has a managed launch')!
		require_descriptors(available)!
	}
	if failures == 0 || successes == 0 { return error('recheck sweep requires refusal and success controls') }
	owner.close()
	require_descriptors(initial)!
	mut recovered := wineadapter.capture_idle_binding_review(data, builtins, store)!
	recovered.close()
	require_descriptors(initial)!
	println('WINE BINDING RECHECK EXHAUSTION PASS failures=${failures} successes=${successes}; retained owner retryable; guard held; close permits recapture')
}

fn run() ! {
	$if track_heap ? {} $else { return error('compile with -d track_heap -gc none -manualfree -enable-globals') }
	verify_hooks()!
	if os.args.len !in [2, 3] { return error('usage: HEAP FRESH_ROOT [ROWS]') }
	rows := if os.args.len == 3 { os.args[2].int() } else { 2 }
	if rows < 1 || rows > 900 { return error('row count must be between 1 and 900') }
	root := os.abs_path(os.args[1])
	if os.exists(root) || os.is_link(root) { return error('fresh fixture required') }
	mut original_limit := C.rlimit{}
	if C.getrlimit(C.RLIMIT_NOFILE, unsafe { &original_limit }) != 0 || original_limit.rlim_cur < 32 {
		return error('descriptor probe requires an available 32-FD soft limit')
	}
	limited := C.rlimit{rlim_cur: 32, rlim_max: original_limit.rlim_max}
	if C.setrlimit(C.RLIMIT_NOFILE, unsafe { &limited }) != 0 { return error('cannot set descriptor probe soft limit') }
	defer { C.setrlimit(C.RLIMIT_NOFILE, unsafe { &original_limit }) }
	mut current_limit := C.rlimit{}
	if C.getrlimit(C.RLIMIT_NOFILE, unsafe { &current_limit }) != 0 || current_limit.rlim_cur != 32 {
		return error('descriptor probe soft limit differs')
	}
	verify_descriptor_probe()!
	store := root + '/store'
	builtins := store + '/generations/1/apps/wine/root/usr/lib/wine/x86_64-windows'
	data := root + '/data'
	os.mkdir_all(builtins)!; os.mkdir(data)!; os.chmod(data, 0o700)!
	for index in 0 .. rows { os.write_file(builtins + '/' + index.str() + '.dll', 'marker')! }
	mut prefix := wineadapter.prepare_prefix(data, builtins)!
	prefix.close()
	sample(data, builtins, store, 100)!
	sample_refusals(data, builtins, store, 100)!
	sample_descriptor_exhaustion(data, builtins, store)!
	sample_recheck_exhaustion(data, builtins, store)!
	selected := store + '/generations/2/apps/wine/root/usr/lib/wine/x86_64-windows'
	os.mkdir_all(selected)!
	for index in 0 .. rows { os.write_file(selected + '/' + index.str() + '.dll', 'new marker')! }
	heap_enabled = true
	mut migration := wineadapter.capture_idle_binding_review(data, selected, store) or {
		heap_enabled = false
		return err
	}
	migration.migrate_bindings() or { migration.close(); heap_enabled = false; return err }
	migration.close()
	require_empty('retarget-close', 1)!
	for index in 0 .. rows {
		name := index.str() + '.dll'
		if os.readlink(data + '/wine/drive_c/windows/system32/' + name)! != selected + '/' + name {
			return error('measured retarget did not complete')
		}
	}
	println('WINE BINDING HEAP PASS V-managed review allocations released')
}

fn main() { run() or { eprintln(err); exit(1) } }
