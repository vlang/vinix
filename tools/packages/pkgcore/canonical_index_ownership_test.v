// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

$if track_heap ? {
#include "@VMODROOT/../../../desktop/tools/tests/heap_tracker.h"
fn C.vinix_heap_begin()
fn C.vinix_heap_end() u64
fn C.vinix_heap_count() u32
}

fn canonical_owner_attempt(index Index, refused bool) {
	if text := canonical_index(index) { unsafe { text.free() }; assert !refused }
	else { message := err.msg(); unsafe { message.free(); err.free() }; assert refused }
}

fn test_canonical_index_retires_sorted_borrowed_buffers_and_partial_refusals() {
	for count in [0, 1, 64]! {
		mut packages := []Package{cap: count}
		for at in 0 .. count {
			packages << Package{ id: 'data-' + (count - at).str(), version: '1.0.0', architecture: 'all', name: 'Data', kind: 'data', license: 'MIT',
				permissions: ['network', 'files'], associations: ['text/plain', 'application/json'],
				files: [Payload{ path: 'z', sha256: '0'.repeat(64), bytes: 1 }, Payload{ path: 'a', sha256: '1'.repeat(64), bytes: 1 }] }
		}
		for mode in ['complete', 'first-invalid', 'last-invalid']! {
			if count == 0 && mode != 'complete' { continue }
			mut input := packages.clone()
			if mode != 'complete' {
				at := if mode == 'first-invalid' { 0 } else { count - 1 }
				// Force validation before/after every valid sorted package, rather
				// than letting an invalid last input sort to the start of the work.
				input[at] = Package{ ...input[at], id: if mode == 'first-invalid' { 'Invalid' } else { 'zz_Invalid' } }
			}
			index := Index{ repository: 'fixture', sequence: 1, expires: 2100000000, packages: input }
			canonical_owner_attempt(index, mode != 'complete')
			mut maximum := u64(0); mut records := u32(0)
			for _ in 0 .. 64 {
				$if track_heap ? { C.vinix_heap_begin() }
				canonical_owner_attempt(index, mode != 'complete')
				$if track_heap ? { kept := C.vinix_heap_end(); count_kept := C.vinix_heap_count(); if kept > maximum { maximum = kept }; if count_kept > records { records = count_kept } }
			}
			$if track_heap ? { println('CANONICAL INDEX count=' + count.str() + ' case=' + mode + ' retained=' + maximum.str() + ' allocations=' + records.str()); assert maximum == 0 && records == 0 }
			for p in input { assert p.files[0].path == 'z' && p.permissions[0] == 'network' && p.associations[0] == 'text/plain' }
			unsafe { (&array(&input)).free() }
		}
		for p in packages { p.close_owned_for_canonical_fixture() }
		unsafe { (&array(&packages)).free() }
	}
	println('CANONICAL INDEX 448 complete/partial-refusal cycles preserve input order and borrowed fields PASS')
}

fn (p Package) close_owned_for_canonical_fixture() {
	// Only the ID and hash strings above were allocated; literals stay borrowed.
	unsafe {
		p.id.free(); for file in p.files { file.sha256.free() }
		(&array(&p.files)).free(); (&array(&p.permissions)).free(); (&array(&p.associations)).free()
		(&array(&p.dependencies)).free(); (&array(&p.arguments)).free()
	}
}
