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

fn flush_attempt(path string, refused bool) {
	if _ := flush_tree(path) { assert !refused }
	else { message := err.msg(); unsafe { message.free(); err.free() }; assert refused }
}

fn test_recursive_publisher_flush_retires_names_and_paths_on_success_and_nested_refusal() {
	work := os.real_path(os.temp_dir()) + '/vinix-flush-owner-' + time.now().unix_micro().str()
	os.mkdir_all(work + '/tree/branch/leaf')!; os.mkdir_all(work + '/other/leaf')!
	defer { os.rmdir_all(work) or {} }
	os.write_file(work + '/other/leaf/keep', 'preserved alias target')!
	os.write_file(work + '/plain', 'preserved ordinary file')!
	for index in 0 .. 12 { os.write_file(work + '/tree/branch/leaf/data-' + index.str(), 'preserved payload')! }
	for mode in ['complete', 'ordinary-file', 'nested-alias']! {
		if mode == 'nested-alias' { os.symlink(work + '/other', work + '/tree/branch/alias')! }
		path := work + if mode == 'ordinary-file' { '/plain' } else { '/tree' }
		refused := mode != 'complete'
		flush_attempt(path, refused)
		mut maximum := u64(0); mut records := u32(0)
		for _ in 0 .. 64 {
			$if track_heap ? { C.vinix_heap_begin() }
			flush_attempt(path, refused)
			$if track_heap ? {
				kept := C.vinix_heap_end(); count := C.vinix_heap_count()
				if kept > maximum { maximum = kept }; if count > records { records = count }
			}
		}
		$if track_heap ? {
			println('PUBLISHER FLUSH case=' + mode + ' retained=' + maximum.str() + ' allocations=' + records.str())
			assert maximum == 0 && records == 0
		}
		assert os.read_file(work + '/other/leaf/keep')! == 'preserved alias target'
		assert os.read_file(work + '/plain')! == 'preserved ordinary file'
		assert os.read_file(work + '/tree/branch/leaf/data-11')! == 'preserved payload'
	}
	println('PUBLISHER FLUSH 192 recursive success and ordinary/nested durability refusal cycles retire names, paths and errors PASS')
}
