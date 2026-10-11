// SPDX-License-Identifier: GPL-2.0-or-later
module volumecli

import os

fn pool_disk(id u8, sector u64, bytes u64) Plan {
	mut plan := Plan{ key: DiskKey{ bytes: bytes, sector: sector, kind: 1 } }
	plan.key.id[0] = id
	return plan
}

fn pool_region(pool u32, disk u32, start u64, end u64, alignment u64) PoolRegion {
	return PoolRegion{ pool: pool, disk: disk, window: SpaceWindow{ start: start, end: end, alignment: alignment } }
}

fn test_pool_membership_atomic_rejection_removal_and_disk_index_compaction() {
	mut set := PlanSet{}
	for i in 0 .. 3 {
		plan := pool_disk(u8(i + 1), 512, 16777216)
		assert append_plan(mut set, &plan)
	}
	region := pool_region(3, 2, 1048576, 2097152, 4096)
	assert bundle_pool_add(mut set, &region)
	set.windows[63] = pool_region(63, 63, 0, 512, 512)
	before := set
	for invalid in [region, pool_region(4, 2, 2096640, 3145728, 512), pool_region(64, 0, 0, 512, 512),
		pool_region(4, 3, 0, 512, 512), pool_region(4, 0, 0, 16777728, 512),
		pool_region(4, 0, 1, 512, 512), pool_region(4, 0, 0, 513, 512),
		pool_region(4, 0, 512, 512, 512), pool_region(4, 0, 0, 512, 256),
		pool_region(4, 0, 0, 512, 768)] {
		assert !bundle_pool_add(mut set, &invalid) && set == before
	}
	assert !bundle_forget_disk(mut set, 2) && set == before
	assert !bundle_pool_remove(mut set, 3, 0) && set == before
	assert !bundle_pool_remove(mut set, 64, 2) && set == before
	assert bundle_forget_disk(mut set, 0)
	assert set.windows[0].disk == 1 && set.plans[1].key.id[0] == 3
	assert bundle_pool_remove(mut set, 3, 1) && set.regions == 0 && set.windows[0] == PoolRegion{}
	assert bundle_forget_disk(mut set, 1) && set.count == 1
	// Same persistent identity with different geometry must not double count.
	mut clone := set.plans[0]
	clone.key.bytes *= 2
	assert append_plan(mut set, &clone)
	first := pool_region(1, 0, 0, 4096, 512)
	second := pool_region(1, 1, 0, 4096, 512)
	assert bundle_pool_add(mut set, &first)
	ambiguous := set
	assert !bundle_pool_add(mut set, &second) && set == ambiguous
}

fn test_pool_allocations_follow_membership_order_skip_sector_mismatch_and_preserve_failure_outputs() {
	mut set := PlanSet{}
	first := pool_disk(1, 4096, 16777216)
	second := pool_disk(2, 512, 16777216)
	assert append_plan(mut set, &first) && append_plan(mut set, &second)
	for region in [pool_region(3, 1, 1048576, 1056768, 4096),
		pool_region(3, 0, 1048576, 1056768, 4096)] {
		assert bundle_pool_add(mut set, &region)
	}
	mut disk := u32(99)
	mut chosen := Request{ slot: 63, length: 99 }
	row := Request{ slot: 9, length: 8192, flags: 1 }
	assert bundle_pool_allocate(mut set, 3, &row, unsafe { &disk }, mut chosen)
	assert disk == 1 && chosen == Request{ slot: 9, offset: 1048576, length: 8192, flags: 1 }
	row2 := Request{ slot: 10, length: 8192 }
	assert bundle_pool_allocate(mut set, 3, &row2, unsafe { &disk }, mut chosen) && disk == 0
	before := set
	old_chosen := chosen
	for request in [row, Request{ slot: 11, length: 512 }, Request{ slot: 11, length: 0 },
		Request{ slot: 11, length: 8192, flags: 2 }, Request{ slot: 64, length: 8192 },
		Request{ slot: 11, length: 8192, version: 2 }] {
		assert !bundle_pool_allocate(mut set, 3, &request, unsafe { &disk }, mut chosen)
		assert set == before && disk == 0 && chosen == old_chosen
	}
	assert !bundle_pool_allocate(mut set, 2, &row2, unsafe { &disk }, mut chosen) && set == before
	// Membership removal leaves the desired mapping and its mode intact.
	assert bundle_pool_remove(mut set, 3, 1) && set.plans[1].rows[0] == row_with_offset(row, 1048576)
	assert bundle_remove_row(mut set, 9)
	region := pool_region(4, 1, 1048576, 1056768, 4096)
	assert bundle_pool_add(mut set, &region)
	short := Request{ slot: 9, length: 512 }
	assert bundle_pool_allocate(mut set, 4, &short, unsafe { &disk }, mut chosen) && disk == 1
}

fn row_with_offset(row Request, offset u64) Request {
	return Request{ version: row.version, slot: row.slot, offset: offset, length: row.length, flags: row.flags }
}

// Independent sector-cell oracle: each occupied bit takes one sector followed
// by one free sector. Pool totals count aligned gap suffixes, not raw holes.
fn oracle_pool_region(mask int, alignment u64, length u64) (u64, u64, u32, u64) {
	mut total := u64(0)
	mut largest := u64(0)
	mut gaps := u32(0)
	mut fit := u64(-1)
	mut cell := 0
	for cell < 8 {
		if cell % 2 == 0 && mask & (1 << (cell / 2)) != 0 {
			cell++
			continue
		}
		start := cell
		for cell < 8 && !(cell % 2 == 0 && mask & (1 << (cell / 2)) != 0) { cell++ }
		mut aligned := u64(start + 2) * 512
		for aligned % alignment != 0 { aligned += 512 }
		end := u64(cell + 2) * 512
		if aligned >= end { continue }
		bytes := end - aligned
		total += bytes
		gaps++
		if bytes > largest { largest = bytes }
		if fit == u64(-1) && bytes >= length { fit = aligned }
	}
	return total, largest, gaps, fit
}

fn test_pool_capacity_and_first_fit_match_independent_fragmentation_oracle() {
	for first_mask in 0 .. 16 {
		for second_mask in 0 .. 16 {
			mut set := PlanSet{}
			for disk in 0 .. 2 {
				mut plan := pool_disk(u8(disk + 1), 512, 8192)
				mask := if disk == 0 { first_mask } else { second_mask }
				for bit in 0 .. 4 {
					if mask & (1 << bit) != 0 {
						plan.rows[plan.count] = Request{ slot: u32(disk * 16 + bit), offset: u64(2 + bit * 2) * 512, length: 512, flags: u64(bit & 1) }
						plan.count++
					}
				}
				assert append_plan(mut set, &plan)
				region := pool_region(3, u32(disk), 1024, 5120, if disk == 0 {
					u64(1024)
				} else {
					u64(2048)
				})
				assert bundle_pool_add(mut set, &region)
			}
			for cells in 1 .. 9 {
				length := u64(cells) * 512
				a_total, a_largest, a_gaps, a_fit := oracle_pool_region(first_mask, 1024, length)
				b_total, b_largest, b_gaps, b_fit := oracle_pool_region(second_mask, 2048, length)
				mut total := PoolSpace{}
				assert bundle_pool_space(&set, 3, mut total)
				assert total.regions == 2 && total.bytes_low == a_total + b_total && total.bytes_high == 0
				assert total.gaps == a_gaps + b_gaps && total.largest == if a_largest > b_largest {
					a_largest
				} else {
					b_largest
				}
				mut trial := set
				request := Request{ slot: 50, length: length }
				mut disk := u32(99)
				mut row := Request{ slot: 63, length: 99 }
				fits := a_fit != u64(-1) || b_fit != u64(-1)
				assert bundle_pool_allocate(mut trial, 3, &request, unsafe { &disk }, mut row) == fits
				if fits {
					assert disk == if a_fit != u64(-1) { u32(0) } else { u32(1) }
					assert row.offset == if a_fit != u64(-1) { a_fit } else { b_fit }
					assert row.slot == 50 && row.length == length && trial.regions == set.regions && trial.windows == set.windows
				} else {
					assert trial == set && disk == 99 && row == Request{ slot: 63, length: 99 }
				}
			}
		}
	}
}

fn test_pool_format_v1_compatibility_v2_roundtrip_corruption_and_appended_disk_indices() {
	mut set := PlanSet{}
	plan := pool_disk(1, 512, 8192)
	assert append_plan(mut set, &plan)
	mut original := [8768]u8{}
	assert encode_bundle(&set, &original[0]) == 128
	region := pool_region(3, 0, 1024, 8192, 4096)
	assert bundle_pool_add(mut set, &region)
	mut bytes := [8768]u8{}
	size := encode_bundle(&set, &bytes[0])
	assert size == 168 && bytes[..8].bytestr() == 'VINIXVS2' && get_le(&bytes[0], 28, 4) == 1
	mut decoded := PlanSet{}
	assert decode_bundle(&bytes[0], size, mut decoded) && decoded == set
	for shorter in 0 .. size {
		decoded = PlanSet{}
		assert !decode_bundle(&bytes[0], shorter, mut decoded) && decoded.count == 0 && decoded.regions == 0
	}
	for at in 0 .. size {
		for bit in 0 .. 8 {
			bytes[at] ^= u8(1 << bit)
			decoded = PlanSet{}
			assert !decode_bundle(&bytes[0], size, mut decoded) && decoded.count == 0 && decoded.regions == 0
			bytes[at] ^= u8(1 << bit)
		}
	}
	for field, value in {
		8:   u64(1)
		28:  0
		32:  1
		128: 64
		132: 1
		136: 8192
		144: 8193
		152: 0
		160: 1
	} {
		mut broken := bytes
		put_le(&broken[0], field, 4, value)
		put_le(&broken[0], 24, 4, crc32(&broken[0], size, 24))
		decoded = PlanSet{}
		assert !decode_bundle(&broken[0], size, mut decoded) && decoded.count == 0 && decoded.regions == 0
	}
	decoded = PlanSet{}
	other := pool_disk(2, 512, 8192)
	assert append_plan(mut decoded, &other)
	assert decode_bundle(&bytes[0], size, mut decoded) && decoded.windows[0].disk == 1
	assert decoded.plans[1] == plan && decoded.regions == 1
	assert bundle_pool_remove(mut set, 3, 0)
	mut after := [8768]u8{}
	assert encode_bundle(&set, &after[0]) == 128 && after[..128] == original[..128]
}

fn test_full_pool_format_bound_and_capacity_totals_exceeding_u64() {
	mut set := PlanSet{}
	for i in 0 .. 64 {
		mut plan := pool_disk(u8(i + 1), 512, u64(-1) & ~u64(511))
		plan.count = 1
		plan.rows[0] = Request{ slot: u32(i), length: 512 }
		assert append_plan(mut set, &plan)
		region := pool_region(3, u32(i), 512, plan.key.bytes, 512)
		assert bundle_pool_add(mut set, &region)
	}
	mut bytes := [8770]u8{}
	bytes[8768] = 0xad
	bytes[8769] = 0xae
	assert encode_bundle(&set, &bytes[0]) == 8768 && bytes[8768] == 0xad && bytes[8769] == 0xae
	mut decoded := PlanSet{}
	assert decode_bundle(&bytes[0], 8768, mut decoded) && decoded == set
	before := set
	region := pool_region(4, 0, 0, 512, 512)
	assert !bundle_pool_add(mut set, &region) && set == before
	mut total := PoolSpace{}
	assert bundle_pool_space(&set, 3, mut total) && total.bytes_high == 63 && total.bytes_low == u64(-65536)
	mut text := [40]char{}
	pool_bytes_decimal(&total, &text[0])
	assert C.strcmp(&text[0], c'1180591620717411237888') == 0
	for test in [PoolSpace{}, PoolSpace{ bytes_low: u64(-1) }, PoolSpace{ bytes_high: 1 },
		PoolSpace{ bytes_high: u64(-1), bytes_low: u64(-1) }] {
		pool_bytes_decimal(&test, &text[0])
		assert C.strlen(&text[0]) >= 1 && C.strlen(&text[0]) <= 39
	}
}

fn test_pool_file_commands_preserve_queries_and_refuse_corrupt_symlink_or_nonregular_inputs() {
	work := os.join_path(os.temp_dir(), 'vinix-pool-${os.getpid()}')
	os.mkdir(work)!
	defer { os.rmdir_all(work) or {} }
	path := work + '/pool.vset'
	mut set := PlanSet{}
	plan := pool_disk(1, 512, 8192)
	assert append_plan(mut set, &plan) && publish_bundle(path.str, &set)
	base := os.read_bytes(path)!
	region := pool_region(3, 0, 1024, 8192, 4096)
	assert edit_pool_plan(path.str, &region, false) == 0
	added := os.read_bytes(path)!
	assert space_pool_plan(path.str, 3) == 0 && os.read_bytes(path)! == added
	assert space_pool_plan(path.str, 4) == 1 && os.read_bytes(path)! == added
	request := Request{ slot: 9, length: 4096, flags: 1 }
	assert allocate_pool_plan(path.str, 3, &request) == 0
	allocated := os.read_bytes(path)!
	assert allocate_pool_plan(path.str, 3, &request) == 1 && os.read_bytes(path)! == allocated
	os.symlink(path, work + '/link')!
	for input in [work + '/link', work + '/missing', work] {
		assert edit_pool_plan(input.str, &region, false) == 1
		assert allocate_pool_plan(input.str, 3, &request) == 1
		assert space_pool_plan(input.str, 3) == 1
	}
	assert edit_pool_plan(path.str, &region, true) == 0
	removed := os.read_bytes(path)!
	mut decoded := PlanSet{}
	assert decode_bundle(removed.data, removed.len, mut decoded) && decoded.regions == 0 && decoded.plans[0].count == 1
	assert edit_bundle_plan(path.str, 0, &request, true) == 0 && os.read_bytes(path)! == base
	mut damaged := added.clone()
	damaged[144] ^= 1
	os.write_file_array(path, damaged)!
	assert edit_pool_plan(path.str, &region, false) == 1 && space_pool_plan(path.str, 3) == 1
	assert allocate_pool_plan(path.str, 3, &request) == 1 && os.read_bytes(path)! == damaged
}

fn test_pool_cli_rejects_counts_indices_modes_and_overflow_before_io() {
	unsafe {
		mut args := [&char(c'vinix-volume'), &char(c'pool-add'), &char(c'/unused'), &char(c'3'),
			&char(c'0'), &char(c'1024'), &char(c'8192'), &char(c'4096'), &char(nil)]!
		assert run(7, &args[0]) == 2 && run(9, &args[0]) == 2
		for bad in [c'', c'-1', c'64', c'1x', c'18446744073709551616'] {
			args[3] = &char(bad)
			assert run(8, &args[0]) == 2
		}
		args[3] = &char(c'3')
		args[1] = &char(c'pool-remove')
		assert run(4, &args[0]) == 2 && run(6, &args[0]) == 2
		args[4] = &char(c'64')
		assert run(5, &args[0]) == 2
		args[1] = &char(c'pool-space')
		assert run(3, &args[0]) == 2 && run(5, &args[0]) == 2
		args[1] = &char(c'pool-allocate')
		args[4] = &char(c'9')
		args[5] = &char(c'0')
		assert run(6, &args[0]) == 2
		args[5] = &char(c'4096')
		args[6] = &char(c'rw')
		assert run(7, &args[0]) == 2 && run(5, &args[0]) == 2 && run(8, &args[0]) == 2
	}
}
