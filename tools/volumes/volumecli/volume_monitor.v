// SPDX-License-Identifier: GPL-2.0-or-later
module volumecli

// Construct a complete public sample privately. No credential or volume key
// enters the encoder; the reference fingerprint covers the complete CH1.
@[direct_array_access]
fn encode_ciphertext_monitor(reference &u8, observed &u8, recovery bool, sample u64, changed_samples u64, output &char) int {
	mut disk := DiskKey{}; mut row := Request{}; mut digest := [32]u8{}
	if sample == 0 || changed_samples > sample || !volume_ciphertext_reference_geometry(reference, mut disk, mut row)
		|| !volume_ciphertext_reference_fingerprint(reference, unsafe { &digest }) { return 0 }
	changed := volume_ciphertext_scrub_changed(reference, observed)
	if changed && changed_samples == 0 { return 0 }
	mut identity := [41]char{}; mut expected := [65]char{}; mut actual := [65]char{}; mut fingerprint := [65]char{}
	disk_identity(&disk, &identity[0])
	unsafe { for i in 0 .. 32 {
		if C.snprintf(&expected[i * 2], usize(65 - i * 2), c'%02x', u32(reference[80 + i])) != 2
			|| C.snprintf(&actual[i * 2], usize(65 - i * 2), c'%02x', u32(observed[i])) != 2
			|| C.snprintf(&fingerprint[i * 2], usize(65 - i * 2), c'%02x', u32(digest[i])) != 2 { return 0 }
	} }
	length := int(C.snprintf(output, usize(2048), c'format=VINIXCM1 operation=monitored-ciphertext source=%s sample=%lu changed_samples=%lu session_changed=%lu\nformat=VINIXCS1 operation=scrubbed-ciphertext mappings=1 matched=%lu changed=%lu algorithm=sha256 reference_sha256=%s\ndisk_bytes=%lu sector=%lu identity=%s slot=%u offset=%lu bytes=%lu readonly=%lu result=%s expected_sha256=%s actual_sha256=%s\n',
		if recovery { &char(c'recovery') } else { &char(c'volume') }, sample, changed_samples, u64(changed_samples != 0), u64(!changed), u64(changed), &fingerprint[0], disk.bytes, disk.sector, &identity[0], row.slot, row.offset, row.length, row.flags,
		if changed { &char(c'changed') } else { &char(c'match') }, &expected[0], &actual[0]))
	return if length > 0 && length < 2048 { length } else { 0 }
}

// Authenticate exactly once and erase secrets before reference/device access.
// The original private reference and selected read-only disk stay owned across
// every scan, stdout check and interrupted sleep; nothing is reloaded/reopened.
@[direct_array_access]
fn monitor_volume_ciphertext(input &char, credential &char, reference &char, interval u32, samples u64, recovery bool) i32 {
	if interval > 86400 || (interval == 0 && samples == 0) { return plan_error(c'invalid ciphertext monitor interval or sample count') }
	mut work := unsafe { &VolumeSealFiles(C.alloca(sizeof(VolumeSealFiles))) }; unsafe { *work = VolumeSealFiles{} }
	defer { close_plan_edit(mut work.edit); erase_key(work, sizeof(VolumeSealFiles)) }
	if recovery {
		if !read_recovery_file(input, &work.envelope[0], volume_seal_bytes)
			|| !volume_recovery_header(&work.envelope[0], volume_seal_bytes) { return plan_error(c'invalid volume recovery format or geometry') }
		if !read_recovery_file(credential, &work.wrapping[0], 64)
			|| !decode_volume_recovery(&work.envelope[0], volume_seal_bytes, &work.wrapping[0], mut work.disk, mut work.request) { return plan_error(c'invalid volume recovery configuration or recovery key') }
	} else if !load_volume_seal(input, credential, mut *work) { return 1 }
	erase_key(&work.password[0], 1024); erase_key(&work.wrapping[0], 64); erase_key(&work.request.key[0], 64)
	mut saved := [128]u8{}; mut observed := [32]u8{}; mut text := [2048]char{}
	if !open_plan_edit(reference, mut work.edit, false) || read_private_key_fd(work.edit.source, &saved[0], volume_ciphertext_bytes, volume_ciphertext_bytes) != volume_ciphertext_bytes { return 1 }
	if !volume_ciphertext_matches(&saved[0], volume_ciphertext_bytes, &work.disk, &work.request.data) { return plan_error(c'ciphertext reference does not match authenticated geometry') }
	fd := ciphertext_scrub_parent(unsafe { nil }, &work.disk, mut work.status)
	if fd < 0 { C.perror(c'vinix-volume: open ciphertext monitor parent'); return 1 }; defer { C.close(fd) }
	mut sample := u64(1); mut changed_samples := u64(0)
	for {
		if !volume_seal_recheck(fd, mut *work) || !read_volume_ciphertext(fd, &work.disk, &work.request.data, unsafe { &observed })
			|| !volume_seal_recheck(fd, mut *work) { return 1 }
		if volume_ciphertext_scrub_changed(&saved[0], &observed[0]) && changed_samples != u64(-1) { changed_samples++ }
		if encode_ciphertext_monitor(&saved[0], &observed[0], recovery, sample, changed_samples, &text[0]) == 0
			|| !volume_seal_recheck(fd, mut *work) || finish_bundle_report(C.printf(c'%s', &text[0]) >= 0) != 0 { return 1 }
		if samples != 0 && sample == samples { return if changed_samples == 0 { 0 } else { 2 } }
		if sample != u64(-1) { sample++ }
		mut remaining := interval; for remaining != 0 { remaining = C.sleep(remaining) }
	}
	return 1
}
