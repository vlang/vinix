// SPDX-License-Identifier: GPL-2.0-or-later
module sessioncore

import os

fn test_atomic_snapshots_replace_sync_and_reject_oversized_reads() {
	directory := os.join_path(os.temp_dir(), 'vinix-session-store-${os.getpid()}')
	os.mkdir(directory) or { panic(err) }
	defer {
		os.rmdir_all(directory) or {}
		unsafe { directory.free() }
	}
	path := '${directory}/state'
	defer { unsafe { path.free() } }
	save(path, 'first snapshot') or { panic(err) }
	save(path, 'replacement') or { panic(err) }
	record := load(path, 64) or { panic(err) }
	defer { unsafe { record.free() } }
	assert record == 'replacement'
	assert os.stat(path)!.mode & 0o077 == 0
	if _ := load(path, 2) {
		assert false, 'oversized state accepted'
	}
	assert os.ls(directory)!.len == 1
}
