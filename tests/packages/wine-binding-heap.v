// SPDX-License-Identifier: GPL-2.0-or-later
// Single-threaded diagnostic for V-managed allocations, not libc/kernel heap.
module main

import os
import tools.packages.wineadapter

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

fn run() ! {
	$if track_heap ? {} $else { return error('compile with -d track_heap -gc none -manualfree -enable-globals') }
	verify_hooks()!
	if os.args.len !in [2, 3] { return error('usage: HEAP FRESH_ROOT [ROWS]') }
	rows := if os.args.len == 3 { os.args[2].int() } else { 2 }
	if rows < 1 || rows > 900 { return error('row count must be between 1 and 900') }
	root := os.abs_path(os.args[1])
	if os.exists(root) || os.is_link(root) { return error('fresh fixture required') }
	store := root + '/store'
	builtins := store + '/generations/1/apps/wine/root/usr/lib/wine/x86_64-windows'
	data := root + '/data'
	os.mkdir_all(builtins)!; os.mkdir(data)!; os.chmod(data, 0o700)!
	for index in 0 .. rows { os.write_file(builtins + '/' + index.str() + '.dll', 'marker')! }
	mut prefix := wineadapter.prepare_prefix(data, builtins)!
	prefix.close()
	sample(data, builtins, store, 100)!
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
