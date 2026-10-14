// SPDX-License-Identifier: GPL-2.0-or-later
module volumecli

const monitor_transcript_max = 67108864
const data_monitor_history_max = 49152

struct DataMonitorHistory {
mut:
	samples u64
	changed_samples u64
	changed [64]u64
	stable [64]u64
	new_changes [64]u64
	restored [64]u64
	changed_again [64]u64
	actual [64][32]u8
}

// Validate the complete frame before advancing any caller session state.
// The supplied DH1 binds omitted native geometry as well as every SR1 row.
@[direct_array_access]
fn accept_data_monitor_sample(manifest &DataManifest, data &u8, size int, prefix int, mut history DataMonitorHistory) bool {
	if prefix <= 0 || prefix >= 256 || prefix >= size || size >= data_monitor_report_max || history.samples == u64(-1) || history.changed_samples > history.samples { return false }
	mut cursor := unsafe { &ScrubReportCursor(C.alloca(sizeof(ScrubReportCursor))) }; unsafe { *cursor = ScrubReportCursor{data: data, size: prefix} }
	if !scrub_report_literal(mut cursor, c'format=VINIXDM1 operation=monitored-data sample=') { return false }
	sample := scrub_report_number(mut cursor) or { return false }
	if sample != history.samples + 1 || !scrub_report_literal(mut cursor, c' changed_samples=') { return false }
	changed_samples := scrub_report_number(mut cursor) or { return false }
	if !scrub_report_literal(mut cursor, c' session_changed=') { return false }
	latched := scrub_report_number(mut cursor) or { return false }
	if latched > 1 || !scrub_report_literal(mut cursor, c'\n') || cursor.at != prefix { return false }
	mut report := unsafe { &DataScrubReport(C.alloca(sizeof(DataScrubReport))) }; unsafe { *report = DataScrubReport{} }
	if !decode_data_scrub_report(unsafe { data + prefix }, size - prefix, mut *report) || !data_scrub_reference_matches(manifest, report) { return false }
	mut changed := false; for i in 0 .. report.count { if report.actual[i] != report.expected[i] { changed = true } }
	if changed_samples != history.changed_samples + u64(changed) || latched != u64(changed_samples != 0) { return false }
	// No failing operation remains. Counts are bounded by the file-size limit;
	// borrowed report storage dies with this helper frame after the copy.
	for i in 0 .. report.count {
		if report.actual[i] != report.expected[i] { history.changed[i]++ }
		if history.samples > 0 {
			if history.actual[i] == report.actual[i] { history.stable[i]++ }
			else if report.actual[i] == report.expected[i] { history.restored[i]++ }
			else if history.actual[i] == report.expected[i] { history.new_changes[i]++ }
			else { history.changed_again[i]++ }
		}
		history.actual[i] = report.actual[i]
	}
	history.samples = sample; history.changed_samples = changed_samples; return true
}

struct DataMonitorReader {
	fd i32
mut:
	remaining i64
	at int
	count int
	failed bool
	bytes [65536]u8
	hash DataSha256
}

// Refill a fixed workspace instead of issuing one syscall per character.
// Hash exactly the accepted input bytes, including every original prefix.
@[direct_array_access]
fn data_monitor_line(mut reader DataMonitorReader, output &u8, maximum int) int {
	mut length := 0
	for {
		if reader.at == reader.count {
			if reader.remaining == 0 { if length != 0 { reader.failed = true }; return length }
			wanted := if reader.remaining > 65536 { usize(65536) } else { usize(reader.remaining) }
			mut count := i64(0)
			for { count = C.read(reader.fd, &reader.bytes[0], wanted); if count < 0 && unsafe { C.errno == C.EINTR } { continue }; break }
			if count <= 0 || count > i64(wanted) || !data_sha_update(mut reader.hash, &reader.bytes[0], usize(count)) { reader.failed = true; return 0 }
			reader.remaining -= count; reader.at = 0; reader.count = int(count)
		}
		byte := reader.bytes[reader.at]; reader.at++
		if length >= maximum || byte == 0 { reader.failed = true; return 0 }
		unsafe { output[length] = byte }; length++
		if byte == `\n` { return length }
	}
	return 0
}

// All persistent parse workspaces precede the loop. Reject diagnostics, partial
// tails, appended data and changed descriptor length before exposing a summary.
@[direct_array_access]
fn read_data_monitor(fd i32, manifest &DataManifest, mut history DataMonitorHistory, digest &[32]u8) bool {
	mut info := C.stat{}
	if !data_manifest_valid(manifest) || C.fstat(fd, &info) != 0 || C.S_ISREG(info.st_mode) == 0 || info.st_size <= 0 || info.st_size > monitor_transcript_max { return false }
	size := info.st_size
	mut reader := unsafe { &DataMonitorReader(C.alloca(sizeof(DataMonitorReader))) }; unsafe { *reader = DataMonitorReader{fd: fd, remaining: size} }; data_sha_init(mut reader.hash)
	mut candidate := unsafe { &DataMonitorHistory(C.alloca(sizeof(DataMonitorHistory))) }; unsafe { *candidate = DataMonitorHistory{} }
	mut frame := [33024]u8{}
	for {
		prefix := data_monitor_line(mut *reader, &frame[0], 255)
		if prefix == 0 { if reader.failed { return false }; break }
		mut length := prefix
		// The trusted reference determines the only valid number of SR1 rows.
		for _ in 0 .. manifest.digests.count + 1 {
			n := data_monitor_line(mut *reader, unsafe { &frame[length] }, data_monitor_report_max - 1 - length)
			if n == 0 || reader.failed { return false }; length += n
		}
		if reader.failed || !accept_data_monitor_sample(manifest, &frame[0], length, prefix, mut *candidate) { return false }
	}
	mut extra := u8(0)
	for { n := C.read(fd, &extra, 1); if n < 0 && unsafe { C.errno == C.EINTR } { continue }; if n != 0 { return false }; break }
	mut sum := [32]u8{}
	if candidate.samples == 0 || C.fstat(fd, &info) != 0 || C.S_ISREG(info.st_mode) == 0 || info.st_size != size || !data_sha_finish(&reader.hash, unsafe { &sum }) { return false }
	history = unsafe { *candidate }; unsafe { *digest = sum }; return true
}

@[direct_array_access]
fn encode_data_monitor_history(manifest &DataManifest, history &DataMonitorHistory, digest &[32]u8, output &char) int {
	if !data_manifest_valid(manifest) || history.samples == 0 || history.changed_samples > history.samples { return 0 }
	mut final_changed := 0
	for i in 0 .. manifest.digests.count {
		if history.changed[i] > history.changed_samples || history.new_changes[i] > history.samples - 1 || history.restored[i] > history.samples - 1
			|| history.changed_again[i] > history.samples - 1 || history.stable[i] > history.samples - 1
			|| history.restored[i] > history.samples - 1 - history.new_changes[i]
			|| history.changed_again[i] > history.samples - 1 - history.new_changes[i] - history.restored[i]
			|| history.stable[i] != history.samples - 1 - history.new_changes[i] - history.restored[i] - history.changed_again[i] { return 0 }
		if history.actual[i] != manifest.digests.values[i] { final_changed++ }
	}
	mut reference := [65]char{}; mut transcript := [65]char{}
	if !data_reference_fingerprint(manifest, &reference[0]) || !scrub_digest_text(digest, &transcript[0]) { return 0 }
	mut length := int(C.snprintf(output, usize(data_monitor_history_max), c'format=VINIXDM1 operation=verified-data-monitor disks=%d mappings=%d samples=%lu changed_samples=%lu session_changed=%lu final_changed=%d algorithm=sha256 reference_sha256=%s transcript_sha256=%s\n', manifest.set.count, manifest.digests.count, history.samples, history.changed_samples, u64(history.changed_samples != 0), final_changed, &reference[0], &transcript[0]))
	if length <= 0 || length >= data_monitor_history_max { return 0 }
	mut identity := [41]char{}; mut expected := [65]char{}; mut actual := [65]char{}; mut record := 0
	for disk in 0 .. manifest.set.count {
		key := unsafe { &manifest.set.plans[disk].key }; disk_identity(key, &identity[0])
		written := int(C.snprintf(unsafe { output + length }, usize(data_monitor_history_max - length), c'disk=%u disk_bytes=%lu sector=%lu identity=%s\n', u32(disk), key.bytes, key.sector, &identity[0]))
		if written <= 0 || written >= data_monitor_history_max - length { return 0 }; length += written
		for at := u32(0); at < manifest.set.plans[disk].count; at++ {
			row := manifest.set.plans[disk].rows[at]
			if !scrub_digest_text(unsafe { &manifest.digests.values[record] }, &expected[0]) || !scrub_digest_text(unsafe { &history.actual[record] }, &actual[0]) { return 0 }
			n := int(C.snprintf(unsafe { output + length }, usize(data_monitor_history_max - length), c'disk=%u slot=%u offset=%lu bytes=%lu readonly=%lu changed_samples=%lu stable=%lu new_changes=%lu restored=%lu changed_again=%lu final=%s expected_sha256=%s final_sha256=%s\n', u32(disk), row.slot, row.offset, row.length, row.flags, history.changed[record], history.stable[record], history.new_changes[record], history.restored[record], history.changed_again[record], if history.actual[record] == manifest.digests.values[record] { &char(c'match') } else { &char(c'changed') }, &expected[0], &actual[0]))
			if n <= 0 || n >= data_monitor_history_max - length { return 0 }; length += n; record++
		}
	}
	return length
}

// Offline ordinary-file owners only: retain both source/parent pairs through
// complete validation, private formatting and final stdout checks.
@[direct_array_access]
fn verify_data_monitor_files(manifest_path &char, transcript_path &char) i32 {
	mut first := unsafe { &PlanEdit(C.alloca(sizeof(PlanEdit))) }; mut second := unsafe { &PlanEdit(C.alloca(sizeof(PlanEdit))) }
	mut manifest := unsafe { &DataManifest(C.alloca(sizeof(DataManifest))) }; mut history := unsafe { &DataMonitorHistory(C.alloca(sizeof(DataMonitorHistory))) }
	unsafe { *first = PlanEdit{}; *second = PlanEdit{}; *manifest = DataManifest{}; *history = DataMonitorHistory{} }
	defer { close_plan_edit(mut second) }; defer { close_plan_edit(mut first) }
	mut digest := [32]u8{}; mut text := [49152]char{}
	if !open_plan_edit(manifest_path, mut first, false) || !read_data_manifest(first.source, mut manifest)
		|| !open_plan_edit(transcript_path, mut second, false) || !read_data_monitor(second.source, manifest, mut *history, unsafe { &digest }) { return plan_error(c'invalid or unreadable data monitor transcript or reference') }
	if encode_data_monitor_history(manifest, history, unsafe { &digest }, &text[0]) == 0 || finish_bundle_report(C.printf(c'%s', &text[0]) >= 0) != 0 { return 1 }
	return if history.changed_samples == 0 { 0 } else { 2 }
}
