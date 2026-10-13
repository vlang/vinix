// SPDX-License-Identifier: GPL-2.0-or-later
module volumecli

struct DataScrubReport {
mut:
	disks int
	count int
	reference [32]u8
	indices [64]u32
	rows [64]Request
	expected [64][32]u8
	actual [64][32]u8
}

struct DataScrubHistory {
mut:
	stable int
	new_changes int
	restored int
	changed_again int
	differences u64
}

@[direct_array_access]
fn data_scrub_records_valid(report &DataScrubReport) bool {
	if report.disks < 1 || report.disks > 64 || report.count < 0 || report.count > 64 { return false }
	mut slots := u64(0)
	for i in 0 .. report.count {
		row := report.rows[i]; disk := report.indices[i]
		if disk >= u32(report.disks) || (i > 0 && disk < report.indices[i - 1]) || row.version != 1
			|| row.slot >= 64 || row.flags > 1 || slots & (u64(1) << row.slot) != 0
			|| row.offset > u64(0x7fffffffffffffff) || row.length == 0 || row.length > data_sha_max_bytes
			|| row.length > u64(0x7fffffffffffffff) - row.offset || row.offset % 512 != 0 || row.length % 512 != 0 { return false }
		for earlier in 0 .. i {
			other := report.rows[earlier]
			if report.indices[earlier] == disk && row.offset < other.offset + other.length && other.offset < row.offset + row.length { return false }
		}
		slots |= u64(1) << row.slot
	}
	return true
}

// The existing strict grammar validates the whole SR1 input first. Decode into
// a private stack candidate; even a late refusal leaves caller state untouched.
@[direct_array_access]
fn decode_data_scrub_report(data &u8, size int, mut report DataScrubReport) bool {
	if !scrub_report_valid(data, size) { return false }
	mut cursor := unsafe { &ScrubReportCursor(C.alloca(sizeof(ScrubReportCursor))) }
	mut candidate := unsafe { &DataScrubReport(C.alloca(sizeof(DataScrubReport))) }
	unsafe { *cursor = ScrubReportCursor{data: data, size: size}; *candidate = DataScrubReport{} }
	if !scrub_report_literal(mut cursor, c'format=VINIXSR1 operation=scrubbed-data disks=') { return false }
	disks := scrub_report_number(mut cursor) or { return false }
	if !scrub_report_literal(mut cursor, c' mappings=') { return false }
	count := scrub_report_number(mut cursor) or { return false }
	if !scrub_report_literal(mut cursor, c' matched=') { return false }
	matched := scrub_report_number(mut cursor) or { return false }
	if !scrub_report_literal(mut cursor, c' changed=') { return false }
	changed := scrub_report_number(mut cursor) or { return false }
	if disks == 0 || disks > 64 || count > 64 || matched > count || changed != count - matched
		|| !scrub_report_literal(mut cursor, c' algorithm=sha256 reference_sha256=')
		|| !scrub_report_hex(mut cursor, &candidate.reference[0]) || !scrub_report_literal(mut cursor, c'\n') { return false }
	candidate.disks = int(disks); candidate.count = int(count); mut findings := u64(0)
	for i in 0 .. int(count) {
		if !scrub_report_literal(mut cursor, c'disk=') { return false }
		disk := scrub_report_number(mut cursor) or { return false }
		if disk >= disks || !scrub_report_literal(mut cursor, c' slot=') { return false }
		slot := scrub_report_number(mut cursor) or { return false }
		if slot >= 64 || !scrub_report_literal(mut cursor, c' offset=') { return false }
		offset := scrub_report_number(mut cursor) or { return false }
		if !scrub_report_literal(mut cursor, c' bytes=') { return false }
		length := scrub_report_number(mut cursor) or { return false }
		if !scrub_report_literal(mut cursor, c' readonly=') { return false }
		readonly := scrub_report_number(mut cursor) or { return false }
		if !scrub_report_literal(mut cursor, c' result=') { return false }
		is_changed := unsafe { cursor.at < cursor.size && cursor.data[cursor.at] == `c` }
		if !scrub_report_literal(mut cursor, if is_changed { &char(c'changed') } else { &char(c'match') })
			|| !scrub_report_literal(mut cursor, c' expected_sha256=')
			|| !scrub_report_hex(mut cursor, &candidate.expected[i][0]) || !scrub_report_literal(mut cursor, c' actual_sha256=')
			|| !scrub_report_hex(mut cursor, &candidate.actual[i][0]) || !scrub_report_literal(mut cursor, c'\n')
			|| (candidate.expected[i] != candidate.actual[i]) != is_changed { return false }
		candidate.indices[i] = u32(disk); candidate.rows[i] = Request{slot: u32(slot), offset: offset, length: length, flags: readonly}
		if is_changed { findings++ }
	}
	if cursor.at != size || findings != changed || !data_scrub_records_valid(candidate) { return false }
	report = unsafe { *candidate }; return true
}

// A validated SR1 has one exact spelling. Reconstruct it to fingerprint every
// canonical input byte, including counts, row order and both recorded digests.
@[direct_array_access]
fn encode_data_scrub_snapshot(report &DataScrubReport, output &char) int {
	if !data_scrub_records_valid(report) { return 0 }
	mut changed := 0; for i in 0 .. report.count { if report.expected[i] != report.actual[i] { changed++ } }
	mut fingerprint := [65]char{}
	if !scrub_digest_text(unsafe { &report.reference }, &fingerprint[0]) { return 0 }
	mut length := int(C.snprintf(output, usize(scrub_report_max), c'format=VINIXSR1 operation=scrubbed-data disks=%d mappings=%d matched=%d changed=%d algorithm=sha256 reference_sha256=%s\n', report.disks, report.count, report.count - changed, changed, &fingerprint[0]))
	if length <= 0 || length >= scrub_report_max { return 0 }
	mut expected := [65]char{}; mut actual := [65]char{}
	for i in 0 .. report.count {
		row := report.rows[i]
		if !scrub_digest_text(unsafe { &report.expected[i] }, &expected[0]) || !scrub_digest_text(unsafe { &report.actual[i] }, &actual[0]) { return 0 }
		written := int(C.snprintf(unsafe { output + length }, usize(scrub_report_max - length), c'disk=%u slot=%u offset=%lu bytes=%lu readonly=%lu result=%s expected_sha256=%s actual_sha256=%s\n', report.indices[i], row.slot, row.offset, row.length, row.flags, if report.expected[i] == report.actual[i] { &char(c'match') } else { &char(c'changed') }, &expected[0], &actual[0]))
		if written <= 0 || written >= scrub_report_max - length { return 0 }; length += written
	}
	return length
}

// Exact reference fingerprint AND every recorded metadata/expected digest must
// agree. A later incompatibility takes precedence over earlier changed bytes.
@[direct_array_access]
fn compare_data_scrubs(before &DataScrubReport, after &DataScrubReport, mut history DataScrubHistory) bool {
	if !data_scrub_records_valid(before) || !data_scrub_records_valid(after) || before.disks != after.disks
		|| before.count != after.count || before.reference != after.reference { return false }
	mut candidate := DataScrubHistory{}
	for i in 0 .. before.count {
		if before.indices[i] != after.indices[i] || before.rows[i] != after.rows[i] || before.expected[i] != after.expected[i] { return false }
		if before.actual[i] == after.actual[i] { candidate.stable++; continue }
		candidate.differences |= u64(1) << i
		if after.actual[i] == after.expected[i] { candidate.restored++ }
		else if before.actual[i] == before.expected[i] { candidate.new_changes++ }
		else { candidate.changed_again++ }
	}
	history = candidate; return true
}

@[direct_array_access]
fn data_scrub_fingerprint(report &DataScrubReport, output &char) bool {
	mut text := [32768]char{}; size := encode_data_scrub_snapshot(report, &text[0]); if size == 0 { return false }
	mut context := unsafe { &DataSha256(C.alloca(sizeof(DataSha256))) }; unsafe { *context = DataSha256{} }
	mut digest := [32]u8{}; data_sha_init(mut context)
	return data_sha_update(mut context, unsafe { &u8(&text[0]) }, usize(size)) && data_sha_finish(context, unsafe { &digest })
		&& scrub_digest_text(unsafe { &digest }, output)
}

@[direct_array_access]
fn encode_data_scrub_comparison(before &DataScrubReport, after &DataScrubReport, output &char) int {
	mut history := DataScrubHistory{}; if !compare_data_scrubs(before, after, mut history) { return 0 }
	mut reference := [65]char{}; mut first := [65]char{}; mut second := [65]char{}
	if !scrub_digest_text(unsafe { &before.reference }, &reference[0]) || !data_scrub_fingerprint(before, &first[0]) || !data_scrub_fingerprint(after, &second[0]) { return 0 }
	mut length := int(C.snprintf(output, usize(scrub_report_max), c'format=VINIXSR1 operation=compared-data-scrubs disks=%d mappings=%d stable=%d changed=%d new_changes=%d restored=%d changed_again=%d algorithm=sha256 reference_sha256=%s before_report_sha256=%s after_report_sha256=%s\n', before.disks, before.count, history.stable, before.count - history.stable, history.new_changes, history.restored, history.changed_again, &reference[0], &first[0], &second[0]))
	if length <= 0 || length >= scrub_report_max { return 0 }
	mut expected := [65]char{}; mut old := [65]char{}; mut next := [65]char{}
	for i in 0 .. before.count {
		row := before.rows[i]; old_changed := before.actual[i] != before.expected[i]; new_changed := after.actual[i] != after.expected[i]
		result := if history.differences & (u64(1) << i) == 0 { &char(c'stable') } else if !new_changed { &char(c'restored') } else if !old_changed { &char(c'new-change') } else { &char(c'changed-again') }
		if !scrub_digest_text(unsafe { &before.expected[i] }, &expected[0]) || !scrub_digest_text(unsafe { &before.actual[i] }, &old[0]) || !scrub_digest_text(unsafe { &after.actual[i] }, &next[0]) { return 0 }
		written := int(C.snprintf(unsafe { output + length }, usize(scrub_report_max - length), c'disk=%u slot=%u offset=%lu bytes=%lu readonly=%lu before=%s after=%s result=%s expected_sha256=%s before_sha256=%s after_sha256=%s\n', before.indices[i], row.slot, row.offset, row.length, row.flags, if old_changed { &char(c'changed') } else { &char(c'match') }, if new_changed { &char(c'changed') } else { &char(c'match') }, result, &expected[0], &old[0], &next[0]))
		if written <= 0 || written >= scrub_report_max - length { return 0 }; length += written
	}
	return length
}

@[direct_array_access]
fn read_data_scrub_report(fd i32, mut report DataScrubReport) bool {
	mut info := C.stat{}
	if C.fstat(fd, &info) != 0 || C.S_ISREG(info.st_mode) == 0 || info.st_size <= 0 || info.st_size >= scrub_report_max { return false }
	mut text := [32768]u8{}; mut done := i64(0)
	for done < info.st_size {
		read := C.read(fd, unsafe { &text[done] }, usize(info.st_size - done))
		if read < 0 && unsafe { C.errno == C.EINTR } { continue }
		if read <= 0 || read > info.st_size - done { return false }; done += read
	}
	mut extra := u8(0)
	for { read := C.read(fd, &extra, 1); if read < 0 && unsafe { C.errno == C.EINTR } { continue }; if read != 0 { return false }; break }
	return decode_data_scrub_report(&text[0], int(done), mut report)
}

// Two independent ordinary input owners survive complete report construction
// and final stdout checks, including same-file/hardlink inputs and late failure.
@[direct_array_access]
fn compare_data_scrub_files(before_path &char, after_path &char) i32 {
	mut first := unsafe { &PlanEdit(C.alloca(sizeof(PlanEdit))) }; mut second := unsafe { &PlanEdit(C.alloca(sizeof(PlanEdit))) }
	mut before := unsafe { &DataScrubReport(C.alloca(sizeof(DataScrubReport))) }; mut after := unsafe { &DataScrubReport(C.alloca(sizeof(DataScrubReport))) }
	unsafe { *first = PlanEdit{}; *second = PlanEdit{}; *before = DataScrubReport{}; *after = DataScrubReport{} }
	defer { close_plan_edit(mut second) }; defer { close_plan_edit(mut first) }
	if !open_plan_edit(before_path, mut first, false) || !read_data_scrub_report(first.source, mut before)
		|| !open_plan_edit(after_path, mut second, false) || !read_data_scrub_report(second.source, mut after) { return plan_error(c'invalid or unreadable data scrub reports') }
	mut history := DataScrubHistory{}; if !compare_data_scrubs(before, after, mut history) { return plan_error(c'data scrub reports have different references or saved rows') }
	mut text := [32768]char{}; length := encode_data_scrub_comparison(before, after, &text[0])
	if length == 0 || finish_bundle_report(C.printf(c'%s', &text[0]) >= 0) != 0 { return 1 }
	return if history.stable == before.count { 0 } else { 2 }
}
