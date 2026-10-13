// SPDX-License-Identifier: GPL-2.0-or-later
module volumecli

import crypto.sha256
import encoding.hex

fn scrub_reference_sha(bytes []u8, mut report DataScrubReport) {
	digest := sha256.sum(bytes); for i in 0 .. 32 { report.reference[i] = digest[i] }
}

fn scrub_reference_fixture(sector u64, kind u32, flags u64, mut manifest DataManifest, mut report DataScrubReport) {
	manifest = DataManifest{}; report = DataScrubReport{disks: 2, count: 2}
	for disk in 0 .. 2 {
		mut plan := Plan{count: 1, key: DiskKey{bytes: u64(-1) & ~(sector - 1), sector: sector, kind: kind}}; plan.key.id[0] = u8(disk + 1); if kind == 2 { plan.key.id[15] = 0x83 }
		plan.rows[0] = Request{slot: if disk == 0 { u32(0) } else { u32(63) }, offset: 8192, length: 73728, flags: if disk == 0 { flags } else { 1 - flags }}
		assert append_plan(mut manifest.set, &plan); manifest.digests.disks[disk] = u32(disk); manifest.digests.slots[disk] = plan.rows[0].slot
		for byte in 0 .. 32 { manifest.digests.values[disk][byte] = u8(byte * 7 + disk * 11) }
		report.indices[disk] = u32(disk); report.rows[disk] = plan.rows[0]; report.expected[disk] = manifest.digests.values[disk]; report.actual[disk] = report.expected[disk]
		region := PoolRegion{pool: 7, disk: u32(disk), window: SpaceWindow{start: 8192, end: 131072, alignment: sector}}; assert bundle_pool_add(mut manifest.set, &region)
	}
	manifest.digests.count = 2; mut bytes := [11392]u8{}; size := encode_data_manifest(&manifest, &bytes[0]); assert size > 0; scrub_reference_sha(bytes[..size], mut report)
}

fn scrub_reference_input(report &DataScrubReport) string {
	mut changed := 0; for i in 0 .. report.count { if report.expected[i] != report.actual[i] { changed++ } }
	mut text := 'format=VINIXSR1 operation=scrubbed-data disks=${report.disks} mappings=${report.count} matched=${report.count - changed} changed=${changed} algorithm=sha256 reference_sha256=' + hex.encode(report.reference[..]) + '\n'
	for i in 0 .. report.count { row := report.rows[i]; text += 'disk=${report.indices[i]} slot=${row.slot} offset=${row.offset} bytes=${row.length} readonly=${row.flags} result=${if report.expected[i] == report.actual[i] { 'match' } else { 'changed' }} expected_sha256=' + hex.encode(report.expected[i][..]) + ' actual_sha256=' + hex.encode(report.actual[i][..]) + '\n' }
	return text
}

fn scrub_reference_expected(manifest &DataManifest, report &DataScrubReport) string {
	mut changed := 0; for i in 0 .. report.count { if report.expected[i] != report.actual[i] { changed++ } }
	mut bytes := [11392]u8{}; size := encode_data_manifest(manifest, &bytes[0]); fingerprint := hex.encode(sha256.sum(bytes[..size]))
	mut text := 'format=VINIXSR1 operation=verified-data-scrub-reference disks=${report.disks} mappings=${report.count} matched=${report.count - changed} changed=${changed} algorithm=sha256 reference_sha256=${fingerprint} report_sha256=' + sha256.hexhash(scrub_reference_input(report)) + '\n'
	mut record := 0
	for disk in 0 .. manifest.set.count {
		key := manifest.set.plans[disk].key; identity := if key.kind == 1 { 'mbr:0000000${disk + 1}' } else { 'gpt:0000000${disk + 1}-0000-0000-0000-000000000083' }
		text += 'disk=${disk} disk_bytes=${key.bytes} sector=${key.sector} identity=${identity}\n'
		for at in 0 .. int(manifest.set.plans[disk].count) { row := manifest.set.plans[disk].rows[at]; text += 'disk=${disk} slot=${row.slot} offset=${row.offset} bytes=${row.length} readonly=${row.flags} result=${if report.expected[record] == report.actual[record] { 'match' } else { 'changed' }} expected_sha256=' + hex.encode(report.expected[record][..]) + ' actual_sha256=' + hex.encode(report.actual[record][..]) + '\n'; record++ }
	}
	return text
}

fn test_scrub_reference_eight_geometry_identity_mode_profiles_every_observed_byte_and_change_mask() {
	for sector in [u64(512), u64(4096)] { for kind in [u32(1), u32(2)] { for flags in [u64(0), u64(1)] {
		mut manifest := DataManifest{}; mut report := DataScrubReport{}; scrub_reference_fixture(sector, kind, flags, mut manifest, mut report)
		for mask in 0 .. 4 { for byte in 0 .. 32 {
			mut observed := report; for disk in 0 .. 2 { if mask & (1 << disk) != 0 { observed.actual[disk][byte] ^= 1 } }
			assert data_scrub_reference_matches(&manifest, &observed)
			mut output := [32768]char{init: char(91)}; size := encode_data_scrub_reference(&manifest, &observed, &output[0]); expected := scrub_reference_expected(&manifest, &observed)
			assert size == expected.len && unsafe { tos(&u8(&output[0]), size) } == expected && output[size] == 0 && output[size + 1] == char(91)
			text := scrub_reference_input(&observed); mut decoded := DataScrubReport{}; assert decode_data_scrub_report(text.str, text.len, mut decoded) && decoded == observed && data_scrub_reference_matches(&manifest, &decoded)
		} }
	} } }
}

fn test_scrub_reference_fingerprint_binds_omitted_identity_capacity_native_sector_and_pool_order_windows() {
	mut manifest := DataManifest{}; mut report := DataScrubReport{}; scrub_reference_fixture(512, 2, 0, mut manifest, mut report); report.actual[0][0] ^= 1
	for fault in 0 .. 11 {
		mut wrong := manifest
		match fault {
			0 { wrong.set.plans[1].key.id[0] = 4 }
			1 { wrong.set.plans[1].key.bytes -= 512 }
			2 { wrong.set.plans[1].key.sector = 4096; wrong.set.plans[1].key.bytes &= ~u64(4095); wrong.set.windows[1].window = SpaceWindow{start: 8192, end: 131072, alignment: 4096} }
			3 { wrong.set.windows[1].window = SpaceWindow{start: 8192, end: 135168, alignment: 512} }
			4 { region := wrong.set.windows[0]; wrong.set.windows[0] = wrong.set.windows[1]; wrong.set.windows[1] = region }
			5 { region := wrong.set.windows[1]; wrong.set.windows[1] = PoolRegion{pool: 8, disk: region.disk, window: region.window} }
			6 { wrong.digests.values[1][31] ^= 1 }
			7 { wrong.set.plans[1].rows[0].offset += 512 }
			8 { wrong.set.plans[1].rows[0].length -= 512 }
			9 { wrong.set.plans[1].rows[0].flags ^= 1 }
			else { wrong.set.regions = 0 }
		}
		assert data_manifest_valid(&wrong), 'valid alternate reference case ${fault}'
		assert !data_scrub_reference_matches(&wrong, &report)
		mut output := [32768]char{init: char(91)}; saved := output; assert encode_data_scrub_reference(&wrong, &report, &output[0]) == 0 && output == saved
	}
	// Even a report claiming the correct fingerprint must match each saved row.
	for fault in 0 .. 8 {
		mut wrong := report
		match fault { 0 { wrong.indices[1] = 0; wrong.rows[1].offset = 131072 } 1 { wrong.rows[1].slot = 62 } 2 { wrong.rows[1].offset += 512 } 3 { wrong.rows[1].length -= 512 } 4 { wrong.rows[1].flags ^= 1 } 5 { wrong.expected[1][31] ^= 1 } 6 { wrong.count = 1 } else { wrong.disks = 3 } }
		assert data_scrub_records_valid(&wrong) && !data_scrub_reference_matches(&manifest, &wrong)
	}
	for row in 0 .. 2 { for byte in 0 .. 32 { mut wrong := report; wrong.expected[row][byte] ^= 1; assert !data_scrub_reference_matches(&manifest, &wrong) } }
	mut invalid := manifest; invalid.digests.slots[1] = 3; assert !data_scrub_reference_matches(&invalid, &report)
	mut bad := report; bad.rows[1].version = 2; assert !data_scrub_reference_matches(&manifest, &bad)
}

fn test_scrub_reference_maximum_report_and_empty_saved_disks_cli() {
	mut manifest := DataManifest{}; mut report := DataScrubReport{disks: 64, count: 64}
	for disk in 0 .. 64 {
		sector := if disk & 1 == 0 { u64(512) } else { u64(4096) }; end := u64(0x7fffffffffffffff) & ~(sector - 1)
		mut plan := Plan{count: 1, key: DiskKey{bytes: end, sector: sector, kind: u32(disk % 2 + 1)}}; plan.key.id[0] = u8(disk + 1); if plan.key.kind == 2 { plan.key.id[15] = 0x83 }
		plan.rows[0] = Request{slot: u32(63 - disk), offset: end - sector * 2, length: sector * 2, flags: u64(disk & 1)}; assert append_plan(mut manifest.set, &plan)
		manifest.digests.disks[disk] = u32(disk); manifest.digests.slots[disk] = u32(63 - disk); manifest.digests.count++
		report.indices[disk] = u32(disk); report.rows[disk] = plan.rows[0]; report.actual[disk][31] = 1
		region := PoolRegion{pool: u32(disk), disk: u32(disk), window: SpaceWindow{start: plan.rows[0].offset, end: end, alignment: sector}}; assert bundle_pool_add(mut manifest.set, &region)
	}
	mut bytes := [11392]u8{}; size := encode_data_manifest(&manifest, &bytes[0]); assert size == 11392; scrub_reference_sha(bytes[..size], mut report)
	mut output := [32768]char{}; n := encode_data_scrub_reference(&manifest, &report, &output[0]); assert n > 17000 && n < 32768
	assert unsafe { C.strstr(&output[0], c'matched=0 changed=64') != nil && C.strstr(&output[0], c'disk=63 slot=0') != nil }
	text := scrub_reference_input(&report); mut decoded := DataScrubReport{}; assert decode_data_scrub_report(text.str, text.len, mut decoded) && data_scrub_reference_matches(&manifest, &decoded)
	for disk in 0 .. 64 { manifest.set.plans[disk].count = 0 }; manifest.set.regions = 0; manifest.set.slots = 0; manifest.digests.count = 0; report = DataScrubReport{disks: 64}
	zero_size := encode_data_manifest(&manifest, &bytes[0]); assert zero_size > 0; scrub_reference_sha(bytes[..zero_size], mut report); assert encode_data_scrub_reference(&manifest, &report, &output[0]) > 0 && data_scrub_reference_matches(&manifest, &report)
	unsafe { mut args := [&char(c'vinix-volume'), &char(c'verify-data-scrub-reference'), &char(c'/missing-manifest'), &char(c'/missing-report'), &char(c'extra'), &char(nil)]!; for count in [2, 3, 5, 6] { assert run(count, &args[0]) == 2 }; for i in [2, 3] { saved := args[i]; args[i] = &char(c''); assert run(4, &args[0]) == 2; args[i] = saved }; assert run(4, &args[0]) == 1 }
}
