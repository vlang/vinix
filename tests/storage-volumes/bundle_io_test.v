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
