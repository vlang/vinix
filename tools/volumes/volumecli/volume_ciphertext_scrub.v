// SPDX-License-Identifier: GPL-2.0-or-later
module volumecli

const volume_ciphertext_scrub_bytes = 224

// Decode public reference geometry privately; a later invalid field leaves the
// caller unchanged. The original reference validator checks every byte/range.
@[direct_array_access]
fn volume_ciphertext_reference_geometry(data &u8, mut disk DiskKey, mut row Request) bool {
	mut candidate := DiskKey{bytes: get_le(data, 16, 8), sector: get_le(data, 24, 8), kind: u32(get_le(data, 32, 4))}
	request := Request{slot: u32(get_le(data, 36, 4)), offset: get_le(data, 40, 8), length: get_le(data, 48, 8), flags: get_le(data, 56, 8)}
	unsafe { for i in 0 .. 16 { candidate.id[i] = data[64 + i] } }
	if !volume_ciphertext_matches(data, volume_ciphertext_bytes, unsafe { &candidate }, unsafe { &request }) { return false }
	disk = candidate; row = request; return true
}

fn volume_ciphertext_reference_fingerprint(reference &u8, digest &[32]u8) bool {
	mut context := unsafe { &DataSha256(C.alloca(sizeof(DataSha256))) }; unsafe { *context = DataSha256{} }
	data_sha_init(mut context)
	return data_sha_update(mut context, reference, volume_ciphertext_bytes) && data_sha_finish(context, digest)
}

@[direct_array_access]
fn volume_ciphertext_scrub_changed(reference &u8, actual &u8) bool {
	mut difference := u8(0)
	unsafe { for i in 0 .. 32 { difference |= reference[80 + i] ^ actual[i] } }
	return difference != 0
}

@[direct_array_access]
fn encode_volume_ciphertext_scrub(reference &u8, actual &u8, output &u8) bool {
	mut disk := DiskKey{}; mut row := Request{}; mut fingerprint := [32]u8{}
	if !volume_ciphertext_reference_geometry(reference, mut disk, mut row)
		|| !volume_ciphertext_reference_fingerprint(reference, unsafe { &fingerprint }) { return false }
	unsafe { for i in 0 .. volume_ciphertext_scrub_bytes { output[i] = 0 } }
	put_le(output, 0, 8, 0x31534358494e4956) // VINIXCS1
	put_le(output, 8, 4, 1); put_le(output, 12, 4, volume_ciphertext_scrub_bytes)
	put_le(output, 16, 4, u64(volume_ciphertext_scrub_changed(reference, actual))); put_le(output, 20, 4, 1)
	unsafe {
		for i in 0 .. 128 { output[32 + i] = reference[i] }
		for i in 0 .. 32 { output[160 + i] = actual[i]; output[192 + i] = fingerprint[i] }
	}
	put_le(output, 28, 4, crc32(output, volume_ciphertext_scrub_bytes, 28)); return true
}

@[direct_array_access]
fn decode_volume_ciphertext_scrub(data &u8, size int, mut disk DiskKey, mut row Request) bool {
	if size != volume_ciphertext_scrub_bytes || get_le(data, 0, 8) != 0x31534358494e4956
		|| get_le(data, 8, 4) != 1 || get_le(data, 12, 4) != volume_ciphertext_scrub_bytes
		|| get_le(data, 16, 4) > 1 || get_le(data, 20, 4) != 1 || get_le(data, 24, 4) != 0
		|| get_le(data, 28, 4) != crc32(data, size, 28) { return false }
	mut candidate := DiskKey{}; mut request := Request{}; mut fingerprint := [32]u8{}
	reference := unsafe { data + 32 }
	if !volume_ciphertext_reference_geometry(reference, mut candidate, mut request)
		|| !volume_ciphertext_reference_fingerprint(reference, unsafe { &fingerprint })
		|| get_le(data, 16, 4) != u64(volume_ciphertext_scrub_changed(reference, unsafe { data + 160 })) { return false }
	unsafe { for i in 0 .. 32 { if data[192 + i] != fingerprint[i] { return false } } }
	disk = candidate; row = request; return true
}

@[direct_array_access]
fn show_volume_ciphertext_scrub(data &u8, disk &DiskKey, row &Request) bool {
	mut identity := [41]char{}; mut expected := [65]char{}; mut actual := [65]char{}; mut fingerprint := [65]char{}
	disk_identity(disk, &identity[0])
	unsafe { for i in 0 .. 32 {
		if C.snprintf(&expected[i * 2], usize(65 - i * 2), c'%02x', u32(data[112 + i])) != 2
			|| C.snprintf(&actual[i * 2], usize(65 - i * 2), c'%02x', u32(data[160 + i])) != 2
			|| C.snprintf(&fingerprint[i * 2], usize(65 - i * 2), c'%02x', u32(data[192 + i])) != 2 { return false }
	} }
	changed := get_le(data, 16, 4)
	return C.printf(c'format=VINIXCS1 operation=scrubbed-ciphertext mappings=1 matched=%lu changed=%lu algorithm=sha256 reference_sha256=%s\n', u64(1) - changed, changed, &fingerprint[0]) >= 0
		&& C.printf(c'disk_bytes=%lu sector=%lu identity=%s slot=%u offset=%lu bytes=%lu readonly=%lu result=%s expected_sha256=%s actual_sha256=%s\n',
			disk.bytes, disk.sector, &identity[0], row.slot, row.offset, row.length, row.flags,
			if changed == 0 { &char(c'match') } else { &char(c'changed') }, &expected[0], &actual[0]) >= 0
}

@[direct_array_access]
fn show_volume_scrub_file(path &char) i32 {
	mut bytes := [224]u8{}; mut disk := DiskKey{}; mut row := Request{}
	if !read_recovery_file(path, &bytes[0], volume_ciphertext_scrub_bytes)
		|| !decode_volume_ciphertext_scrub(&bytes[0], volume_ciphertext_scrub_bytes, mut disk, mut row) { return plan_error(c'invalid private ciphertext scrub report') }
	return finish_bundle_report(show_volume_ciphertext_scrub(&bytes[0], unsafe { &disk }, unsafe { &row }))
}

// A changed digest is a complete finding. Incomplete reads never publish;
// late output failure can leave a complete report and takes precedence over 2.
@[direct_array_access]
fn scrub_volume_ciphertext(device &char, input &char, credential &char, reference &char, report &char, recovery bool) i32 {
	mut work := unsafe { &VolumeSealFiles(C.alloca(sizeof(VolumeSealFiles))) }; unsafe { *work = VolumeSealFiles{} }
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
	mut saved := [128]u8{}; mut observed := [32]u8{}; mut bytes := [224]u8{}
	if !read_recovery_file(reference, &saved[0], volume_ciphertext_bytes)
		|| !volume_ciphertext_matches(&saved[0], volume_ciphertext_bytes, &work.disk, &work.request.data) { return plan_error(c'ciphertext reference does not match authenticated geometry') }
	fd := C.open(device, C.O_RDONLY | C.O_CLOEXEC | C.O_NOFOLLOW | C.O_NONBLOCK)
	if fd < 0 { C.perror(c'vinix-volume: open ciphertext scrub parent'); return 1 }; defer { C.close(fd) }
	if !probe_disk(fd, mut work.after, mut work.status) || !key_matches(&work.disk, &work.after)
		|| !volume_seal_recheck(fd, mut *work) || !volume_seal_recheck(fd, mut *work)
		|| !read_volume_ciphertext(fd, &work.disk, &work.request.data, unsafe { &observed })
		|| !volume_seal_recheck(fd, mut *work) { return plan_error(c'ciphertext scrub disk or complete read changed') }
	if !encode_volume_ciphertext_scrub(&saved[0], &observed[0], &bytes[0])
		|| !open_plan_destination(report, mut work.edit, true) || !volume_seal_recheck(fd, mut *work)
		|| !publish_recovery(&work.edit, &bytes[0], volume_ciphertext_scrub_bytes) { return 1 }
	if finish_bundle_report(show_volume_ciphertext_scrub(&bytes[0], &work.disk, &work.request.data)) != 0 { return 1 }
	return if volume_ciphertext_scrub_changed(&saved[0], &observed[0]) { 2 } else { 0 }
}
