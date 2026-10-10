// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module volumecli

import os

struct BundleIO {
mut:
	mode    int
	writes  int
	flushes int
	closes  int
	renames int
}

__global bundle_io BundleIO

fn bundle_mock_write(fd i32, buffer voidptr, bytes usize) i64 {
	bundle_io.writes++
	if bundle_io.mode == 1 && bundle_io.writes == 1 {
		unsafe {
			C.errno = C.EINTR
		}
		return -1
	}
	if bundle_io.mode == 2 {
		unsafe {
			C.errno = C.EIO
		}
		return -1
	}
	return C.write(fd, buffer, if bundle_io.mode == 1 && bytes > 3 { usize(3) } else { bytes })
}

fn bundle_mock_fsync(fd i32) i32 {
	bundle_io.flushes++
	if (bundle_io.mode == 3 && bundle_io.flushes == 1)
		|| (bundle_io.mode == 4 && bundle_io.flushes == 2) {
		unsafe {
			C.errno = C.EIO
		}
		return -1
	}
	return C.fsync(fd)
}

fn bundle_mock_close(fd i32) i32 {
	bundle_io.closes++
	result := C.close(fd)
	if bundle_io.mode == 5 && bundle_io.closes == 1 {
		unsafe {
			C.errno = C.EIO
		}
		return -1
	}
	return result
}

fn bundle_mock_renameat(from_fd i32, from &char, to_fd i32, to &char) i32 {
	bundle_io.renames++
	if bundle_io.mode == 6 {
		unsafe {
			C.errno = C.EIO
		}
		return -1
	}
	return C.renameat(from_fd, from, to_fd, to)
}

fn test_bundle_publication_handles_interruption_short_writes_and_every_durability_failure() {
	work := os.join_path(os.temp_dir(), 'vinix-bundle-io-${os.getpid()}')
	os.mkdir(work)!
	defer { os.rmdir_all(work) or {} }
	path := work + '/saved.vset'
	mut set := PlanSet{}
	mut plan := Plan{
		count: 1
		key:   DiskKey{
			bytes:  4096
			sector: 512
			kind:   1
		}
	}
	plan.key.id[0] = 1
	plan.rows[0] = Request{
		slot:   2
		length: 512
	}
	assert append_plan(mut set, &plan)
	for mode in 1 .. 7 {
		bundle_io = BundleIO{}
		set.plans[0].rows[0].length = 512
		assert publish_bundle(path.str, &set)
		original := os.read_bytes(path)!
		set.plans[0].rows[0].length = 1024
		bundle_io = BundleIO{
			mode: mode
		}
		assert publish_bundle(path.str, &set) == (mode == 1)
		assert bundle_io.closes == 2 // Temporary and anchored directory, each once.
		assert os.ls(work)!.len == 1 // No temporary survives any failure.
		current := os.read_bytes(path)!
		mut decoded := PlanSet{}
		assert decode_bundle(current.data, current.len, mut decoded)
		if mode == 1 || mode == 4 {
			assert current != original && decoded.plans[0].rows[0].length == 1024
			assert bundle_io.renames == 1 && bundle_io.flushes == 2
		} else {
			assert current == original && decoded.plans[0].rows[0].length == 512
		}
		if mode == 1 { assert bundle_io.writes > 50
		 }
		if mode == 2 || mode == 3 || mode == 5 { assert bundle_io.renames == 0
		 }
	}
}
