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

fn publisher_io_refused(result IError, expected string) {
	message := result.msg()
	assert message.contains(expected), message
	unsafe { message.free(); result.free() }
}

fn publisher_io_failed(_ int) int { C.errno = C.EIO; return -1 }
fn C.link(&char, &char) int

fn publisher_io_once(mode string, root int, path string) ! {
	match mode {
		'capture' { fd := capture_prepared_root(path, 'test')!; C.close(fd) }
		'capture-alias' { capture_prepared_root(path, 'test') or { publisher_io_refused(err, 'ordinary directory'); return }; assert false }
		'workspace' { physical := publisher_workspace(path, false)!; unsafe { physical.free() } }
		'workspace-alias' { publisher_workspace(path, false) or { publisher_io_refused(err, 'ordinary directory'); return }; assert false }
		'workspace-unsafe' { publisher_workspace(path, false) or { publisher_io_refused(err, 'not writable'); return }; assert false }
		'outside', 'relative-outside' { publisher_outside_source(root, path)! }
		'contained', 'relative-contained' { publisher_outside_source(root, path) or { publisher_io_refused(err, 'outside the package source'); return }; assert false }
		'lock' { guard := publisher_lock(path)!; guard.release() }
		'busy' { publisher_lock(path) or { publisher_io_refused(err, 'another publisher'); return }; assert false }
		'hard-linked' { publisher_lock(path) or { publisher_io_refused(err, 'without hard links'); return }; assert false }
		'file' { sync_file(path)! }
		'directory' { sync_directory(path)! }
		'file-alias' { sync_file(path) or { publisher_io_refused(err, 'cannot open ordinary'); return }; assert false }
		'directory-alias' { sync_directory(path) or { publisher_io_refused(err, 'cannot open ordinary'); return }; assert false }
		'flush-failure' { sync_path_with(path, false, DurabilityOptions{ flush: publisher_io_failed }) or { publisher_io_refused(err, 'cannot flush captured'); return }; assert false }
		else { panic(mode) }
	}
}

fn test_publisher_io_repeated_admission_locking_and_durability_retire_scratch() {
	work := os.real_path(os.temp_dir()) + '/vinix-publisher-io-owned-' + os.getpid().str() + '-' + time.now().unix_micro().str()
	defer { os.rmdir_all(work) or {} }
	source := work + '/source'; workspace := work + '/repository'; file := work + '/file'
	outside := work + '/new/deep/repository'; contained := source + '/new/deep/repository'
	os.mkdir_all(source)!; os.mkdir(workspace)!; os.write_file(file, 'preserved')!
	os.mkdir(source + '/sub')!; os.symlink(source + '/sub', work + '/alias')!
	os.symlink(workspace, work + '/repository-alias')!; os.symlink(file, work + '/file-alias')!
	os.mkdir(work + '/unsafe')!; os.chmod(work + '/unsafe', 0o777)!
	cwd := os.getwd(); os.chdir(work)!; defer { os.chdir(cwd) or { panic(err) } }
	root := capture_prepared_root(source, 'test')!; defer { C.close(root) }
	guard := publisher_lock(workspace)!; guard.release()
	for mode in ['capture', 'capture-alias', 'workspace', 'workspace-alias', 'workspace-unsafe', 'outside', 'relative-outside', 'contained', 'relative-contained', 'lock', 'busy', 'hard-linked', 'file', 'directory', 'file-alias', 'directory-alias', 'flush-failure']! {
		path := match mode { 'capture' { source } 'capture-alias' { work + '/alias///' }
			'workspace-alias', 'directory-alias' { work + '/repository-alias///' } 'workspace-unsafe' { work + '/unsafe' }
			'outside' { outside } 'contained' { contained } 'relative-outside' { 'new/deep/repository' }
			'relative-contained' { 'alias/../new/deep/repository' } 'file-alias' { work + '/file-alias' }
			'file', 'flush-failure' { file } else { workspace } }
		busy := if mode == 'busy' { publisher_lock(workspace)! } else { Lock{ fd: -1 } }
		defer { if busy.fd >= 0 { busy.release() } }
		linked := work + '/linked-lock'
		if mode == 'hard-linked' { lock_path := workspace + '/.publisher/lock'; assert C.link(lock_path.str, linked.str) == 0 }
		defer { if mode == 'hard-linked' { os.rm(linked) or { panic(err) } } }
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
