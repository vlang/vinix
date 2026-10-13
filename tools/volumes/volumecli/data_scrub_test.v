// SPDX-License-Identifier: GPL-2.0-or-later
module volumecli

import os
import encoding.hex
import crypto.sha256

fn scrub_fixture(mut manifest DataManifest, count int) {
	mut plan := Plan{count: u32(count), key: DiskKey{bytes: 1048576, sector: 512, kind: 1}}
	plan.key.id[0] = 0x37
	for i in 0 .. count {
		plan.rows[i] = Request{slot: u32(63 - i), offset: u64(4096 + i * 1024), length: 512, flags: u64(i & 1)}
		manifest.digests.disks[i] = 0; manifest.digests.slots[i] = u32(63 - i)
		for byte in 0 .. 32 { manifest.digests.values[i][byte] = u8(i * 37 + byte * 13) }
	}
	assert append_plan(mut manifest.set, &plan); manifest.digests.count = count
}

fn test_complete_scrub_comparison_matches_4096_independent_change_masks() {
	mut manifest := DataManifest{}; scrub_fixture(mut manifest, 12)
	for mask in 0 .. 4096 {
		mut observed := manifest.digests; mut expected := 0
		for i in 0 .. 12 { if mask & (1 << i) != 0 { observed.values[i][i] ^= 0x81; expected++ } }
		mut summary := DataScrub{changed: 71, bits: u64(-1)}
		assert compare_scrub_digests(&manifest, &observed, mut summary) && summary.changed == expected && summary.bits == u64(mask)
	}
	mut observed := manifest.digests; observed.values[0][31] ^= 1; observed.values[11][0] ^= 1
	old := DataScrub{changed: 71, bits: 0x91}; mut summary := old
	observed.slots[11] = 17; assert !compare_scrub_digests(&manifest, &observed, mut summary) && summary == old
	observed = manifest.digests; observed.disks[11] = 1; assert !compare_scrub_digests(&manifest, &observed, mut summary) && summary == old
	for count in [-1, 11, 13, 65] { observed = manifest.digests; observed.count = count; assert !compare_scrub_digests(&manifest, &observed, mut summary) && summary == old }
	mut invalid := manifest; invalid.set.plans[0].rows[11].slot = invalid.set.plans[0].rows[0].slot
	assert !compare_scrub_digests(&invalid, &manifest.digests, mut summary) && summary == old
}

fn test_scrub_report_exact_complete_canonical_text_with_both_digests_and_zero_rows() {
	mut manifest := DataManifest{}; scrub_fixture(mut manifest, 3); mut observed := manifest.digests
	observed.values[0][31] ^= 1; observed.values[2][0] ^= 1
	mut bytes := [11392]u8{}; size := encode_data_manifest(&manifest, &bytes[0]); fingerprint := hex.encode(sha256.sum(bytes[..size]))
	mut expected := 'format=VINIXSR1 operation=scrubbed-data disks=1 mappings=3 matched=1 changed=2 algorithm=sha256 reference_sha256=${fingerprint}\n'
	for i in 0 .. 3 {
		row := manifest.set.plans[0].rows[i]; result := if i == 1 { 'match' } else { 'changed' }
		expected += 'disk=0 slot=${row.slot} offset=${row.offset} bytes=${row.length} readonly=${row.flags} result=${result} expected_sha256=' + hex.encode(manifest.digests.values[i][..]) + ' actual_sha256=' + hex.encode(observed.values[i][..]) + '\n'
	}
	mut text := [32768]char{init: char(91)}; length := encode_scrub_report(&manifest, &observed, &text[0])
	assert length == expected.len && unsafe { tos(&u8(&text[0]), length) } == expected && text[length] == 0 && text[length + 1] == char(91)
	mut wrong := observed; wrong.slots[2] = 15; old := text
	assert encode_scrub_report(&manifest, &wrong, &text[0]) == 0 && text == old
	manifest = DataManifest{}; scrub_fixture(mut manifest, 0); observed = manifest.digests
	zero_size := encode_data_manifest(&manifest, &bytes[0]); zero_fingerprint := hex.encode(sha256.sum(bytes[..zero_size]))
	length_zero := encode_scrub_report(&manifest, &observed, &text[0]); assert unsafe { tos(&u8(&text[0]), length_zero) } == 'format=VINIXSR1 operation=scrubbed-data disks=1 mappings=0 matched=0 changed=0 algorithm=sha256 reference_sha256=${zero_fingerprint}\n'
}

fn test_scrub_maximum_64_disks_rows_regions_and_full_width_offsets_report_bounds_cli_132_arguments() {
	mut manifest := DataManifest{}
	for disk in 0 .. 64 {
		sector := if disk & 1 == 0 { u64(512) } else { u64(4096) }; end := u64(0x7fffffffffffffff) & ~(sector - 1)
		mut plan := Plan{count: 1, key: DiskKey{bytes: end, sector: sector, kind: u32(disk % 2 + 1)}}
		plan.key.id[0] = u8(disk + 1); if plan.key.kind == 2 { plan.key.id[15] = 0x83 }
		plan.rows[0] = Request{slot: u32(63 - disk), offset: end - sector * 2, length: sector * 2, flags: u64(disk & 1)}
		assert append_plan(mut manifest.set, &plan)
		region := PoolRegion{pool: u32(disk), disk: u32(disk), window: SpaceWindow{start: plan.rows[0].offset, end: end, alignment: sector}}; assert bundle_pool_add(mut manifest.set, &region)
		manifest.digests.disks[disk] = u32(disk); manifest.digests.slots[disk] = u32(63 - disk); manifest.digests.count++
	}
	mut observed := manifest.digests; for i in 0 .. 64 { observed.values[i][31] = 1 }
	mut summary := DataScrub{}; assert compare_scrub_digests(&manifest, &observed, mut summary) && summary.changed == 64 && summary.bits == u64(-1)
	mut text := [32768]char{}; length := encode_scrub_report(&manifest, &observed, &text[0]); report := unsafe { tos(&u8(&text[0]), length) }
	assert length > 12000 && length < scrub_report_max && report.count(' result=changed ') == 64 && report.count(' expected_sha256=') == 64 && report.count(' actual_sha256=') == 64 && text[length] == 0
	assert report.starts_with('format=VINIXSR1 operation=scrubbed-data disks=64 mappings=64 matched=0 changed=64 algorithm=sha256 reference_sha256=')
	work := os.join_path(os.temp_dir(), 'vinix-scrub-max-${os.getpid()}'); os.mkdir(work)!; defer { os.rmdir_all(work) or {} }; path := work + '/data.vhash'; output := work + '/scrub.txt'
	mut bytes := [11392]u8{}; size := encode_data_manifest(&manifest, &bytes[0]); assert size == 11392; os.write_file_array(path, bytes[..size])!
	unsafe {
		mut args := [133]&char{}; mut indices := [64][4]char{}
		args[0] = &char(c'vinix-volume'); args[1] = &char(c'scrub-data'); args[2] = path.str; args[3] = output.str
		for disk in 0 .. 64 { C.snprintf(&indices[disk][0], 4, c'%u', u32(disk)); args[4 + disk * 2] = &indices[disk][0]; args[5 + disk * 2] = &char(c'/missing-scrub-device') }
		assert run(132, &args[0]) == 1 && !os.exists(output) && os.read_bytes(path)! == bytes[..size]
	}
}

fn test_scrub_complete_cli_token_count_and_remainder_rejection() {
	unsafe {
		mut args := [&char(c'vinix-volume'), &char(c'scrub-data'), &char(c'/unused-reference'), &char(c'/unused-report'), &char(c'0'), &char(c'/unused-device'), &char(c'1'), &char(c'/unused-later'), &char(nil)]!
		for count in [2, 3, 4, 5, 7, 133, 134] { assert run(count, &args[0]) == 2 }
		for at in [4, 6] { old := args[at]; for bad in [c'', c'-1', c'1x', c'64', c'18446744073709551616'] { args[at] = &char(bad); assert run(8, &args[0]) == 2 }; args[at] = old }
		args[7] = &char(c''); assert run(8, &args[0]) == 2
	}
}
