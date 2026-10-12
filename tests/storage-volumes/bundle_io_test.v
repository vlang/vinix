// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module volumecli

import os

fn C.fork() i32
fn C.dup2(i32, i32) i32
fn C.waitpid(i32, &i32, i32) i32
fn C._exit(i32)
fn C.setvbuf(voidptr, &char, i32, usize) i32

// Reopen the inode to obtain an independent open description. Duplicating the
// publisher descriptor would share its lock and would not test exclusion.
fn bundle_assert_directory_locked(directory i32) {
	probe := C.openat(directory, c'.', C.O_RDONLY | C.O_DIRECTORY | C.O_CLOEXEC)
	assert probe >= 0
	assert C.flock(probe, C.LOCK_EX | C.LOCK_NB) == -1
	assert unsafe { C.errno == C.EWOULDBLOCK || C.errno == C.EAGAIN }
	assert C.close(probe) == 0
}

struct BundleIO {
mut:
	mode    int
	writes  int
	flushes int
	closes  int
	renames int
}

__global bundle_io BundleIO

struct EnrollmentReadIO {
mut:
	mode int
	opens int
	closes int
	stats int
	reads int
	fds [64]i32
	first &char = unsafe { nil }
	replacement &char = unsafe { nil }
	moved &char = unsafe { nil }
}

__global enrollment_read_io EnrollmentReadIO

fn enrollment_mock_open(path &char, flags i32) i32 {
	enrollment_read_io.opens++
	if enrollment_read_io.mode == 9 && enrollment_read_io.opens == 2 { unsafe { C.errno = C.EIO }; return -1 }
	fd := C.open(path, flags)
	if fd >= 0 {
		assert enrollment_read_io.opens <= 64
		enrollment_read_io.fds[enrollment_read_io.opens - 1] = fd
		assert C.fcntl(fd, C.F_GETFD) & C.FD_CLOEXEC != 0 && C.fcntl(fd, C.F_GETFL) & C.O_ACCMODE == C.O_RDONLY
	}
	if enrollment_read_io.opens == 2 && enrollment_read_io.mode in [1, 2, 3, 4] {
		if enrollment_read_io.mode == 4 {
			assert C.renameat(C.AT_FDCWD, enrollment_read_io.first, C.AT_FDCWD, enrollment_read_io.moved) == 0
			assert C.renameat(C.AT_FDCWD, enrollment_read_io.replacement, C.AT_FDCWD, enrollment_read_io.first) == 0
		} else {
			changed := C.open(enrollment_read_io.first, C.O_WRONLY | if enrollment_read_io.mode == 3 { C.O_TRUNC } else { 0 })
			assert changed >= 0
			if enrollment_read_io.mode == 1 {
				mut byte := u8(0x77); assert C.write(changed, &byte, 1) == 1
			} else if enrollment_read_io.mode == 2 {
				mut replacement := Plan{key: DiskKey{bytes: 65536, sector: 4096, kind: 2}}
				replacement.key.id[0] = 2; mut bytes := [2112]u8{}
				size := encode_plan(&replacement, &bytes[0]); assert size == 64 && C.write(changed, &bytes[0], usize(size)) == size
			}
			assert C.close(changed) == 0
		}
	}
	return fd
}

fn enrollment_mock_close(fd i32) i32 {
	enrollment_read_io.closes++
	return C.close(fd)
}

fn enrollment_mock_fstat(fd i32, info &C.stat) i32 {
	enrollment_read_io.stats++
	if enrollment_read_io.mode == 8 && enrollment_read_io.stats == 2 { unsafe { C.errno = C.EIO }; return -1 }
	result := C.fstat(fd, info)
	if result == 0 && enrollment_read_io.mode == 7 { unsafe { info.st_size++ } }
	return result
}

fn enrollment_mock_pread(fd i32, buffer voidptr, bytes usize, offset i64) i64 {
	enrollment_read_io.reads++
	if enrollment_read_io.mode == 5 && enrollment_read_io.reads == 1 { unsafe { C.errno = C.EINTR }; return -1 }
	if enrollment_read_io.mode == 6 { return 0 }
	return C.pread(fd, buffer, if enrollment_read_io.mode == 5 && bytes > 7 { usize(7) } else { bytes }, offset)
}

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
	mut info := C.stat{}
	assert C.fstat(fd, &info) == 0
	if info.st_mode & C.S_IFMT == C.S_IFDIR { bundle_assert_directory_locked(fd) }
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
	assert from_fd == to_fd
	bundle_assert_directory_locked(from_fd)
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

fn test_add_and_remove_commands_use_atomic_publication_and_cleanup_on_every_io_failure() {
	work := os.join_path(os.temp_dir(), 'vinix-edit-io-${os.getpid()}')
	os.mkdir(work)!
	defer { os.rmdir_all(work) or {} }
	path := work + '/saved.vset'
	for remove in [false, true] {
		for mode in 1 .. 7 {
			mut set := PlanSet{}
			mut plan := Plan{count: if remove { u32(2) } else { u32(1) },
				key: DiskKey{bytes: 4096, sector: 512, kind: 1}}
			plan.key.id[0] = 1
			plan.rows[0] = Request{slot: 2, length: 512}
			plan.rows[1] = Request{slot: 5, offset: 1024, length: 512, flags: 1}
			assert append_plan(mut set, &plan)
			bundle_io = BundleIO{}
			assert publish_bundle(path.str, &set)
			original := os.read_bytes(path)!
			row := if remove { plan.rows[0] } else { plan.rows[1] }
			bundle_io = BundleIO{mode: mode}
			assert edit_bundle_plan(path.str, 0, &row, remove) == if mode == 1 { 0 } else { 1 }
			assert bundle_io.closes == 2 && os.ls(work)!.len == 1
			current := os.read_bytes(path)!
			mut decoded := PlanSet{}
			assert decode_bundle(current.data, current.len, mut decoded)
			if mode == 1 || mode == 4 {
				assert current != original && decoded.plans[0].count == if remove { u32(1) } else { u32(2) }
				assert decoded.plans[0].rows[if remove { 0 } else { 1 }].slot == 5
				assert bundle_io.renames == 1 && bundle_io.flushes == 2
			} else {
				assert current == original
			}
		}
	}
}

fn test_enroll_and_forget_commands_preserve_inputs_and_use_atomic_publication_on_io_failures() {
	work := os.join_path(os.temp_dir(), 'vinix-membership-io-${os.getpid()}')
	os.mkdir(work)!
	defer { os.rmdir_all(work) or {} }
	path := work + '/saved.vset'
	source := work + '/member.vmap'
	for forget in [false, true] {
		for mode in 1 .. 7 {
			mut set := PlanSet{}
			mut first := Plan{count: 1, key: DiskKey{bytes: 4096, sector: 512, kind: 1}}
			first.key.id[0] = 1
			first.rows[0] = Request{slot: 2, length: 512}
			mut second := Plan{key: DiskKey{bytes: 4096, sector: 512, kind: 1}}
			second.key.id[0] = 2
			assert append_plan(mut set, &first)
			if forget { assert append_plan(mut set, &second) }
			bundle_io = BundleIO{}
			assert publish_bundle(path.str, &set) && publish_plan(source.str, &second)
			original := os.read_bytes(path)!
			input := os.read_bytes(source)!
			bundle_io = BundleIO{mode: mode}
			result := if forget { forget_bundle_disk(path.str, 1) } else { enroll_bundle_disk(path.str, source.str) }
			assert result == if mode == 1 { 0 } else { 1 }
			assert bundle_io.closes == 2 && os.ls(work)!.len == 2
			assert os.read_bytes(source)! == input
			current := os.read_bytes(path)!
			mut decoded := PlanSet{}
			assert decode_bundle(current.data, current.len, mut decoded) && decoded.plans[0] == first
			if mode == 1 || mode == 4 {
				assert current != original && decoded.count == if forget { 1 } else { 2 }
				assert bundle_io.renames == 1 && bundle_io.flushes == 2
			} else { assert current == original }
		}
	}
}

fn test_allocation_uses_shared_atomic_publisher_for_every_io_fault() {
	work := os.join_path(os.temp_dir(), 'vinix-space-io-${os.getpid()}')
	os.mkdir(work)!
	defer { os.rmdir_all(work) or {} }
	path := work + '/saved.vset'
	for mode in 1 .. 7 {
		mut set := PlanSet{}
		mut plan := Plan{count: 1, key: DiskKey{bytes: 4096, sector: 512, kind: 1}}
		plan.key.id[0] = 1
		plan.rows[0] = Request{slot: 2, length: 512}
		assert append_plan(mut set, &plan)
		bundle_io = BundleIO{}
		assert publish_bundle(path.str, &set)
		original := os.read_bytes(path)!
		bundle_io = BundleIO{mode: mode}
		window := SpaceWindow{start: 512, end: 4096, alignment: 1024}
		row := Request{slot: 9, length: 512, flags: 1}
		assert space_bundle_plan(path.str, 0, window, &row, true) == if mode == 1 { 0 } else { 1 }
		assert bundle_io.closes == 2 && os.ls(work)!.len == 1
		current := os.read_bytes(path)!
		mut decoded := PlanSet{}
		assert decode_bundle(current.data, current.len, mut decoded)
		assert decoded.plans[0].rows[0] == plan.rows[0]
		if mode == 1 || mode == 4 {
			assert current != original && decoded.plans[0].count == 2
			assert decoded.plans[0].rows[1] == Request{slot: 9, offset: 1024, length: 512, flags: 1}
			assert bundle_io.renames == 1 && bundle_io.flushes == 2
		} else { assert current == original }
	}
}

fn test_pool_membership_and_allocation_publish_metadata_and_mappings_together_on_every_fault() {
	work := os.join_path(os.temp_dir(), 'vinix-pool-io-${os.getpid()}')
	os.mkdir(work)!
	defer { os.rmdir_all(work) or {} }
	path := work + '/saved.vset'
	for operation in 0 .. 3 {
		for mode in 1 .. 7 {
			mut set := PlanSet{}
			mut plan := Plan{ key: DiskKey{ bytes: 8192, sector: 512, kind: 1 } }
			plan.key.id[0] = 1
			assert append_plan(mut set, &plan)
			region := PoolRegion{ pool: 3, disk: 0, window: SpaceWindow{ start: 1024, end: 8192, alignment: 4096 } }
			if operation != 0 {
				assert bundle_pool_add(mut set, &region)
			}
			bundle_io = BundleIO{}
			assert publish_bundle(path.str, &set)
			original := os.read_bytes(path)!
			bundle_io = BundleIO{ mode: mode }
			row := Request{ slot: 9, length: 4096, flags: 1 }
			result := if operation == 2 {
				allocate_pool_plan(path.str, 3, &row)
			} else {
				edit_pool_plan(path.str, &region, operation == 1)
			}
			assert result == if mode == 1 { 0 } else { 1 }
			assert bundle_io.closes == 2 && os.ls(work)!.len == 1
			current := os.read_bytes(path)!
			mut decoded := PlanSet{}
			assert decode_bundle(current.data, current.len, mut decoded)
			if mode == 1 || mode == 4 {
				assert current != original && bundle_io.renames == 1 && bundle_io.flushes == 2
				assert decoded.regions == if operation == 1 { 0 } else { 1 }
				assert decoded.plans[0].count == if operation == 2 { u32(1) } else { u32(0) }
				if operation == 2 {
					assert decoded.windows[0] == region
					assert decoded.plans[0].rows[0] == Request{ slot: 9, offset: 4096, length: 4096, flags: 1 }
				}
			} else {
				assert current == original
			}
		}
	}
}

fn test_pool_expansion_growth_and_equal_size_retries_complete_the_shared_durability_protocol() {
	work := os.join_path(os.temp_dir(), 'vinix-pool-growth-io-${os.getpid()}')
	os.mkdir(work)!
	defer { os.rmdir_all(work) or {} }
	path := work + '/saved.vset'
	for expand in [false, true] {
		for equal in [false, true] {
			for mode in 1 .. 7 {
				mut set := PlanSet{}
				mut plan := Plan{count: 1, key: DiskKey{bytes: 32768, sector: 512, kind: 1}}
				plan.key.id[0] = 1
				plan.rows[0] = Request{slot: 9, offset: 4096, length: if !expand && equal { u64(8192) } else { u64(4096) }, flags: 1}
				assert append_plan(mut set, &plan)
				region := PoolRegion{pool: 3, disk: 0, window: SpaceWindow{start: 4096,
					end: if expand && !equal { u64(8192) } else { u64(16384) }, alignment: 4096}}
				assert bundle_pool_add(mut set, &region)
				bundle_io = BundleIO{}
				assert publish_bundle(path.str, &set)
				original := os.read_bytes(path)!
				bundle_io = BundleIO{mode: mode}
				index := if expand { u32(0) } else { u32(9) }
				size := if expand { u64(16384) } else { u64(8192) }
				assert grow_pool_plan(path.str, 3, index, size, expand) == if mode == 1 { 0 } else { 1 }
				assert bundle_io.closes == 2 && os.ls(work)!.len == 1 && bundle_io.writes > 0
				current := os.read_bytes(path)!
				mut decoded := PlanSet{}
				assert decode_bundle(current.data, current.len, mut decoded) && decoded.regions == 1
				if mode == 1 || mode == 4 {
					assert (current == original) == equal && bundle_io.renames == 1 && bundle_io.flushes == 2
					assert decoded.windows[0].window.end == 16384
					assert decoded.plans[0].rows[0].length == if expand { u64(4096) } else { u64(8192) }
					assert decoded.plans[0].rows[0].flags == 1 && decoded.plans[0].rows[0].offset == 4096
					// A retry after failed directory fsync must publish and flush even
					// though the complete new desired geometry is already visible.
					bundle_io = BundleIO{}
					assert grow_pool_plan(path.str, 3, index, size, expand) == 0 && os.read_bytes(path)! == current
					assert bundle_io.writes > 0 && bundle_io.renames == 1 && bundle_io.flushes == 2 && bundle_io.closes == 2
				} else { assert current == original }
			}
		}
	}
}

fn test_pool_expansion_and_growth_detect_buffered_stdout_failure_after_complete_publication() {
	work := os.join_path(os.temp_dir(), 'vinix-pool-growth-output-${os.getpid()}')
	os.mkdir(work)!
	defer { os.rmdir_all(work) or {} }
	path := work + '/saved.vset'
	for expand in [false, true] {
		mut set := PlanSet{}
		mut plan := Plan{count: 1, key: DiskKey{bytes: 32768, sector: 512, kind: 1}}
		plan.key.id[0] = 1
		plan.rows[0] = Request{slot: 9, offset: 4096, length: 4096, flags: 1}
		assert append_plan(mut set, &plan)
		region := PoolRegion{pool: 3, disk: 0, window: SpaceWindow{start: 4096,
			end: if expand { u64(8192) } else { u64(16384) }, alignment: 4096}}
		assert bundle_pool_add(mut set, &region)
		bundle_io = BundleIO{}
		assert publish_bundle(path.str, &set) && C.fflush(C.stdout) == 0
		child := C.fork()
		assert child >= 0
		if child == 0 {
			fd := C.open(c'/dev/null', C.O_RDONLY)
			if fd < 0 || C.dup2(fd, 1) != 1 { C._exit(2) }
			C.close(fd)
			mut buffer := [4096]char{}
			if C.setvbuf(C.stdout, &buffer[0], C._IOFBF, 4096) != 0 { C._exit(3) }
			result := grow_pool_plan(path.str, 3, if expand { u32(0) } else { u32(9) },
				if expand { u64(16384) } else { u64(8192) }, expand)
			C._exit(if result == 1 { 0 } else { 4 })
		}
		mut result := i32(-1)
		assert C.waitpid(child, &result, 0) == child && result == 0
		data := os.read_bytes(path)!
		mut decoded := PlanSet{}
		assert decode_bundle(data.data, data.len, mut decoded) && decoded.windows[0].window.end == 16384
		assert decoded.plans[0].rows[0].length == if expand { u64(4096) } else { u64(8192) }
	}
}

fn test_pool_batches_publish_all_rows_or_preserve_old_file_and_retry_every_durability_failure() {
	work := os.join_path(os.temp_dir(), 'vinix-pool-batch-io-${os.getpid()}')
	os.mkdir(work)!
	defer { os.rmdir_all(work) or {} }
	path := work + '/saved.vset'
	mut batch := PoolBatch{count: 2}
	batch.rows[0] = Request{slot: 20, length: 4096, flags: 1}
	batch.rows[1] = Request{slot: 21, length: 4096}
	for retry in [false, true] {
		for mode in 1 .. 7 {
			mut set := PlanSet{}
			for p in 0 .. 2 {
				mut plan := Plan{key: DiskKey{bytes: 32768, sector: 512, kind: 1}}
				plan.key.id[0] = u8(p + 1)
				assert append_plan(mut set, &plan)
				region := PoolRegion{pool: 3, disk: u32(p), window: SpaceWindow{start: 4096, end: 8192, alignment: 4096}}
				assert bundle_pool_add(mut set, &region)
			}
			bundle_io = BundleIO{}
			assert publish_bundle(path.str, &set)
			if retry { assert batch_pool_plan(path.str, 3, &batch, false) == 0 }
			original := os.read_bytes(path)!
			bundle_io = BundleIO{mode: mode}
			assert batch_pool_plan(path.str, 3, &batch, false) == if mode == 1 { 0 } else { 1 }
			assert bundle_io.closes == 2 && bundle_io.writes > 0 && os.ls(work)!.len == 1
			current := os.read_bytes(path)!
			mut decoded := PlanSet{}
			assert decode_bundle(current.data, current.len, mut decoded)
			if mode == 1 || mode == 4 {
				assert (current == original) == retry && bundle_io.renames == 1 && bundle_io.flushes == 2
				assert decoded.plans[0].count == 1 && decoded.plans[1].count == 1
				assert decoded.plans[0].rows[0] == Request{slot: 20, offset: 4096, length: 4096, flags: 1}
				assert decoded.plans[1].rows[0] == Request{slot: 21, offset: 4096, length: 4096}
			} else { assert current == original }
			// The failed directory flush left a complete new bundle. A retry
			// keeps those exact rows and completes both publisher flushes.
			bundle_io = BundleIO{}
			assert batch_pool_plan(path.str, 3, &batch, false) == 0
			assert bundle_io.writes > 0 && bundle_io.renames == 1 && bundle_io.flushes == 2 && bundle_io.closes == 2
			completed := os.read_bytes(path)!
			bundle_io = BundleIO{mode: mode}
			assert batch_pool_plan(path.str, 3, &batch, true) == 0 && os.read_bytes(path)! == completed
			assert bundle_io == BundleIO{mode: mode} // Preview never enters the publisher.
			batch.rows[1].length = 8192
			assert batch_pool_plan(path.str, 3, &batch, false) == 1 && os.read_bytes(path)! == completed
			assert bundle_io == BundleIO{mode: mode}
			batch.rows[1].length = 4096
		}
	}
}

fn test_pool_batch_preview_and_publication_detect_buffered_stdout_failure() {
	work := os.join_path(os.temp_dir(), 'vinix-pool-batch-output-${os.getpid()}')
	os.mkdir(work)!
	defer { os.rmdir_all(work) or {} }
	path := work + '/saved.vset'
	mut batch := PoolBatch{count: 2}
	batch.rows[0] = Request{slot: 20, length: 4096, flags: 1}
	batch.rows[1] = Request{slot: 21, length: 4096}
	for preview in [false, true] {
		mut set := PlanSet{}
		mut plan := Plan{key: DiskKey{bytes: 32768, sector: 512, kind: 1}}
		plan.key.id[0] = 1
		assert append_plan(mut set, &plan)
		region := PoolRegion{pool: 3, disk: 0, window: SpaceWindow{start: 4096, end: 16384, alignment: 4096}}
		assert bundle_pool_add(mut set, &region)
		bundle_io = BundleIO{}
		assert publish_bundle(path.str, &set) && C.fflush(C.stdout) == 0
		original := os.read_bytes(path)!
		child := C.fork()
		assert child >= 0
		if child == 0 {
			fd := C.open(c'/dev/null', C.O_RDONLY)
			if fd < 0 || C.dup2(fd, 1) != 1 { C._exit(2) }
			C.close(fd)
			mut buffer := [4096]char{}
			if C.setvbuf(C.stdout, &buffer[0], C._IOFBF, 4096) != 0 { C._exit(3) }
			result := batch_pool_plan(path.str, 3, &batch, preview)
			C._exit(if result == 1 { 0 } else { 4 })
		}
		mut result := i32(-1)
		assert C.waitpid(child, &result, 0) == child && result == 0
		current := os.read_bytes(path)!
		assert (current == original) == preview
		mut decoded := PlanSet{}
		assert decode_bundle(current.data, current.len, mut decoded)
		assert decoded.plans[0].count == if preview { u32(0) } else { u32(2) }
	}
}

fn test_pool_growth_batches_complete_publication_and_equal_size_retries_under_every_fault() {
	work := os.join_path(os.temp_dir(), 'vinix-grow-batch-io-${os.getpid()}')
	os.mkdir(work)!
	defer { os.rmdir_all(work) or {} }
	path := work + '/saved.vset'
	mut batch := PoolGrowthBatch{count: 2}
	batch.slots[0] = 20; batch.lengths[0] = 8192
	batch.slots[1] = 21; batch.lengths[1] = 8192
	for retry in [false, true] {
		for mode in 1 .. 7 {
			mut set := PlanSet{}
			for p in 0 .. 2 {
				mut plan := Plan{count: 1, key: DiskKey{bytes: 32768, sector: 512, kind: 1}}
				plan.key.id[0] = u8(p + 1)
				plan.rows[0] = Request{slot: u32(20 + p), offset: 4096, length: 4096, flags: u64(p)}
				assert append_plan(mut set, &plan)
				region := PoolRegion{pool: 3, disk: u32(p), window: SpaceWindow{start: 4096, end: 16384, alignment: 4096}}
				assert bundle_pool_add(mut set, &region)
			}
			bundle_io = BundleIO{}
			assert publish_bundle(path.str, &set)
			if retry { assert grow_batch_pool_plan(path.str, 3, &batch, false) == 0 }
			original := os.read_bytes(path)!
			bundle_io = BundleIO{mode: mode}
			assert grow_batch_pool_plan(path.str, 3, &batch, false) == if mode == 1 { 0 } else { 1 }
			assert bundle_io.closes == 2 && bundle_io.writes > 0 && os.ls(work)!.len == 1
			current := os.read_bytes(path)!
			mut decoded := PlanSet{}
			assert decode_bundle(current.data, current.len, mut decoded)
			if mode == 1 || mode == 4 {
				assert (current == original) == retry && bundle_io.renames == 1 && bundle_io.flushes == 2
				for p in 0 .. 2 { assert decoded.plans[p].rows[0] == Request{slot: u32(20 + p), offset: 4096, length: 8192, flags: u64(p)} }
			} else { assert current == original }
			bundle_io = BundleIO{}
			assert grow_batch_pool_plan(path.str, 3, &batch, false) == 0
			assert bundle_io.writes > 0 && bundle_io.renames == 1 && bundle_io.flushes == 2 && bundle_io.closes == 2
			completed := os.read_bytes(path)!
			bundle_io = BundleIO{mode: mode}
			assert grow_batch_pool_plan(path.str, 3, &batch, true) == 0 && os.read_bytes(path)! == completed
			assert bundle_io == BundleIO{mode: mode}
			batch.lengths[1] = 16384
			assert grow_batch_pool_plan(path.str, 3, &batch, false) == 1 && os.read_bytes(path)! == completed
			assert bundle_io == BundleIO{mode: mode}
			batch.lengths[1] = 8192
		}
	}
}

fn test_pool_growth_batch_preview_and_publication_detect_buffered_output_failure() {
	work := os.join_path(os.temp_dir(), 'vinix-grow-batch-output-${os.getpid()}')
	os.mkdir(work)!
	defer { os.rmdir_all(work) or {} }
	path := work + '/saved.vset'
	for preview in [false, true] {
		mut set := PlanSet{}
		mut plan := Plan{count: 1, key: DiskKey{bytes: 32768, sector: 512, kind: 1}}
		plan.key.id[0] = 1; plan.rows[0] = Request{slot: 20, offset: 4096, length: 4096, flags: 1}
		assert append_plan(mut set, &plan)
		region := PoolRegion{pool: 3, disk: 0, window: SpaceWindow{start: 4096, end: 16384, alignment: 4096}}
		assert bundle_pool_add(mut set, &region)
		bundle_io = BundleIO{}
		assert publish_bundle(path.str, &set) && C.fflush(C.stdout) == 0
		original := os.read_bytes(path)!
		child := C.fork()
		assert child >= 0
		if child == 0 {
			fd := C.open(c'/dev/null', C.O_RDONLY)
			if fd < 0 || C.dup2(fd, 1) != 1 { C._exit(2) }
			C.close(fd)
			mut buffer := [4096]char{}
			if C.setvbuf(C.stdout, &buffer[0], C._IOFBF, 4096) != 0 { C._exit(3) }
			mut batch := PoolGrowthBatch{count: 1}
			batch.slots[0] = 20; batch.lengths[0] = 8192
			C._exit(if grow_batch_pool_plan(path.str, 3, &batch, preview) == 1 { 0 } else { 4 })
		}
		mut code := i32(-1)
		assert C.waitpid(child, &code, 0) == child && code == 0
		current := os.read_bytes(path)!
		assert (current == original) == preview
		mut decoded := PlanSet{}
		assert decode_bundle(current.data, current.len, mut decoded)
		assert decoded.plans[0].rows[0].length == if preview { u64(4096) } else { u64(8192) }
	}
}

fn test_pool_expansion_batches_publish_whole_members_and_equal_end_retries_under_every_fault() {
	work := os.join_path(os.temp_dir(), 'vinix-expand-batch-io-${os.getpid()}')
	os.mkdir(work)!
	defer { os.rmdir_all(work) or {} }
	path := work + '/saved.vset'
	mut batch := PoolExpansionBatch{count: 2}
	batch.disks[0] = 0; batch.ends[0] = 16384; batch.disks[1] = 1; batch.ends[1] = 16384
	for retry in [false, true] {
		for mode in 1 .. 7 {
			mut set := PlanSet{}
			for p in 0 .. 2 {
				mut plan := Plan{count: 1, key: DiskKey{bytes: 32768, sector: 512, kind: 1}}
				plan.key.id[0] = u8(p + 1)
				plan.rows[0] = Request{slot: u32(20 + p), offset: 4096, length: 8192, flags: u64(p)}
				assert append_plan(mut set, &plan)
				region := PoolRegion{pool: 3, disk: u32(p), window: SpaceWindow{start: 4096, end: 8192, alignment: 4096}}
				assert bundle_pool_add(mut set, &region)
			}
			bundle_io = BundleIO{}
			assert publish_bundle(path.str, &set)
			if retry { assert expand_batch_pool_plan(path.str, 3, &batch, false) == 0 }
			original := os.read_bytes(path)!
			bundle_io = BundleIO{mode: mode}
			assert expand_batch_pool_plan(path.str, 3, &batch, false) == if mode == 1 { 0 } else { 1 }
			assert bundle_io.closes == 2 && bundle_io.writes > 0 && os.ls(work)!.len == 1
			current := os.read_bytes(path)!
			mut decoded := PlanSet{}
			assert decode_bundle(current.data, current.len, mut decoded) && decoded.plans == set.plans
			if mode == 1 || mode == 4 {
				assert (current == original) == retry && bundle_io.renames == 1 && bundle_io.flushes == 2
				for p in 0 .. 2 { assert decoded.windows[p] == PoolRegion{pool: 3, disk: u32(p), window: SpaceWindow{start: 4096, end: 16384, alignment: 4096}} }
			} else { assert current == original }
			bundle_io = BundleIO{}
			assert expand_batch_pool_plan(path.str, 3, &batch, false) == 0
			assert bundle_io.writes > 0 && bundle_io.renames == 1 && bundle_io.flushes == 2 && bundle_io.closes == 2
			completed := os.read_bytes(path)!
			bundle_io = BundleIO{mode: mode}
			assert expand_batch_pool_plan(path.str, 3, &batch, true) == 0 && os.read_bytes(path)! == completed
			assert bundle_io == BundleIO{mode: mode}
			batch.ends[1] = 36864
			assert expand_batch_pool_plan(path.str, 3, &batch, false) == 1 && os.read_bytes(path)! == completed
			assert bundle_io == BundleIO{mode: mode}
			batch.ends[1] = 16384
		}
	}
}

fn test_pool_expansion_batch_preview_and_publication_detect_buffered_output_failure() {
	work := os.join_path(os.temp_dir(), 'vinix-expand-batch-output-${os.getpid()}')
	os.mkdir(work)!
	defer { os.rmdir_all(work) or {} }
	path := work + '/saved.vset'
	for preview in [false, true] {
		mut set := PlanSet{}
		mut plan := Plan{count: 1, key: DiskKey{bytes: 32768, sector: 512, kind: 1}}
		plan.key.id[0] = 1; plan.rows[0] = Request{slot: 20, offset: 4096, length: 4096, flags: 1}
		assert append_plan(mut set, &plan)
		region := PoolRegion{pool: 3, disk: 0, window: SpaceWindow{start: 4096, end: 8192, alignment: 4096}}
		assert bundle_pool_add(mut set, &region)
		bundle_io = BundleIO{}
		assert publish_bundle(path.str, &set) && C.fflush(C.stdout) == 0
		original := os.read_bytes(path)!
		child := C.fork()
		assert child >= 0
		if child == 0 {
			fd := C.open(c'/dev/null', C.O_RDONLY)
			if fd < 0 || C.dup2(fd, 1) != 1 { C._exit(2) }
			C.close(fd)
			mut buffer := [4096]char{}
			if C.setvbuf(C.stdout, &buffer[0], C._IOFBF, 4096) != 0 { C._exit(3) }
			mut batch := PoolExpansionBatch{count: 1}
			batch.disks[0] = 0; batch.ends[0] = 16384
			C._exit(if expand_batch_pool_plan(path.str, 3, &batch, preview) == 1 { 0 } else { 4 })
		}
		mut code := i32(-1)
		assert C.waitpid(child, &code, 0) == child && code == 0
		current := os.read_bytes(path)!
		assert (current == original) == preview
		mut decoded := PlanSet{}
		assert decode_bundle(current.data, current.len, mut decoded) && decoded.plans == set.plans
		assert decoded.windows[0].window.end == if preview { u64(8192) } else { u64(16384) }
	}
}

fn members_io_fixture(mut set PlanSet, present bool) {
	for disk in 0 .. 2 {
		mut plan := Plan{count: 1, key: DiskKey{bytes: 32768, sector: if disk == 0 { u64(512) } else { u64(4096) }, kind: 1}}
		plan.key.id[0] = u8(disk + 1)
		plan.rows[0] = Request{slot: u32(disk + 2), length: 8192, flags: u64(disk)}
		assert append_plan(mut set, &plan)
		other := PoolRegion{pool: 4, disk: u32(disk), window: SpaceWindow{start: 16384, end: 24576, alignment: 4096}}
		assert bundle_pool_add(mut set, &other)
		if present {
			row := PoolRegion{pool: 3, disk: u32(disk), window: SpaceWindow{start: 8192, end: 12288, alignment: 4096}}
			assert bundle_pool_add(mut set, &row)
		}
	}
}

fn test_pool_membership_batches_and_retries_use_shared_atomic_publication_under_every_fault() {
	work := os.join_path(os.temp_dir(), 'vinix-members-batch-io-${os.getpid()}')
	os.mkdir(work)!
	defer { os.rmdir_all(work) or {} }
	path := work + '/saved.vset'
	mut batch := PoolMembersBatch{count: 2}
	for i in 0 .. 2 { batch.rows[i] = PoolRegion{pool: 3, disk: u32(1 - i), window: SpaceWindow{start: 8192, end: 12288, alignment: 4096}} }
	for remove in [false, true] {
		for retry in [false, true] {
			for mode in 1 .. 7 {
				mut set := PlanSet{}
				members_io_fixture(mut set, remove)
				bundle_io = BundleIO{}
				assert publish_bundle(path.str, &set)
				mut expected := set
				mut outcome := PoolMembersResults{}
				assert bundle_pool_members_batch(mut expected, 3, &batch, remove, mut outcome)
				if retry { assert members_batch_pool_plan(path.str, 3, &batch, remove, false) == 0 }
				original := os.read_bytes(path)!
				bundle_io = BundleIO{mode: mode}
				assert members_batch_pool_plan(path.str, 3, &batch, remove, false) == if mode == 1 { 0 } else { 1 }
				assert bundle_io.closes == 2 && bundle_io.writes > 0 && os.ls(work)!.len == 1
				current := os.read_bytes(path)!
				mut decoded := PlanSet{}
				assert decode_bundle(current.data, current.len, mut decoded)
				if mode == 1 || mode == 4 {
					assert decoded == expected && (current == original) == retry
					assert bundle_io.renames == 1 && bundle_io.flushes == 2
				} else { assert current == original }
				bundle_io = BundleIO{}
				assert members_batch_pool_plan(path.str, 3, &batch, remove, false) == 0
				assert bundle_io.renames == 1 && bundle_io.flushes == 2 && bundle_io.closes == 2 && bundle_io.writes > 0
				completed := os.read_bytes(path)!
				bundle_io = BundleIO{mode: mode}
				assert members_batch_pool_plan(path.str, 3, &batch, remove, true) == 0
				assert os.read_bytes(path)! == completed && bundle_io == BundleIO{mode: mode}
				batch.rows[1].disk = 2
				assert members_batch_pool_plan(path.str, 3, &batch, remove, false) == 1
				assert os.read_bytes(path)! == completed && bundle_io == BundleIO{mode: mode}
				batch.rows[1].disk = 0
			}
		}
	}
}

fn test_pool_membership_batch_previews_and_publication_detect_buffered_stdout_failure() {
	work := os.join_path(os.temp_dir(), 'vinix-members-batch-output-${os.getpid()}')
	os.mkdir(work)!
	defer { os.rmdir_all(work) or {} }
	path := work + '/saved.vset'
	mut batch := PoolMembersBatch{count: 2}
	for disk in 0 .. 2 { batch.rows[disk] = PoolRegion{pool: 3, disk: u32(disk), window: SpaceWindow{start: 8192, end: 12288, alignment: 4096}} }
	for remove in [false, true] {
		for preview in [false, true] {
			mut set := PlanSet{}
			members_io_fixture(mut set, remove)
			bundle_io = BundleIO{}
			assert publish_bundle(path.str, &set) && C.fflush(C.stdout) == 0
			original := os.read_bytes(path)!
			child := C.fork(); assert child >= 0
			if child == 0 {
				fd := C.open(c'/dev/null', C.O_RDONLY)
				if fd < 0 || C.dup2(fd, 1) != 1 { C._exit(2) }
				C.close(fd)
				mut buffer := [4096]char{}
				if C.setvbuf(C.stdout, &buffer[0], C._IOFBF, 4096) != 0 { C._exit(3) }
				C._exit(if members_batch_pool_plan(path.str, 3, &batch, remove, preview) == 1 { 0 } else { 4 })
			}
			mut code := i32(-1)
			assert C.waitpid(child, &code, 0) == child && code == 0
			current := os.read_bytes(path)!
			assert (current == original) == preview
			mut expected := set
			mut result := PoolMembersResults{}
			if !preview { assert bundle_pool_members_batch(mut expected, 3, &batch, remove, mut result) }
			mut decoded := PlanSet{}
			assert decode_bundle(current.data, current.len, mut decoded) && decoded == expected
		}
	}
}

fn test_priority_changes_and_all_keep_retries_use_atomic_publication_under_every_fault() {
	work := os.join_path(os.temp_dir(), 'vinix-priority-io-${os.getpid()}')
	os.mkdir(work)!; defer { os.rmdir_all(work) or {} }
	path := work + '/saved.vset'
	mut order := PoolOrder{count: 2}; order.disks[0] = 1; order.disks[1] = 0
	for retry in [false, true] {
		for mode in 1 .. 7 {
			mut set := PlanSet{}; members_io_fixture(mut set, true)
			bundle_io = BundleIO{}; assert publish_bundle(path.str, &set)
			mut expected := set; expected.windows[1] = set.windows[3]; expected.windows[3] = set.windows[1]
			if retry { assert order_pool_plan(path.str, 3, &order, false) == 0 }
			original := os.read_bytes(path)!
			bundle_io = BundleIO{mode: mode}
			assert order_pool_plan(path.str, 3, &order, false) == if mode == 1 { 0 } else { 1 }
			assert bundle_io.closes == 2 && bundle_io.writes > 0 && os.ls(work)!.len == 1
			current := os.read_bytes(path)!
			mut decoded := PlanSet{}; assert decode_bundle(current.data, current.len, mut decoded)
			if mode == 1 || mode == 4 {
				assert decoded == expected && (current == original) == retry
				assert bundle_io.renames == 1 && bundle_io.flushes == 2
			} else { assert current == original }
			bundle_io = BundleIO{}; assert order_pool_plan(path.str, 3, &order, false) == 0
			assert bundle_io.renames == 1 && bundle_io.flushes == 2 && bundle_io.closes == 2 && bundle_io.writes > 0
			completed := os.read_bytes(path)!
			bundle_io = BundleIO{mode: mode}
			assert order_pool_plan(path.str, 3, &order, true) == 0 && os.read_bytes(path)! == completed
			assert bundle_io == BundleIO{mode: mode}
			order.disks[1] = 2
			assert order_pool_plan(path.str, 3, &order, false) == 1 && os.read_bytes(path)! == completed
			assert bundle_io == BundleIO{mode: mode}; order.disks[1] = 0
		}
	}
}

fn test_priority_preview_and_publication_detect_buffered_stdout_failure() {
	work := os.join_path(os.temp_dir(), 'vinix-priority-output-${os.getpid()}')
	os.mkdir(work)!; defer { os.rmdir_all(work) or {} }
	path := work + '/saved.vset'
	mut order := PoolOrder{count: 2}; order.disks[0] = 1; order.disks[1] = 0
	for preview in [false, true] {
		mut set := PlanSet{}; members_io_fixture(mut set, true)
		bundle_io = BundleIO{}; assert publish_bundle(path.str, &set) && C.fflush(C.stdout) == 0
		original := os.read_bytes(path)!
		child := C.fork(); assert child >= 0
		if child == 0 {
			fd := C.open(c'/dev/null', C.O_RDONLY)
			if fd < 0 || C.dup2(fd, 1) != 1 { C._exit(2) }; C.close(fd)
			mut buffer := [4096]char{}
			if C.setvbuf(C.stdout, &buffer[0], C._IOFBF, 4096) != 0 { C._exit(3) }
			C._exit(if order_pool_plan(path.str, 3, &order, preview) == 1 { 0 } else { 4 })
		}
		mut code := i32(-1); assert C.waitpid(child, &code, 0) == child && code == 0
		current := os.read_bytes(path)!; assert (current == original) == preview
		mut expected := set
		if !preview { expected.windows[1] = set.windows[3]; expected.windows[3] = set.windows[1] }
		mut decoded := PlanSet{}; assert decode_bundle(current.data, current.len, mut decoded) && decoded == expected
	}
}

fn test_mapping_removal_batches_and_absent_retries_are_atomic_under_every_publisher_fault() {
	work := os.join_path(os.temp_dir(), 'vinix-removal-batch-io-${os.getpid()}')
	os.mkdir(work)!; defer { os.rmdir_all(work) or {} }
	path := work + '/saved.vset'
	mut batch := MappingRemovalBatch{count: 3}
	batch.slots[0] = 3; batch.slots[1] = 63; batch.slots[2] = 2
	for retry in [false, true] {
		for mode in 1 .. 7 {
			mut set := PlanSet{}; members_io_fixture(mut set, true)
			bundle_io = BundleIO{}; assert publish_bundle(path.str, &set)
			mut expected := set; expected.slots = 0
			for disk in 0 .. 2 { expected.plans[disk].count = 0; expected.plans[disk].rows[0] = Request{} }
			if retry { assert remove_batch_bundle_plan(path.str, &batch, false) == 0 }
			original := os.read_bytes(path)!
			bundle_io = BundleIO{mode: mode}
			assert remove_batch_bundle_plan(path.str, &batch, false) == if mode == 1 { 0 } else { 1 }
			assert bundle_io.closes == 2 && bundle_io.writes > 0 && os.ls(work)!.len == 1
			current := os.read_bytes(path)!
			mut decoded := PlanSet{}; assert decode_bundle(current.data, current.len, mut decoded)
			if mode == 1 || mode == 4 {
				assert decoded == expected && (current == original) == retry
				assert bundle_io.renames == 1 && bundle_io.flushes == 2
			} else { assert current == original }
			bundle_io = BundleIO{}; assert remove_batch_bundle_plan(path.str, &batch, false) == 0
			assert bundle_io.renames == 1 && bundle_io.flushes == 2 && bundle_io.closes == 2 && bundle_io.writes > 0
			completed := os.read_bytes(path)!
			bundle_io = BundleIO{mode: mode}
			assert remove_batch_bundle_plan(path.str, &batch, true) == 0 && os.read_bytes(path)! == completed
			assert bundle_io == BundleIO{mode: mode}
			batch.slots[2] = 3
			assert remove_batch_bundle_plan(path.str, &batch, false) == 1 && os.read_bytes(path)! == completed
			assert bundle_io == BundleIO{mode: mode}; batch.slots[2] = 2
		}
	}
}

fn test_mapping_removal_preview_and_publication_detect_buffered_stdout_failure() {
	work := os.join_path(os.temp_dir(), 'vinix-removal-batch-output-${os.getpid()}')
	os.mkdir(work)!; defer { os.rmdir_all(work) or {} }
	path := work + '/saved.vset'
	mut batch := MappingRemovalBatch{count: 2}; batch.slots[0] = 3; batch.slots[1] = 2
	for preview in [false, true] {
		mut set := PlanSet{}; members_io_fixture(mut set, true)
		bundle_io = BundleIO{}; assert publish_bundle(path.str, &set) && C.fflush(C.stdout) == 0
		original := os.read_bytes(path)!
		child := C.fork(); assert child >= 0
		if child == 0 {
			fd := C.open(c'/dev/null', C.O_RDONLY)
			if fd < 0 || C.dup2(fd, 1) != 1 { C._exit(2) }; C.close(fd)
			mut buffer := [4096]char{}
			if C.setvbuf(C.stdout, &buffer[0], C._IOFBF, 4096) != 0 { C._exit(3) }
			C._exit(if remove_batch_bundle_plan(path.str, &batch, preview) == 1 { 0 } else { 4 })
		}
		mut code := i32(-1); assert C.waitpid(child, &code, 0) == child && code == 0
		current := os.read_bytes(path)!; assert (current == original) == preview
		mut expected := set
		if !preview {
			expected.slots = 0
			for disk in 0 .. 2 { expected.plans[disk].count = 0; expected.plans[disk].rows[0] = Request{} }
		}
		mut decoded := PlanSet{}; assert decode_bundle(current.data, current.len, mut decoded) && decoded == expected
	}
}

fn enrollment_io_fixture(mut set PlanSet, mut first Plan, mut second Plan) {
	mut anchor := Plan{count: 1, key: DiskKey{bytes: 32768, sector: 512, kind: 1}}
	anchor.key.id[0] = 1; anchor.rows[0] = Request{slot: 2, length: 4096, flags: 1}
	assert append_plan(mut set, &anchor)
	region := PoolRegion{pool: 3, disk: 0, window: SpaceWindow{start: 16384, end: 24576, alignment: 4096}}
	assert bundle_pool_add(mut set, &region)
	first = Plan{key: DiskKey{bytes: 32768, sector: 4096, kind: 2}}; first.key.id[0] = 2
	second = Plan{count: 1, key: DiskKey{bytes: 65536, sector: 4096, kind: 1}}
	second.key.id[0] = 3; second.rows[0] = Request{slot: 9, offset: 4096, length: 8192, flags: 1}
}

fn test_enrollment_pins_and_rechecks_every_source_and_closes_all_descriptors_on_failure() {
	work := os.join_path(os.temp_dir(), 'vinix-enrollment-read-${os.getpid()}')
	os.mkdir(work)!; defer { os.rmdir_all(work) or {} }
	path := work + '/saved.vset'; first_path := work + '/first.vmap'; second_path := work + '/second.vmap'
	replacement_path := work + '/replacement.vmap'; moved_path := work + '/moved.vmap'
	for preview in [false, true] {
		for mode in 0 .. 10 {
			mut set := PlanSet{}; mut first := Plan{}; mut second := Plan{}
			enrollment_io_fixture(mut set, mut first, mut second)
			bundle_io = BundleIO{}; enrollment_read_io = EnrollmentReadIO{}
			assert publish_bundle(path.str, &set) && publish_plan(first_path.str, &first) && publish_plan(second_path.str, &second)
			mut replacement := first; replacement.key.id[0] = 99
			assert publish_plan(replacement_path.str, &replacement)
			original := os.read_bytes(path)!
			enrollment_read_io = EnrollmentReadIO{mode: mode, first: first_path.str, replacement: replacement_path.str, moved: moved_path.str}
			bundle_io = BundleIO{}
			unsafe {
				inputs := [first_path.str, second_path.str]!
				success := mode in [0, 4, 5]
				assert enroll_batch_bundle_plan(path.str, 2, &inputs[0], preview) == if success { 0 } else { 1 }
				assert enrollment_read_io.closes == if mode == 9 { 1 } else { 2 }
				for i in 0 .. enrollment_read_io.closes { assert C.fcntl(enrollment_read_io.fds[i], C.F_GETFD) == -1 }
				if !success || preview { assert os.read_bytes(path)! == original && bundle_io == BundleIO{} }
				else {
					mut expected := set; expected.count = 3; expected.slots |= u64(1) << 9
					expected.plans[1] = first; expected.plans[2] = second
					current := os.read_bytes(path)!; mut decoded := PlanSet{}
					assert decode_bundle(current.data, current.len, mut decoded) && decoded == expected
					assert bundle_io.renames == 1 && bundle_io.flushes == 2
				}
				if success { assert enrollment_read_io.stats == 2 && enrollment_read_io.reads >= 4 }
				if mode == 5 { assert enrollment_read_io.reads > 20 }
			}
			if mode == 4 { os.rm(moved_path)! }
		}
	}
	enrollment_read_io = EnrollmentReadIO{}
}

fn test_enrollment_batches_and_all_keep_retries_use_atomic_publication_under_every_fault() {
	work := os.join_path(os.temp_dir(), 'vinix-enrollment-publish-${os.getpid()}')
	os.mkdir(work)!; defer { os.rmdir_all(work) or {} }
	path := work + '/saved.vset'; first_path := work + '/first.vmap'; second_path := work + '/second.vmap'
	for retry in [false, true] {
		for mode in 1 .. 7 {
			mut set := PlanSet{}; mut first := Plan{}; mut second := Plan{}
			enrollment_io_fixture(mut set, mut first, mut second)
			bundle_io = BundleIO{}; enrollment_read_io = EnrollmentReadIO{}
			assert publish_bundle(path.str, &set) && publish_plan(first_path.str, &first) && publish_plan(second_path.str, &second)
			mut expected := set; expected.count = 3; expected.slots |= u64(1) << 9
			expected.plans[1] = first; expected.plans[2] = second
			unsafe {
				inputs := [first_path.str, second_path.str]!
				if retry { assert enroll_batch_bundle_plan(path.str, 2, &inputs[0], false) == 0 }
				original := os.read_bytes(path)!
				bundle_io = BundleIO{mode: mode}; enrollment_read_io = EnrollmentReadIO{}
				assert enroll_batch_bundle_plan(path.str, 2, &inputs[0], false) == if mode == 1 { 0 } else { 1 }
				assert enrollment_read_io.closes == 2 && enrollment_read_io.stats == 2
				assert bundle_io.closes == 2 && bundle_io.writes > 0 && os.ls(work)!.len == 3
				current := os.read_bytes(path)!; mut decoded := PlanSet{}
				assert decode_bundle(current.data, current.len, mut decoded)
				if mode == 1 || mode == 4 {
					assert decoded == expected && (current == original) == retry
					assert bundle_io.renames == 1 && bundle_io.flushes == 2
				} else { assert current == original }
				bundle_io = BundleIO{}; enrollment_read_io = EnrollmentReadIO{}
				assert enroll_batch_bundle_plan(path.str, 2, &inputs[0], false) == 0 && bundle_io.flushes == 2 && bundle_io.renames == 1
				completed := os.read_bytes(path)!
				bundle_io = BundleIO{mode: mode}; enrollment_read_io = EnrollmentReadIO{}
				assert enroll_batch_bundle_plan(path.str, 2, &inputs[0], true) == 0 && os.read_bytes(path)! == completed
				assert bundle_io == BundleIO{mode: mode} && enrollment_read_io.closes == 2 && enrollment_read_io.stats == 2
			}
		}
	}
}

fn test_enrollment_preview_and_publication_detect_buffered_stdout_failure() {
	work := os.join_path(os.temp_dir(), 'vinix-enrollment-output-${os.getpid()}')
	os.mkdir(work)!; defer { os.rmdir_all(work) or {} }
	path := work + '/saved.vset'; first_path := work + '/first.vmap'; second_path := work + '/second.vmap'
	for preview in [false, true] {
		mut set := PlanSet{}; mut first := Plan{}; mut second := Plan{}
		enrollment_io_fixture(mut set, mut first, mut second)
		bundle_io = BundleIO{}; enrollment_read_io = EnrollmentReadIO{}
		assert publish_bundle(path.str, &set) && publish_plan(first_path.str, &first) && publish_plan(second_path.str, &second) && C.fflush(C.stdout) == 0
		original := os.read_bytes(path)!
		child := C.fork(); assert child >= 0
		if child == 0 {
			fd := C.open(c'/dev/null', C.O_RDONLY)
			if fd < 0 || C.dup2(fd, 1) != 1 { C._exit(2) }; C.close(fd)
			mut buffer := [4096]char{}
			if C.setvbuf(C.stdout, &buffer[0], C._IOFBF, 4096) != 0 { C._exit(3) }
			unsafe {
				inputs := [first_path.str, second_path.str]!
				C._exit(if enroll_batch_bundle_plan(path.str, 2, &inputs[0], preview) == 1 && enrollment_read_io.closes == 2 { 0 } else { 4 })
			}
		}
		mut code := i32(-1); assert C.waitpid(child, &code, 0) == child && code == 0
		current := os.read_bytes(path)!; assert (current == original) == preview
		mut expected := set
		if !preview { expected.count = 3; expected.slots |= u64(1) << 9; expected.plans[1] = first; expected.plans[2] = second }
		mut decoded := PlanSet{}; assert decode_bundle(current.data, current.len, mut decoded) && decoded == expected
	}
}

fn forget_io_fixture(mut set PlanSet, mut batch DiskForgetBatch, mut expected PlanSet) {
	for member in [2, 1, 3, 4]! {
		mut plan := Plan{key: DiskKey{bytes: 65536, sector: 512, kind: 1}}
		plan.key.id[0] = u8(member)
		if member == 1 { plan.count = 1; plan.rows[0] = Request{slot: 2, length: 4096, flags: 1} }
		assert append_plan(mut set, &plan)
	}
	for disk in [u32(3), 1]! {
		region := PoolRegion{pool: 3, disk: disk, window: SpaceWindow{start: 32768, end: 49152, alignment: 4096}}
		assert bundle_pool_add(mut set, &region)
	}
	batch.count = 3; batch.keys[0] = set.plans[2].key; batch.keys[1] = set.plans[0].key
	batch.keys[2] = DiskKey{kind: 1}; batch.keys[2].id[0] = 9
	expected = PlanSet{count: 2, slots: set.slots, regions: 2}
	expected.plans[0] = set.plans[1]; expected.plans[1] = set.plans[3]
	expected.windows[0] = set.windows[0]; expected.windows[0].disk = 1
	expected.windows[1] = set.windows[1]; expected.windows[1].disk = 0
}

fn test_forget_batches_and_absent_retries_preserve_complete_sets_under_publisher_faults() {
	work := os.join_path(os.temp_dir(), 'vinix-forget-publish-${os.getpid()}')
	os.mkdir(work)!; defer { os.rmdir_all(work) or {} }
	path := work + '/saved.vset'
	for retry in [false, true] {
		for mode in 1 .. 7 {
			mut set := PlanSet{}; mut batch := DiskForgetBatch{}; mut expected := PlanSet{}
			forget_io_fixture(mut set, mut batch, mut expected)
			bundle_io = BundleIO{}
			assert publish_bundle(path.str, &set)
			if retry { assert forget_batch_bundle_plan(path.str, &batch, false) == 0 }
			original := os.read_bytes(path)!
			bundle_io = BundleIO{mode: mode}
			assert forget_batch_bundle_plan(path.str, &batch, false) == if mode == 1 { 0 } else { 1 }
			assert bundle_io.closes == 2 && bundle_io.writes > 0 && os.ls(work)!.len == 1
			current := os.read_bytes(path)!; mut decoded := PlanSet{}
			assert decode_bundle(current.data, current.len, mut decoded)
			if mode == 1 || mode == 4 {
				assert decoded == expected && (current == original) == retry && bundle_io.renames == 1 && bundle_io.flushes == 2
			} else { assert current == original }
			bundle_io = BundleIO{}
			assert forget_batch_bundle_plan(path.str, &batch, false) == 0 && bundle_io.renames == 1 && bundle_io.flushes == 2
			completed := os.read_bytes(path)!; bundle_io = BundleIO{mode: mode}
			assert forget_batch_bundle_plan(path.str, &batch, true) == 0 && os.read_bytes(path)! == completed && bundle_io == BundleIO{mode: mode}
		}
	}
}

fn test_forget_preview_and_publication_detect_buffered_stdout_failure() {
	work := os.join_path(os.temp_dir(), 'vinix-forget-output-${os.getpid()}')
	os.mkdir(work)!; defer { os.rmdir_all(work) or {} }
	path := work + '/saved.vset'
	for preview in [false, true] {
		mut set := PlanSet{}; mut batch := DiskForgetBatch{}; mut expected := PlanSet{}
		forget_io_fixture(mut set, mut batch, mut expected); bundle_io = BundleIO{}
		assert publish_bundle(path.str, &set) && C.fflush(C.stdout) == 0
		original := os.read_bytes(path)!
		child := C.fork(); assert child >= 0
		if child == 0 {
			fd := C.open(c'/dev/null', C.O_RDONLY)
			if fd < 0 || C.dup2(fd, 1) != 1 { C._exit(2) }; C.close(fd)
			mut buffer := [4096]char{}
			if C.setvbuf(C.stdout, &buffer[0], C._IOFBF, 4096) != 0 { C._exit(3) }
			C._exit(if forget_batch_bundle_plan(path.str, &batch, preview) == 1 { 0 } else { 4 })
		}
		mut code := i32(-1); assert C.waitpid(child, &code, 0) == child && code == 0
		current := os.read_bytes(path)!; assert (current == original) == preview
		mut decoded := PlanSet{}; assert decode_bundle(current.data, current.len, mut decoded) && decoded == if preview { set } else { expected }
	}
}

fn addition_io_fixture(mut set PlanSet, mut batch MappingAdditionBatch, mut expected PlanSet) {
	for member in [1, 2]! {
		mut plan := Plan{key: DiskKey{bytes: 65536, sector: if member == 1 { u64(512) } else { u64(4096) }, kind: u32(member)}}
		plan.key.id[0] = u8(member)
		if member == 1 { plan.count = 1; plan.rows[0] = Request{slot: 2, length: 4096, flags: 1} }
		assert append_plan(mut set, &plan)
	}
	for disk in [u32(1), 0]! {
		region := PoolRegion{pool: 3, disk: disk, window: SpaceWindow{start: 32768, end: 49152, alignment: 4096}}
		assert bundle_pool_add(mut set, &region)
	}
	batch.count = 3; batch.keys[0] = set.plans[0].key; batch.rows[0] = set.plans[0].rows[0]
	batch.keys[1] = set.plans[1].key; batch.rows[1] = Request{slot: 9, offset: 8192, length: 4096, flags: 1}
	batch.keys[2] = set.plans[0].key; batch.rows[2] = Request{slot: 12, offset: 8192, length: 8192}
	unsafe { expected = *(&set) }; expected.plans[0].count = 2; expected.plans[0].rows[1] = batch.rows[2]
	expected.plans[1].count = 1; expected.plans[1].rows[0] = batch.rows[1]; expected.slots |= (u64(1) << 9) | (u64(1) << 12)
}

fn test_explicit_addition_batches_and_keep_retries_use_atomic_publication_under_every_fault() {
	work := os.join_path(os.temp_dir(), 'vinix-addition-publish-${os.getpid()}')
	os.mkdir(work)!; defer { os.rmdir_all(work) or {} }
	path := work + '/saved.vset'
	for retry in [false, true] {
		for mode in 1 .. 7 {
			mut set := PlanSet{}; mut batch := MappingAdditionBatch{}; mut expected := PlanSet{}
			addition_io_fixture(mut set, mut batch, mut expected); bundle_io = BundleIO{}
			assert publish_bundle(path.str, &set)
			if retry { assert add_batch_bundle_plan(path.str, &batch, false) == 0 }
			original := os.read_bytes(path)!; bundle_io = BundleIO{mode: mode}
			assert add_batch_bundle_plan(path.str, &batch, false) == if mode == 1 { 0 } else { 1 }
			assert bundle_io.closes == 2 && bundle_io.writes > 0 && os.ls(work)!.len == 1
			current := os.read_bytes(path)!; mut decoded := PlanSet{}
			assert decode_bundle(current.data, current.len, mut decoded)
			if mode == 1 || mode == 4 { assert decoded == expected && (current == original) == retry && bundle_io.renames == 1 && bundle_io.flushes == 2 }
			else { assert current == original }
			bundle_io = BundleIO{}
			assert add_batch_bundle_plan(path.str, &batch, false) == 0 && bundle_io.renames == 1 && bundle_io.flushes == 2
			completed := os.read_bytes(path)!; bundle_io = BundleIO{mode: mode}
			assert add_batch_bundle_plan(path.str, &batch, true) == 0 && os.read_bytes(path)! == completed && bundle_io == BundleIO{mode: mode}
		}
	}
}

fn test_explicit_addition_preview_and_publication_detect_buffered_stdout_failure() {
	work := os.join_path(os.temp_dir(), 'vinix-addition-output-${os.getpid()}')
	os.mkdir(work)!; defer { os.rmdir_all(work) or {} }
	path := work + '/saved.vset'
	for preview in [false, true] {
		mut set := PlanSet{}; mut batch := MappingAdditionBatch{}; mut expected := PlanSet{}
		addition_io_fixture(mut set, mut batch, mut expected); bundle_io = BundleIO{}
		assert publish_bundle(path.str, &set) && C.fflush(C.stdout) == 0
		original := os.read_bytes(path)!; child := C.fork(); assert child >= 0
		if child == 0 {
			fd := C.open(c'/dev/null', C.O_RDONLY)
			if fd < 0 || C.dup2(fd, 1) != 1 { C._exit(2) }; C.close(fd)
			mut buffer := [4096]char{}
			if C.setvbuf(C.stdout, &buffer[0], C._IOFBF, 4096) != 0 { C._exit(3) }
			C._exit(if add_batch_bundle_plan(path.str, &batch, preview) == 1 { 0 } else { 4 })
		}
		mut code := i32(-1); assert C.waitpid(child, &code, 0) == child && code == 0
		current := os.read_bytes(path)!; assert (current == original) == preview
		mut decoded := PlanSet{}; assert decode_bundle(current.data, current.len, mut decoded)
		if preview { assert decoded == set } else { assert decoded == expected }
	}
}

fn explicit_growth_io_fixture(mut set PlanSet, mut batch MappingGrowthBatch, mut expected PlanSet) {
	for member in [1, 2]! {
		mut plan := Plan{key: DiskKey{bytes: 65536, sector: if member == 1 { u64(512) } else { u64(4096) }, kind: u32(member)}, count: 1}
		plan.key.id[0] = u8(member)
		plan.rows[0] = Request{slot: if member == 1 { u32(2) } else { u32(9) }, offset: 8192, length: 4096, flags: u64(member & 1)}
		if member == 1 { plan.count = 2; plan.rows[1] = Request{slot: 12, offset: 16384, length: 4096} }
		assert append_plan(mut set, &plan)
	}
	for disk in [u32(1), 0]! {
		region := PoolRegion{pool: 3, disk: disk, window: SpaceWindow{start: 32768, end: 49152, alignment: 4096}}
		assert bundle_pool_add(mut set, &region)
	}
	batch.count = 3; batch.keys[0] = set.plans[0].key; batch.slots[0] = 2; batch.lengths[0] = 4096
	batch.keys[1] = set.plans[1].key; batch.slots[1] = 9; batch.lengths[1] = 8192
	batch.keys[2] = set.plans[0].key; batch.slots[2] = 12; batch.lengths[2] = 8192
	unsafe { expected = *(&set) }; expected.plans[0].rows[1].length = 8192; expected.plans[1].rows[0].length = 8192
}

fn test_explicit_growth_and_equal_size_retries_publish_whole_sets_under_every_fault() {
	work := os.join_path(os.temp_dir(), 'vinix-explicit-growth-publish-${os.getpid()}')
	os.mkdir(work)!; defer { os.rmdir_all(work) or {} }
	path := work + '/saved.vset'
	for retry in [false, true] {
		for mode in 1 .. 7 {
			mut set := PlanSet{}; mut batch := MappingGrowthBatch{}; mut expected := PlanSet{}
			explicit_growth_io_fixture(mut set, mut batch, mut expected); bundle_io = BundleIO{}
			assert publish_bundle(path.str, &set)
			if retry { assert grow_batch_bundle_plan(path.str, &batch, false) == 0 }
			original := os.read_bytes(path)!; bundle_io = BundleIO{mode: mode}
			assert grow_batch_bundle_plan(path.str, &batch, false) == if mode == 1 { 0 } else { 1 }
			assert bundle_io.closes == 2 && bundle_io.writes > 0 && os.ls(work)!.len == 1
			current := os.read_bytes(path)!; mut decoded := PlanSet{}
			assert decode_bundle(current.data, current.len, mut decoded)
			if mode == 1 || mode == 4 { assert decoded == expected && (current == original) == retry && bundle_io.renames == 1 && bundle_io.flushes == 2 }
			else { assert current == original }
			bundle_io = BundleIO{}
			assert grow_batch_bundle_plan(path.str, &batch, false) == 0 && bundle_io.renames == 1 && bundle_io.flushes == 2
			completed := os.read_bytes(path)!; bundle_io = BundleIO{mode: mode}
			assert grow_batch_bundle_plan(path.str, &batch, true) == 0 && os.read_bytes(path)! == completed && bundle_io == BundleIO{mode: mode}
		}
	}
}

fn test_explicit_growth_preview_and_publication_detect_buffered_stdout_failure() {
	work := os.join_path(os.temp_dir(), 'vinix-explicit-growth-output-${os.getpid()}')
	os.mkdir(work)!; defer { os.rmdir_all(work) or {} }
	path := work + '/saved.vset'
	for preview in [false, true] {
		mut set := PlanSet{}; mut batch := MappingGrowthBatch{}; mut expected := PlanSet{}
		explicit_growth_io_fixture(mut set, mut batch, mut expected); bundle_io = BundleIO{}
		assert publish_bundle(path.str, &set) && C.fflush(C.stdout) == 0
		original := os.read_bytes(path)!; child := C.fork(); assert child >= 0
		if child == 0 {
			fd := C.open(c'/dev/null', C.O_RDONLY)
			if fd < 0 || C.dup2(fd, 1) != 1 { C._exit(2) }; C.close(fd)
			mut buffer := [4096]char{}
			if C.setvbuf(C.stdout, &buffer[0], C._IOFBF, 4096) != 0 { C._exit(3) }
			C._exit(if grow_batch_bundle_plan(path.str, &batch, preview) == 1 { 0 } else { 4 })
		}
		mut code := i32(-1); assert C.waitpid(child, &code, 0) == child && code == 0
		current := os.read_bytes(path)!; assert (current == original) == preview
		mut decoded := PlanSet{}; assert decode_bundle(current.data, current.len, mut decoded)
		if preview { assert decoded == set } else { assert decoded == expected }
	}
}

fn contraction_io_fixture(mut set PlanSet, mut batch PoolContractionBatch, mut expected PlanSet) {
	for member in [1, 2, 3]! {
		mut plan := Plan{key: DiskKey{bytes: 65536, sector: if member == 2 { u64(4096) } else { u64(512) }, kind: if member == 2 { u32(2) } else { u32(1) }}, count: 1}
		plan.key.id[0] = u8(member); plan.rows[0] = Request{slot: u32(member), offset: 8192, length: 4096, flags: u64(member & 1)}
		assert append_plan(mut set, &plan)
	}
	for disk in [u32(2), 0, 1]! {
		region := PoolRegion{pool: 3, disk: disk, window: SpaceWindow{start: 8192, end: 32768, alignment: 4096}}; assert bundle_pool_add(mut set, &region)
		other := PoolRegion{pool: 4, disk: disk, window: SpaceWindow{start: 32768, end: 49152, alignment: 4096}}; assert bundle_pool_add(mut set, &other)
	}
	batch.count = 3; batch.keys[0] = set.plans[2].key; batch.ends[0] = 32768
	batch.keys[1] = set.plans[1].key; batch.ends[1] = 24576; batch.keys[2] = set.plans[0].key; batch.ends[2] = 16384
	unsafe { expected = *(&set) }
	for disk in [1, 0]! {
		for at in 0 .. expected.regions {
			row := expected.windows[at]; if row.pool != 3 || row.disk != u32(disk) { continue }
			expected.windows[at] = PoolRegion{pool: 3, disk: row.disk, window: SpaceWindow{start: row.window.start, end: if disk == 1 { u64(24576) } else { u64(16384) }, alignment: row.window.alignment}}
		}
	}
}

fn test_pool_contraction_and_equal_end_retries_publish_complete_sets_under_every_fault() {
	work := os.join_path(os.temp_dir(), 'vinix-contraction-publish-${os.getpid()}'); os.mkdir(work)!; defer { os.rmdir_all(work) or {} }; path := work + '/saved.vset'
	for retry in [false, true] {
		for mode in 1 .. 7 {
			mut set := PlanSet{}; mut batch := PoolContractionBatch{}; mut expected := PlanSet{}
			contraction_io_fixture(mut set, mut batch, mut expected); bundle_io = BundleIO{}; assert publish_bundle(path.str, &set)
			if retry { assert contract_batch_pool_plan(path.str, 3, &batch, false) == 0 }
			original := os.read_bytes(path)!; bundle_io = BundleIO{mode: mode}
			assert contract_batch_pool_plan(path.str, 3, &batch, false) == if mode == 1 { 0 } else { 1 }
			assert bundle_io.closes == 2 && bundle_io.writes > 0 && os.ls(work)!.len == 1
			current := os.read_bytes(path)!; mut decoded := PlanSet{}; assert decode_bundle(current.data, current.len, mut decoded)
			if mode == 1 || mode == 4 { assert decoded == expected && (current == original) == retry && bundle_io.renames == 1 && bundle_io.flushes == 2 } else { assert current == original }
			bundle_io = BundleIO{}; assert contract_batch_pool_plan(path.str, 3, &batch, false) == 0 && bundle_io.renames == 1 && bundle_io.flushes == 2
			completed := os.read_bytes(path)!; bundle_io = BundleIO{mode: mode}
			assert contract_batch_pool_plan(path.str, 3, &batch, true) == 0 && os.read_bytes(path)! == completed && bundle_io == BundleIO{mode: mode}
		}
	}
}

fn test_pool_contraction_preview_and_publication_detect_buffered_stdout_failure() {
	work := os.join_path(os.temp_dir(), 'vinix-contraction-output-${os.getpid()}'); os.mkdir(work)!; defer { os.rmdir_all(work) or {} }; path := work + '/saved.vset'
	for preview in [false, true] {
		mut set := PlanSet{}; mut batch := PoolContractionBatch{}; mut expected := PlanSet{}
		contraction_io_fixture(mut set, mut batch, mut expected); bundle_io = BundleIO{}; assert publish_bundle(path.str, &set) && C.fflush(C.stdout) == 0
		original := os.read_bytes(path)!; child := C.fork(); assert child >= 0
		if child == 0 {
			fd := C.open(c'/dev/null', C.O_RDONLY); if fd < 0 || C.dup2(fd, 1) != 1 { C._exit(2) }; C.close(fd)
			mut buffer := [4096]char{}; if C.setvbuf(C.stdout, &buffer[0], C._IOFBF, 4096) != 0 { C._exit(3) }
			C._exit(if contract_batch_pool_plan(path.str, 3, &batch, preview) == 1 { 0 } else { 4 })
		}
		mut code := i32(-1); assert C.waitpid(child, &code, 0) == child && code == 0
		current := os.read_bytes(path)!; assert (current == original) == preview
		mut decoded := PlanSet{}; assert decode_bundle(current.data, current.len, mut decoded); if preview { assert decoded == set } else { assert decoded == expected }
	}
}

fn resize_io_fixture(mut set PlanSet, mut batch PoolResizeBatch, mut expected PlanSet) {
	mut contractions := PoolContractionBatch{}; contraction_io_fixture(mut set, mut contractions, mut expected)
	unsafe { expected = *(&set) }
	batch.count = 4
	batch.rows[0] = PoolResizeRequest{key: set.plans[2].key, pool: 3, start: 8192, end: 32768}
	batch.rows[1] = PoolResizeRequest{key: set.plans[1].key, pool: 4, start: 24576, end: 49152}
	batch.rows[2] = PoolResizeRequest{key: set.plans[1].key, pool: 3, start: 8192, end: 24576}
	batch.rows[3] = PoolResizeRequest{key: set.plans[0].key, pool: 3, start: 4096, end: 16384}
	expected.windows[2] = PoolRegion{pool: 3, disk: 0, window: SpaceWindow{start: 4096, end: 16384, alignment: 4096}}
	expected.windows[4] = PoolRegion{pool: 3, disk: 1, window: SpaceWindow{start: 8192, end: 24576, alignment: 4096}}
	expected.windows[5] = PoolRegion{pool: 4, disk: 1, window: SpaceWindow{start: 24576, end: 49152, alignment: 4096}}
}

fn test_cross_pool_resize_and_equal_bound_retries_publish_complete_sets_under_every_fault() {
	work := os.join_path(os.temp_dir(), 'vinix-resize-publish-${os.getpid()}'); os.mkdir(work)!; defer { os.rmdir_all(work) or {} }; path := work + '/saved.vset'
	for retry in [false, true] { for mode in 1 .. 7 {
		mut set := PlanSet{}; mut batch := PoolResizeBatch{}; mut expected := PlanSet{}
		resize_io_fixture(mut set, mut batch, mut expected); bundle_io = BundleIO{}; assert publish_bundle(path.str, &set)
		if retry { assert resize_batch_pool_plan(path.str, &batch, false) == 0 }
		original := os.read_bytes(path)!; bundle_io = BundleIO{mode: mode}
		assert resize_batch_pool_plan(path.str, &batch, false) == if mode == 1 { 0 } else { 1 }
		assert bundle_io.closes == 2 && bundle_io.writes > 0 && os.ls(work)!.len == 1
		current := os.read_bytes(path)!; mut decoded := PlanSet{}; assert decode_bundle(current.data, current.len, mut decoded)
		if mode == 1 || mode == 4 { assert decoded == expected && (current == original) == retry && bundle_io.renames == 1 && bundle_io.flushes == 2 } else { assert current == original }
		bundle_io = BundleIO{}; assert resize_batch_pool_plan(path.str, &batch, false) == 0 && bundle_io.renames == 1 && bundle_io.flushes == 2
		completed := os.read_bytes(path)!; bundle_io = BundleIO{mode: mode}
		assert resize_batch_pool_plan(path.str, &batch, true) == 0 && os.read_bytes(path)! == completed && bundle_io == BundleIO{mode: mode}
	} }
}

fn test_cross_pool_resize_preview_and_publication_detect_buffered_stdout_failure() {
	work := os.join_path(os.temp_dir(), 'vinix-resize-output-${os.getpid()}'); os.mkdir(work)!; defer { os.rmdir_all(work) or {} }; path := work + '/saved.vset'
	for preview in [false, true] {
		mut set := PlanSet{}; mut batch := PoolResizeBatch{}; mut expected := PlanSet{}
		resize_io_fixture(mut set, mut batch, mut expected); bundle_io = BundleIO{}; assert publish_bundle(path.str, &set) && C.fflush(C.stdout) == 0
		original := os.read_bytes(path)!; child := C.fork(); assert child >= 0
		if child == 0 {
			fd := C.open(c'/dev/null', C.O_RDONLY); if fd < 0 || C.dup2(fd, 1) != 1 { C._exit(2) }; C.close(fd)
			mut buffer := [4096]char{}; if C.setvbuf(C.stdout, &buffer[0], C._IOFBF, 4096) != 0 { C._exit(3) }
			C._exit(if resize_batch_pool_plan(path.str, &batch, preview) == 1 { 0 } else { 4 })
		}
		mut code := i32(-1); assert C.waitpid(child, &code, 0) == child && code == 0
		current := os.read_bytes(path)!; assert (current == original) == preview
		mut decoded := PlanSet{}; assert decode_bundle(current.data, current.len, mut decoded); if preview { assert decoded == set } else { assert decoded == expected }
	}
}

fn test_multi_pool_batches_publish_all_rows_or_preserve_old_file_and_retry_every_durability_failure() {
	work := os.join_path(os.temp_dir(), 'vinix-multi-pool-batch-io-${os.getpid()}')
	os.mkdir(work)!
	defer { os.rmdir_all(work) or {} }
	path := work + '/saved.vset'
	mut batch := MultiPoolBatch{count: 2}
	batch.pools[0] = 3; batch.pools[1] = 4
	batch.rows[0] = Request{slot: 20, length: 4096, flags: 1}
	batch.rows[1] = Request{slot: 21, length: 4096}
	for retry in [false, true] {
		for mode in 1 .. 7 {
			mut set := PlanSet{}
			for p in 0 .. 2 {
				mut plan := Plan{key: DiskKey{bytes: 32768, sector: 512, kind: 1}}
				plan.key.id[0] = u8(p + 1)
				assert append_plan(mut set, &plan)
				region := PoolRegion{pool: u32(3 + p), disk: u32(p), window: SpaceWindow{start: 4096, end: 8192, alignment: 4096}}
				assert bundle_pool_add(mut set, &region)
			}
			bundle_io = BundleIO{}
			assert publish_bundle(path.str, &set)
			if retry { assert multi_pool_batch_plan(path.str, &batch, false) == 0 }
			original := os.read_bytes(path)!
			bundle_io = BundleIO{mode: mode}
			assert multi_pool_batch_plan(path.str, &batch, false) == if mode == 1 { 0 } else { 1 }
			assert bundle_io.closes == 2 && bundle_io.writes > 0 && os.ls(work)!.len == 1
			current := os.read_bytes(path)!
			mut decoded := PlanSet{}
			assert decode_bundle(current.data, current.len, mut decoded)
			if mode == 1 || mode == 4 {
				assert (current == original) == retry && bundle_io.renames == 1 && bundle_io.flushes == 2
				assert decoded.plans[0].count == 1 && decoded.plans[1].count == 1
				assert decoded.plans[0].rows[0] == Request{slot: 20, offset: 4096, length: 4096, flags: 1}
				assert decoded.plans[1].rows[0] == Request{slot: 21, offset: 4096, length: 4096}
			} else { assert current == original }
			// The failed directory flush left a complete new bundle. A retry
			// keeps those exact rows and completes both publisher flushes.
			bundle_io = BundleIO{}
			assert multi_pool_batch_plan(path.str, &batch, false) == 0
			assert bundle_io.writes > 0 && bundle_io.renames == 1 && bundle_io.flushes == 2 && bundle_io.closes == 2
			completed := os.read_bytes(path)!
			bundle_io = BundleIO{mode: mode}
			assert multi_pool_batch_plan(path.str, &batch, true) == 0 && os.read_bytes(path)! == completed
			assert bundle_io == BundleIO{mode: mode} // Preview never enters the publisher.
			batch.rows[1].length = 8192
			assert multi_pool_batch_plan(path.str, &batch, false) == 1 && os.read_bytes(path)! == completed
			assert bundle_io == BundleIO{mode: mode}
			batch.rows[1].length = 4096
		}
	}
}


fn test_multi_pool_batch_preview_and_publication_detect_buffered_stdout_failure() {
	work := os.join_path(os.temp_dir(), 'vinix-multi-pool-batch-output-${os.getpid()}')
	os.mkdir(work)!
	defer { os.rmdir_all(work) or {} }
	path := work + '/saved.vset'
	mut batch := MultiPoolBatch{count: 2}
	batch.pools[0] = 3; batch.pools[1] = 4
	batch.rows[0] = Request{slot: 20, length: 4096, flags: 1}
	batch.rows[1] = Request{slot: 21, length: 4096}
	for preview in [false, true] {
		mut set := PlanSet{}
		mut plan := Plan{key: DiskKey{bytes: 32768, sector: 512, kind: 1}}
		plan.key.id[0] = 1
		assert append_plan(mut set, &plan)
		region := PoolRegion{pool: 3, disk: 0, window: SpaceWindow{start: 4096, end: 8192, alignment: 4096}}
		assert bundle_pool_add(mut set, &region)
		other := PoolRegion{pool: 4, disk: 0, window: SpaceWindow{start: 8192, end: 12288, alignment: 4096}}
		assert bundle_pool_add(mut set, &other)
		bundle_io = BundleIO{}
		assert publish_bundle(path.str, &set) && C.fflush(C.stdout) == 0
		original := os.read_bytes(path)!
		child := C.fork()
		assert child >= 0
		if child == 0 {
			fd := C.open(c'/dev/null', C.O_RDONLY)
			if fd < 0 || C.dup2(fd, 1) != 1 { C._exit(2) }
			C.close(fd)
			mut buffer := [4096]char{}
			if C.setvbuf(C.stdout, &buffer[0], C._IOFBF, 4096) != 0 { C._exit(3) }
			result := multi_pool_batch_plan(path.str, &batch, preview)
			C._exit(if result == 1 { 0 } else { 4 })
		}
		mut result := i32(-1)
		assert C.waitpid(child, &result, 0) == child && result == 0
		current := os.read_bytes(path)!
		assert (current == original) == preview
		mut decoded := PlanSet{}
		assert decode_bundle(current.data, current.len, mut decoded)
		assert decoded.plans[0].count == if preview { u32(0) } else { u32(2) }
	}
}
