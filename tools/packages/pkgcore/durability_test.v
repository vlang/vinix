// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

import os
import time

#include <sys/resource.h>
fn C.getrlimit(int, voidptr) int
fn C.setrlimit(int, voidptr) int
struct DurabilityLimit { current u64 maximum u64 }

fn durability_work() !string {
	path := os.real_path(os.temp_dir()) + '/vinix-durability-' + os.getpid().str() + '-' + time.now().unix_micro().str()
	os.mkdir(path)!
	return path
}

fn durability_change(phase string, path string) ! {
	if phase != os.file_name(os.dir(path)) { return }
	if os.file_name(path) == 'grow' {
		mut file := os.open_file(path, 'a', 0o600)!
		file.write_string('changed')!; file.close()
	} else {
		os.rename(path, path + '.saved')!
		if os.file_name(path) == 'ordinary' { os.write_file(path, 'replacement')!
		} else { os.symlink(os.getenv('VINIX_DURABILITY_OUTSIDE'), path)! }
	}
}

fn durability_record(fd int) int {
	mut opened := C.stat{}
	assert C.fstat(fd, &opened) == 0
	info := os.lstat(os.getenv('VINIX_DURABILITY_ORIGINAL')) or { panic(err) }
	assert u64(opened.st_dev) == info.dev && u64(opened.st_ino) == info.inode
	os.write_file(os.getenv('VINIX_DURABILITY_FLUSHED'), 'once') or { panic(err) }
	return C.fsync(fd)
}

fn durability_interrupted(fd int) int {
	if os.getenv('VINIX_DURABILITY_INTERRUPTED') == '' {
		os.setenv('VINIX_DURABILITY_INTERRUPTED', 'once', true)
		C.errno = C.EINTR
		return -1
	}
	return C.fsync(fd)
}

fn durability_failed(_ int) int { C.errno = C.EIO; return -1 }

fn test_durability_captured_identity_size_flush_and_interruption() {
	work := durability_work()!
	defer { os.rmdir_all(work) or {} }
	defer { for key in ['VINIX_DURABILITY_OUTSIDE', 'VINIX_DURABILITY_ORIGINAL', 'VINIX_DURABILITY_FLUSHED', 'VINIX_DURABILITY_INTERRUPTED'] { os.unsetenv(key) } }
	for directory in [false, true] {
		base := work + '/' + if directory { 'directory' } else { 'file' }
		os.mkdir(base)!
		outside := base + '/outside'
		if directory { os.mkdir(outside)! } else { os.write_file(outside, 'preserved')! }
		os.setenv('VINIX_DURABILITY_OUTSIDE', outside, true)
		for phase in ['captured', 'flushed'] {
			os.mkdir(base + '/' + phase)!
			for kind in if directory { ['alias'] } else { ['alias', 'ordinary', 'grow'] } {
				path := base + '/' + phase + '/' + kind
				if directory { os.mkdir(path)! } else { os.write_file(path, 'original')! }
				os.setenv('VINIX_DURABILITY_ORIGINAL', path, true)
				os.setenv('VINIX_DURABILITY_FLUSHED', base + '/marker', true)
				if os.exists(base + '/marker') { os.rm(base + '/marker')! }
				mut refused := false
				sync_path_with(path, directory, DurabilityOptions{ checkpoint: durability_change, flush: durability_record }) or {
					refused = err.msg().contains('changed while flushing')
				}
				assert refused && os.exists(base + '/marker') == (phase == 'flushed'), phase + '/' + kind
				if directory { assert os.ls(outside)!.len == 0 } else { assert os.read_file(outside)! == 'preserved' }
			}
		}
		path := base + '/valid'
		if directory { os.mkdir(path)! } else { os.write_file(path, 'original')! }
		os.unsetenv('VINIX_DURABILITY_INTERRUPTED')
		sync_path_with(path, directory, DurabilityOptions{ flush: durability_interrupted })!
		assert os.getenv('VINIX_DURABILITY_INTERRUPTED') == 'once'
		mut refused := false
		sync_path_with(path, directory, DurabilityOptions{ flush: durability_failed }) or { refused = err.msg().contains('cannot flush captured') }
		assert refused
		sync_path_with(path, directory, DurabilityOptions{})!
	}
}

fn test_durability_repeated_success_and_refusal_close_descriptors() {
	work := durability_work()!
	defer { os.rmdir_all(work) or {} }
	os.write_file(work + '/file', 'unchanged')!
	os.symlink(work + '/file', work + '/alias')!
	mut original := DurabilityLimit{}
	assert C.getrlimit(C.RLIMIT_NOFILE, voidptr(&original)) == 0
	limit := DurabilityLimit{ current: 32, maximum: original.maximum }
	assert C.setrlimit(C.RLIMIT_NOFILE, voidptr(&limit)) == 0
	defer { assert C.setrlimit(C.RLIMIT_NOFILE, voidptr(&original)) == 0 }
	for _ in 0 .. 128 {
		sync_file(work + '/file')!; sync_directory(work + '///')!
		mut rejected := 0
		for path in [work + '/alias', work, work + '/file\x00ignored'] {
			sync_file(path) or { rejected++ }
		}
		sync_path_with(work + '/file', false, DurabilityOptions{ flush: durability_failed }) or { rejected++ }
		assert rejected == 4
	}
}
