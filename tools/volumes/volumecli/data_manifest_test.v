// SPDX-License-Identifier: GPL-2.0-or-later
module volumecli

import os

import crypto.sha256

fn manifest_fixture(mut manifest DataManifest) {
	for disk in 0 .. 2 {
		sector := if disk == 0 { u64(512) } else { u64(4096) }
		mut plan := Plan{count: 2, key: DiskKey{bytes: sector * 64, sector: sector, kind: u32(disk + 1)}}
		plan.key.id[0] = u8(disk + 1); if disk == 1 { plan.key.id[15] = 0x83 }
		for at in 0 .. 2 { plan.rows[at] = Request{slot: u32(disk * 8 + at * 3 + 2), offset: sector * u64(4 + at * 12), length: sector * u64(3 - at), flags: u64(at)} }
		assert append_plan(mut manifest.set, &plan)
		region := PoolRegion{pool: u32(7 + disk), disk: u32(disk), window: SpaceWindow{start: sector, end: sector * 32, alignment: sector}}
		assert bundle_pool_add(mut manifest.set, &region)
		for at in 0 .. 2 {
			i := manifest.digests.count; manifest.digests.disks[i] = u32(disk); manifest.digests.slots[i] = plan.rows[at].slot
			for byte in 0 .. 32 { manifest.digests.values[i][byte] = u8(i * 37 + byte * 13) }; manifest.digests.count++
		}
	}
}

fn test_streaming_sha256_matches_independent_standard_library_in_8192_boundary_chunk_cases() {
	for length in 0 .. 1024 {
		data := []u8{len: length, init: u8(index * 31 + (index >> 4))}; expected := sha256.sum(data)
		for step in [1, 55, 56, 63, 64, 65, 511, 65536] {
			mut context := DataSha256{}; data_sha_init(mut context); mut at := 0
			for at < length { part := if length - at < step { length - at } else { step }; assert data_sha_update(mut context, unsafe { &data[at] }, usize(part)); at += part }
			assert data_sha_update(mut context, unsafe { nil }, 0)
			mut output := [32]u8{}; before := context
			assert data_sha_finish(&context, &output) && output[..] == expected && context == before
			assert data_sha_finish(&context, &output) && output[..] == expected && context == before
		}
	}
	million := []u8{len: 1000000, init: `a`}; mut context := DataSha256{}; data_sha_init(mut context)
	assert data_sha_update(mut context, million.data, usize(million.len)); mut output := [32]u8{}
	assert data_sha_finish(&context, &output) && output[..] == sha256.sum(million)
}

fn test_sha256_invalid_counts_nil_data_and_length_overflow_preserve_caller_state_and_output() {
	mut context := DataSha256{}; data_sha_init(mut context); initial := context
	assert !data_sha_update(mut context, unsafe { nil }, 1) && context == initial
	context.bytes = data_sha_max_bytes; context.used = 63; before := context; mut input := [64]u8{}
	assert !data_sha_update(mut context, &input[0], 1) && context == before
	for bad in 0 .. 4 {
		context = initial
		if bad == 0 { context.used = -1 } else if bad == 1 { context.used = 64 } else if bad == 2 { context.bytes = data_sha_max_bytes + 1 } else { context.used = 1 }
		old := context; mut output := [32]u8{init: 0x91}; old_output := output
		assert !data_sha_update(mut context, &input[0], 1) && context == old
		assert !data_sha_finish(&context, &output) && output == old_output
	}
}

fn test_manifest_exact_mixed_sector_roundtrip_and_all_4992_single_bit_corruptions_rollback() {
	mut original := DataManifest{}; manifest_fixture(mut original); mut bytes := [11392]u8{}
	size := encode_data_manifest(&original, &bytes[0]); assert size == 624
	assert get_le(&bytes[0], 0, 8) == 0x31484458494e4956 && get_le(&bytes[0], 20, 4) == 400 && get_le(&bytes[0], 24, 4) == 4
	mut decoded := DataManifest{}; assert decode_data_manifest(&bytes[0], size, mut decoded) && decoded == original
	mut baseline := DataManifest{}; baseline.digests.count = 17; baseline.digests.values[63][31] = 91; baseline.set.plans[63].key.id[0] = 42
	for at in 0 .. size { for bit in 0 .. 8 {
		mut damaged := bytes; damaged[at] ^= u8(1 << bit); mut output := baseline
		assert !decode_data_manifest(&damaged[0], size, mut output) && output == baseline
	} }
	for length in [0, 1, 63, size - 1, size + 1, 11393] { mut output := baseline; assert !decode_data_manifest(&bytes[0], length, mut output) && output == baseline }
}

fn test_manifest_checksummed_invalid_headers_and_later_records_preserve_every_output_field() {
	mut manifest := DataManifest{}; manifest_fixture(mut manifest); mut original := [11392]u8{}; size := encode_data_manifest(&manifest, &original[0])
	mut baseline := DataManifest{}; baseline.digests.count = 17; baseline.digests.values[63][31] = 91
	for bad in 0 .. 12 {
		mut bytes := original
		match bad {
			0 { put_le(&bytes[0], 0, 8, 0) }
			1 { put_le(&bytes[0], 8, 4, 2) }
			2 { put_le(&bytes[0], 12, 4, 63) }
			3 { put_le(&bytes[0], 16, 4, u64(size + 1)) }
			4 { put_le(&bytes[0], 20, 4, 8769) }
			5 { put_le(&bytes[0], 24, 4, 65) }
			6 { bytes[63] = 1 }
			7 { put_le(&bytes[0], 64 + 400 + 120, 4, 64) }
			8 { put_le(&bytes[0], 64 + 400 + 124, 4, 63) }
			9 { put_le(&bytes[0], 64 + 400 + 124, 4, 10) }
			10 { put_le(&bytes[0], 64 + 400, 4, 1) }
			else { bytes[64 + 24] ^= 1 }
		}
		put_le(&bytes[0], 28, 4, crc32(&bytes[0], size, 28)); mut output := baseline
		assert !decode_data_manifest(&bytes[0], size, mut output) && output == baseline
	}
}

fn test_manifest_maximum_64_disks_rows_regions_near_u64_and_11392_byte_format() {
	mut manifest := DataManifest{}
	for disk in 0 .. 64 {
		sector := if disk & 1 == 0 { u64(512) } else { u64(4096) }; end := u64(0x7fffffffffffffff) & ~(sector - 1)
		mut plan := Plan{count: 1, key: DiskKey{bytes: u64(-1) & ~(sector - 1), sector: sector, kind: if disk & 1 == 0 { u32(1) } else { u32(2) }}}
		plan.key.id[0] = u8(disk + 1); if plan.key.kind == 2 { plan.key.id[15] = 0x83 }
		plan.rows[0] = Request{slot: u32(63 - disk), offset: end - sector * 2, length: sector * 2, flags: u64(disk & 1)}
		assert append_plan(mut manifest.set, &plan)
		region := PoolRegion{pool: u32(disk), disk: u32(disk), window: SpaceWindow{start: plan.rows[0].offset, end: end, alignment: sector}}
		assert bundle_pool_add(mut manifest.set, &region)
		manifest.digests.disks[disk] = u32(disk); manifest.digests.slots[disk] = u32(63 - disk); manifest.digests.values[disk][0] = u8(disk + 1); manifest.digests.count++
	}
	mut bytes := [11392]u8{}; assert encode_data_manifest(&manifest, &bytes[0]) == 11392
	mut decoded := DataManifest{}; assert decode_data_manifest(&bytes[0], 11392, mut decoded) && decoded == manifest
	work := os.join_path(os.temp_dir(), 'vinix-data-max-${os.getpid()}'); os.mkdir(work)!; defer { os.rmdir_all(work) or {} }
	path := work + '/data.vhash'; os.write_file_array(path, bytes[..11392])!
	unsafe {
		mut args := [133]&char{}; mut indices := [64][4]char{}
		args[0] = &char(c'vinix-volume'); args[1] = &char(c'verify-data'); args[2] = path.str
		for disk in 0 .. 64 { C.snprintf(&indices[disk][0], 4, c'%u', u32(disk)); args[3 + disk * 2] = &indices[disk][0]; args[4 + disk * 2] = &char(c'/missing-checksum-device') }
		assert run(131, &args[0]) == 1 && os.read_bytes(path)! == bytes[..11392]
		args[1] = &char(c'show-data'); assert run(3, &args[0]) == 0 && os.read_bytes(path)! == bytes[..11392]
	}
	mut wrong := manifest; wrong.digests.count = 63; assert encode_data_manifest(&wrong, &bytes[0]) == 0
	wrong = manifest; wrong.digests.disks[63] = 0; assert encode_data_manifest(&wrong, &bytes[0]) == 0
	wrong = manifest; wrong.set.plans[0].rows[0].offset = u64(0x8000000000000000); assert !data_ranges_valid(&wrong.set)
	wrong = manifest; wrong.set.plans[0].rows[0].offset = 0; wrong.set.plans[0].rows[0].length = data_sha_max_bytes + 1; assert !data_ranges_valid(&wrong.set)
}

fn test_data_complete_cli_argument_and_token_bounds() {
	unsafe {
		mut args := [&char(c'vinix-volume'), &char(c'hash-bundle'), &char(c'/unused'), &char(c'/unused-manifest'), &char(c'0'), &char(c'/unused-device'), &char(c'1'), &char(c'/unused-device-1'), &char(nil)]!
		for count in [2, 3, 4, 5, 7, 133, 134] { assert run(count, &args[0]) == 2 }
		for at in [4, 6] { old := args[at]; for bad in [c'', c'-1', c'1x', c'64', c'18446744073709551616'] { args[at] = &char(bad); assert run(8, &args[0]) == 2 }; args[at] = old }
		args[7] = &char(c''); assert run(8, &args[0]) == 2
		args[1] = &char(c'verify-data'); args[3] = &char(c'0'); args[4] = &char(c'/unused-device'); args[5] = &char(c'64'); args[6] = &char(c'/unused-device-1')
		for count in [2, 3, 4, 6, 132, 133] { assert run(count, &args[0]) == 2 }; assert run(7, &args[0]) == 2
		args[1] = &char(c'show-data'); for count in [2, 4] { assert run(count, &args[0]) == 2 }
	}
}
