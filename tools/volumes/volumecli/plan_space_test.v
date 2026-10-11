// SPDX-License-Identifier: GPL-2.0-or-later
module volumecli

import os

fn space_sample(mask u32) PlanSet {
	mut plan := Plan{ key: DiskKey{ bytes: 8192, sector: 512, kind: 1 } }
	plan.key.id[0] = 1
	// Deliberately descending physical order, mixing writable and read-only rows.
	for i := 7; i >= 0; i-- {
		if mask & (u32(1) << i) == 0 { continue }
		plan.rows[plan.count] = Request{
			slot:   u32(i)
			offset: u64(i * 512)
			length: 512
			flags:  u64(i & 1)
		}
		plan.count++
	}
	mut set := PlanSet{}
	assert append_plan(mut set, &plan)
	return set
}

// Independent cell oracle uses integer division and occupancy, not interval
// sorting or the planner's bitwise rounding. All 256 fragmentation patterns.
fn test_free_extents_match_cell_oracle_for_every_small_fragmented_window() {
	for mask in 0 .. 256 {
		set := space_sample(u32(mask))
		for start in 0 .. 8 {
			for end in start + 1 .. 9 {
				for alignment in [1, 2, 4] {
					window := SpaceWindow{
						start:     u64(start * 512)
						end:       u64(end * 512)
						alignment: u64(alignment * 512)
					}
					mut got := FreeExtents{}
					assert bundle_free_extents(&set, 0, window, mut got)
					mut expected := FreeExtents{}
					mut cell := start
					for cell < end {
						if mask & (1 << cell) != 0 {
							cell++
							continue
						}
						first := cell
						for cell < end && mask & (1 << cell) == 0 { cell++ }
						aligned := ((first + alignment - 1) / alignment) * alignment
						if aligned >= cell { continue }
						gap := FreeExtent{ offset: u64(aligned * 512), length: u64((cell - aligned) * 512) }
						expected.rows[expected.count] = gap
						expected.count++
						expected.total += gap.length
						if gap.length > expected.largest { expected.largest = gap.length }
					}
					assert got == expected
				}
			}
		}
		assert set == space_sample(u32(mask))
	}
}

fn test_first_fit_allocation_matches_brute_force_and_preserves_desired_rows() {
	for mask in 0 .. 256 {
		for alignment in [1, 2, 4] {
			mut set := space_sample(u32(mask))
			original := set
			window := SpaceWindow{ end: 4096, alignment: u64(alignment * 512) }
			request := Request{ slot: 63, length: 1024, flags: 1 }
			mut chosen := Request{ offset: 123 }
			mut expected := -1
			for cell in 0 .. 7 {
				if cell % alignment == 0 && mask & (3 << cell) == 0 {
					expected = cell
					break
				}
			}
			assert bundle_allocate_row(mut set, 0, window, &request, mut chosen) == (expected >= 0)
			if expected < 0 {
				assert set == original && chosen == Request{ offset: 123 }
			} else {
				assert chosen == Request{ slot: 63, offset: u64(expected * 512), length: 1024, flags: 1 }
				assert set.plans[0].count == original.plans[0].count + 1
				for i := u32(0); i < original.plans[0].count; i++ {
					assert set.plans[0].rows[i] == original.plans[0].rows[i]
				}
				assert set.slots == original.slots | (u64(1) << 63)
				mut bytes := [6208]u8{}
				size := encode_bundle(&set, &bytes[0])
				mut decoded := PlanSet{}
				assert decode_bundle(&bytes[0], size, mut decoded) && decoded == set
			}
		}
	}
}

fn test_invalid_ranges_and_allocations_leave_state_and_outputs_unchanged() {
	mut set := space_sample(0b11)
	original := set
	valid := SpaceWindow{ start: 1024, end: 8192, alignment: 512 }
	request := Request{ slot: 9, length: 512 }
	for failure in 0 .. 14 {
		mut window := valid
		mut row := request
		mut disk := 0
		match failure {
			0 { disk = -1 }
			1 { disk = 1 }
			2 { window = SpaceWindow{ start: 8192, end: 8192, alignment: 512 } }
			3 { window = SpaceWindow{ start: 8192, end: 1024, alignment: 512 } }
			4 { window = SpaceWindow{ end: 8704, alignment: 512 } }
			5 { window = SpaceWindow{ end: 8192, alignment: 0 } }
			6 { window = SpaceWindow{ end: 8192, alignment: 1536 } }
			7 { window = SpaceWindow{ end: 8192, alignment: 256 } }
			8 { window = SpaceWindow{ start: 1, end: 8192, alignment: 512 } }
			9 { window = SpaceWindow{ end: 8191, alignment: 512 } }
			10 { row.slot = 0 }
			11 { row.slot = 64 }
			12 { row.length = 513 }
			else { row.flags = 2 }
		}
		mut chosen := Request{ offset: 123 }
		assert !bundle_allocate_row(mut set, disk, window, &row, mut chosen)
		assert set == original && chosen == Request{ offset: 123 }
		if failure < 10 {
			mut space := FreeExtents{ total: 123 }
			assert !bundle_free_extents(&set, disk, window, mut space)
			assert space == FreeExtents{ total: 123 }
		}
	}
	for row in [Request{ slot: 9 }, Request{ slot: 9, length: 512, version: 2 },
		Request{ slot: 9, length: u64(-1) }] {
		mut chosen := Request{}
		assert !bundle_allocate_row(mut set, 0, valid, &row, mut chosen) && set == original
	}
}

fn test_maximum_gaps_global_slots_sector_sizes_and_overflow_rounding() {
	mut plan := Plan{ count: 64, key: DiskKey{ bytes: 131072, sector: 512, kind: 1 } }
	plan.key.id[0] = 1
	for i in 0 .. 64 {
		plan.rows[i] = Request{ slot: u32(i), offset: u64((2 * i + 1) * 512), length: 512 }
	}
	mut set := PlanSet{}
	assert append_plan(mut set, &plan)
	mut space := FreeExtents{}
	assert bundle_free_extents(&set, 0, SpaceWindow{ end: 66048, alignment: 512 }, mut space)
	assert space.count == 65 && space.total == 65 * 512 && space.largest == 512
	for i in 0 .. 65 {
		assert space.rows[i] == FreeExtent{ offset: u64(i * 1024), length: 512 }
	}
	mut second := Plan{ key: DiskKey{ bytes: 16384, sector: 4096, kind: 1 } }
	second.key.id[0] = 2
	assert append_plan(mut set, &second)
	original := set
	mut chosen := Request{}
	row := Request{ slot: 63, length: 4096 }
	assert !bundle_allocate_row(mut set, 1, SpaceWindow{ end: 16384, alignment: 4096 }, &row, mut chosen)
	assert set == original // Free physical space cannot bypass global slot ownership.
	assert bundle_remove_row(mut set, 63)
	assert bundle_allocate_row(mut set, 1, SpaceWindow{ start: 4096, end: 16384, alignment: 8192 }, &row, mut chosen)
	assert chosen.offset == 8192 && chosen.length == 4096
	mut huge := Plan{ key: DiskKey{ bytes: u64(-1) & ~u64(511), sector: 512, kind: 1 } }
	huge.key.id[0] = 3
	mut big := PlanSet{}
	assert append_plan(mut big, &huge)
	assert bundle_free_extents(&big, 0, SpaceWindow{
		start:     huge.key.bytes - 512
		end:       huge.key.bytes
		alignment: u64(1) << 63
	}, mut space) && space.count == 0
	assert bundle_free_extents(&big, 0, SpaceWindow{
		start:     (u64(1) << 63) - 512
		end:       (u64(1) << 63) + 512
		alignment: u64(1) << 63
	}, mut space)
	assert space.count == 1 && space.rows[0] == FreeExtent{ offset: u64(1) << 63, length: 512 }
}

fn test_space_files_are_offline_and_atomic_and_bad_inputs_do_not_replace_bytes() {
	work := os.join_path(os.temp_dir(), 'vinix-plan-space-${os.getpid()}')
	os.mkdir(work)!
	defer { os.rmdir_all(work) or {} }
	path := work + '/saved.vset'
	set := space_sample(0b101)
	assert publish_bundle(path.str, &set)
	original := os.read_bytes(path)!
	window := SpaceWindow{ end: 4096, alignment: 1024 }
	row := Request{ slot: 9, length: 1024, flags: 1 }
	assert space_bundle_plan(path.str, 0, window, &row, false) == 0
	assert os.read_bytes(path)! == original
	assert space_bundle_plan(path.str, 0, window, &row, true) == 0
	added := os.read_bytes(path)!
	mut decoded := PlanSet{}
	assert decode_bundle(added.data, added.len, mut decoded)
	assert decoded.plans[0].rows[2] == Request{ slot: 9, offset: 2048, length: 1024, flags: 1 }
	assert space_bundle_plan(path.str, 0, window, &row, true) == 1 && os.read_bytes(path)! == added
	os.symlink(path, work + '/link')!
	for allocate in [false, true] {
		assert space_bundle_plan((work + '/link').str, 0, window, &row, allocate) == 1
		assert space_bundle_plan(work.str, 0, window, &row, allocate) == 1
		assert space_bundle_plan((work + '/missing').str, 0, window, &row, allocate) == 1
	}
	mut corrupt := added.clone()
	corrupt[40] ^= 1
	os.write_file_array(path, corrupt)!
	for allocate in [false, true] {
		assert space_bundle_plan(path.str, 0, window, &row, allocate) == 1
		assert os.read_bytes(path)! == corrupt
	}
	assert os.ls(work)!.len == 2
}

fn test_space_cli_rejects_syntax_before_opening_files() {
	unsafe {
		mut args := [&char(c'vinix-volume'), &char(c'plan-allocate'), &char(c'/unused'), &char(c'0'),
			&char(c'9'), &char(c'1024'), &char(c'0'), &char(c'4096'), &char(c'1024'), &char(c'bad'),
			&char(nil)]!
		assert run(8, &args[0]) == 2 && run(11, &args[0]) == 2 && run(10, &args[0]) == 2
		for index in [3, 4, 5, 6, 7, 8] {
			saved := args[index]
			args[index] = &char(c'18446744073709551616')
			assert run(9, &args[0]) == 2
			args[index] = saved
		}
		args[4] = &char(c'64')
		assert run(9, &args[0]) == 2
		args[4] = &char(c'9')
		args[5] = &char(c'0')
		assert run(9, &args[0]) == 2
		args[1] = &char(c'plan-space')
		args[4] = &char(c'0')
		args[5] = &char(c'4096')
		args[6] = &char(c'0')
		assert run(6, &args[0]) == 2 && run(8, &args[0]) == 2 && run(7, &args[0]) == 2
		args[6] = &char(c'768')
		assert run(7, &args[0]) == 2
		args[4] = &char(c'-1')
		assert run(7, &args[0]) == 2
	}
}
