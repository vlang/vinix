// SPDX-License-Identifier: GPL-2.0-or-later
module volumecli

import os

fn growth_sample(mut set PlanSet) {
	mut plan := Plan{
		count: 2
		key:   DiskKey{
			bytes:  16777216
			sector: 512
			kind:   1
		}
	}
	plan.key.id[0] = 0x78
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
	plan.key.id[0] = 0x79
	plan.count = 1
	plan.rows[0].slot = 9
	assert append_plan(mut set, &plan)
}

fn test_bundle_capacity_edit_preserves_geometry_and_rejects_shrink_alignment_overlap_and_overflow() {
	mut set := PlanSet{}
	growth_sample(mut set)
	assert bundle_grow_row(mut set, 2, 8192)
	assert set.plans[0].rows[0].length == 8192 && set.plans[0].rows[0].offset == 1048576
	assert set.plans[0].rows[1].flags == 1 && set.plans[1].rows[0].length == 4096
	assert bundle_grow_row(mut set, 2, 8192) // Idempotent desired capacity.
	assert bundle_grow_row(mut set, 5, 12288) && set.plans[0].rows[1].flags == 1
	for invalid in [u64(0), 4096, 8193, 1048576 + 512, 16777216, u64(-1)] {
		assert !bundle_grow_row(mut set, 2, invalid)
		assert set.plans[0].rows[0].length == 8192 && bundle_set_valid(&set)
	}
	assert !bundle_grow_row(mut set, 12, 8192) && !bundle_grow_row(mut set, 64, 8192)
	assert bundle_grow_row(mut set, 9, 8192)
	assert set.count == 2 && set.slots == (u64(1) << 2) | (u64(1) << 5) | (u64(1) << 9)
}

fn test_growth_policy_requires_same_identity_mode_sector_slot_and_strictly_larger_length() {
	parent := Status{
		disk_id: 7
		sector:  512
	}
	row := Request{
		slot:   2
		offset: 1048576
		length: 8192
	}
	valid := Status{
		flags:      8
		disk_id:    7
		sector:     512
		start:      1048576
		bytes:      4096
		slot:       2
		generation: 99
	}
	assert mapping_growable(&valid, &parent, &row)
	for field in 0 .. 9 {
		mut invalid := valid
		match field {
			0 { invalid.disk_id++ }
			1 { invalid.sector *= 2 }
			2 { invalid.start += 512 }
			3 { invalid.slot++ }
			4 { invalid.flags |= 1 }
			5 { invalid.flags = 0 }
			6 { invalid.generation = 0 }
			7 { invalid.bytes = 0 }
			else { invalid.bytes = 4097 }
		}

		assert !mapping_growable(&invalid, &parent, &row)
	}
	for size in [u64(8192), 12288] {
		mut invalid := valid
		invalid.bytes = size
		assert !mapping_growable(&invalid, &parent, &row)
	}
	assert !mapping_growable(&valid, &Status{}, &row)
}

fn growth_load(path string, mut set PlanSet) bool {
	fd := C.open(path.str, C.O_RDONLY | C.O_NOFOLLOW | C.O_CLOEXEC)
	if fd < 0 { return false }
	defer { C.close(fd) }
	return read_bundle(fd, mut set, false)
}

fn test_planned_capacity_publication_is_offline_atomic_and_preserves_file_on_invalid_edit() {
	work := os.join_path(os.temp_dir(), 'vinix-capacity-${os.getpid()}')
	os.mkdir(work)!
	defer { os.rmdir_all(work) or {} }
	path := work + '/saved.vset'
	mut set := PlanSet{}
	growth_sample(mut set)
	assert publish_bundle(path.str, &set)
	original := os.read_bytes(path)!
	assert grow_bundle_plan(path.str, 2, 8192) == 0
	grown := os.read_bytes(path)!
	assert grown != original
	mut loaded := PlanSet{}
	assert growth_load(path, mut loaded) && loaded.plans[0].rows[0].length == 8192
	assert key_matches(&set.plans[0].key, &loaded.plans[0].key)
	assert grow_bundle_plan(path.str, 2, 8192) == 0 && os.read_bytes(path)! == grown
	for invalid in [u64(0), 4096, 8193, 1048576 + 512, u64(-1)] {
		assert grow_bundle_plan(path.str, 2, invalid) == 1 && os.read_bytes(path)! == grown
	}
	assert grow_bundle_plan(path.str, 12, 8192) == 1 && os.read_bytes(path)! == grown
	os.symlink(path, work + '/link')!
	assert grow_bundle_plan((work + '/link').str, 2, 12288) == 1 && os.read_bytes(path)! == grown
	assert os.ls(work)!.len == 2
}
