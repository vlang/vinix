// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

import os
import time

#include <sys/resource.h>
#include <sys/wait.h>
fn C.fork() int
fn C.waitpid(int, &int, int) int
fn C._exit(int)
fn C.alarm(u32) u32
fn C.mkfifo(&char, u32) int
fn C.fcntl(int, int, ...int) int
fn C.getrlimit(int, voidptr) int
fn C.setrlimit(int, voidptr) int

struct AtomicLimit { current u64 maximum u64 }

fn atomic_work() !string {
	work := os.real_path(os.temp_dir()) + '/vinix-atomic-' + os.getpid().str() + '-' + time.now().unix_micro().str()
	os.mkdir(work)!
	return work
}

fn observe_atomic_write(phase string, temporary string) ! {
	if phase == 'published' { return }
	assert os.read_file(os.dir(temporary) + '/metadata')! == 'previous'
	info := os.lstat(temporary)!
	assert info.mode & 0o777 == if phase == 'flushed' { 0o644 } else { 0o600 }
	if phase == 'created' {
		assert info.size == 0
		mut descriptors := 0
		parent := os.stat(os.dir(temporary))!
		for fd in 3 .. 128 {
			mut opened := C.stat{}
			if C.fstat(fd, &opened) != 0 { continue }
			if (u64(opened.st_dev) == info.dev && u64(opened.st_ino) == info.inode)
				|| (u64(opened.st_dev) == parent.dev && u64(opened.st_ino) == parent.inode) {
				assert C.fcntl(fd, C.F_GETFD) & C.FD_CLOEXEC != 0
				descriptors++
			}
		}
		assert descriptors == 2
	}
}

fn test_atomic_writes_owned_complete_bytes_with_private_temporary_and_public_final_mode() {
	work := atomic_work()!
	defer { os.rmdir_all(work) or {} }
	path := work + '/metadata'
	os.write_file(path, 'previous')!
	atomic_write_with(path, 'complete\x00contents', AtomicWriteOptions{ checkpoint: observe_atomic_write })!
	assert os.read_file(path)! == 'complete\x00contents' && os.lstat(path)!.mode & 0o777 == 0o644
	for text in ['', 'small metadata', 'x'.repeat(65537), 'z'.repeat(max_metadata)] {
		atomic_write(path, text)!
		assert read_metadata(path)! == text
		assert os.ls(work)!.sorted() == ['metadata']
	}
	write_administration_metadata(path, 'administration')!
	assert read_metadata(path)! == 'administration'
}

fn atomic_failure(phase string, temporary string) ! {
	if phase == os.file_name(os.dir(temporary)) { return error('injected atomic ' + phase + ' failure') }
}

fn atomic_short_interrupted_write(fd int, data voidptr, count usize) isize {
	flags := C.fcntl(fd, C.F_GETFL)
	if flags & C.O_NONBLOCK != 0 {
		assert C.fcntl(fd, C.F_SETFL, flags & ~C.O_NONBLOCK) == 0
		C.errno = C.EINTR
		return -1
	}
	return C.write(fd, data, if count > 7 { usize(7) } else { count })
}

fn atomic_zero_write(_ int, _ voidptr, _ usize) isize { return 0 }
fn atomic_bad_write(_ int, _ voidptr, _ usize) isize { C.errno = C.EIO; return -1 }

fn atomic_file_flush_failure(fd int) int {
	mut info := C.stat{}
	assert C.fstat(fd, &info) == 0
	return if info.st_mode & 0o170000 == 0o100000 { -1 } else { C.fsync(fd) }
}

fn atomic_directory_flush_failure(fd int) int {
	mut info := C.stat{}
	assert C.fstat(fd, &info) == 0
	return if info.st_mode & 0o170000 == 0o040000 { -1 } else { C.fsync(fd) }
}

fn test_atomic_prepublication_failures_preserve_old_bytes_and_postpublication_errors_retain_saved_bytes() {
	work := atomic_work()!
	defer { os.rmdir_all(work) or {} }
	for phase in ['created', 'written', 'flushed', 'published'] {
		os.mkdir(work + '/' + phase)!
		path := work + '/' + phase + '/metadata'
		atomic_write(path, 'previous')!
		mut message := ''
		atomic_write_with(path, 'replacement', AtomicWriteOptions{ checkpoint: atomic_failure }) or { message = err.msg() }
		assert message.contains('injected atomic ' + phase + ' failure')
		assert message.contains('saved, but') == (phase == 'published')
		assert read_metadata(path)! == if phase == 'published' { 'replacement' } else { 'previous' }
		assert os.ls(os.dir(path))!.sorted() == ['metadata']
		atomic_write(path, 'retry')!
		assert read_metadata(path)! == 'retry'
	}
	path := work + '/metadata'
	text := 'short writes with one interrupted system call\x00and binary data'.repeat(37)
	atomic_write_with(path, text, AtomicWriteOptions{ write: atomic_short_interrupted_write })!
	assert read_metadata(path)! == text
	for writer in [atomic_zero_write, atomic_bad_write] {
		mut refused := false
		atomic_write_with(path, 'replacement', AtomicWriteOptions{ write: writer }) or { refused = err.msg().contains('cannot write package metadata') }
		assert refused && read_metadata(path)! == text
	}
	for flush in [atomic_file_flush_failure, atomic_directory_flush_failure] {
		atomic_write(path, 'previous')!
		mut message := ''
		atomic_write_with(path, 'replacement', AtomicWriteOptions{ flush: flush }) or { message = err.msg() }
		assert message.contains('flush')
		assert read_metadata(path)! == if message.contains('saved, but') { 'replacement' } else { 'previous' }
		assert os.ls(work)!.all(!it.starts_with('.package-'))
	}
}

fn replace_atomic_temporary(phase string, temporary string) ! {
	if phase != os.file_name(os.dir(temporary)) { return }
	os.rename(temporary, temporary + '.saved')!
	os.symlink(os.dir(os.dir(temporary)) + '/outside', temporary)!
}

fn replace_atomic_parent(phase string, temporary string) ! {
	parent := os.dir(temporary)
	if phase != os.file_name(os.dir(parent)) { return }
	os.rename(parent, parent + '.saved')!
	os.symlink(os.dir(parent) + '/outside', parent)!
}

fn test_atomic_name_and_parent_substitution_never_publish_or_clean_up_through_replacements() {
	work := atomic_work()!
	defer { os.rmdir_all(work) or {} }
	os.write_file(work + '/outside', 'untouched')!
	os.chmod(work + '/outside', 0o600)!
	for phase in ['created', 'written', 'flushed'] {
		os.mkdir(work + '/' + phase)!
		path := work + '/' + phase + '/metadata'
		atomic_write(path, 'previous')!
		mut refused := false
		atomic_write_with(path, 'replacement', AtomicWriteOptions{ checkpoint: replace_atomic_temporary }) or { refused = err.msg().contains('temporary file changed') }
		assert refused && read_metadata(path)! == 'previous'
		assert os.read_file(work + '/outside')! == 'untouched' && os.lstat(work + '/outside')!.mode & 0o777 == 0o600
		for name in os.ls(os.dir(path))!.filter(it.starts_with('.package-') && !it.ends_with('.saved')) {
			assert os.is_link(os.dir(path) + '/' + name)
		}
	}
	for phase in ['created', 'written', 'flushed', 'published'] {
		base := work + '/parent/' + phase
		os.mkdir_all(base + '/original')!
		os.mkdir(base + '/outside')!
		os.write_file(base + '/outside/metadata', 'outside preserved')!
		path := base + '/original/metadata'
		atomic_write(path, 'previous')!
		mut message := ''
		atomic_write_with(path, 'replacement', AtomicWriteOptions{ checkpoint: replace_atomic_parent }) or { message = err.msg() }
		assert message.contains('parent path changed')
		assert message.contains('saved in its captured directory') == (phase == 'published')
		assert read_metadata(base + '/original.saved/metadata')! == if phase == 'published' { 'replacement' } else { 'previous' }
		assert read_metadata(base + '/outside/metadata')! == 'outside preserved'
		assert os.ls(base + '/original.saved')!.sorted() == ['metadata']
	}
}

fn test_atomic_refuses_invalid_names_oversized_text_and_directory_destinations_without_leftovers() {
	work := atomic_work()!
	defer { os.rmdir_all(work) or {} }
	path := work + '/metadata'
	atomic_write(path, 'previous')!
	os.mkdir(work + '/directory')!
	os.symlink(work + '/directory', work + '/parent-alias')!
	assert C.mkfifo((work + '/parent-fifo').str, 0o600) == 0
	for invalid in ['', work + '/', work + '/.', work + '/..', path + '\x00ignored', work + '/missing/metadata',
		work + '/parent-alias/metadata', work + '/parent-fifo/metadata', path + '/child', work + '/directory'] {
		mut refused := false
		atomic_write(invalid, 'replacement') or { refused = true }
		assert refused, invalid
		assert read_metadata(path)! == 'previous' && os.ls(work + '/directory')!.len == 0
		assert os.ls(work)!.all(!it.starts_with('.package-'))
	}
	for administration in [false, true] {
		mut refused := false
		if administration { write_administration_metadata(path, 'x'.repeat(max_metadata + 1)) or { refused = err.msg().contains('size limit') } }
		else { atomic_write(path, 'x'.repeat(max_metadata + 1)) or { refused = err.msg().contains('size limit') } }
		assert refused && read_metadata(path)! == 'previous'
	}
}

fn test_atomic_concurrent_writers_and_readers_observe_only_complete_documents() {
	work := atomic_work()!
	defer { os.rmdir_all(work) or {} }
	path := work + '/metadata'
	texts := ['p'.repeat(65537), 'a'.repeat(65537), 'b'.repeat(65537), 'c'.repeat(65537), 'd'.repeat(65537)]
	atomic_write(path, texts[0])!
	mut children := []int{}
	for i in 1 .. texts.len {
		child := C.fork()
		assert child >= 0
		if child == 0 {
			C.alarm(8)
			for _ in 0 .. 8 { atomic_write(path, texts[i]) or { C._exit(42) } }
			C._exit(0)
		}
		children << child
	}
	for _ in 0 .. 200 {
		text := read_metadata(path)!
		assert text in texts
		unsafe { text.free() }
	}
	for child in children { mut status := 0; assert C.waitpid(child, &status, 0) == child && status == 0 }
	assert read_metadata(path)! in texts && os.ls(work)!.sorted() == ['metadata']
}

fn test_atomic_success_and_all_checkpoint_failures_release_descriptors() {
	work := atomic_work()!
	defer { os.rmdir_all(work) or {} }
	for phase in ['created', 'written', 'flushed', 'published'] { os.mkdir(work + '/' + phase)! }
	mut original := AtomicLimit{}
	assert C.getrlimit(C.RLIMIT_NOFILE, voidptr(&original)) == 0
	limited := AtomicLimit{ current: 32, maximum: original.maximum }
	assert C.setrlimit(C.RLIMIT_NOFILE, voidptr(&limited)) == 0
	defer { assert C.setrlimit(C.RLIMIT_NOFILE, voidptr(&original)) == 0 }
	for _ in 0 .. 128 {
		atomic_write(work + '/metadata', 'complete')!
		assert read_metadata(work + '/metadata')! == 'complete'
		for phase in ['created', 'written', 'flushed', 'published'] {
			mut refused := false
			atomic_write_with(work + '/' + phase + '/metadata', 'replacement', AtomicWriteOptions{ checkpoint: atomic_failure }) or {
				refused = err.msg().contains('injected atomic ' + phase + ' failure')
				message := err.msg(); unsafe { message.free(); err.free() }
			}
			assert refused && os.ls(work + '/' + phase)!.all(!it.starts_with('.package-'))
		}
	}
}
