// SPDX-License-Identifier: GPL-2.0-or-later
module allocationhost

import cachecli
import hosttest
import os

// The rootfs copy preserves links, including dangling targets, and copy2's
// source metadata. No source or pre-existing destination is removed.
fn copy_rootfs(source string, destination string) ! {
	cachecli.checkpoint()!
	if destination.starts_with(source.trim_right('/') + '/') {
		return error('rootfs destination is inside the source')
	}
	os.mkdir(destination)!
	for name in os.ls(source)! {
		cachecli.checkpoint()!
		from := source + '/' + name
		to := destination + '/' + name
		if os.is_link(from) {
			os.symlink(os.readlink(from)!, to)!
			hosttest.module_copy_link_stat(from, to)!
		} else if os.is_dir(from) {
			copy_rootfs(from, to)!
		} else if os.is_file(from) {
			hosttest.module_copy_file_preserving_stat(from, to)!
		} else {
			return error('unsupported special rootfs file: ' + from)
		}
	}
	hosttest.module_copy_directory_stat(source, destination)!
}

fn make_dirs(path string) ! {
	if os.is_dir(path) { return }
	if path.contains('\x00') { return error('embedded null byte') }
	parent := path.all_before_last('/')
	if parent != '' && parent != path { make_dirs(parent)! }
	os.mkdir(path) or { if !os.is_dir(path) { return err } }
}
