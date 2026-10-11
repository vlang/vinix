// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module volumecli

struct GrowthIO {
mut:
	parent  Status
	views   [64]Status
	exists  [64]bool
	balance int
	creates int
	grows   int
	mode    int
}

__global growth_io GrowthIO

fn growth_fixture() Plan {
	growth_io = GrowthIO{
		parent: Status{
			version: 1
			bytes:   16777216
			sector:  512
			flags:   4
			disk_id: 7
			slot:    u64(-1)
		}
	}
	growth_io.exists[2] = true
	growth_io.views[2] = Status{
		version:    1
		bytes:      4096
		sector:     512
		flags:      12
		disk_id:    7
		start:      1048576
		slot:       2
		generation: 99
	}
	mut plan := Plan{
		count: 2
		key:   DiskKey{
			bytes:  16777216
			sector: 512
			kind:   1
		}
	}
	put_le(&plan.key.id[0], 0, 4, 0x12345678)
	plan.rows[0] = Request{
		slot:   2
		offset: 1048576
		length: 8192
	}
	plan.rows[1] = Request{
		slot:   5
		offset: 2097152
		length: 8192
		flags:  1
	}
	return plan
}

fn growth_mock_open(path &char, flags i32) i32 {
	assert flags & C.O_NOFOLLOW != 0 && flags & C.O_CLOEXEC != 0
	assert flags & C.O_ACCMODE == C.O_RDONLY
	for slot in 0 .. 64 {
		mut name := [64]char{}
		volume_path(u32(slot), &name[0])
		if C.strcmp(path, &name[0]) != 0 { continue
		 }
		if !growth_io.exists[slot] {
			unsafe {
				C.errno = C.ENOENT
			}
			return -1
		}
		if slot == 2 && growth_io.mode == 3 { growth_io.views[slot].generation++ }
		if slot == 2 && growth_io.mode == 4 { growth_io.views[slot].bytes += 512 }
		growth_io.balance++
		return i32(200 + slot)
	}
	unsafe {
		C.errno = C.ENOENT
	}
	return -1
}

fn growth_mock_close(fd i32) i32 {
	assert fd >= 200 && fd < 264 && growth_io.balance > 0
	growth_io.balance--
	return 0
}

fn growth_mock_pread(fd i32, output voidptr, size usize, offset i64) i64 {
	assert fd == 100 && size == 1024 && offset == 0
	unsafe {
		for i in 0 .. 1024 {
			(&u8(output))[i] = 0
		}
	}
	put_le(&u8(output), 440, 4, 0x12345678)
	put_le(&u8(output), 510, 2, 0xaa55)
	return 1024
}

fn growth_mock_ioctl(fd i32, request u64, output voidptr) i32 {
	if request == 0x56560004 {
		unsafe {
			*(&Status(output)) = if fd == 100 { growth_io.parent } else { growth_io.views[fd - 200] }
		}
		return 0
	}
	row := unsafe { *(&Request(output)) }
	if request == 0x56560001 {
		assert fd == 100
		growth_io.creates++
		if growth_io.mode == 2 {
			unsafe {
				C.errno = C.ENOSPC
			}
			return -1
		}
		assert !growth_io.exists[row.slot]
		growth_io.exists[row.slot] = true
		growth_io.views[row.slot] = Status{
			version:    1
			bytes:      row.length
			sector:     512
			flags:      12 | row.flags
			disk_id:    7
			start:      row.offset
			slot:       row.slot
			generation: 100
		}
		return 0
	}
	assert request == 0x56560002 && fd >= 200 && fd < 264
	assert row.version == 1 && row.slot == 0 && row.offset == 0 && row.flags == 0
	growth_io.grows++
	if growth_io.mode == 1 {
		unsafe {
			C.errno = C.EBUSY
		}
		return -1
	}
	assert row.length > growth_io.views[fd - 200].bytes
	growth_io.views[fd - 200].bytes = row.length
	return 0
}

fn test_growth_restore_is_opt_in_and_keeps_generations_with_idempotent_replay() {
	plan := growth_fixture()
	mut state := RestoreState{}
	assert !prepare_restore(100, &plan, mut state)
	assert growth_io.balance == 0 && growth_io.grows == 0 && growth_io.creates == 0
	assert prepare_restore_mode(100, &plan, mut state, true)
	assert state.grow[0] && state.present[0] && state.generation[0] == 99
		&& state.previous_bytes[0] == 4096
	assert !state.present[1] && !state.grow[1]
	assert apply_restore(100, &plan, &state) == 0 && growth_io.balance == 0
	assert growth_io.grows == 1 && growth_io.creates == 1
	assert growth_io.views[2].bytes == 8192 && growth_io.views[2].generation == 99
	assert growth_io.views[5].flags & 1 == 1
	assert prepare_restore_mode(100, &plan, mut state, true)
	assert apply_restore(100, &plan, &state) == 0
	assert growth_io.grows == 1 && growth_io.creates == 1 && growth_io.balance == 0
}

fn test_growth_preflight_rejects_later_conflicts_and_unlisted_extension_overlaps_without_mutation() {
	for conflict in 0 .. 2 {
		plan := growth_fixture()
		growth_io.exists[9] = true
		growth_io.views[9] = growth_io.views[2]
		growth_io.views[9].slot = 9
		growth_io.views[9].start = 1048576 + 4096
		if conflict == 1 {
			growth_io.exists[9] = false
			growth_io.exists[5] = true
			growth_io.views[5] = growth_io.views[2]
			growth_io.views[5].slot = 5
			growth_io.views[5].start = 3145728
		}
		mut state := RestoreState{}
		assert !prepare_restore_mode(100, &plan, mut state, true)
		assert growth_io.balance == 0 && growth_io.grows == 0 && growth_io.creates == 0
		assert growth_io.views[2].bytes == 4096
	}
}

fn test_growth_rechecks_generation_geometry_and_closes_on_failure_then_resumes_a_created_prefix() {
	for mode in [1, 2, 3, 4] {
		plan := growth_fixture()
		mut state := RestoreState{}
		assert prepare_restore_mode(100, &plan, mut state, true)
		growth_io.mode = mode
		assert apply_restore(100, &plan, &state) == 1 && growth_io.balance == 0
		assert !growth_io.exists[5]
		if mode == 3 || mode == 4 { assert growth_io.grows == 0
		 }
		if mode == 1 { assert growth_io.views[2].bytes == 4096 && growth_io.creates == 0
		 }
		if mode == 2 {
			assert growth_io.views[2].bytes == 8192 && growth_io.views[2].generation == 99
			growth_io.mode = 0
			assert prepare_restore_mode(100, &plan, mut state, true) && !state.grow[0]
			assert apply_restore(100, &plan, &state) == 0 && growth_io.balance == 0
			assert growth_io.grows == 1 && growth_io.creates == 2 && growth_io.exists[5]
		}
	}
}
