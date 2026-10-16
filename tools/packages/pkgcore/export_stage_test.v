// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

import os

#include <sys/resource.h>
fn C.getrlimit(int, voidptr) int
fn C.setrlimit(int, voidptr) int
fn C.link(&char, &char) int
fn C.mkfifo(&char, u32) int
fn C.sleep(u32) u32
struct ExportRetirementLimit { current u64 maximum u64 }

$if track_heap ? {
	#include "@VMODROOT/../../../desktop/tools/tests/heap_tracker.h"
	fn C.vinix_heap_begin()
	fn C.vinix_heap_end() u64
}

fn export_retirement_work(label string) !string {
	work := os.real_path(os.temp_dir()) + '/vinix-export-retirement-' + label + '-' + os.getpid().str()
	os.mkdir(work)!
	return work
}

fn export_retirement_file(directory int, name string) ! {
	fd := C.openat(directory, name.str, C.O_WRONLY | C.O_CREAT | C.O_EXCL | C.O_NOFOLLOW, 0o600)
	if fd < 0 {
		code := C.errno
		return error('cannot create retirement fixture (errno=${code}, directory=${directory})')
	}
	defer { C.close(fd) }
	if C.write(fd, c'preserved', 9) != 9 { return error('cannot write retirement fixture') }
}

fn export_retirement_cycle(parent string, depth int) ! {
	mut stage := create_export_stage(parent, '.vinix-test', 'fixture export')!
	defer { stage.close() }
	stage.check()!
	mut fd := C.openat(stage.root, c'.', C.O_RDONLY | C.O_DIRECTORY | C.O_CLOEXEC)
	if fd < 0 { return error('cannot reopen fixture stage') }
	defer { C.close(fd) }
	for _ in 0 .. depth {
		if C.mkdirat(fd, c'n', 0o700) != 0 { return error('cannot create nested fixture') }
		next := C.openat(fd, c'n', C.O_RDONLY | C.O_DIRECTORY | C.O_NOFOLLOW | C.O_CLOEXEC)
		if next < 0 { return error('cannot open nested fixture') }
		C.close(fd); fd = next
	}
	export_retirement_file(fd, 'keep')!
	stage.retire()!
	assert !os.exists(stage.path)
}

fn test_export_retirement_uses_bounded_descriptors_and_retires_owned_scratch() {
	work := export_retirement_work('cycles')!; defer { os.rmdir_all(work) or {} }
	export_retirement_cycle(work, 0)!
	mut original := ExportRetirementLimit{}
	assert C.getrlimit(C.RLIMIT_NOFILE, unsafe { &original }) == 0
	limit := ExportRetirementLimit{ current: 32, maximum: original.maximum }
	assert C.setrlimit(C.RLIMIT_NOFILE, unsafe { &limit }) == 0
	defer { assert C.setrlimit(C.RLIMIT_NOFILE, unsafe { &original }) == 0 }
	$if track_heap ? {
		C.vinix_heap_begin()
		for i in 0 .. 1000 {
			export_retirement_cycle(work, 0) or {
				C.vinix_heap_end()
				panic('export retirement cycle ${i}: ${err}')
			}
		}
		kept := C.vinix_heap_end()
		println('EXPORT RETIREMENT 1000 create/check/retire/close cycles retained ${kept} bytes')
		assert kept == 0
	}
	$if linux {
		// Vinix retains unlinked kernel nodes for a five-second lookup grace
		// period. Isolate heap cycles from the following 6,144-directory stress
		// instead of combining both bursts under one owner's kernel budget.
		if os.exists('/proc/kernel-resources') {
			before := os.read_file('/proc/kernel-resources')!
			println('EXPORT RETIREMENT kernel resources before grace:\n' + before)
			C.sleep(6)
			after := os.read_file('/proc/kernel-resources')!
			println('EXPORT RETIREMENT kernel resources after grace:\n' + after)
			unsafe { before.free(); after.free() }
		}
	}
	for _ in 0 .. 128 { export_retirement_cycle(work, 48)! }
	assert os.ls(work)!.len == 0
	println('EXPORT RETIREMENT 128 deep-tree retirements use at most 32 descriptors and leave no staging names PASS')
}

fn test_export_retirement_unlinks_special_leaves_without_following_or_chmod() {
	work := export_retirement_work('leaves')!; defer { os.rmdir_all(work) or {} }
	os.mkdir(work + '/outside')!; os.chmod(work + '/outside', 0o700)!
	os.write_file(work + '/outside/keep', 'preserved')!; os.chmod(work + '/outside/keep', 0o600)!
	mut stage := create_export_stage(work, '.vinix-test', 'fixture export')!
	defer { stage.close() }
	os.symlink(work + '/outside', stage.path + '/alias')!
	os.symlink(work + '/absent', stage.path + '/dangling')!
	assert C.link((work + '/outside/keep').str, (stage.path + '/hardlink').str) == 0
	assert C.mkfifo((stage.path + '/fifo').str, 0o600) == 0
	stage.retire()!
	assert !os.exists(stage.path) && os.read_file(work + '/outside/keep')! == 'preserved'
	assert os.stat(work + '/outside')!.mode & 0o777 == 0o700 && os.stat(work + '/outside/keep')!.mode & 0o777 == 0o600
	println('EXPORT RETIREMENT alias/dangling/FIFO/hard-link leaves retire without outside traversal, content or mode changes PASS')
}

fn export_retirement_no_flush(_ int) int { return -1 }

fn test_export_publication_failure_preserves_complete_saved_tree_and_exclusive_destinations() {
	work := export_retirement_work('publish')!; defer { os.rmdir_all(work) or {} }
	mut stage := create_export_stage(work, '.vinix-test', 'fixture export')!
	defer { stage.close(); stage.close() }
	export_retirement_file(stage.root, 'keep')!
	mut message := ''
	stage.publish_with(work + '/saved', export_retirement_no_flush) or {
		cause := stage.failure(err); message = cause.msg(); unsafe { cause.free() }
	}
	assert message.contains('published at') && message.contains('directory flush failed') && stage.published
	assert os.read_file(work + '/saved/keep')! == 'preserved' && !os.exists(stage.path)
	for kind in ['file', 'directory', 'alias', 'dangling', 'fifo']! {
		path := work + '/' + kind
		match kind {
			'file' { os.write_file(path, 'preserved')! }
			'directory' { os.mkdir(path)!; os.write_file(path + '/keep', 'preserved')! }
			'alias' { os.symlink(work + '/saved', path)! }
			'dangling' { os.symlink(work + '/absent', path)! }
			else { assert C.mkfifo(path.str, 0o600) == 0 }
		}
		mut collision := create_export_stage(work, '.vinix-test', 'fixture export')!
		mut refused := false
		collision.publish(path) or { cause := collision.failure(err); refused = cause.msg().contains('without replacing'); unsafe { cause.free() } }
		assert refused && !collision.published && !os.exists(collision.path)
		collision.close()
	}
	assert os.read_file(work + '/file')! == 'preserved' && os.read_file(work + '/directory/keep')! == 'preserved'
	assert os.readlink(work + '/alias')! == work + '/saved' && os.readlink(work + '/dangling')! == work + '/absent'
	println('EXPORT RETIREMENT post-publication flush failure retains complete output; existing ordinary/alias/special destinations refuse without replacement PASS')
}

fn test_export_retirement_refuses_unsafe_root_and_foreign_directory_before_unlinking() {
	work := export_retirement_work('refusal')!; defer { os.rmdir_all(work) or {} }
	mut stage := create_export_stage(work, '.vinix-test', 'fixture export')!; defer { stage.close() }
	export_retirement_file(stage.root, 'keep')!
	os.chmod(stage.path, 0o777)!
	mut refused := false
	stage.retire() or { refused = true }
	assert refused && os.read_file(stage.path + '/keep')! == 'preserved'
	os.chmod(stage.path, 0o700)!
	if os.geteuid() == 0 {
		os.mkdir(stage.path + '/foreign')!
		assert C.chown((stage.path + '/foreign').str, 12345, 12345) == 0
		refused = false; stage.retire() or { refused = true }
		assert refused && os.read_file(stage.path + '/keep')! == 'preserved'
		assert C.chown((stage.path + '/foreign').str, 0, 0) == 0
	}
	stage.retire()!
	println('EXPORT RETIREMENT unsafe roots and foreign directory inventory refuse before unlinking; restored ownership/modes permit retry PASS')
}
