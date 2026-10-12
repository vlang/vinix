// SPDX-License-Identifier: GPL-2.0-or-later
module volumecli

const data_manifest_header = 64
const data_manifest_max = 11392 // Header + maximum V2 bundle + 64 SHA-256 records.

struct DataDigests {
mut:
	count int
	disks [64]u32
	slots [64]u32
	values [64][32]u8
}

struct DataManifest {
mut:
	set PlanSet
	digests DataDigests
}

@[direct_array_access]
fn data_ranges_valid(set &PlanSet) bool {
	if !bundle_set_valid(set) { return false }
	mut rows := 0
	for disk in 0 .. set.count {
		for earlier in 0 .. disk {
			if enrollment_identity_matches(unsafe { &set.plans[disk].key }, unsafe { &set.plans[earlier].key }) { return false }
		}
		for at := u32(0); at < set.plans[disk].count; at++ {
			row := set.plans[disk].rows[at]
			if row.length > data_sha_max_bytes || row.offset > u64(0x7fffffffffffffff)
				|| row.length > u64(0x7fffffffffffffff) - row.offset { return false }
			rows++
		}
	}
	return rows <= 64
}

@[direct_array_access]
fn data_manifest_valid(manifest &DataManifest) bool {
	if !data_ranges_valid(unsafe { &manifest.set }) || manifest.digests.count < 0 || manifest.digests.count > 64 { return false }
	mut record := 0
	for disk in 0 .. manifest.set.count { for at := u32(0); at < manifest.set.plans[disk].count; at++ {
		if record >= manifest.digests.count || manifest.digests.disks[record] != u32(disk)
			|| manifest.digests.slots[record] != manifest.set.plans[disk].rows[at].slot { return false }
		record++
	} }
	return record == manifest.digests.count
}

@[direct_array_access]
fn encode_data_manifest(manifest &DataManifest, output &u8) int {
	if !data_manifest_valid(manifest) { return 0 }
	unsafe { for i in 0 .. data_manifest_header { output[i] = 0 } }
	bundle_size := encode_bundle(unsafe { &manifest.set }, unsafe { output + data_manifest_header })
	if bundle_size == 0 { return 0 }
	size := data_manifest_header + bundle_size + manifest.digests.count * 40
	put_le(output, 0, 8, 0x31484458494e4956) // VINIXDH1
	put_le(output, 8, 4, 1); put_le(output, 12, 4, data_manifest_header)
	put_le(output, 16, 4, u64(size)); put_le(output, 20, 4, u64(bundle_size)); put_le(output, 24, 4, u64(manifest.digests.count))
	for i in 0 .. manifest.digests.count {
		at := data_manifest_header + bundle_size + i * 40
		put_le(output, at, 4, manifest.digests.disks[i]); put_le(output, at + 4, 4, manifest.digests.slots[i])
		unsafe { for byte in 0 .. 32 { output[at + 8 + byte] = manifest.digests.values[i][byte] } }
	}
	put_le(output, 28, 4, crc32(output, size, 28)); return size
}

// Decode entirely privately: even a later bad record preserves the caller.
@[direct_array_access]
fn decode_data_manifest(data &u8, size int, mut manifest DataManifest) bool {
	if size < data_manifest_header || size > data_manifest_max || get_le(data, 0, 8) != 0x31484458494e4956
		|| get_le(data, 8, 4) != 1 || get_le(data, 12, 4) != data_manifest_header || get_le(data, 16, 4) != u64(size)
		|| get_le(data, 28, 4) != crc32(data, size, 28) { return false }
	bundle_size := get_le(data, 20, 4); records := get_le(data, 24, 4)
	if bundle_size < bundle_header_bytes || bundle_size > bundle_max_bytes || records > 64
		|| data_manifest_header + int(bundle_size) + int(records) * 40 != size { return false }
	unsafe { for i in 32 .. data_manifest_header { if data[i] != 0 { return false } } }
	mut candidate := unsafe { &DataManifest(C.alloca(sizeof(DataManifest))) }; unsafe { *candidate = DataManifest{} }
	if !decode_bundle(unsafe { data + data_manifest_header }, int(bundle_size), mut candidate.set) { return false }
	candidate.digests.count = int(records)
	for i in 0 .. int(records) {
		at := data_manifest_header + int(bundle_size) + i * 40
		candidate.digests.disks[i] = u32(get_le(data, at, 4)); candidate.digests.slots[i] = u32(get_le(data, at + 4, 4))
		unsafe { for byte in 0 .. 32 { candidate.digests.values[i][byte] = data[at + 8 + byte] } }
	}
	if !data_manifest_valid(candidate) { return false }
	manifest = unsafe { *candidate }; return true
}

@[direct_array_access]
fn read_data_manifest(fd i32, mut manifest DataManifest) bool {
	mut info := C.stat{}
	if C.fstat(fd, &info) != 0 || C.S_ISREG(info.st_mode) == 0 || info.st_size < data_manifest_header || info.st_size > data_manifest_max {
		plan_error(c'data manifest must be a bounded regular file'); return false
	}
	mut bytes := [11392]u8{}; mut done := i64(0)
	for done < info.st_size {
		read := C.read(fd, unsafe { &bytes[done] }, usize(info.st_size - done))
		if read < 0 && unsafe { C.errno == C.EINTR } { continue }
		if read <= 0 || read > info.st_size - done { return false }; done += read
	}
	mut extra := u8(0)
	for {
		read := C.read(fd, &extra, 1); if read < 0 && unsafe { C.errno == C.EINTR } { continue }
		if read != 0 { return false }; break
	}
	if !decode_data_manifest(&bytes[0], int(done), mut manifest) { plan_error(c'invalid data manifest checksum, bundle or digest records'); return false }
	return true
}
