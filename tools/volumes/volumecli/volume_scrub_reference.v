// SPDX-License-Identifier: GPL-2.0-or-later
module volumecli

// Validate both complete records and bind the entire embedded CH1, including
// native geometry, saved mode and expected digest, before publishing geometry.
@[direct_array_access]
fn volume_scrub_reference_matches(reference &u8, reference_size int, report &u8, report_size int, mut disk DiskKey, mut row Request) bool {
	if reference_size != volume_ciphertext_bytes || report_size != volume_ciphertext_scrub_bytes { return false }
	mut candidate := DiskKey{}; mut request := Request{}; mut saved := DiskKey{}; mut observed := Request{}
	if !volume_ciphertext_reference_geometry(reference, mut candidate, mut request)
		|| !decode_volume_ciphertext_scrub(report, report_size, mut saved, mut observed) { return false }
	unsafe { for i in 0 .. volume_ciphertext_bytes { if reference[i] != report[32 + i] { return false } } }
	disk = candidate; row = request; return true
}

// Historical evidence only: no credentials, physical reads or repair. The
// complete view remains private until validation, binding and formatting finish.
@[direct_array_access]
fn encode_volume_scrub_reference(reference &u8, report &u8, output &char) int {
	mut disk := DiskKey{}; mut row := Request{}
	if !volume_scrub_reference_matches(reference, volume_ciphertext_bytes, report, volume_ciphertext_scrub_bytes, mut disk, mut row) { return 0 }
	mut context := unsafe { &DataSha256(C.alloca(sizeof(DataSha256))) }; unsafe { *context = DataSha256{} }; data_sha_init(mut context)
	mut digest := [32]u8{}
	if !data_sha_update(mut context, report, volume_ciphertext_scrub_bytes) || !data_sha_finish(context, unsafe { &digest }) { return 0 }
	mut identity := [41]char{}; mut expected := [65]char{}; mut actual := [65]char{}; mut fingerprint := [65]char{}; mut report_hash := [65]char{}
	disk_identity(&disk, &identity[0])
	unsafe { for i in 0 .. 32 {
		if C.snprintf(&expected[i * 2], usize(65 - i * 2), c'%02x', u32(reference[80 + i])) != 2
			|| C.snprintf(&actual[i * 2], usize(65 - i * 2), c'%02x', u32(report[160 + i])) != 2
			|| C.snprintf(&fingerprint[i * 2], usize(65 - i * 2), c'%02x', u32(report[192 + i])) != 2
			|| C.snprintf(&report_hash[i * 2], usize(65 - i * 2), c'%02x', u32(digest[i])) != 2 { return 0 }
	} }
	changed := get_le(report, 16, 4)
	length := int(C.snprintf(output, usize(2048), c'format=VINIXCS1 operation=verified-ciphertext-scrub-reference mappings=1 matched=%lu changed=%lu algorithm=sha256 reference_sha256=%s report_sha256=%s\ndisk_bytes=%lu sector=%lu identity=%s slot=%u offset=%lu bytes=%lu readonly=%lu result=%s expected_sha256=%s actual_sha256=%s\n',
		u64(1) - changed, changed, &fingerprint[0], &report_hash[0], disk.bytes, disk.sector, &identity[0], row.slot, row.offset, row.length, row.flags,
		if changed == 0 { &char(c'match') } else { &char(c'changed') }, &expected[0], &actual[0]))
	return if length > 0 && length < 2048 { length } else { 0 }
}

// Both private input files and parent directories remain pinned through final
// stdout checks. Operational failures take precedence over recorded changes.
@[direct_array_access]
fn verify_volume_scrub_reference_files(reference_path &char, report_path &char) i32 {
	mut first := unsafe { &PlanEdit(C.alloca(sizeof(PlanEdit))) }; mut second := unsafe { &PlanEdit(C.alloca(sizeof(PlanEdit))) }
	unsafe { *first = PlanEdit{}; *second = PlanEdit{} }
	defer { close_plan_edit(mut second) }; defer { close_plan_edit(mut first) }
	mut reference := [128]u8{}; mut report := [224]u8{}; mut disk := DiskKey{}; mut row := Request{}
	if !open_plan_edit(reference_path, mut first, false) || read_private_key_fd(first.source, &reference[0], volume_ciphertext_bytes, volume_ciphertext_bytes) != volume_ciphertext_bytes
		|| !open_plan_edit(report_path, mut second, false) || read_private_key_fd(second.source, &report[0], volume_ciphertext_scrub_bytes, volume_ciphertext_scrub_bytes) != volume_ciphertext_scrub_bytes { return 1 }
	if !volume_scrub_reference_matches(&reference[0], volume_ciphertext_bytes, &report[0], volume_ciphertext_scrub_bytes, mut disk, mut row) { return plan_error(c'ciphertext scrub report does not match the supplied reference') }
	mut text := [2048]char{}
	if encode_volume_scrub_reference(&reference[0], &report[0], &text[0]) == 0 || finish_bundle_report(C.printf(c'%s', &text[0]) >= 0) != 0 { return 1 }
	return if get_le(&report[0], 16, 4) == 0 { 0 } else { 2 }
}
