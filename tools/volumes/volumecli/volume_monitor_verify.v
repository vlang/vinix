// SPDX-License-Identifier: GPL-2.0-or-later
module volumecli

fn C.memcmp(voidptr, voidptr, usize) i32

struct CipherMonitorHistory {
mut:
	samples u64
	changed_samples u64
	stable u64
	new_changes u64
	restored u64
	changed_again u64
	recovery bool
	actual [32]u8
}

// The final digest has a fixed canonical suffix. Reconstruct and compare the
// entire frame to bind every prefix, native geometry, result and reference byte.
// Caller state advances only after all validation has succeeded.
@[direct_array_access]
fn accept_ciphertext_monitor(reference &u8, data &u8, size int, prefix int, mut history CipherMonitorHistory) bool {
	if prefix <= 0 || prefix >= 256 || prefix >= size || size >= 2048 || size < 79 || history.samples == u64(-1) || history.changed_samples > history.samples { return false }
	mut cursor := unsafe { &ScrubReportCursor(C.alloca(sizeof(ScrubReportCursor))) }; unsafe { *cursor = ScrubReportCursor{data: data, size: prefix} }
	if !scrub_report_literal(mut cursor, c'format=VINIXCM1 operation=monitored-ciphertext source=') { return false }
	recovery := unsafe { cursor.at < cursor.size && data[cursor.at] == `r` }
	if !scrub_report_literal(mut cursor, if recovery { c'recovery' } else { c'volume' }) || (history.samples != 0 && recovery != history.recovery) || !scrub_report_literal(mut cursor, c' sample=') { return false }
	sample := scrub_report_number(mut cursor) or { return false }
	if sample != history.samples + 1 || !scrub_report_literal(mut cursor, c' changed_samples=') { return false }
	changed_samples := scrub_report_number(mut cursor) or { return false }
	if !scrub_report_literal(mut cursor, c' session_changed=') { return false }
	latched := scrub_report_number(mut cursor) or { return false }
	if latched > 1 || !scrub_report_literal(mut cursor, c'\n') || cursor.at != prefix { return false }
	unsafe { *cursor = ScrubReportCursor{data: data, size: size, at: size - 79} }; mut actual := [32]u8{}
	if !scrub_report_literal(mut cursor, c'actual_sha256=') || !scrub_report_hex(mut cursor, &actual[0]) || !scrub_report_literal(mut cursor, c'\n') || cursor.at != size { return false }
	changed := volume_ciphertext_scrub_changed(reference, &actual[0])
	if changed_samples != history.changed_samples + u64(changed) || latched != u64(changed_samples != 0) { return false }
	mut canonical := [2048]char{}
	if encode_ciphertext_monitor(reference, &actual[0], recovery, sample, changed_samples, &canonical[0]) != size || C.memcmp(data, &canonical[0], usize(size)) != 0 { return false }
	if history.samples != 0 {
		if history.actual == actual { history.stable++ }
		else if !changed { history.restored++ }
		else if !volume_ciphertext_scrub_changed(reference, &history.actual[0]) { history.new_changes++ }
		else { history.changed_again++ }
	}
	history.samples = sample; history.changed_samples = changed_samples; history.recovery = recovery; history.actual = actual; return true
}

// Reuse the bounded original-byte reader. Persistent workspaces precede the
// frame loop; no borrowed frame pointer survives a sample helper's return.
@[direct_array_access]
fn read_ciphertext_monitor(fd i32, reference &u8, mut history CipherMonitorHistory, digest &[32]u8) bool {
	mut disk := DiskKey{}; mut row := Request{}; mut info := C.stat{}
	if !volume_ciphertext_reference_geometry(reference, mut disk, mut row) || C.fstat(fd, &info) != 0 || C.S_ISREG(info.st_mode) == 0 || info.st_size <= 0 || info.st_size > monitor_transcript_max { return false }
	size := info.st_size
	mut reader := unsafe { &DataMonitorReader(C.alloca(sizeof(DataMonitorReader))) }; unsafe { *reader = DataMonitorReader{fd: fd, remaining: size} }; data_sha_init(mut reader.hash)
	mut candidate := unsafe { &CipherMonitorHistory(C.alloca(sizeof(CipherMonitorHistory))) }; unsafe { *candidate = CipherMonitorHistory{} }; mut frame := [2048]u8{}
	for {
		prefix := data_monitor_line(mut *reader, &frame[0], 255); if prefix == 0 { if reader.failed { return false }; break }
		mut length := prefix
		for _ in 0 .. 2 { n := data_monitor_line(mut *reader, unsafe { &frame[length] }, 2047 - length); if n == 0 || reader.failed { return false }; length += n }
		if reader.failed || !accept_ciphertext_monitor(reference, &frame[0], length, prefix, mut *candidate) { return false }
	}
	mut extra := u8(0)
	for { n := C.read(fd, &extra, 1); if n < 0 && unsafe { C.errno == C.EINTR } { continue }; if n != 0 { return false }; break }
	mut sum := [32]u8{}
	if candidate.samples == 0 || C.fstat(fd, &info) != 0 || C.S_ISREG(info.st_mode) == 0 || info.st_size != size || !data_sha_finish(&reader.hash, unsafe { &sum }) { return false }
	history = unsafe { *candidate }; unsafe { *digest = sum }; return true
}

@[direct_array_access]
fn encode_ciphertext_monitor_history(reference &u8, history &CipherMonitorHistory, digest &[32]u8, output &char) int {
	mut disk := DiskKey{}; mut row := Request{}; mut fingerprint := [32]u8{}
	if history.samples == 0 || history.changed_samples > history.samples || history.new_changes > history.samples - 1 || history.restored > history.samples - 1 - history.new_changes
		|| history.changed_again > history.samples - 1 - history.new_changes - history.restored || history.stable != history.samples - 1 - history.new_changes - history.restored - history.changed_again
		|| !volume_ciphertext_reference_geometry(reference, mut disk, mut row) || !volume_ciphertext_reference_fingerprint(reference, unsafe { &fingerprint }) { return 0 }
	changed := volume_ciphertext_scrub_changed(reference, &history.actual[0]); if changed && history.changed_samples == 0 { return 0 }
	mut identity := [41]char{}; mut expected := [65]char{}; mut actual := [65]char{}; mut saved := [65]char{}; mut transcript := [65]char{}; mut recorded := [32]u8{}
	unsafe { for i in 0 .. 32 { recorded[i] = reference[80 + i] } }
	disk_identity(&disk, &identity[0])
	if !scrub_digest_text(&recorded, &expected[0]) || !scrub_digest_text(&history.actual, &actual[0]) || !scrub_digest_text(&fingerprint, &saved[0]) || !scrub_digest_text(digest, &transcript[0]) { return 0 }
	n := int(C.snprintf(output, 2048, c'format=VINIXCM1 operation=verified-ciphertext-monitor source=%s mappings=1 samples=%lu changed_samples=%lu session_changed=%lu final_changed=%lu stable=%lu new_changes=%lu restored=%lu changed_again=%lu algorithm=sha256 reference_sha256=%s transcript_sha256=%s\ndisk_bytes=%lu sector=%lu identity=%s slot=%u offset=%lu bytes=%lu readonly=%lu result=%s expected_sha256=%s final_sha256=%s\n',
		if history.recovery { &char(c'recovery') } else { &char(c'volume') }, history.samples, history.changed_samples, u64(history.changed_samples != 0), u64(changed), history.stable, history.new_changes, history.restored, history.changed_again, &saved[0], &transcript[0], disk.bytes, disk.sector, &identity[0], row.slot, row.offset, row.length, row.flags, if changed { &char(c'changed') } else { &char(c'match') }, &expected[0], &actual[0]))
	return if n > 0 && n < 2048 { n } else { 0 }
}

// The CH1 retains private reference policy. The public ASCII transcript is an
// ordinary regular file. Both original file/directory pairs survive stdout.
@[direct_array_access]
fn verify_volume_monitor_files(reference_path &char, transcript_path &char) i32 {
	mut first := unsafe { &PlanEdit(C.alloca(sizeof(PlanEdit))) }; mut second := unsafe { &PlanEdit(C.alloca(sizeof(PlanEdit))) }
	mut history := unsafe { &CipherMonitorHistory(C.alloca(sizeof(CipherMonitorHistory))) }; unsafe { *first = PlanEdit{}; *second = PlanEdit{}; *history = CipherMonitorHistory{} }
	defer { close_plan_edit(mut second) }; defer { close_plan_edit(mut first) }
	mut reference := [128]u8{}; mut digest := [32]u8{}; mut text := [2048]char{}
	if !open_plan_edit(reference_path, mut first, false) || read_private_key_fd(first.source, &reference[0], volume_ciphertext_bytes, volume_ciphertext_bytes) != volume_ciphertext_bytes
		|| !open_plan_edit(transcript_path, mut second, false) || !read_ciphertext_monitor(second.source, &reference[0], mut *history, unsafe { &digest }) { return plan_error(c'invalid private ciphertext reference or monitor transcript') }
	if encode_ciphertext_monitor_history(&reference[0], history, unsafe { &digest }, &text[0]) == 0 || finish_bundle_report(C.printf(c'%s', &text[0]) >= 0) != 0 { return 1 }
	return if history.changed_samples == 0 { 0 } else { 2 }
}
