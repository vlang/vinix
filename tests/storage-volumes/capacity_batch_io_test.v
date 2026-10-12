// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module volumecli

import os

fn C.strncmp(&char, &char, usize) i32
fn C.fork() i32
fn C.dup2(i32, i32) i32
fn C.waitpid(i32, &i32, i32) i32
fn C._exit(i32)
fn C.setvbuf(voidptr, &char, i32, usize) i32

struct CapacityBatchIO {
mut:
	active bool
	count int
	mode int
	fault int = 1
	sector [64]u64
	kind [64]u32
	bytes [64]u64
	ids [64]u64
	statuses [64]int
	reads [64]int
	opened [64]int
	closed [64]int
	live int
	maximum int
	other_fd i32 = -1
	other_opened int
	other_closed int
	steps int
	sequence [256]int
	publish_mode int
	writes int
	flushes int
	publish_closes int
	renames int
	lock_path &char = unsafe { nil }
	preview bool
}

__global capacity_batch_io CapacityBatchIO

fn capacity_batch_mock_open(path &char, flags i32) i32 {
	assert flags == C.O_RDONLY | C.O_CLOEXEC | C.O_NOFOLLOW | C.O_NONBLOCK
	if C.strncmp(path, c'/capacity-batch-device-', 23) != 0 {
		fd := C.open(path, flags)
		if fd >= 0 { capacity_batch_io.other_fd = fd; capacity_batch_io.other_opened++ }
		return fd
	}
	disk := decimal(unsafe { path + 23 }) or { return -1 }
	assert disk < 64 && flags == C.O_RDONLY | C.O_CLOEXEC | C.O_NOFOLLOW | C.O_NONBLOCK
	if capacity_batch_io.mode == 12 && int(disk) == capacity_batch_io.fault {
		unsafe { C.errno = C.ENODEV }; return -1
	}
	capacity_batch_io.opened[disk]++
	capacity_batch_io.live++
	if capacity_batch_io.live > capacity_batch_io.maximum { capacity_batch_io.maximum = capacity_batch_io.live }
	return 999900 + i32(disk)
}

fn capacity_batch_mock_close(fd i32) i32 {
	if fd < 999900 || fd >= 999964 {
		assert fd == capacity_batch_io.other_fd
		capacity_batch_io.other_closed++
		return C.close(fd)
	}
	disk := int(fd - 999900)
	capacity_batch_io.closed[disk]++
	assert capacity_batch_io.closed[disk] == capacity_batch_io.opened[disk]
	capacity_batch_io.live--
	// Device pins drain before the writer's directory descriptor is released.
	if capacity_batch_io.lock_path != unsafe { nil } {
		other := C.open(capacity_batch_io.lock_path, C.O_RDONLY | C.O_DIRECTORY | C.O_CLOEXEC)
		assert other >= 0
		assert (C.flock(other, C.LOCK_EX | C.LOCK_NB) == 0) == capacity_batch_io.preview
		assert C.close(other) == 0
	}
	return 0
}

fn capacity_batch_mock_ioctl(fd i32, request u64, output voidptr) i32 {
	if fd < 999900 || fd >= 999964 { unsafe { C.errno = C.ENOTTY }; return -1 }
	assert request == 0x56560004 // Only read-only status queries are permitted.
	disk := int(fd - 999900)
	capacity_batch_io.statuses[disk]++
	capacity_batch_io.sequence[capacity_batch_io.steps] = disk
	capacity_batch_io.steps++
	if capacity_batch_io.statuses[disk] == 2 {
		for i in 0 .. capacity_batch_io.count { assert capacity_batch_io.statuses[i] >= 1 }
		assert capacity_batch_io.live == capacity_batch_io.count
	}
	mode := if disk == capacity_batch_io.fault { capacity_batch_io.mode } else { 0 }
	if mode == 3 { unsafe { C.errno = C.EIO }; return -1 }
	mut result := Status{version: 1, bytes: capacity_batch_io.bytes[disk], sector: capacity_batch_io.sector[disk],
		flags: 5, disk_id: capacity_batch_io.ids[disk], slot: u64(-1)} // Readonly physical devices are accepted.
	match mode {
		4 { result.flags |= 2 }
		5 { result.flags |= 8 }
		6 { result.flags |= 16; result.start = 512 }
		7 { result.sector = if result.sector == 512 { u64(4096) } else { u64(512) } }
		10 { if capacity_batch_io.statuses[disk] == 2 { result.bytes += result.sector } }
		11 { if capacity_batch_io.statuses[disk] == 2 { result.disk_id++ } }
		17 { result.reserved = 1 }
		else {}
	}
	// An early disk changes only after a later disk's first probe. A per-disk
	// immediate check would miss it; the final all-descriptor pass must reject.
	if capacity_batch_io.mode == 18 && disk == 0 && capacity_batch_io.statuses[1] > 0 { result.bytes += result.sector }
	unsafe { *(&Status(output)) = result }
	return 0
}

fn capacity_batch_mock_pread(fd i32, output voidptr, size usize, offset i64) i64 {
	assert fd >= 999900 && fd < 999964 && offset == 0 && size >= 1024 && size <= 8192
	disk := int(fd - 999900)
	capacity_batch_io.reads[disk]++
	mode := if disk == capacity_batch_io.fault { capacity_batch_io.mode } else { 0 }
	if mode == 1 && capacity_batch_io.reads[disk] == 1 { unsafe { C.errno = C.EINTR }; return -1 }
	if mode == 2 || (mode == 14 && capacity_batch_io.reads[disk] == 2) { return i64(size - 1) }
	if mode == 15 && capacity_batch_io.reads[disk] == 2 { unsafe { C.errno = C.EIO }; return -1 }
	unsafe { for i in 0 .. int(size) { (&u8(output))[i] = 0 } }
	identity := u64(disk + 1) + if mode == 8 || (mode == 9 && capacity_batch_io.reads[disk] == 2) { u64(32) } else { u64(0) }
	put_le(&u8(output), 440, 4, identity); put_le(&u8(output), 510, 2, 0xaa55)
	if capacity_batch_io.kind[disk] == 2 {
		put_le(&u8(output), 450, 1, 0xee)
		header := unsafe { &u8(output) + int(size / 2) }
		put_le(header, 0, 8, 0x5452415020494645); put_le(header, 8, 4, 0x10000)
		put_le(header, 12, 4, 92); put_le(header, 24, 8, 1)
		put_le(header, 56, 1, identity); put_le(header, 71, 1, 0x83)
		put_le(header, 16, 4, crc32(header, 92, 16))
		if mode == 13 { put_le(header, 16, 4, 0) }
	}
	return i64(size)
}

fn capacity_batch_publish_write(fd i32, data voidptr, size usize) i64 {
	if capacity_batch_io.active { assert capacity_batch_io.live == capacity_batch_io.count }
	capacity_batch_io.writes++
	if capacity_batch_io.publish_mode == 1 && capacity_batch_io.writes == 1 { unsafe { C.errno = C.EINTR }; return -1 }
	if capacity_batch_io.publish_mode == 2 { unsafe { C.errno = C.EIO }; return -1 }
	return C.write(fd, data, if capacity_batch_io.publish_mode == 1 && size > 3 { usize(3) } else { size })
}

fn capacity_batch_publish_fsync(fd i32) i32 {
	if capacity_batch_io.active { assert capacity_batch_io.live == capacity_batch_io.count }
	capacity_batch_io.flushes++
	if (capacity_batch_io.publish_mode == 3 && capacity_batch_io.flushes == 1)
		|| (capacity_batch_io.publish_mode == 4 && capacity_batch_io.flushes == 2) { unsafe { C.errno = C.EIO }; return -1 }
	return C.fsync(fd)
}

fn capacity_batch_publish_close(fd i32) i32 {
	capacity_batch_io.publish_closes++
	result := C.close(fd)
	if capacity_batch_io.publish_mode == 5 && capacity_batch_io.publish_closes == 1 { unsafe { C.errno = C.EIO }; return -1 }
	return result
}

fn capacity_batch_publish_renameat(from_fd i32, from &char, to_fd i32, to &char) i32 {
	if capacity_batch_io.active { assert capacity_batch_io.live == capacity_batch_io.count }
	capacity_batch_io.renames++
	if capacity_batch_io.publish_mode == 6 { unsafe { C.errno = C.EIO }; return -1 }
	return C.renameat(from_fd, from, to_fd, to)
}

fn capacity_batch_reset(count int) {
	capacity_batch_io = CapacityBatchIO{active: true, count: count}
	for disk in 0 .. count {
		capacity_batch_io.sector[disk] = if disk & 1 == 0 { u64(512) } else { u64(4096) }
		capacity_batch_io.kind[disk] = if disk & 1 == 0 { u32(1) } else { u32(2) }
		capacity_batch_io.bytes[disk] = if disk == 0 { u64(25165824) } else { u64(33554432) }
		capacity_batch_io.ids[disk] = u64(disk + 7)
	}
}

fn capacity_batch_io_fixture(path string, count int) PlanSet {
	capacity_batch_io = CapacityBatchIO{}
	mut set := PlanSet{}
	for disk in 0 .. count {
		mut plan := Plan{count: 1, key: DiskKey{bytes: 16777216,
			sector: if disk & 1 == 0 { u64(512) } else { u64(4096) }, kind: if disk & 1 == 0 { u32(1) } else { u32(2) }}}
		plan.key.id[0] = u8(disk + 1)
		if plan.key.kind == 2 { plan.key.id[15] = 0x83 }
		plan.rows[0] = Request{slot: u32(disk), offset: 1048576, length: 8192, flags: u64(disk & 1)}
		assert append_plan(mut set, &plan)
		region := PoolRegion{pool: 3, disk: u32(disk), window: SpaceWindow{start: 6291456, end: 6303744, alignment: 4096}}
		assert bundle_pool_add(mut set, &region)
	}
	assert publish_bundle(path.str, &set)
	capacity_batch_reset(count)
	return set
}

fn two_capacity_requests() CapacityBatch {
	mut batch := CapacityBatch{count: 2}
	batch.disks[0] = 0; batch.devices[0] = c'/capacity-batch-device-0'; batch.expected[0] = 25165824
	batch.disks[1] = 1; batch.devices[1] = c'/capacity-batch-device-1'; batch.expected[1] = 33554432
	return batch
}

fn assert_capacity_batch_pins_drained() {
	assert capacity_batch_io.live == 0
	assert capacity_batch_io.other_opened == capacity_batch_io.other_closed
	for i in 0 .. capacity_batch_io.count { assert capacity_batch_io.opened[i] == capacity_batch_io.closed[i] }
}

fn test_capacity_batch_later_regular_missing_and_symlink_devices_close_the_earlier_pin() {
	work := os.join_path(os.temp_dir(), 'vinix-capacity-batch-device-${os.getpid()}')
	os.mkdir(work)!; defer { os.rmdir_all(work) or {} }
	path := work + '/saved.vset'
	capacity_batch_io_fixture(path, 2)
	original := os.read_bytes(path)!
	os.symlink(path, work + '/device-link')!
	for preview in [false, true] {
		for device in [path, work + '/device-link', work + '/missing-device'] {
			capacity_batch_reset(2)
			mut batch := two_capacity_requests(); batch.devices[1] = device.str
			assert capacity_batch_bundle_plan(path.str, &batch, preview) == 1 && os.read_bytes(path)! == original
			assert capacity_batch_io.opened[0] == 1 && capacity_batch_io.closed[0] == 1 && capacity_batch_io.writes == 0
			assert_capacity_batch_pins_drained()
		}
	}
}

fn test_capacity_batch_pins_all_devices_rechecks_in_order_and_previews_under_writer_lock() {
	work := os.join_path(os.temp_dir(), 'vinix-capacity-batch-probe-${os.getpid()}')
	os.mkdir(work)!; defer { os.rmdir_all(work) or {} }
	path := work + '/saved.vset'
	before := capacity_batch_io_fixture(path, 2)
	batch := two_capacity_requests()
	original := os.read_bytes(path)!
	mut editor := PlanEdit{}
	assert open_plan_edit(path.str, mut editor, true)
	assert capacity_batch_bundle_plan(path.str, &batch, false) == 1 && capacity_batch_io.live == 0 && capacity_batch_io.opened[0] == 0
	capacity_batch_io.preview = true
	assert capacity_batch_bundle_plan(path.str, &batch, true) == 0 && os.read_bytes(path)! == original
	assert capacity_batch_io.maximum == 2 && capacity_batch_io.steps == 4
	assert capacity_batch_io.sequence[..4] == [0, 1, 0, 1] && capacity_batch_io.writes == 0
	assert_capacity_batch_pins_drained()
	close_plan_edit(mut editor)
	capacity_batch_reset(2); capacity_batch_io.mode = 1; capacity_batch_io.lock_path = work.str
	assert capacity_batch_bundle_plan(path.str, &batch, false) == 0
	assert_capacity_batch_pins_drained()
	assert capacity_batch_io.maximum == 2 && capacity_batch_io.reads[0] == 2 && capacity_batch_io.reads[1] == 3
	mut decoded := PlanSet{}
	data := os.read_bytes(path)!
	assert decode_bundle(data.data, data.len, mut decoded)
	mut expected := before; expected.plans[0].key.bytes = 25165824; expected.plans[1].key.bytes = 33554432
	assert decoded == expected
	capacity_batch_reset(2); capacity_batch_io.lock_path = work.str
	assert capacity_batch_bundle_plan(path.str, &batch, false) == 0 && os.read_bytes(path)! == data
	assert capacity_batch_io.writes > 0 && capacity_batch_io.renames == 1 && capacity_batch_io.flushes == 2
	assert_capacity_batch_pins_drained()
}

fn test_capacity_batch_later_probe_open_and_recheck_failures_preserve_whole_file_and_close_all_pins() {
	work := os.join_path(os.temp_dir(), 'vinix-capacity-batch-fail-${os.getpid()}')
	os.mkdir(work)!; defer { os.rmdir_all(work) or {} }
	path := work + '/saved.vset'
	batch := two_capacity_requests()
	for preview in [false, true] {
		for mode in [2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 17, 18] {
			capacity_batch_io_fixture(path, 2)
			original := os.read_bytes(path)!
			capacity_batch_io.mode = mode; capacity_batch_io.preview = preview; capacity_batch_io.lock_path = work.str
			assert capacity_batch_bundle_plan(path.str, &batch, preview) == 1 && os.read_bytes(path)! == original
			assert capacity_batch_io.writes == 0 && os.ls(work)!.len == 1
			assert_capacity_batch_pins_drained()
		}
		capacity_batch_io_fixture(path, 2)
		original := os.read_bytes(path)!
		capacity_batch_io.ids[1] = capacity_batch_io.ids[0]
		assert capacity_batch_bundle_plan(path.str, &batch, preview) == 1 && os.read_bytes(path)! == original
		assert capacity_batch_io.writes == 0
		assert_capacity_batch_pins_drained()
	}
}

fn test_capacity_batch_invalid_lists_and_saved_inputs_never_open_devices() {
	work := os.join_path(os.temp_dir(), 'vinix-capacity-batch-input-${os.getpid()}')
	os.mkdir(work)!; defer { os.rmdir_all(work) or {} }
	path := work + '/saved.vset'
	capacity_batch_io_fixture(path, 2)
	original := os.read_bytes(path)!
	for preview in [false, true] {
		for bad in 0 .. 6 {
			mut batch := two_capacity_requests()
			match bad {
				0 { batch.disks[1] = 0 }
				1 { batch.disks[1] = 2 }
				2 { batch.expected[1] = 8388608 }
				3 { batch.expected[1] = 33554433 }
				4 { batch.devices[1] = unsafe { nil } }
				else { batch.devices[1] = c'' }
			}
			assert capacity_batch_bundle_plan(path.str, &batch, preview) == 1 && os.read_bytes(path)! == original
		}
	}
	batch := two_capacity_requests()
	os.symlink(path, work + '/link')!
	for input in [work + '/link', work + '/missing', work] {
		for preview in [false, true] { assert capacity_batch_bundle_plan(input.str, &batch, preview) == 1 }
	}
	mut damaged := original.clone(); damaged[24] ^= 1
	os.write_file_array(path, damaged)!
	for preview in [false, true] { assert capacity_batch_bundle_plan(path.str, &batch, preview) == 1 && os.read_bytes(path)! == damaged }
	assert capacity_batch_io.opened[0] == 0 && capacity_batch_io.opened[1] == 0 && capacity_batch_io.writes == 0
}

fn test_capacity_batch_changed_and_equal_retries_under_all_publisher_faults_and_preview_is_readonly() {
	work := os.join_path(os.temp_dir(), 'vinix-capacity-batch-publish-${os.getpid()}')
	os.mkdir(work)!; defer { os.rmdir_all(work) or {} }
	path := work + '/saved.vset'
	batch := two_capacity_requests()
	for retry in [false, true] {
		for mode in 1 .. 7 {
			before := capacity_batch_io_fixture(path, 2)
			if retry { assert capacity_batch_bundle_plan(path.str, &batch, false) == 0 }
			original := os.read_bytes(path)!
			capacity_batch_reset(2); capacity_batch_io.publish_mode = mode; capacity_batch_io.lock_path = work.str
			assert capacity_batch_bundle_plan(path.str, &batch, false) == if mode == 1 { 0 } else { 1 }
			assert_capacity_batch_pins_drained()
			assert capacity_batch_io.publish_closes == 2 && os.ls(work)!.len == 1
			current := os.read_bytes(path)!
			mut decoded := PlanSet{}
			assert decode_bundle(current.data, current.len, mut decoded)
			mut expected := before
			if retry || mode == 1 || mode == 4 { expected.plans[0].key.bytes = 25165824; expected.plans[1].key.bytes = 33554432 }
			assert decoded == expected
			if mode == 1 || mode == 4 { assert (current == original) == retry && capacity_batch_io.renames == 1 && capacity_batch_io.flushes == 2 }
			else { assert current == original }
			capacity_batch_reset(2)
			assert capacity_batch_bundle_plan(path.str, &batch, false) == 0 && capacity_batch_io.flushes == 2 && capacity_batch_io.renames == 1
			complete := os.read_bytes(path)!
			capacity_batch_reset(2); capacity_batch_io.publish_mode = mode; capacity_batch_io.preview = true; capacity_batch_io.lock_path = work.str
			assert capacity_batch_bundle_plan(path.str, &batch, true) == 0 && os.read_bytes(path)! == complete
			assert capacity_batch_io.writes == 0 && capacity_batch_io.flushes == 0 && capacity_batch_io.renames == 0
			assert_capacity_batch_pins_drained()
		}
	}
}

fn test_capacity_batch_buffered_stdout_failure_closes_every_device_and_preserves_publication_rules() {
	work := os.join_path(os.temp_dir(), 'vinix-capacity-batch-output-${os.getpid()}')
	os.mkdir(work)!; defer { os.rmdir_all(work) or {} }
	path := work + '/saved.vset'
	batch := two_capacity_requests()
	for preview in [false, true] {
		capacity_batch_io_fixture(path, 2)
		original := os.read_bytes(path)!
		assert C.fflush(C.stdout) == 0
		child := C.fork(); assert child >= 0
		if child == 0 {
			fd := C.open(c'/dev/null', C.O_RDONLY)
			if fd < 0 || C.dup2(fd, 1) != 1 { C._exit(2) }
			C.close(fd)
			mut buffer := [4096]char{}
			if C.setvbuf(C.stdout, &buffer[0], C._IOFBF, 4096) != 0 { C._exit(3) }
			capacity_batch_io.preview = preview; capacity_batch_io.lock_path = work.str
			result := capacity_batch_bundle_plan(path.str, &batch, preview)
			C._exit(if result == 1 && capacity_batch_io.live == 0 && capacity_batch_io.closed[0] == 1 && capacity_batch_io.closed[1] == 1 { 0 } else { 4 })
		}
		mut code := i32(-1)
		assert C.waitpid(child, &code, 0) == child && code == 0
		current := os.read_bytes(path)!
		assert (current == original) == preview
		mut decoded := PlanSet{}
		assert decode_bundle(current.data, current.len, mut decoded)
		assert decoded.plans[0].key.bytes == if preview { u64(16777216) } else { u64(25165824) }
		assert decoded.plans[1].key.bytes == if preview { u64(16777216) } else { u64(33554432) }
	}
}

fn test_maximum_capacity_batch_cli_pins_all_64_devices_with_all_195_arguments() {
	work := os.join_path(os.temp_dir(), 'vinix-capacity-batch-full-${os.getpid()}')
	os.mkdir(work)!; defer { os.rmdir_all(work) or {} }
	path := work + '/saved.vset'
	before := capacity_batch_io_fixture(path, 64)
	unsafe {
		mut args := [196]&char{}
		mut disks := [64][4]char{}; mut devices := [64][64]char{}; mut ends := [64][21]char{}
		args[0] = &char(c'vinix-volume'); args[1] = &char(c'plan-capacity-batch'); args[2] = path.str
		for i in 0 .. 64 {
			disk := 63 - i
			capacity_batch_io.bytes[disk] = u64(-1) & ~(before.plans[disk].key.sector - 1)
			C.snprintf(&disks[i][0], 4, c'%u', u32(disk)); C.snprintf(&devices[i][0], 64, c'/capacity-batch-device-%u', u32(disk))
			C.snprintf(&ends[i][0], 21, c'%lu', capacity_batch_io.bytes[disk])
			args[3 + i * 3] = &disks[i][0]; args[4 + i * 3] = &devices[i][0]; args[5 + i * 3] = &ends[i][0]
		}
		assert run(195, &args[0]) == 0 && capacity_batch_io.maximum == 64 && capacity_batch_io.steps == 128
		assert_capacity_batch_pins_drained()
		current := os.read_bytes(path)!
		mut decoded := PlanSet{}
		assert current.len == 8768 && decode_bundle(current.data, current.len, mut decoded)
		mut expected := before
		for disk in 0 .. 64 { expected.plans[disk].key.bytes = capacity_batch_io.bytes[disk] }
		assert decoded == expected
		assert run(195, &args[0]) == 0 && os.read_bytes(path)! == current
		assert_capacity_batch_pins_drained()
	}
}

fn contract_capacity_io_reset(count int) {
	capacity_batch_reset(count)
	for disk in 0 .. count { capacity_batch_io.bytes[disk] = 16777216 }
}

fn contract_capacity_io_fixture(path string, count int) PlanSet {
	mut set := capacity_batch_io_fixture(path, count)
	capacity_batch_io.active = false
	for disk in 0 .. count { set.plans[disk].key.bytes = 33554432 }
	assert publish_bundle(path.str, &set)
	contract_capacity_io_reset(count)
	return set
}

fn two_contract_capacity_requests(set &PlanSet) CapacityContractBatch {
	mut batch := CapacityContractBatch{count: 2}
	for i in 0 .. 2 { batch.keys[i] = set.plans[i].key; batch.expected[i] = 16777216 }
	batch.devices[0] = c'/capacity-batch-device-0'; batch.devices[1] = c'/capacity-batch-device-1'
	return batch
}

fn test_contract_capacity_complete_validation_before_open_and_saved_input_rejection() {
	work := os.join_path(os.temp_dir(), 'vinix-contract-capacity-input-${os.getpid()}')
	os.mkdir(work)!; defer { os.rmdir_all(work) or {} }; path := work + '/saved.vset'
	before := contract_capacity_io_fixture(path, 2); original := os.read_bytes(path)!
	for preview in [false, true] { for bad in 0 .. 8 {
		mut batch := two_contract_capacity_requests(&before)
		match bad {
			0 { batch.keys[1] = batch.keys[0] }
			1 { batch.keys[1].id[0] = 67 }
			2 { batch.expected[1] = 4194304 }
			3 { batch.expected[1] = 33554433 }
			4 { batch.devices[1] = unsafe { nil } }
			5 { batch.devices[1] = c'' }
			6 { batch.expected[1] = 67108864 }
			else { batch.expected[1] = 4096 }
		}
		assert contract_capacity_batch_plan(path.str, &batch, preview) == 1 && os.read_bytes(path)! == original
	} }
	batch := two_contract_capacity_requests(&before); os.symlink(path, work + '/link')!
	for input in [work + '/link', work + '/missing', work] { for preview in [false, true] { assert contract_capacity_batch_plan(input.str, &batch, preview) == 1 } }
	mut damaged := original.clone(); damaged[24] ^= 1; os.write_file_array(path, damaged)!
	for preview in [false, true] { assert contract_capacity_batch_plan(path.str, &batch, preview) == 1 && os.read_bytes(path)! == damaged }
	assert capacity_batch_io.opened[0] == 0 && capacity_batch_io.opened[1] == 0 && capacity_batch_io.writes == 0
}

fn test_contract_capacity_later_device_probe_and_final_recheck_failures_rollback_and_drain() {
	work := os.join_path(os.temp_dir(), 'vinix-contract-capacity-fail-${os.getpid()}')
	os.mkdir(work)!; defer { os.rmdir_all(work) or {} }; path := work + '/saved.vset'
	before := contract_capacity_io_fixture(path, 2); original := os.read_bytes(path)!; requests := two_contract_capacity_requests(&before)
	os.symlink(path, work + '/device-link')!
	for preview in [false, true] {
		for device in [path, work + '/device-link', work + '/missing-device'] {
			contract_capacity_io_reset(2); mut batch := requests; batch.devices[1] = device.str
			assert contract_capacity_batch_plan(path.str, &batch, preview) == 1 && os.read_bytes(path)! == original
			assert capacity_batch_io.opened[0] == 1 && capacity_batch_io.closed[0] == 1 && capacity_batch_io.writes == 0
			assert_capacity_batch_pins_drained()
		}
		for mode in [2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 17, 18] {
			contract_capacity_io_reset(2); capacity_batch_io.mode = mode; capacity_batch_io.preview = preview; capacity_batch_io.lock_path = work.str
			assert contract_capacity_batch_plan(path.str, &requests, preview) == 1 && os.read_bytes(path)! == original
			assert capacity_batch_io.writes == 0 && os.ls(work)!.len == 2; assert_capacity_batch_pins_drained()
		}
		contract_capacity_io_reset(2); capacity_batch_io.ids[1] = capacity_batch_io.ids[0]
		assert contract_capacity_batch_plan(path.str, &requests, preview) == 1 && os.read_bytes(path)! == original
		assert_capacity_batch_pins_drained()
	}
}

fn test_contract_capacity_mixed_keep_contract_writer_exclusion_preview_and_pin_order() {
	work := os.join_path(os.temp_dir(), 'vinix-contract-capacity-probe-${os.getpid()}')
	os.mkdir(work)!; defer { os.rmdir_all(work) or {} }; path := work + '/saved.vset'
	mut before := contract_capacity_io_fixture(path, 2); before.plans[1].key.bytes = 16777216
	capacity_batch_io.active = false; assert publish_bundle(path.str, &before); contract_capacity_io_reset(2)
	batch := two_contract_capacity_requests(&before); original := os.read_bytes(path)!
	mut editor := PlanEdit{}; assert open_plan_edit(path.str, mut editor, true)
	assert contract_capacity_batch_plan(path.str, &batch, false) == 1 && capacity_batch_io.opened[0] == 0
	capacity_batch_io.preview = true
	assert contract_capacity_batch_plan(path.str, &batch, true) == 0 && os.read_bytes(path)! == original
	assert capacity_batch_io.maximum == 2 && capacity_batch_io.steps == 4 && capacity_batch_io.sequence[..4] == [0, 1, 0, 1]
	assert capacity_batch_io.writes == 0; assert_capacity_batch_pins_drained(); close_plan_edit(mut editor)
	contract_capacity_io_reset(2); capacity_batch_io.mode = 1; capacity_batch_io.lock_path = work.str
	assert contract_capacity_batch_plan(path.str, &batch, false) == 0
	assert capacity_batch_io.reads[0] == 2 && capacity_batch_io.reads[1] == 3; assert_capacity_batch_pins_drained()
	mut decoded := PlanSet{}; data := os.read_bytes(path)!; assert decode_bundle(data.data, data.len, mut decoded)
	mut expected := before; expected.plans[0].key.bytes = 16777216; assert decoded == expected
}

fn test_contract_capacity_changed_and_keep_publication_faults_preview_and_buffered_output_failure() {
	work := os.join_path(os.temp_dir(), 'vinix-contract-capacity-publish-${os.getpid()}')
	os.mkdir(work)!; defer { os.rmdir_all(work) or {} }; path := work + '/saved.vset'
	for retry in [false, true] { for mode in 1 .. 7 {
		before := contract_capacity_io_fixture(path, 2); batch := two_contract_capacity_requests(&before)
		if retry { assert contract_capacity_batch_plan(path.str, &batch, false) == 0 }
		original := os.read_bytes(path)!
		contract_capacity_io_reset(2); capacity_batch_io.publish_mode = mode; capacity_batch_io.lock_path = work.str
		assert contract_capacity_batch_plan(path.str, &batch, false) == if mode == 1 { 0 } else { 1 }
		assert_capacity_batch_pins_drained(); assert capacity_batch_io.publish_closes == 2 && os.ls(work)!.len == 1
		current := os.read_bytes(path)!; mut decoded := PlanSet{}; assert decode_bundle(current.data, current.len, mut decoded)
		mut expected := before
		if retry || mode == 1 || mode == 4 { expected.plans[0].key.bytes = 16777216; expected.plans[1].key.bytes = 16777216 }
		assert decoded == expected
		if mode == 1 || mode == 4 { assert (current == original) == retry && capacity_batch_io.renames == 1 && capacity_batch_io.flushes == 2 }
		else { assert current == original }
		contract_capacity_io_reset(2); assert contract_capacity_batch_plan(path.str, &batch, false) == 0
		assert capacity_batch_io.flushes == 2 && capacity_batch_io.renames == 1; complete := os.read_bytes(path)!
		contract_capacity_io_reset(2); capacity_batch_io.publish_mode = mode; capacity_batch_io.preview = true; capacity_batch_io.lock_path = work.str
		assert contract_capacity_batch_plan(path.str, &batch, true) == 0 && os.read_bytes(path)! == complete
		assert capacity_batch_io.writes == 0 && capacity_batch_io.flushes == 0 && capacity_batch_io.renames == 0; assert_capacity_batch_pins_drained()
	} }
	for preview in [false, true] {
		before := contract_capacity_io_fixture(path, 2); batch := two_contract_capacity_requests(&before); original := os.read_bytes(path)!
		assert C.fflush(C.stdout) == 0; child := C.fork(); assert child >= 0
		if child == 0 {
			fd := C.open(c'/dev/null', C.O_RDONLY); if fd < 0 || C.dup2(fd, 1) != 1 { C._exit(2) }; C.close(fd)
			mut buffer := [4096]char{}; if C.setvbuf(C.stdout, &buffer[0], C._IOFBF, 4096) != 0 { C._exit(3) }
			capacity_batch_io.preview = preview; capacity_batch_io.lock_path = work.str
			result := contract_capacity_batch_plan(path.str, &batch, preview)
			C._exit(if result == 1 && capacity_batch_io.live == 0 && capacity_batch_io.closed[0] == 1 && capacity_batch_io.closed[1] == 1 { 0 } else { 4 })
		}
		mut code := i32(-1); assert C.waitpid(child, &code, 0) == child && code == 0
		current := os.read_bytes(path)!; assert (current == original) == preview
		mut decoded := PlanSet{}; assert decode_bundle(current.data, current.len, mut decoded)
		if preview { assert decoded == before } else { assert decoded.plans[0].key.bytes == 16777216 && decoded.plans[1].key.bytes == 16777216 }
	}
}

fn test_maximum_contract_capacity_cli_64_identities_195_arguments_full_width_rechecks_and_retry() {
	work := os.join_path(os.temp_dir(), 'vinix-contract-capacity-full-${os.getpid()}')
	os.mkdir(work)!; defer { os.rmdir_all(work) or {} }; path := work + '/saved.vset'
	mut before := contract_capacity_io_fixture(path, 64); capacity_batch_io.active = false
	for disk in 0 .. 64 { before.plans[disk].key.bytes = u64(-1) & ~(before.plans[disk].key.sector - 1) }
	assert publish_bundle(path.str, &before); contract_capacity_io_reset(64)
	unsafe {
		mut args := [196]&char{}; mut identities := [64][41]char{}; mut devices := [64][64]char{}; mut ends := [64][21]char{}
		args[0] = &char(c'vinix-volume'); args[1] = &char(c'plan-preview-contract-capacity-batch'); args[2] = path.str
		for i in 0 .. 64 {
			disk := 63 - i; capacity_batch_io.bytes[disk] = before.plans[disk].key.bytes - 8192
			disk_identity(&before.plans[disk].key, &identities[i][0]); C.snprintf(&devices[i][0], 64, c'/capacity-batch-device-%u', u32(disk))
			C.snprintf(&ends[i][0], 21, c'%lu', capacity_batch_io.bytes[disk])
			args[3 + i * 3] = &identities[i][0]; args[4 + i * 3] = &devices[i][0]; args[5 + i * 3] = &ends[i][0]
		}
		original := os.read_bytes(path)!; assert run(195, &args[0]) == 0 && os.read_bytes(path)! == original
		assert capacity_batch_io.maximum == 64 && capacity_batch_io.steps == 128 && capacity_batch_io.writes == 0; assert_capacity_batch_pins_drained()
		mut observed := capacity_batch_io.bytes; contract_capacity_io_reset(64); capacity_batch_io.bytes = observed
		args[1] = &char(c'plan-contract-capacity-batch'); assert run(195, &args[0]) == 0
		current := os.read_bytes(path)!; mut decoded := PlanSet{}; assert current.len == 8768 && decode_bundle(current.data, current.len, mut decoded)
		mut expected := before; for disk in 0 .. 64 { expected.plans[disk].key.bytes = observed[disk] }; assert decoded == expected
		assert capacity_batch_io.maximum == 64 && capacity_batch_io.steps == 128; assert_capacity_batch_pins_drained()
		contract_capacity_io_reset(64); capacity_batch_io.bytes = observed; capacity_batch_io.mode = 1
		assert run(195, &args[0]) == 0 && os.read_bytes(path)! == current && capacity_batch_io.renames == 1 && capacity_batch_io.flushes == 2
		assert_capacity_batch_pins_drained()
	}
}
