// SPDX-License-Identifier: GPL-2.0-or-later
module volumecli

// Bind every field available in SR1 to the complete canonical DH1 reference.
// Its fingerprint also covers the identities/native geometry/pools SR1 omits.
@[direct_array_access]
fn data_scrub_reference_matches(manifest &DataManifest, report &DataScrubReport) bool {
	if !data_manifest_valid(manifest) || !data_scrub_records_valid(report) || manifest.set.count != report.disks
		|| manifest.digests.count != report.count { return false }
	mut expected := [65]char{}; mut recorded := [65]char{}
	if !data_reference_fingerprint(manifest, &expected[0]) || !scrub_digest_text(unsafe { &report.reference }, &recorded[0])
		|| C.strcmp(&expected[0], &recorded[0]) != 0 { return false }
	mut record := 0
	for disk in 0 .. manifest.set.count { for at := u32(0); at < manifest.set.plans[disk].count; at++ {
		if report.indices[record] != u32(disk) || report.rows[record] != manifest.set.plans[disk].rows[at]
			|| report.expected[record] != manifest.digests.values[record] { return false }
		record++
	} }
	return record == report.count
}

// Construct the entire bounded view before stdout. This verifies saved evidence
// against a supplied reference; it neither scans nor repairs current devices.
@[direct_array_access]
fn encode_data_scrub_reference(manifest &DataManifest, report &DataScrubReport, output &char) int {
	if !data_scrub_reference_matches(manifest, report) { return 0 }
	mut reference := [65]char{}; mut fingerprint := [65]char{}
	if !data_reference_fingerprint(manifest, &reference[0]) || !data_scrub_fingerprint(report, &fingerprint[0]) { return 0 }
	mut changed := 0; for i in 0 .. report.count { if report.expected[i] != report.actual[i] { changed++ } }
	mut length := int(C.snprintf(output, usize(scrub_report_max), c'format=VINIXSR1 operation=verified-data-scrub-reference disks=%d mappings=%d matched=%d changed=%d algorithm=sha256 reference_sha256=%s report_sha256=%s\n', report.disks, report.count, report.count - changed, changed, &reference[0], &fingerprint[0]))
	if length <= 0 || length >= scrub_report_max { return 0 }
	mut identity := [41]char{}; mut expected := [65]char{}; mut actual := [65]char{}; mut record := 0
	for disk in 0 .. manifest.set.count {
		key := unsafe { &manifest.set.plans[disk].key }; disk_identity(key, &identity[0])
		written := int(C.snprintf(unsafe { output + length }, usize(scrub_report_max - length), c'disk=%u disk_bytes=%lu sector=%lu identity=%s\n', u32(disk), key.bytes, key.sector, &identity[0]))
		if written <= 0 || written >= scrub_report_max - length { return 0 }; length += written
		for at := u32(0); at < manifest.set.plans[disk].count; at++ {
			row := report.rows[record]
			if !scrub_digest_text(unsafe { &report.expected[record] }, &expected[0]) || !scrub_digest_text(unsafe { &report.actual[record] }, &actual[0]) { return 0 }
			count := int(C.snprintf(unsafe { output + length }, usize(scrub_report_max - length), c'disk=%u slot=%u offset=%lu bytes=%lu readonly=%lu result=%s expected_sha256=%s actual_sha256=%s\n', u32(disk), row.slot, row.offset, row.length, row.flags, if report.expected[record] == report.actual[record] { &char(c'match') } else { &char(c'changed') }, &expected[0], &actual[0]))
			if count <= 0 || count >= scrub_report_max - length { return 0 }; length += count; record++
		}
	}
	return length
}

// Independent ordinary input owners remain pinned through the final output
// checks. Operational errors take precedence over historical changed findings.
@[direct_array_access]
fn verify_data_scrub_reference_files(manifest_path &char, report_path &char) i32 {
	mut first := unsafe { &PlanEdit(C.alloca(sizeof(PlanEdit))) }; mut second := unsafe { &PlanEdit(C.alloca(sizeof(PlanEdit))) }
	mut manifest := unsafe { &DataManifest(C.alloca(sizeof(DataManifest))) }; mut report := unsafe { &DataScrubReport(C.alloca(sizeof(DataScrubReport))) }
	unsafe { *first = PlanEdit{}; *second = PlanEdit{}; *manifest = DataManifest{}; *report = DataScrubReport{} }
	defer { close_plan_edit(mut second) }; defer { close_plan_edit(mut first) }
	if !open_plan_edit(manifest_path, mut first, false) || !read_data_manifest(first.source, mut manifest)
		|| !open_plan_edit(report_path, mut second, false) || !read_data_scrub_report(second.source, mut report) { return 1 }
	if !data_scrub_reference_matches(manifest, report) { return plan_error(c'data scrub report does not match the supplied reference') }
	mut text := [32768]char{}; size := encode_data_scrub_reference(manifest, report, &text[0])
	if size == 0 || finish_bundle_report(C.printf(c'%s', &text[0]) >= 0) != 0 { return 1 }
	for i in 0 .. report.count { if report.expected[i] != report.actual[i] { return 2 } }
	return 0
}
