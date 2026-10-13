// SPDX-License-Identifier: GPL-2.0-or-later
module volumecli

fn data_reference_fixture(mut manifest DataManifest, sector u64, kind u32, flags u64) {
	for disk in 0 .. 2 {
		mut plan := Plan{count: 1, key: DiskKey{bytes: u64(-1) & ~(sector - 1), sector: sector, kind: kind}}
		plan.key.id[0] = u8(disk + 1); if kind == 2 { plan.key.id[15] = 0x83 }
		plan.rows[0] = Request{slot: if disk == 0 { u32(0) } else { u32(63) }, offset: 8192, length: 73728, flags: flags}
		assert append_plan(mut manifest.set, unsafe { &plan })
		manifest.digests.disks[disk] = u32(disk); manifest.digests.slots[disk] = plan.rows[0].slot
		manifest.digests.values[disk] = [32]u8{init: u8(index * 7 + disk * 11)}
	}
	manifest.digests.count = 2
}

fn test_data_reference_all_digest_bytes_complete_metadata_and_transactional_findings() {
	for sector in [u64(512), u64(4096)] { for kind in [u32(1), u32(2)] { for flags in [u64(0), u64(1)] {
		mut first := DataManifest{}; data_reference_fixture(mut first, sector, kind, flags)
		for mask in 0 .. 4 { for byte in 0 .. 32 {
			mut second := first; for disk in 0 .. 2 { if mask & (1 << disk) != 0 { second.digests.values[disk][byte] ^= 1 } }
			mut result := DataScrub{changed: 9, bits: 17}
			assert compare_data_references(unsafe { &first }, unsafe { &second }, mut result)
			assert result == DataScrub{changed: int(mask & 1 != 0) + int(mask & 2 != 0), bits: u64(mask)}
			assert compare_data_references(unsafe { &second }, unsafe { &first }, mut result) && result.bits == u64(mask)
		} }
		for fault in 0 .. 14 {
			mut second := first
			match fault {
				0 { second.set.plans[1].key.id[0] = 4 }
				1 { second.set.plans[1].key.bytes -= sector }
				2 { second.set.plans[1].rows[0].offset += sector }
				3 { second.set.plans[1].rows[0].length += sector }
				4 { second.set.plans[1].rows[0].flags ^= 1 }
				5 { second.set.regions = 1; second.set.windows[0] = PoolRegion{pool: 3, disk: 1, window: SpaceWindow{start: 8192, end: 131072, alignment: sector}} }
				6 { second.digests.count = 1 }
				7 { second.digests.disks[1] = 0 }
				8 { second.digests.slots[1] = 0 }
				9 { second.set.plans[1].key = second.set.plans[0].key }
				10 { second.set.count = 65 }
				11 { second.set.plans[1].rows[0].offset++ }
				12 { second.set.plans[1].rows[0].length = u64(0x8000000000000000) }
				else { second.set.plans[1].rows[0].version = 2 }
			}
			mut result := DataScrub{changed: 9, bits: 17}
			assert !compare_data_references(unsafe { &first }, unsafe { &second }, mut result) && result == DataScrub{changed: 9, bits: 17}
			assert !compare_data_references(unsafe { &second }, unsafe { &first }, mut result) && result == DataScrub{changed: 9, bits: 17}
		}
	} } }
}

fn test_data_reference_pool_order_maximum_report_and_empty_mapping_sets() {
	mut first := DataManifest{}
	for disk in 0 .. 64 {
		mut plan := Plan{count: 1, key: DiskKey{bytes: u64(-1) & ~u64(4095), sector: 4096, kind: 2}}
		plan.key.id[0] = u8(disk + 1); plan.key.id[15] = 0x83
		plan.rows[0] = Request{slot: u32(disk), offset: 0x7fffffffffff0000, length: 4096, flags: u64(disk & 1)}
		assert append_plan(mut first.set, unsafe { &plan })
		first.set.windows[disk] = PoolRegion{pool: 3, disk: u32(disk), window: SpaceWindow{start: 0x7fffffffffff0000, end: 0x7fffffffffff8000, alignment: 4096}}
		first.digests.disks[disk] = u32(disk); first.digests.slots[disk] = u32(disk); first.digests.values[disk] = [32]u8{init: u8(index + disk)}
	}
	first.set.regions = 64; first.digests.count = 64; assert data_manifest_valid(unsafe { &first })
	mut second := first; for disk in 0 .. 64 { second.digests.values[disk][31] ^= 1 }
	mut text := [32768]char{}; n := encode_data_reference_comparison(unsafe { &first }, unsafe { &second }, &text[0]); assert n > 20000 && n < 32768
	assert unsafe { C.strstr(&text[0], c'stable=0 changed=64') != nil && C.strstr(&text[0], c'disk=63 slot=63') != nil }
	second = first; swap := second.set.windows[0]; second.set.windows[0] = second.set.windows[63]; second.set.windows[63] = swap
	mut summary := DataScrub{changed: 3, bits: 11}; assert !compare_data_references(unsafe { &first }, unsafe { &second }, mut summary) && summary.bits == 11
	second = first; window := second.set.windows[63].window
	second.set.windows[63].window = SpaceWindow{start: window.start, end: window.end + 4096, alignment: window.alignment}
	assert !compare_data_references(unsafe { &first }, unsafe { &second }, mut summary)
	first.set.count = 1; first.set.plans[0].count = 0; first.set.regions = 0; first.set.slots = 0; first.digests.count = 0
	assert compare_data_references(unsafe { &first }, unsafe { &first }, mut summary) && summary == DataScrub{}
	assert encode_data_reference_comparison(unsafe { &first }, unsafe { &first }, &text[0]) > 0
}

fn test_data_reference_cli_exact_arity_and_nonempty_paths() {
	unsafe {
		mut args := [&char(c'vinix-volume'), &char(c'compare-data-references'), &char(c'/unused'), &char(c'/unused'), &char(nil)]!
		for count in [2, 3, 5] { assert run(count, &args[0]) == 2 }
		for at in [2, 3] { args[at] = &char(c''); assert run(4, &args[0]) == 2; args[at] = &char(c'/unused') }
	}
}
