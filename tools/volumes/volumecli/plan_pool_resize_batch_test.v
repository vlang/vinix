// SPDX-License-Identifier: GPL-2.0-or-later
module volumecli
import os

fn resize_key(member int, kind u32) DiskKey {
	mut key := DiskKey{bytes: 65536, sector: if member & 1 == 0 { u64(4096) } else { u64(512) }, kind: if member & 1 == 0 { u32(3) - kind } else { kind }}
	key.id[0] = u8(member); if key.kind == 2 { key.id[15] = 0x55 }; return key
}

fn resize_fixture(mut set PlanSet, transferred u32, kind u32) {
	for member in [10, 1, 2, 11, 3, 4]! {
		mut plan := Plan{key: resize_key(member, kind)}
		if member < 10 {
			plan.count = 2; plan.rows[0] = Request{slot: u32(member - 1), offset: 8192, length: 8192, flags: u64(member & 1)}
			plan.rows[1] = Request{slot: u32(member + 3), offset: 40960, length: 4096, flags: u64((member + 1) & 1)}
		}
		assert append_plan(mut set, &plan)
	}
	for member in [4, 2, 1, 3]! {
		disk := if member < 3 { member } else { member + 1 }
		boundary := if transferred & (u32(1) << (member - 1)) != 0 { u64(24576) } else { u64(32768) }
		for pool in [u32(3), 5, 4]! {
			region := PoolRegion{pool: pool, disk: u32(disk), window: SpaceWindow{start: if pool == 3 { u64(8192) } else if pool == 4 { boundary } else { u64(49152) },
				end: if pool == 3 { boundary } else if pool == 4 { u64(49152) } else { u64(65536) }, alignment: 4096}}
			assert bundle_pool_add(mut set, &region)
		}
	}
	set.plans[1].rows[63] = Request{slot: 61, length: 99}; set.plans[63].key.id[0] = 77; set.windows[63] = PoolRegion{pool: 62}
}

fn test_cross_pool_transfers_match_1024_independent_bounds_action_and_priority_oracles() {
	mut attempts := 0
	for kind in [u32(1), 2] { for reverse in [false, true] { for transferred in u32(0) .. 16 { for requested in u32(0) .. 16 {
		mut set := PlanSet{}; resize_fixture(mut set, transferred, kind); original := set; mut expected := set
		mut batch := PoolResizeBatch{}; mut wanted := PoolResizeResults{}
		for ordinal in 0 .. 4 {
			member := if reverse { 4 - ordinal } else { ordinal + 1 }; if requested & (u32(1) << (member - 1)) == 0 { continue }
			disk := if member < 3 { member } else { member + 1 }
			for step in 0 .. 2 {
				pool := if (step == 0) == reverse { u32(4) } else { u32(3) }; at := batch.count
				batch.rows[at] = PoolResizeRequest{key: original.plans[disk].key, pool: pool, start: if pool == 3 { u64(8192) } else { u64(24576) }, end: if pool == 3 { u64(24576) } else { u64(49152) }}; batch.count++
				for region in 0 .. expected.regions {
					row := expected.windows[region]; if row.pool != pool || row.disk != u32(disk) { continue }
					wanted.previous[at] = row.window
					expected.windows[region] = PoolRegion{pool: pool, disk: row.disk, window: SpaceWindow{start: batch.rows[at].start, end: batch.rows[at].end, alignment: 4096}}
					wanted.rows[at] = expected.windows[region]
				}
			}
		}
		mut result := PoolResizeResults{count: 77}; result.previous[63] = SpaceWindow{start: 99}; result.rows[63].disk = 55
		if requested == 0 { before := result; assert !bundle_pool_resize_batch(mut set, &batch, mut result) && set == original && result == before }
		else {
			wanted.count = batch.count; assert bundle_pool_resize_batch(mut set, &batch, mut result) && set == expected && result == wanted
			for i in 0 .. wanted.count { wanted.previous[i] = wanted.rows[i].window }
			assert bundle_pool_resize_batch(mut set, &batch, mut result) && set == expected && result == wanted
		}
		attempts++
	} } } }
	assert attempts == 1024
}

// Occupied cells independently retain their original pool ownership. The oracle
// uses membership of individual cells, rather than production interval clipping.
fn test_2592_two_sided_boundary_and_occupation_cases_match_a_cell_oracle() {
	mut attempts := 0
	for pattern in u32(0) .. 16 { for boundary in 20 .. 29 { for start in 16 .. 19 { for end in 30 .. 33 { for reverse in [false, true] {
		mut set := PlanSet{}; mut plan := Plan{key: resize_key(1, 1)}; cells := [17, 21, 25, 29]!
		mut allowed := true
		for i, cell in cells {
			if pattern & (u32(1) << i) == 0 { continue }
			plan.rows[plan.count] = Request{slot: u32(i), offset: u64(cell * 512), length: 512, flags: u64(i & 1)}; plan.count++
			if cell < 24 { if cell < start || cell >= boundary { allowed = false } }
			else if cell < boundary || cell >= end { allowed = false }
		}
		assert append_plan(mut set, &plan)
		for pool in [u32(3), 4]! {
			region := PoolRegion{pool: pool, disk: 0, window: SpaceWindow{start: if pool == 3 { u64(8192) } else { u64(12288) }, end: if pool == 3 { u64(12288) } else { u64(16384) }, alignment: 4096}}; assert bundle_pool_add(mut set, &region)
		}
		original := set; mut expected := set; mut wanted := PoolResizeResults{count: 2}; mut batch := PoolResizeBatch{count: 2}
		for i in 0 .. 2 {
			pool := if (i == 0) == reverse { u32(4) } else { u32(3) }; index := int(pool - 3)
			batch.rows[i] = PoolResizeRequest{key: plan.key, pool: pool, start: u64(if pool == 3 { start } else { boundary }) * 512, end: u64(if pool == 3 { boundary } else { end }) * 512}
			expected.windows[index] = PoolRegion{pool: pool, disk: 0, window: SpaceWindow{start: batch.rows[i].start, end: batch.rows[i].end, alignment: 4096}}
			wanted.previous[i] = original.windows[index].window; wanted.rows[i] = expected.windows[index]
		}
		mut result := PoolResizeResults{count: 71}; result.rows[63].disk = 99; before := result
		assert bundle_pool_resize_batch(mut set, &batch, mut result) == allowed
		if allowed { assert set == expected && result == wanted } else { assert set == original && result == before }
		attempts++
	} } } } }
	assert attempts == 2592
}

fn test_later_resize_failures_preserve_the_whole_set_and_result_including_inactive_storage() {
	mut baseline := PlanSet{}; resize_fixture(mut baseline, 0, 1)
	for mode in 0 .. 16 {
		mut set := baseline; mut batch := PoolResizeBatch{count: 2}
		batch.rows[0] = PoolResizeRequest{key: set.plans[1].key, pool: 4, start: 24576, end: 49152}
		batch.rows[1] = PoolResizeRequest{key: set.plans[1].key, pool: 3, start: 8192, end: 24576}
		match mode {
			0 { batch.count = -1 } 1 { batch.count = 0 } 2 { batch.count = 65 }
			3 { batch.rows[1].key.id[0] = 99 } 4 { batch.rows[1].key = DiskKey{} }
			5 { batch.rows[1].pool = 64 } 6 { batch.rows[1].pool = 6 }
			7 { batch.rows[1].key = set.plans[0].key }
			8 { batch.rows[1].start = 16384 } 9 { batch.rows[1].end = 12288 }
			10 { batch.rows[1].start = 8193 } 11 { batch.rows[1].end = 24577 }
			12 { batch.rows[1].end = u64(-1) } 13 { batch.rows[1].end = 0 }
			14 { batch.rows[1].end = 32768 } // Final overlap after the earlier expansion.
			else { batch.rows[1] = batch.rows[0]; batch.rows[1].key.bytes *= 2 }
		}
		mut result := PoolResizeResults{count: 71}; result.rows[63].disk = 99; result.previous[63] = SpaceWindow{end: 55}; before := result
		assert !bundle_pool_resize_batch(mut set, &batch, mut result) && set == baseline && result == before
	}
	mut set := baseline; mut alias := Plan{key: set.plans[1].key}; alias.key.bytes *= 2; assert append_plan(mut set, &alias); ambiguous := set
	mut batch := PoolResizeBatch{count: 1}; batch.rows[0] = PoolResizeRequest{key: baseline.plans[1].key, pool: 3, start: 8192, end: 32768}; mut result := PoolResizeResults{count: 77}
	assert !bundle_pool_resize_batch(mut set, &batch, mut result) && set == ambiguous && result == PoolResizeResults{count: 77}
	set = baseline; set.plans[0].key.kind = 3; invalid := set; assert !bundle_pool_resize_batch(mut set, &batch, mut result) && set == invalid
}

fn test_resize_preserves_clipped_intersections_and_resolves_saved_geometry_after_disk_compaction() {
	mut set := PlanSet{}; mut plan := Plan{key: resize_key(1, 1), count: 1}
	plan.rows[0] = Request{slot: 1, offset: 4096, length: 8704, flags: 1}; assert append_plan(mut set, &plan)
	region := PoolRegion{pool: 3, disk: 0, window: SpaceWindow{start: 8192, end: 32768, alignment: 4096}}; assert bundle_pool_add(mut set, &region)
	mut batch := PoolResizeBatch{count: 1}; batch.rows[0] = PoolResizeRequest{key: plan.key, pool: 3, start: 8192, end: 12800}; mut result := PoolResizeResults{}
	assert bundle_pool_resize_batch(mut set, &batch, mut result) && set.plans[0] == plan && result.rows[0].window.end == 12800
	before := set; batch.rows[0].start = 8704; assert !bundle_pool_resize_batch(mut set, &batch, mut result) && set == before
	set.plans[0].rows[0] = Request{slot: 1, offset: 28672, length: 8192, flags: 1}; set.windows[0] = region
	batch.rows[0].start = 28672; batch.rows[0].end = 32768; assert bundle_pool_resize_batch(mut set, &batch, mut result)
	assert set.plans[0].rows[0].length == 8192 && result.rows[0].window.start == 28672
	set = PlanSet{}; resize_fixture(mut set, 0, 1); batch.rows[0] = PoolResizeRequest{key: set.plans[1].key, pool: 3, start: 7680, end: 25088}
	batch.rows[0].key.bytes *= 2; batch.rows[0].key.sector = 4096
	assert bundle_pool_resize_batch(mut set, &batch, mut result) && result.rows[0].disk == 1
	assert bundle_forget_disk(mut set, 0); compacted := set
	assert bundle_pool_resize_batch(mut set, &batch, mut result) && set == compacted && result.rows[0].disk == 0
}

fn test_full_259_argument_resize_cli_preserves_full_v2_sets_and_durable_equal_bound_retries() {
	work := os.join_path(os.temp_dir(), 'vinix-resize-full-${os.getpid()}'); os.mkdir(work)!; defer { os.rmdir_all(work) or {} }; path := work + '/saved.vset'; mut set := PlanSet{}
	for disk in 0 .. 64 {
		mut plan := Plan{key: resize_key(disk + 1, 1), count: 1}; plan.key.bytes = u64(-1) & ~u64(4095)
		plan.rows[0] = Request{slot: u32(disk), offset: plan.key.bytes - 16384, length: 4096, flags: u64(disk & 1)}; assert append_plan(mut set, &plan)
	}
	for disk in 0 .. 64 { end := set.plans[disk].key.bytes; region := PoolRegion{pool: u32(disk), disk: u32(disk), window: SpaceWindow{start: end - 32768, end: end - 8192, alignment: 4096}}; assert bundle_pool_add(mut set, &region) }
	assert publish_bundle(path.str, &set); original := os.read_bytes(path)!; assert original.len == 8768
	mut expected := set; mut values := []string{cap: 256}
	for ordinal in 0 .. 64 {
		disk := 63 - ordinal; row := set.windows[disk]; end := set.plans[disk].key.bytes
		expected.windows[disk] = PoolRegion{pool: row.pool, disk: row.disk, window: SpaceWindow{start: end - 24576, end: end, alignment: 4096}}
		mut identity := [41]char{}; disk_identity(&set.plans[disk].key, &identity[0]); values << unsafe { cstring_to_vstring(&identity[0]) }; values << row.pool.str(); values << (end - 24576).str(); values << end.str()
	}
	unsafe {
		mut args := [260]&char{}; args[0] = &char(c'vinix-volume'); args[2] = path.str
		for i in 0 .. values.len { args[3 + i] = values[i].str }
		args[1] = &char(c'pool-preview-resize-batch'); assert run(259, &args[0]) == 0 && os.read_bytes(path)! == original
		args[1] = &char(c'pool-resize-batch'); assert run(259, &args[0]) == 0
		current := os.read_bytes(path)!; mut decoded := PlanSet{}; assert current.len == 8768 && decode_bundle(current.data, current.len, mut decoded) && decoded == expected
		assert run(259, &args[0]) == 0 && os.read_bytes(path)! == current
		args[258] = &char(c'1'); assert run(259, &args[0]) == 2 && os.read_bytes(path)! == current
	}
}

fn test_resize_sources_and_every_later_cli_token_fail_without_publication_prefixes() {
	work := os.join_path(os.temp_dir(), 'vinix-resize-cli-${os.getpid()}'); os.mkdir(work)!; defer { os.rmdir_all(work) or {} }; path := work + '/saved.vset'
	mut set := PlanSet{}; resize_fixture(mut set, 0, 1); assert publish_bundle(path.str, &set); original := os.read_bytes(path)!; os.symlink(path, work + '/alias')!
	mut batch := PoolResizeBatch{count: 1}; batch.rows[0] = PoolResizeRequest{key: set.plans[1].key, pool: 3, start: 8192, end: 24576}
	for preview in [false, true] { for bad in [work + '/missing', work, work + '/alias'] { assert resize_batch_pool_plan(bad.str, &batch, preview) == 1 } }
	unsafe {
		mut args := [&char(c'vinix-volume'), &char(c'pool-resize-batch'), path.str, &char(c'mbr:00000001'), &char(c'4'), &char(c'24576'), &char(c'49152'), &char(c'mbr:00000001'), &char(c'3'), &char(c'8192'), &char(c'24576'), &char(nil)]!
		for command in [c'pool-resize-batch', c'pool-preview-resize-batch'] {
			assert publish_bundle(path.str, &set)
			args[1] = &char(command); for count in [2, 3, 6, 8, 10, 260, 400] { assert run(count, &args[0]) == 2 }
			for at in [7, 8, 9, 10] { previous := args[at]; args[at] = &char(c'bad'); assert run(11, &args[0]) == 2 && os.read_bytes(path)! == original; args[at] = previous }
			args[8] = &char(c'64'); assert run(11, &args[0]) == 2; args[8] = &char(c'3')
			for invalid in [c'0', c'8192', c'18446744073709551616'] { args[10] = &char(invalid); assert run(11, &args[0]) == 2 }; args[10] = &char(c'24576')
			assert run(11, &args[0]) == 0
		}
	}
	assert os.ls(work)!.len == 2
	os.write_file(path, 'bad bundle')!; assert resize_batch_pool_plan(path.str, &batch, false) == 1 && os.read_file(path)! == 'bad bundle'
}
