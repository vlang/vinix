// SPDX-License-Identifier: GPL-2.0-or-later
module volumecli

fn capacity_plan(id u8, slot u32, sector u64, kind u32) Plan {
	mut plan := Plan{ count: 2, key: DiskKey{ bytes: 16777216, sector: sector, kind: kind } }
	plan.key.id[0] = id
	if kind == 2 { plan.key.id[15] = 0x83 }
	// Desired order differs from physical order; one row is read-only.
	plan.rows[0] = Request{ slot: slot, offset: 4194304, length: 8192, flags: 1 }
	plan.rows[1] = Request{ slot: slot + 1, offset: 1048576, length: 12288 }
	return plan
}

fn test_capacity_adoption_preserves_all_desired_rows_members_and_inactive_storage() {
	for sector in [u64(512), 4096] {
		for kind in [u32(1), 2] {
			mut set := PlanSet{}
			first := capacity_plan(1, 2, sector, kind)
			second := capacity_plan(2, 9, sector, kind)
			assert append_plan(mut set, &first) && append_plan(mut set, &second)
			set.plans[63] = capacity_plan(99, 62, sector, kind)
			before := set
			mut key := first.key
			key.bytes = 25165824
			assert bundle_adopt_capacity(mut set, 0, &key, key.bytes)
			assert set.plans[0].key == key
			set.plans[0].key.bytes = first.key.bytes
			assert set == before
			set.plans[0].key.bytes = key.bytes
			grown := set
			assert bundle_adopt_capacity(mut set, 0, &key, key.bytes) && set == grown
			mut bytes := [6208]u8{}
			size := encode_bundle(&set, &bytes[0])
			mut decoded := PlanSet{}
			assert size == 320 && decode_bundle(&bytes[0], size, mut decoded)
			assert decoded.plans[0] == set.plans[0] && decoded.plans[1] == second
			// The adopted tail becomes available to the existing bounded allocator.
			window := SpaceWindow{ start: first.key.bytes, end: key.bytes, alignment: 4096 }
			row := Request{ slot: 14, length: 8192, flags: 1 }
			mut chosen := Request{}
			assert bundle_allocate_row(mut set, 0, window, &row, mut chosen)
			assert chosen == Request{ slot: 14, offset: 16777216, length: 8192, flags: 1 }
		}
	}
}

fn test_refused_capacity_changes_leave_every_bundle_field_unchanged() {
	mut set := PlanSet{}
	first := capacity_plan(1, 2, 512, 1)
	second := capacity_plan(2, 9, 512, 1)
	assert append_plan(mut set, &first) && append_plan(mut set, &second)
	before := set
	for failure in 0 .. 9 {
		mut key := first.key
		key.bytes = 25165824
		mut expected := key.bytes
		match failure {
			0 { key.id[0] = 3 }
			1 { key.sector = 4096 }
			2 { key.kind = 2 }
			3 {
				key.bytes = 8388608
				expected = key.bytes
			}
			4 { expected = 25166336 }
			5 {
				key.bytes++
				expected = key.bytes
			}
			6 { key.id = [16]u8{} }
			7 { key.id[15] = 1 }
			else { key.sector = 0 }
		}
		assert !bundle_adopt_capacity(mut set, 0, &key, expected) && set == before
	}
	for disk in [-1, 2, 64] {
		assert !bundle_adopt_capacity(mut set, disk, &first.key, first.key.bytes) && set == before
	}
	mut empty := PlanSet{}
	assert !bundle_adopt_capacity(mut empty, 0, &first.key, first.key.bytes) && empty == PlanSet{}
	set.plans[1].rows[1].slot = 2
	invalid := set
	assert !bundle_adopt_capacity(mut set, 0, &first.key, first.key.bytes) && set == invalid
}

fn test_capacity_adoption_rejects_duplicate_identifiers_even_at_different_geometries() {
	for equal in [false, true] {
		mut set := PlanSet{}
		first := capacity_plan(1, 2, 512, 1)
		mut second := capacity_plan(1, 9, 512, 1)
		second.key.bytes = 25165824
		if equal { second.key.sector = 4096 }
		assert append_plan(mut set, &first) && append_plan(mut set, &second)
		before := set
		mut key := first.key
		key.bytes = if equal { first.key.bytes } else { second.key.bytes }
		assert !bundle_adopt_capacity(mut set, 0, &key, key.bytes) && set == before
	}
}

fn test_capacity_adoption_handles_full_bundle_and_last_aligned_u64_capacity() {
	mut set := PlanSet{}
	for i in 0 .. 64 {
		mut plan := Plan{ count: 1, key: DiskKey{ bytes: 16777216, sector: 512, kind: 1 } }
		plan.key.id[0] = u8(i + 1)
		plan.rows[0] = Request{ slot: u32(i), offset: 512, length: 512 }
		assert append_plan(mut set, &plan)
	}
	for disk in 0 .. 64 {
		mut key := set.plans[disk].key
		key.bytes = u64(-1) & ~u64(511)
		assert bundle_adopt_capacity(mut set, disk, &key, key.bytes)
	}
	assert set.slots == u64(-1) && set.count == 64
	mut bytes := [6208]u8{}
	assert encode_bundle(&set, &bytes[0]) == 6208
	mut decoded := PlanSet{}
	assert decode_bundle(&bytes[0], 6208, mut decoded) && decoded == set
}

fn test_capacity_cli_rejects_malformed_arguments_before_opening_files() {
	unsafe {
		mut args := [&char(c'vinix-volume'), &char(c'plan-capacity'), &char(c'/unused'), &char(c'0'),
			&char(c'/unused-device'), &char(c'25165824'), &char(nil)]!
		for count in [2, 3, 4, 5, 7] {
			assert run(count, &args[0]) == 2
		}
		for bad in [c'', c'-1', c'64', c'1x', c'18446744073709551616'] {
			args[3] = &char(bad)
			assert run(6, &args[0]) == 2
		}
		args[3] = &char(c'0')
		for bad in [c'', c'0', c'-1', c'1x', c'18446744073709551616'] {
			args[5] = &char(bad)
			assert run(6, &args[0]) == 2
		}
	}
}
