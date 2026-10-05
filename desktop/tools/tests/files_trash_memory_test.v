// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os
import ui2

#include "@VMODROOT/heap_tracker.h"

fn C.vinix_heap_begin()
fn C.vinix_heap_end() u64

fn trash_heap_home(suffix string) string {
	base := os.real_path(os.temp_dir())
	pid := C.getpid().str()
	path := '${base}/vinix-trash-heap-${pid}-${suffix}'
	unsafe {
		base.free()
		pid.free()
	}
	os.rmdir_all(path) or {}
	os.mkdir(path) or { panic(err) }
	return path
}

fn trash_heap_write(directory int, name string, text string) bool {
	fd := C.openat(directory, &char(name.str), C.O_WRONLY | C.O_CREAT | C.O_TRUNC | C.O_NOFOLLOW | C.O_CLOEXEC, 0o600)
	if fd < 0 { return false }
	written := desktop_write_all(fd, text.str, u64(text.len))
	closed := desktop_close(fd) == 0
	return written && closed
}

fn trash_heap_descriptors() int {
	mut count := 0
	for fd in 0 .. 512 { if C.fcntl(fd, C.F_GETFD) >= 0 { count++ } }
	return count
}

fn test_trash_measured_move_refresh_conflict_restore_empty_and_frames_release_owned_bytes() {
	home := trash_heap_home('workflows')
	defer {
		os.rmdir_all(home) or {}
		unsafe { home.free() }
	}
	path := '${home}/Café 日本語 😀.txt'
	empty := '${home}/empty'
	defer { unsafe {
		path.free()
		empty.free()
	}
	 }
	mut trash := files_trash_new(home)
	assert trash_heap_write(trash.home_fd, 'Café 日本語 😀.txt', 'contents')
	assert trash.move(path)
	assert C.mkdirat(trash.home_fd, c'empty', 0o700) == 0
	assert trash.move(empty)
	trash.confirming = true
	begin_frame_elements()
	warm := trash.build(ui2.rect(0, 0, 700, 400))
	free_tree(warm)
	trash.empty_confirmed()
	descriptors := trash_heap_descriptors()
	C.vinix_heap_begin()
	for _ in 0 .. 50 {
		assert trash_heap_write(trash.home_fd, 'Café 日本語 😀.txt', 'contents')
		assert trash.move(path)
		trash.reload()
		assert !trash.damaged && trash.entries.len == 1
		trash.action(trash.entries[0].action)
		assert trash_heap_write(trash.home_fd, 'Café 日本語 😀.txt', 'replacement')
		trash.restore()
		assert trash.status == 'files.trash.conflict'
		assert C.unlinkat(trash.home_fd, c'Café 日本語 😀.txt', 0) == 0
		trash.restore()
		assert trash.status == 'files.trash.restored'
		assert trash.move(path)
		assert C.mkdirat(trash.home_fd, c'empty', 0o700) == 0
		assert trash.move(empty)
		trash.action('files.trash.empty')
		begin_frame_elements()
		frame := trash.build(ui2.rect(0, 0, 700, 400))
		free_tree(frame)
		trash.action('files.trash.confirm')
		assert trash.status == 'files.trash.emptied' && trash.entries.len == 0
	}
	assert trash_heap_descriptors() == descriptors
	trash.close()
	trash.close()
	assert C.vinix_heap_end() == 0
}

fn test_trash_measured_init_reload_build_close_release_model_and_descriptors() {
	home := trash_heap_home('lifecycle')
	defer {
		os.rmdir_all(home) or {}
		unsafe { home.free() }
	}
	path := '${home}/saved'
	defer { unsafe { path.free() } }
	mut warm := files_trash_new(home)
	assert trash_heap_write(warm.home_fd, 'saved', 'persistent')
	assert warm.move(path)
	begin_frame_elements()
	tree := warm.build(ui2.rect(0, 0, 700, 376))
	free_tree(tree)
	warm.close()
	descriptors := trash_heap_descriptors()
	C.vinix_heap_begin()
	for _ in 0 .. 50 {
		mut trash := files_trash_new(home)
		trash.reload()
		assert trash.entries.len == 1 && trash.entries[0].path == 'saved'
		trash.reload()
		begin_frame_elements()
		frame := trash.build(ui2.rect(0, 0, 700, 376))
		free_tree(frame)
		trash.close()
		trash.close()
	}
	assert trash_heap_descriptors() == descriptors
	assert C.vinix_heap_end() == 0
}

fn test_trash_measured_invalid_metadata_busy_and_refusal_paths_release_temporaries() {
	home := trash_heap_home('failures')
	defer {
		os.rmdir_all(home) or {}
		unsafe { home.free() }
	}
	path := '${home}/saved'
	unsafe_path := '${home}/../unsafe'
	defer { unsafe {
		path.free()
		unsafe_path.free()
	}
	 }
	mut trash := files_trash_new(home)
	assert trash_heap_write(trash.home_fd, 'saved', 'keep')
	trash.reload()
	lock_fd := files_trash_lock(trash.store_fd)
	assert lock_fd >= 0
	C.vinix_heap_begin()
	for _ in 0 .. 100 {
		assert !trash.move(path) && trash.status == 'files.trash.busy'
		assert !trash.move(unsafe_path) && trash.status == 'files.trash.unsafe'
		if mut row := files_trash_parse('VINIX TRASH 1\n1\t2\t33188\n../unsafe\n') {
			unsafe { row.path.free() }
			assert false
		}
	}
	desktop_close(lock_fd)
	assert trash.move(path)
	bucket := files_trash_checked_bucket(trash.store_fd, &trash.entries[0])
	assert bucket >= 0
	assert trash_heap_write(bucket, 'info', 'corrupt')
	desktop_close(bucket)
	for _ in 0 .. 50 {
		trash.reload()
		assert trash.damaged && trash.entries.len == 0
		trash.action('files.trash.empty')
		trash.action('files.trash.confirm')
		assert trash.status == 'files.trash.damaged'
	}
	trash.close()
	assert C.vinix_heap_end() == 0
}
