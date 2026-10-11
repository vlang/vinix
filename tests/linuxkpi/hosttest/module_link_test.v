// SPDX-License-Identifier: GPL-2.0-or-later
module hosttest

import os

fn test_link_copy_uses_own_sdk_nanosecond_times_without_following_targets() {
	work := work_dir('', 'vinix-link-stat-') or { panic(err) }
	defer { remove_work_dir(work) or { panic(err) } }
	source := work + '/source'
	target := work + '/target'
	os.symlink('absent', source) or { panic(err) }
	os.symlink('/definitely/not/a/vinix/file', target) or { panic(err) }
	times := [C.timespec{1700000000, 123456789}, C.timespec{1700000001, 987654321}]!
	assert C.utimensat(C.AT_FDCWD, source.str, &times[0], C.AT_SYMLINK_NOFOLLOW) == 0
	module_copy_link_stat(source, target) or { panic(err) }
	mut original := C.vinix_module_stat{}
	mut copied := C.vinix_module_stat{}
	assert C.vinix_module_lstat_path(source.str, &original) == 0
	assert C.vinix_module_lstat_path(target.str, &copied) == 0
	assert original.st_atime == copied.st_atime
	assert original.st_mtime == copied.st_mtime
	assert original.vinix_module_atime_nsec == copied.vinix_module_atime_nsec
	assert original.vinix_module_mtime_nsec == copied.vinix_module_mtime_nsec
	assert os.readlink(target) or { panic(err) } == '/definitely/not/a/vinix/file'
}
