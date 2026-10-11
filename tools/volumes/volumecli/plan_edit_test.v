// SPDX-License-Identifier: GPL-2.0-or-later
module volumecli

import os

fn edit_sample(mut set PlanSet) {
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
		length: 4096
	}
	plan.rows[1] = Request{
		slot:   5
		offset: 2097152
		length: 8192
		flags:  1
	}
	assert append_plan(mut set, &plan)
	put_le(&plan.key.id[0], 0, 4, 0x12345679)
	plan.count = 0 // An enrolled empty disk can receive its first planned mapping.
	assert append_plan(mut set, &plan)
}

fn edit_load(path string, mut set PlanSet) bool {
	fd := C.open(path.str, C.O_RDONLY | C.O_NOFOLLOW | C.O_CLOEXEC)
	if fd < 0 { return false }
	defer { C.close(fd) }
	return read_bundle(fd, mut set, false)
}

fn test_addition_and_middle_last_removal_preserve_identities_order_and_slot_ownership() {
	mut set := PlanSet{}
	edit_sample(mut set)
	first_key := set.plans[0].key
	second_key := set.plans[1].key
	readonly := Request{
		slot:   12
		offset: 4194304
		length: 4096
		flags:  1
	}
	writable := Request{
		slot:   9
		offset: 1048576
		length: 4096
	}
	assert bundle_add_row(mut set, 0, &readonly) && bundle_add_row(mut set, 1, &writable)
	assert set.plans[0].count == 3 && set.plans[1].count == 1
	assert set.plans[0].rows[2] == readonly && set.plans[1].rows[0] == writable
	assert bundle_remove_row(mut set, 5)
	assert set.plans[0].count == 2 && set.plans[0].rows[0].slot == 2
		&& set.plans[0].rows[1] == readonly
	assert bundle_remove_row(mut set, 9) && set.plans[1].count == 0
	assert key_matches(&set.plans[0].key, &first_key) && key_matches(&set.plans[1].key, &second_key)
	assert set.slots == (u64(1) << 2) | (u64(1) << 12)
	// The freed global slot can belong to another disk in the saved configuration.
	reused := Request{
		slot:   5
		offset: 2097152
		length: 8192
	}
	assert bundle_add_row(mut set, 1, &reused) && set.plans[1].rows[0] == reused
	assert bundle_remove_row(mut set, 2) && bundle_remove_row(mut set, 12)
	assert bundle_remove_row(mut set, 5) && set.count == 2 && set.slots == 0
	mut bytes := [6208]u8{}
	size := encode_bundle(&set, &bytes[0])
	mut loaded := PlanSet{}
	assert size == 192 && decode_bundle(&bytes[0], size, mut loaded)
	assert loaded.count == 2 && loaded.slots == 0 && loaded.plans[0].count == 0
}

fn test_invalid_addition_rolls_back_all_fields_and_rejects_cross_disk_slots_and_geometry() {
	mut set := PlanSet{}
	edit_sample(mut set)
	original := set
	valid := Request{
		slot:   9
		offset: 3145728
		length: 4096
	}
	for failure in 0 .. 12 {
		mut row := valid
		mut disk := 0
		match failure {
			0 {
				disk = -1
			}
			1 {
				disk = 2
			}
			2 {
				row.slot = 64
			}
			3 {
				row.slot = 2
				disk = 1
			}
			4 {
				row.offset = 2097152
			}
			5 {
				row.offset++
			}
			6 {
				row.length++
			}
			7 {
				row.length = 0
			}
			8 {
				row.offset = 16777216
			}
			9 {
				row.length = u64(-1)
			}
			10 {
				row.flags = 2
			}
			else {
				row.version = 2
			}
		}

		assert !bundle_add_row(mut set, disk, &row) && set == original
	}
	assert !bundle_remove_row(mut set, 9) && !bundle_remove_row(mut set, 64)
	assert set == original
	// Overflowing absolute offsets must fail before endpoint arithmetic.
	bad := Request{
		slot:   9
		offset: u64(-1)
		length: 512
	}
	assert !bundle_add_row(mut set, 1, &bad) && set == original
}

fn test_full_slot_and_disk_boundaries_remain_encodable_after_remove_and_reuse() {
	mut set := PlanSet{}
	for disk in 0 .. 64 {
		mut plan := Plan{
			count: 1
			key:   DiskKey{
				bytes:  4096
				sector: 512
				kind:   1
			}
		}
		put_le(&plan.key.id[0], 0, 4, u64(disk + 1))
		plan.rows[0] = Request{
			slot:   u32(disk)
			length: 512
		}
		assert append_plan(mut set, &plan)
	}
	original := set
	extra := Request{
		slot:   63
		offset: 1024
		length: 512
	}
	assert !bundle_add_row(mut set, 0, &extra) && set == original
	assert bundle_remove_row(mut set, 63) && set.plans[63].count == 0
	assert bundle_add_row(mut set, 0, &extra) && set.slots == u64(-1)
	mut bytes := [6208]u8{}
	assert encode_bundle(&set, &bytes[0]) == 6208
	mut loaded := PlanSet{}
	assert decode_bundle(&bytes[0], 6208, mut loaded) && loaded.slots == u64(-1)
	// A completely occupied per-disk row array must never be indexed at 64.
	mut single := PlanSet{}
	mut plan := Plan{
		count: 64
		key:   DiskKey{
			bytes:  65536
			sector: 512
			kind:   1
		}
	}
	plan.key.id[0] = 1
	for i in 0 .. 64 {
		plan.rows[i] = Request{
			slot:   u32(i)
			offset: u64(i * 512)
			length: 512
		}
	}
	assert append_plan(mut single, &plan)
	full := single
	assert !bundle_add_row(mut single, 0, &extra) && single == full
}

fn test_file_edits_are_offline_checksummed_and_preserve_previous_bytes_on_invalid_input() {
	work := os.join_path(os.temp_dir(), 'vinix-plan-edit-${os.getpid()}')
	os.mkdir(work)!
	defer { os.rmdir_all(work) or {} }
	path := work + '/saved.vset'
	mut set := PlanSet{}
	edit_sample(mut set)
	assert publish_bundle(path.str, &set)
	original := os.read_bytes(path)!
	row := Request{
		slot:   9
		offset: 1048576
		length: 4096
		flags:  1
	}
	assert edit_bundle_plan(path.str, 1, &row, false) == 0
	added := os.read_bytes(path)!
	assert added.len == original.len + 32
	mut loaded := PlanSet{}
	assert edit_load(path, mut loaded) && loaded.plans[1].rows[0] == row
	assert key_matches(&set.plans[1].key, &loaded.plans[1].key)
	assert edit_bundle_plan(path.str, 0, &row, false) == 1 && os.read_bytes(path)! == added
	os.symlink(path, work + '/link')!
	assert edit_bundle_plan((work + '/link').str, 1, &row, true) == 1
	assert os.read_bytes(path)! == added
	assert edit_bundle_plan(path.str, 1, &row, true) == 0 && os.read_bytes(path)! == original
	assert edit_bundle_plan(path.str, 1, &row, true) == 1 && os.read_bytes(path)! == original
	mut damaged := original.clone()
	damaged[128] ^= 1
	os.write_file_array(path, damaged)!
	assert edit_bundle_plan(path.str, 1, &row, false) == 1 && os.read_bytes(path)! == damaged
	assert os.ls(work)!.len == 2 // Saved file and symlink; no publication temporary.
}

fn test_planning_cli_rejects_bad_numbers_modes_and_argument_counts_before_io() {
	unsafe {
		mut args := [&char(c'vinix-volume'), &char(c'plan-add'), &char(c'/unused'), &char(c'0'),
			&char(c'12'), &char(c'4194304'), &char(c'4096'), &char(c'bad'), &char(nil)]!
		assert run(8, &args[0]) == 2 && run(6, &args[0]) == 2 && run(9, &args[0]) == 2
		args[3] = &char(c'64')
		assert run(7, &args[0]) == 2
		args[3] = &char(c'0')
		args[4] = &char(c'-1')
		assert run(7, &args[0]) == 2
		args[4] = &char(c'12')
		args[5] = &char(c'18446744073709551616')
		assert run(7, &args[0]) == 2
		args[5] = &char(c'4194304')
		args[6] = &char(c'0')
		assert run(7, &args[0]) == 2
		args[1] = &char(c'plan-remove')
		args[3] = &char(c'64')
		assert run(4, &args[0]) == 2 && run(3, &args[0]) == 2 && run(5, &args[0]) == 2
	}
}
