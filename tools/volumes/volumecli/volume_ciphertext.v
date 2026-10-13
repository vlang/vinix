// SPDX-License-Identifier: GPL-2.0-or-later
module volumecli

const volume_ciphertext_bytes = 128

// Ciphertext references contain public geometry and a digest, never credentials
// or keys. They intentionally survive credential rotation and VC1/VR1 rescue.
fn volume_ciphertext_range(disk &DiskKey, row &Request) bool {
	return volume_seal_geometry(disk, row) && row.offset <= u64(0x7fffffffffffffff)
		&& row.length <= u64(0x7fffffffffffffff) - row.offset && row.length <= data_sha_max_bytes
}

@[direct_array_access]
fn encode_volume_ciphertext(disk &DiskKey, row &Request, digest &u8, output &u8) bool {
	if !volume_ciphertext_range(disk, row) { return false }
	unsafe { for i in 0 .. volume_ciphertext_bytes { output[i] = 0 } }
	put_le(output, 0, 8, 0x31484358494e4956) // VINIXCH1
	put_le(output, 8, 4, 1); put_le(output, 12, 4, volume_ciphertext_bytes)
	put_le(output, 16, 8, disk.bytes); put_le(output, 24, 8, disk.sector)
	put_le(output, 32, 4, disk.kind); put_le(output, 36, 4, row.slot)
	put_le(output, 40, 8, row.offset); put_le(output, 48, 8, row.length); put_le(output, 56, 8, row.flags)
	unsafe { for i in 0 .. 16 { output[64 + i] = disk.id[i] }; for i in 0 .. 32 { output[80 + i] = digest[i] } }
	put_le(output, 124, 4, crc32(output, volume_ciphertext_bytes, 124))
	return true
}

@[direct_array_access]
fn volume_ciphertext_matches(data &u8, size int, disk &DiskKey, row &Request) bool {
	if size != volume_ciphertext_bytes || get_le(data, 0, 8) != 0x31484358494e4956
		|| get_le(data, 8, 4) != 1 || get_le(data, 12, 4) != volume_ciphertext_bytes
		|| get_le(data, 124, 4) != crc32(data, size, 124) || !volume_ciphertext_range(disk, row) { return false }
	unsafe { for i in 112 .. 124 { if data[i] != 0 { return false } } }
	if get_le(data, 16, 8) != disk.bytes || get_le(data, 24, 8) != disk.sector
		|| get_le(data, 32, 4) != disk.kind || get_le(data, 36, 4) != row.slot
		|| get_le(data, 40, 8) != row.offset || get_le(data, 48, 8) != row.length || get_le(data, 56, 8) != row.flags { return false }
	unsafe { for i in 0 .. 16 { if data[64 + i] != disk.id[i] { return false } } }
	return true
}

// One bounded streaming workspace; interrupted and aligned short transfers are
// retried. A digest is returned only after the complete authenticated extent.
@[direct_array_access]
fn read_volume_ciphertext(fd i32, disk &DiskKey, row &Request, digest &[32]u8) bool {
	if !volume_ciphertext_range(disk, row) { return false }
	mut context := unsafe { &DataSha256(C.alloca(sizeof(DataSha256))) }
	unsafe { *context = DataSha256{} }; data_sha_init(mut context)
	mut bytes := [65536]u8{}; mut done := u64(0)
	for done < row.length {
		wanted := if row.length - done > 65536 { usize(65536) } else { usize(row.length - done) }
		read := C.pread(fd, &bytes[0], wanted, i64(row.offset + done))
		if read < 0 && unsafe { C.errno == C.EINTR } { continue }
		if read <= 0 || u64(read) > u64(wanted) || u64(read) % disk.sector != 0
			|| !data_sha_update(mut context, &bytes[0], usize(read)) {
			plan_error(c'ciphertext read failed or returned an invalid native-sector transfer'); return false
		}
		done += u64(read)
	}
	return data_sha_finish(context, digest)
}

@[direct_array_access]
fn show_volume_ciphertext(disk &DiskKey, row &Request, digest &u8, recovery bool, verify bool) bool {
	mut identity := [41]char{}; mut text := [65]char{}
	disk_identity(disk, &identity[0])
	unsafe { for i in 0 .. 32 { C.snprintf(&text[i * 2], usize(65 - i * 2), c'%02x', u32(digest[i])) } }
	return C.printf(c'operation=%s format=%s algorithm=sha256\n',
		if verify { &char(c'verified-ciphertext') } else { &char(c'recorded-ciphertext') },
		if recovery { &char(c'recovery') } else { &char(c'volume') }) >= 0
		&& C.printf(c'disk_bytes=%lu sector=%lu identity=%s slot=%u offset=%lu bytes=%lu readonly=%lu sha256=%s\n',
			disk.bytes, disk.sector, &identity[0], row.slot, row.offset, row.length, row.flags, &text[0]) >= 0
}

@[direct_array_access]
fn volume_ciphertext_file(device &char, input &char, credential &char, reference &char, recovery bool, verify bool) i32 {
	mut work := unsafe { &VolumeSealFiles(C.alloca(sizeof(VolumeSealFiles))) }
	unsafe { *work = VolumeSealFiles{} }
	defer { close_plan_edit(mut work.edit); erase_key(work, sizeof(VolumeSealFiles)) }
	if recovery {
		if !read_recovery_file(input, &work.envelope[0], volume_seal_bytes)
			|| !volume_recovery_header(&work.envelope[0], volume_seal_bytes) { return plan_error(c'invalid volume recovery format or geometry') }
		if !read_recovery_file(credential, &work.wrapping[0], 64)
			|| !decode_volume_recovery(&work.envelope[0], volume_seal_bytes, &work.wrapping[0], mut work.disk, mut work.request) {
			return plan_error(c'invalid volume recovery configuration or recovery key')
		}
	} else if !load_volume_seal(input, credential, mut *work) { return 1 }
	erase_key(&work.password[0], 1024); erase_key(&work.wrapping[0], 64); erase_key(&work.request.key[0], 64)
	if !volume_ciphertext_range(&work.disk, &work.request.data) { return plan_error(c'ciphertext extent exceeds the signed read or SHA-256 limit') }
	mut record := [128]u8{}; mut digest := [32]u8{}
	if verify {
		if !read_recovery_file(reference, &record[0], volume_ciphertext_bytes)
			|| !volume_ciphertext_matches(&record[0], volume_ciphertext_bytes, &work.disk, &work.request.data) {
			return plan_error(c'ciphertext reference format or authenticated geometry does not match')
		}
	}
	fd := C.open(device, C.O_RDONLY | C.O_CLOEXEC | C.O_NOFOLLOW | C.O_NONBLOCK)
	if fd < 0 { C.perror(c'vinix-volume: open ciphertext parent'); return 1 }; defer { C.close(fd) }
	if !probe_disk(fd, mut work.after, mut work.status) || !key_matches(&work.disk, &work.after)
		|| !volume_seal_recheck(fd, mut *work) || !volume_seal_recheck(fd, mut *work)
		|| !read_volume_ciphertext(fd, &work.disk, &work.request.data, &digest)
		|| !volume_seal_recheck(fd, mut *work) { return plan_error(c'ciphertext disk identity, geometry or read changed') }
	if verify {
		for i in 0 .. 32 { if digest[i] != record[80 + i] { return plan_error(c'ciphertext does not match recorded SHA-256') } }
	} else {
		if !encode_volume_ciphertext(&work.disk, &work.request.data, &digest[0], &record[0])
			|| !open_plan_destination(reference, mut work.edit, true)
			|| !volume_seal_recheck(fd, mut *work)
			|| !publish_recovery(&work.edit, &record[0], volume_ciphertext_bytes) { return 1 }
	}
	return finish_bundle_report(show_volume_ciphertext(&work.disk, &work.request.data, &digest[0], recovery, verify))
}
