// SPDX-License-Identifier: GPL-2.0-or-later
module volumecli

import os

fn bundle_sample(mut set PlanSet) {
	mut first := Plan{
		count: 2
		key:   DiskKey{
			bytes:  16 * 1024 * 1024
			sector: 512
			kind:   1
		}
	}
	first.key.id[0] = 0x78
	first.rows[0] = Request{
		slot:   2
		offset: 1048576
		length: 4096
	}
	first.rows[1] = Request{
		slot:   5
		offset: 2097152
		length: 8192
		flags:  1
	}
	mut second := first
	second.count = 1
	second.key.id[0] = 0x79
	second.rows[0].slot = 9
	assert append_plan(mut set, &first) && append_plan(mut set, &second)
}

fn test_bundle_roundtrip_truncation_corruption_and_decode_rollback() {
	mut set := PlanSet{}
	bundle_sample(mut set)
	mut bytes := [6208]u8{}
	size := encode_bundle(&set, &bytes[0])
	assert size == 288 && bytes[..8].bytestr() == 'VINIXVS1'
	mut decoded := PlanSet{}
	assert decode_bundle(&bytes[0], size, mut decoded)
	assert decoded.count == 2 && decoded.slots == set.slots
	assert key_matches(&decoded.plans[1].key, &set.plans[1].key)
	assert decoded.plans[0].rows[1].flags == 1 && decoded.plans[1].rows[0].slot == 9
	decoded = PlanSet{}
	mut existing := set.plans[1]
	existing.key.id[0]++
	existing.rows[0].slot = 12
	assert append_plan(mut decoded, &existing)
	for shorter in 0 .. size {
		assert !decode_bundle(&bytes[0], shorter, mut decoded)
		assert decoded.count == 1 && decoded.slots == u64(1) << 12
	}
	assert !decode_bundle(&bytes[0], size + 1, mut decoded)
	for index in 0 .. size {
		for bit in 0 .. 8 {
			bytes[index] ^= u8(1 << bit)
			assert !decode_bundle(&bytes[0], size, mut decoded)
			assert decoded.count == 1 && decoded.slots == u64(1) << 12
			bytes[index] ^= u8(1 << bit)
		}
	}
	assert decode_bundle(&bytes[0], size, mut decoded) && decoded.count == 3
	assert decoded.plans[0].rows[0].slot == 12 && decoded.plans[2].rows[0].slot == 9
}

fn test_checksummed_invalid_bundle_headers_and_later_plans_fail_without_partial_append() {
	mut set := PlanSet{}
	bundle_sample(mut set)
	for field, value in {
		8:   u64(2)
		12:  0
		16:  289
		20:  65
		28:  1
		204: 65
	} {
		mut bytes := [6208]u8{}
		size := encode_bundle(&set, &bytes[0])
		put_le(&bytes[0], field, 4, value)
		put_le(&bytes[0], 24, 4, crc32(&bytes[0], size, 24))
		mut decoded := PlanSet{}
		assert !decode_bundle(&bytes[0], size, mut decoded)
		assert decoded.count == 0 && decoded.slots == 0
	}
	for kind in 0 .. 4 {
		mut bytes := [6208]u8{}
		size := encode_bundle(&set, &bytes[0])
		if kind == 0 { bytes[232] = 0x78 } // Duplicate disk key in the second plan.
		if kind == 1 { put_le(&bytes[0], 260, 4, 2) } // Global slot collision.
		if kind == 2 { put_le(&bytes[0], 272, 8, 0) } // Invalid later record.
		if kind == 3 { bytes[200] = 2 } // Unknown nested version.
		put_le(&bytes[0], 228, 4, crc32(&bytes[192], 96, 36))
		put_le(&bytes[0], 24, 4, crc32(&bytes[0], size, 24))
		mut decoded := PlanSet{}
		assert !decode_bundle(&bytes[0], size, mut decoded)
		assert decoded.count == 0 && decoded.slots == 0
	}
	// A valid bundle also cannot conflict with a legacy/directory boot plan.
	mut bytes := [6208]u8{}
	size := encode_bundle(&set, &bytes[0])
	mut decoded := PlanSet{}
	assert append_plan(mut decoded, &set.plans[1])
	assert !decode_bundle(&bytes[0], size, mut decoded)
	assert decoded.count == 1 && decoded.slots == u64(1) << 9
}

fn test_bundle_maximum_disk_and_mapping_bounds_and_output_canaries() {
	mut set := PlanSet{}
	mut bytes := [6210]u8{}
	bytes[6208] = 0xad
	bytes[6209] = 0xae
	assert encode_bundle(&set, &bytes[0]) == 0
	for i in 0 .. 64 {
		mut plan := Plan{
			count: 1
			key:   DiskKey{
				bytes:  4096
				sector: 512
				kind:   1
			}
		}
		plan.key.id[0] = u8(i + 1)
		plan.rows[0] = Request{
			slot:   u32(i)
			length: 512
		}
		assert append_plan(mut set, &plan)
	}
	assert encode_bundle(&set, &bytes[0]) == 6208
	assert bytes[6208] == 0xad && bytes[6209] == 0xae
	mut decoded := PlanSet{}
	assert decode_bundle(&bytes[0], 6208, mut decoded)
	assert decoded.count == 64 && decoded.slots == u64(-1)
	set.plans[63].rows[0].slot = 0
	assert encode_bundle(&set, &bytes[0]) == 0
	set.count = 65
	assert encode_bundle(&set, &bytes[0]) == 0
	// Disks without mappings remain valid participants.
	set = PlanSet{}
	mut empty := Plan{
		key: DiskKey{
			bytes:  4096
			sector: 512
			kind:   1
		}
	}
	empty.key.id[0] = 1
	assert append_plan(mut set, &empty)
	assert encode_bundle(&set, &bytes[0]) == 128
	decoded = PlanSet{}
	assert decode_bundle(&bytes[0], 128, mut decoded) && decoded.count == 1 && decoded.slots == 0
}

fn host_bundle(path string, mut set PlanSet, trusted bool) bool {
	fd := C.open(path.str, C.O_RDONLY | C.O_NOFOLLOW | C.O_NONBLOCK | C.O_CLOEXEC)
	if fd < 0 { return false }
	defer { C.close(fd) }
	return read_bundle(fd, mut set, trusted)
}

fn test_bundle_publication_replacement_failure_cleanup_type_and_trust() {
	work := os.join_path(os.temp_dir(), 'vinix-bundle-test-${os.getpid()}')
	os.mkdir(work)!
	defer { os.rmdir_all(work) or {} }
	path := work + '/saved.vset'
	mut set := PlanSet{}
	bundle_sample(mut set)
	assert publish_bundle(path.str, &set)
	original := os.read_bytes(path)!
	mut decoded := PlanSet{}
	assert host_bundle(path, mut decoded, false) && decoded.count == 2
	set.plans[1].rows[0].slot = 2
	assert !publish_bundle(path.str, &set) && os.read_bytes(path)! == original
	set.plans[1].rows[0].slot = 9
	assert !publish_bundle((work + '/missing/saved').str, &set)
	os.mkdir(work + '/directory')!
	assert !publish_bundle((work + '/directory').str, &set)
	assert os.ls(work)!.len == 2 && os.read_bytes(path)! == original
	os.symlink(path, work + '/link')!
	decoded = PlanSet{}
	assert !host_bundle(work + '/link', mut decoded, false)
	assert !host_bundle(work, mut decoded, false)
	os.chmod(path, 0o622)!
	assert !host_bundle(path, mut decoded, true)
	assert host_bundle(path, mut decoded, false)
	os.write_file(path, 'truncated')!
	decoded = PlanSet{}
	assert !host_bundle(path, mut decoded, false) && decoded.count == 0
	os.write_file(path, 'x'.repeat(6209))!
	assert !host_bundle(path, mut decoded, false)
	assert publish_bundle(path.str, &set) && os.read_bytes(path)! == original
	set.plans[1].rows[0].length = 8192
	assert publish_bundle(path.str, &set)
	assert os.read_bytes(path)! != original
	decoded = PlanSet{}
	assert host_bundle(path, mut decoded, false) && decoded.plans[1].rows[0].length == 8192
	// A destination matching the first temporary candidate must survive cleanup.
	collision := work + '/.vinix-volume-${os.getpid()}-0'
	assert publish_bundle(collision.str, &set)
	decoded = PlanSet{}
	assert host_bundle(collision, mut decoded, false) && decoded.count == 2
}
