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

fn publisher_io_refused(result IError) {
	message := result.msg()
	assert message != ''
	unsafe { message.free(); result.free() }
}

fn publisher_io_failed(_ int) int { C.errno = C.EIO; return -1 }

fn publisher_io_once(mode string, root int, path string) ! {
	match mode {
		'capture' { fd := capture_prepared_root(path, 'test')!; C.close(fd) }
		'workspace' { physical := publisher_workspace(path, false)!; unsafe { physical.free() } }
		'outside' { publisher_outside_source(root, path)! }
		'contained' { publisher_outside_source(root, path) or { publisher_io_refused(err); return }; assert false }
		'lock' { guard := publisher_lock(path)!; guard.release() }
		'busy' { publisher_lock(path) or { publisher_io_refused(err); return }; assert false }
		'file' { sync_file(path)! }
		'directory' { sync_directory(path)! }
		'flush-failure' { sync_path_with(path, false, DurabilityOptions{ flush: publisher_io_failed }) or { publisher_io_refused(err); return }; assert false }
		else { panic(mode) }
	}
}

fn test_publisher_io_repeated_admission_locking_and_durability_retire_scratch() {
	work := os.real_path(os.temp_dir()) + '/vinix-publisher-io-owned-' + os.getpid().str() + '-' + time.now().unix_micro().str()
	defer { os.rmdir_all(work) or {} }
	source := work + '/source'; workspace := work + '/repository'; file := work + '/file'
	outside := work + '/new/deep/repository'; contained := source + '/new/deep/repository'
	os.mkdir_all(source)!; os.mkdir(workspace)!; os.write_file(file, 'preserved')!
	root := capture_prepared_root(source, 'test')!; defer { C.close(root) }
	guard := publisher_lock(workspace)!; guard.release()
	for mode in ['capture', 'workspace', 'outside', 'contained', 'lock', 'busy', 'file', 'directory', 'flush-failure']! {
		path := match mode { 'capture' { source } 'outside' { outside } 'contained' { contained }
			'file', 'flush-failure' { file } else { workspace } }
		busy := if mode == 'busy' { publisher_lock(workspace)! } else { Lock{ fd: -1 } }
		defer { if busy.fd >= 0 { busy.release() } }
		mut maximum := u64(0); mut records := u32(0)
		for _ in 0 .. 128 {
			$if track_heap ? { C.vinix_heap_begin() }
			publisher_io_once(mode, root, path)!
			$if track_heap ? {
				kept := C.vinix_heap_end(); allocations := C.vinix_heap_count()
				if kept > maximum { maximum = kept }; if allocations > records { records = allocations }
			}
		}
		$if track_heap ? {
			println('PUBLISHER IO OWNERSHIP mode=' + mode + ' retained=' + maximum.str() + ' allocations=' + records.str())
			$if !publisher_io_baseline ? { assert maximum == 0 && records == 0 }
		}
	}
	assert os.read_file(file)! == 'preserved' && !os.exists(outside) && !os.exists(contained)
	println('PUBLISHER IO OWNERSHIP admission, containment, exclusion and durability scratch PASS')
}
