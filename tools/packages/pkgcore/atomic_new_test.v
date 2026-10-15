// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

import os
import time

fn C.mkfifo(&char, u32) int
fn C.link(&char, &char) int
fn C.fork() int
fn C.waitpid(int, &int, int) int
fn C._exit(int)

fn new_metadata_work() !string {
	work := os.real_path(os.temp_dir()) + '/vinix-new-metadata-' + os.getpid().str() + '-' + time.now().unix_micro().str()
	os.mkdir(work)!
	return work
}

fn new_metadata_checkpoint(phase string, temporary string) ! {
	kind := os.file_name(os.dir(temporary))
	path := os.dir(temporary) + '/saved'
	if kind == 'destination-race' && phase == 'flushed' { os.write_file(path, 'racing writer')! }
	if kind == 'mode-change' && phase == 'flushed' { os.chmod(temporary, 0o600)! }
	if kind == 'parent-change' && phase == 'flushed' {
		parent := os.dir(temporary)
		os.rename(parent, parent + '.moved')!; os.mkdir(parent)!
	}
	if kind == 'final-change' && phase == 'published' {
		os.rename(path, path + '.moved')!; os.symlink(path + '.moved', path)!
	}
	if kind == 'final-truncate' && phase == 'published' { os.write_file(path, '')! }
	if kind == phase { return error('injected new metadata ' + phase + ' failure') }
}

fn new_metadata_flush_failure(fd int) int {
	mut info := C.stat{}; assert C.fstat(fd, &info) == 0
	return if info.st_mode & 0o170000 == 0o040000 { -1 } else { C.fsync(fd) }
}

fn new_metadata_write_failure(_ int, _ voidptr, _ usize) isize { C.errno = C.ENOSPC; return -1 }

fn test_new_metadata_never_replaces_existing_files_aliases_fifo_directories_or_hardlinks() {
	work := new_metadata_work()!; defer { os.rmdir_all(work) or {} }
	os.write_file(work + '/outside', 'untouched')!; os.chmod(work + '/outside', 0o600)!
	for kind in ['file', 'alias', 'dangling', 'fifo', 'directory', 'hardlink'] {
		path := work + '/' + kind
		match kind {
			'file' { os.write_file(path, 'preserved')! }
			'alias' { os.symlink(work + '/outside', path)! }
			'dangling' { os.symlink(work + '/absent', path)! }
			'fifo' { assert C.mkfifo(path.str, 0o600) == 0 }
			'directory' { os.mkdir(path)! }
			'hardlink' { assert C.link((work + '/outside').str, path.str) == 0 }
			else {}
		}
		before := os.lstat(path)!
		mut refused := false; atomic_write_new(path, 'replacement') or { refused = err.msg().contains('already exists') }; assert refused
		after := os.lstat(path)!
		assert before.inode == after.inode && before.mode == after.mode && before.size == after.size
	}
	assert os.read_file(work + '/file')! == 'preserved' && os.read_file(work + '/outside')! == 'untouched'
	assert os.lstat(work + '/outside')!.mode & 0o777 == 0o600
	assert os.ls(work)!.all(!it.starts_with('.package-'))
	println('NEW METADATA existing file/alias/dangling/FIFO/directory/hardlink destinations refuse without replacement or blocking PASS')
}

fn test_new_metadata_failure_boundaries_preserve_absence_or_report_saved_files() {
	work := new_metadata_work()!; defer { os.rmdir_all(work) or {} }
	for kind in ['created', 'written', 'flushed', 'published', 'destination-race', 'mode-change', 'parent-change', 'final-change', 'final-truncate'] {
		os.mkdir(work + '/' + kind)!
		path := work + '/' + kind + '/saved'
		mut message := ''
		atomic_write_with(path, 'complete', AtomicWriteOptions{ exclusive: true, checkpoint: new_metadata_checkpoint }) or { message = err.msg() }
		assert message != '', kind
		if kind == 'destination-race' { assert os.read_file(path)! == 'racing writer' }
		else if kind == 'published' { assert message.contains('saved, but') && os.read_file(path)! == 'complete' }
		else if kind == 'final-change' { assert message.contains('saved, but') && os.is_link(path) && os.read_file(path + '.moved')! == 'complete' }
		else if kind == 'final-truncate' { assert message.contains('saved, but') && os.read_file(path)! == '' }
		else { assert !os.exists(path) && !os.is_link(path) }
		assert os.ls(os.dir(path))!.all(!it.starts_with('.package-'))
		if kind == 'parent-change' { assert os.ls(work + '/' + kind + '.moved')!.len == 0 }
	}
	path := work + '/full'
	mut refused := false
	atomic_write_with(path, 'complete', AtomicWriteOptions{ exclusive: true, write: new_metadata_write_failure }) or { refused = true }; assert refused && !os.exists(path)
	mut message := ''
	atomic_write_with(path, 'complete', AtomicWriteOptions{ exclusive: true, flush: new_metadata_flush_failure }) or { message = err.msg() }
	assert message.contains('saved, but directory flush failed') && os.read_file(path)! == 'complete'
	refused = false; atomic_write_new(path, 'retry') or { refused = true }; assert refused && os.read_file(path)! == 'complete'
	assert os.ls(work)!.all(!it.starts_with('.package-'))
	println('NEW METADATA checkpoint/write/space/flush failures, destination races, mode/parent/final substitutions, cleanup and saved-file retry refusal PASS')
}

fn test_new_metadata_concurrent_publishers_produce_one_complete_durable_winner() {
	work := new_metadata_work()!; defer { os.rmdir_all(work) or {} }
	path := work + '/saved'
	texts := ['a'.repeat(65537), 'b'.repeat(65537), 'c'.repeat(65537), 'd'.repeat(65537)]
	mut children := []int{cap: 4}
	for text in texts {
		child := C.fork(); assert child >= 0
		if child == 0 { atomic_write_new(path, text) or { C._exit(42) }; C._exit(0) }
		children << child
	}
	mut winners := 0
	for child in children { mut status := 0; assert C.waitpid(child, &status, 0) == child; assert status in [0, 42 << 8]; if status == 0 { winners++ } }
	assert winners == 1 && read_metadata(path)! in texts && os.lstat(path)!.mode & 0o777 == 0o644
	assert os.ls(work)! == ['saved']
	println('NEW METADATA concurrent publishers admit exactly one complete file with canonical final mode and no temporary leftovers PASS')
}
