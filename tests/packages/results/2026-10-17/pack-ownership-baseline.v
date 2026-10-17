// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

import os
import time

$if track_heap ? {
	#include "@VMODROOT/../../../desktop/tools/tests/heap_tracker.h"
	fn C.vinix_heap_begin()
	fn C.vinix_heap_end() u64
	fn C.vinix_heap_count() u32
}

fn pack_owned_fixture(count int) !(string, string, string, string) {
	work := os.real_path(os.temp_dir()) + '/vinix-pack-owned-' + os.getpid().str() + '-' + time.now().unix_micro().str()
	root := work + '/source'; manifest := work + '/manifest.json'; repository := work + '/repository'
	os.mkdir_all(root + '/d')!
	for index in 0 .. count {
		digits := index.str()
		os.write_file(root + '/d/data-' + digits, 'payload-' + digits)!
	}
	text := publisher_json(Package{ id: 'fixture', name: 'Fixture', version: '1.0.0', architecture: 'all', kind: 'data', license: 'MIT',
		permissions: ['files'], arguments: ['--literal', 'a b'], associations: ['text/plain'],
		files: [Payload{ path: 'ignored/template', sha256: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa', bytes: 7 }] })
	os.write_file(manifest, text)!
	return work, root, manifest, repository
}

fn pack_owned_refuse(phase string, relative string) ! {
	if phase == 'hashed' && relative == 'd/data-9' { return error('injected late packing refusal') }
}

fn pack_owned_once(root string, manifest string, repository string, refused bool) ! {
	options := if refused { PackSourceOptions{ checkpoint: pack_owned_refuse } } else { PackSourceOptions{} }
	if p := pack_with(manifest, root, repository, options) {
		close_decoded_package(p)
		assert !refused
	} else {
		message := err.msg()
		assert refused && message.contains('injected late packing refusal')
		unsafe { message.free(); err.free() }
	}
}

fn test_pack_owned_baseline_retention() {
	if '--pack-owned-baseline' !in os.args { return }
	for count in [1, 32]! {
		work, root, manifest, repository := pack_owned_fixture(count)!
		defer { os.rmdir_all(work) or {} }
		pack_owned_once(root, manifest, repository, false)!
		for refused in [false, true]! {
			if refused && count == 1 { continue }
			$if track_heap ? { C.vinix_heap_begin() }
			pack_owned_once(root, manifest, repository, refused)!
			$if track_heap ? {
				kept := C.vinix_heap_end(); allocations := C.vinix_heap_count()
				println('PACK OWNERSHIP baseline files=' + count.str() + ' refused=' + refused.str() + ' retained=' + kept.str() + ' allocations=' + allocations.str())
			}
		}
	}
}
