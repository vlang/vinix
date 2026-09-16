// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os

#include <sys/stat.h>

fn C.mkfifo(path &char, mode u32) int

fn scale_test_home(name string) string {
	home := os.join_path(os.temp_dir(), 'vinix-scale-${name}-${os.getpid()}')
	os.mkdir(home) or { panic(err) }
	return home
}

fn test_scale_first_boot_preserves_geometry_defaults_without_writing() {
	home := scale_test_home('defaults')
	defer { os.rmdir_all(home) or {} }
	assert desktop_configure_saved_scale(1920, 1080, home) == desktop_scale_100
	assert desktop_configure_saved_scale(2560, 1600, home) == desktop_scale_200
	assert desktop_load_scale_preference(home) == none
	assert os.ls(home)!.len == 0
}

fn test_scale_preferences_round_trip_both_choices_across_startup() {
	home := scale_test_home('round-trip')
	defer { os.rmdir_all(home) or {} }
	for scale in [desktop_scale_200, desktop_scale_100, desktop_scale_200] {
		assert desktop_save_scale_preference(home, scale)
		assert desktop_load_scale_preference(home)? == scale
		// Startup resets all scale globals before restoring the saved value.
		// A saved 200% overrides QEMU's default, and 100% overrides HiDPI.
		for width in [1920, 2560] {
			assert desktop_configure_saved_scale(width, 1600, home) == scale
			assert desktop_requested_scale() == scale
			assert desktop_current_scale() == scale
			w, h := desktop_scaled_physical_extents(scale)
			assert w == width / scale && h == 1600 / scale
		}
	}
	assert os.ls(home)! == [desktop_scale_preference_name]
}

fn test_scale_preferences_reject_entire_malformed_records() {
	home := scale_test_home('invalid')
	defer { os.rmdir_all(home) or {} }
	path := desktop_scale_preference_path(home)
	for record in ['', '0', '3', '-1', '100', '200', '2junk', '1\n2', '2\n\n',
		'2\x00', ' 2', '2 ', '2\r\n', '2\n' + 'x'.repeat(4096)] {
		os.write_file(path, record)!
		assert desktop_load_scale_preference(home) == none
		assert desktop_configure_saved_scale(1920, 1080, home) == desktop_scale_100
		assert desktop_configure_saved_scale(2560, 1600, home) == desktop_scale_200
		assert os.read_file(path)! == record
	}
	for record in ['1', '1\n', '2', '2\n'] {
		os.write_file(path, record)!
		assert desktop_load_scale_preference(home)? == int(record[0] - `0`)
	}
}

fn test_scale_preferences_save_only_committed_changes() {
	home := scale_test_home('commit')
	defer { os.rmdir_all(home) or {} }
	previous := desktop_configure_saved_scale(1920, 1080, home)
	desktop_request_scale(desktop_scale_200)
	assert desktop_save_scale_change(previous, home)
	assert desktop_load_scale_preference(home) == none
	// Rejection restores the request; it must not create a preference either.
	desktop_restore_requested_scale()
	assert desktop_save_scale_change(previous, home)
	assert desktop_load_scale_preference(home) == none
	desktop_request_scale(desktop_scale_200)
	desktop_commit_scale(desktop_scale_200)
	assert desktop_save_scale_change(previous, home)
	assert desktop_load_scale_preference(home)? == desktop_scale_200
	// With no new commit, even an inaccessible home must require no I/O.
	assert desktop_save_scale_change(desktop_scale_200, '${home}/absent')
}

fn test_scale_preferences_replace_atomically_and_keep_old_open_file() {
	home := scale_test_home('replace')
	defer { os.rmdir_all(home) or {} }
	path := desktop_scale_preference_path(home)
	assert desktop_save_scale_preference(home, desktop_scale_200)
	fd := desktop_open_rw(path)
	assert fd >= 0
	defer { desktop_close(fd) }
	assert desktop_save_scale_preference(home, desktop_scale_100)
	mut old := [2]u8{}
	assert desktop_read(fd, &old[0], 2) == 2
	assert old == [u8(`2`), `\n`]!
	assert os.read_file(path)! == '1\n'
	mut info := C.stat{}
	assert C.fstat(fd, &info) == 0
	assert u32(info.st_mode) & 0o777 == 0o600
	for invalid in [-1, 0, 3, 100, 200] {
		assert !desktop_save_scale_preference(home, invalid)
		assert os.read_file(path)! == '1\n'
	}
	assert os.ls(home)! == [desktop_scale_preference_name]
}

fn test_scale_preferences_failures_clean_up_without_changing_live_scale() {
	home := scale_test_home('failures')
	defer { os.rmdir_all(home) or {} }
	assert desktop_load_scale_preference('') == none
	assert !desktop_save_scale_preference('', desktop_scale_200)
	assert !desktop_save_scale_preference('${home}/absent', desktop_scale_200)
	// A directory at the destination forces rename to fail after the write.
	path := desktop_scale_preference_path(home)
	os.mkdir(path)!
	assert desktop_load_scale_preference(home) == none
	desktop_configure_scale(1920, 1080)
	desktop_request_scale(desktop_scale_200)
	desktop_commit_scale(desktop_scale_200)
	assert !desktop_save_scale_change(desktop_scale_100, home)
	assert desktop_current_scale() == desktop_scale_200
	assert desktop_requested_scale() == desktop_scale_200
	assert os.is_dir(path)
	assert os.ls(home)! == [desktop_scale_preference_name]
}

fn test_scale_preferences_fifo_does_not_block_startup() {
	home := scale_test_home('fifo')
	defer { os.rmdir_all(home) or {} }
	path := desktop_scale_preference_path(home)
	assert C.mkfifo(&char(path.str), 0o600) == 0
	assert desktop_load_scale_preference(home) == none
	assert desktop_configure_saved_scale(1920, 1080, home) == desktop_scale_100
}
