// SPDX-License-Identifier: GPL-2.0-or-later
module volumecli

// Compare complete canonical saved metadata, including pool order and windows.
// Caller findings stay unchanged when either reference is invalid or differs.
@[direct_array_access]
fn compare_data_references(before &DataManifest, after &DataManifest, mut summary DataScrub) bool {
	if !data_manifest_valid(before) || !data_manifest_valid(after) { return false }
	mut first := [8768]u8{}; mut second := [8768]u8{}
	left := encode_bundle(unsafe { &before.set }, &first[0]); right := encode_bundle(unsafe { &after.set }, &second[0])
	if left == 0 || left != right { return false }
	for i in 0 .. left { if first[i] != second[i] { return false } }
	return compare_scrub_digests(before, unsafe { &after.digests }, mut summary)
}

@[direct_array_access]
fn data_reference_fingerprint(manifest &DataManifest, output &char) bool {
	mut bytes := [11392]u8{}; size := encode_data_manifest(manifest, &bytes[0]); if size == 0 { return false }
	mut context := unsafe { &DataSha256(C.alloca(sizeof(DataSha256))) }; unsafe { *context = DataSha256{} }
	mut digest := [32]u8{}; data_sha_init(mut context)
	return data_sha_update(mut context, &bytes[0], usize(size)) && data_sha_finish(context, unsafe { &digest })
		&& scrub_digest_text(unsafe { &digest }, output)
}

// Build the entire bounded report before any output. Both fingerprints cover
// all canonical metadata and digest bytes, not just the changed row records.
@[direct_array_access]
fn encode_data_reference_comparison(before &DataManifest, after &DataManifest, output &char) int {
	mut summary := DataScrub{}
	if !compare_data_references(before, after, mut summary) { return 0 }
	mut first := [65]char{}; mut second := [65]char{}
	if !data_reference_fingerprint(before, &first[0]) || !data_reference_fingerprint(after, &second[0]) { return 0 }
	mut length := int(C.snprintf(output, usize(scrub_report_max),
		c'format=VINIXDH1 operation=compared-data-references disks=%d mappings=%d stable=%d changed=%d algorithm=sha256 before_reference_sha256=%s after_reference_sha256=%s\n',
		before.set.count, before.digests.count, before.digests.count - summary.changed, summary.changed, &first[0], &second[0]))
	if length <= 0 || length >= scrub_report_max { return 0 }
	mut record := 0; mut old := [65]char{}; mut next := [65]char{}; mut identity := [41]char{}
	for disk in 0 .. before.set.count {
		key := unsafe { &before.set.plans[disk].key }; disk_identity(key, &identity[0])
		written := int(C.snprintf(unsafe { output + length }, usize(scrub_report_max - length),
			c'disk=%u disk_bytes=%lu sector=%lu identity=%s\n', u32(disk), key.bytes, key.sector, &identity[0]))
		if written <= 0 || written >= scrub_report_max - length { return 0 }; length += written
		for at := u32(0); at < before.set.plans[disk].count; at++ {
			row := before.set.plans[disk].rows[at]
			if !scrub_digest_text(unsafe { &before.digests.values[record] }, &old[0]) || !scrub_digest_text(unsafe { &after.digests.values[record] }, &next[0]) { return 0 }
			result := if summary.bits & (u64(1) << record) != 0 { unsafe { &char(c'changed') } } else { unsafe { &char(c'stable') } }
			count := int(C.snprintf(unsafe { output + length }, usize(scrub_report_max - length),
				c'disk=%u slot=%u offset=%lu bytes=%lu readonly=%lu result=%s before_sha256=%s after_sha256=%s\n',
				u32(disk), row.slot, row.offset, row.length, row.flags, result, &old[0], &next[0]))
			if count <= 0 || count >= scrub_report_max - length { return 0 }; length += count; record++
		}
	}
	return length
}

// Ordinary plain-data readers, no writer lock or physical discovery. The two
// independently pinned input owners remain alive through final output flushing.
@[direct_array_access]
fn data_reference_files(before_path &char, after_path &char) i32 {
	mut first := unsafe { &PlanEdit(C.alloca(sizeof(PlanEdit))) }; mut second := unsafe { &PlanEdit(C.alloca(sizeof(PlanEdit))) }
	mut before := unsafe { &DataManifest(C.alloca(sizeof(DataManifest))) }; mut after := unsafe { &DataManifest(C.alloca(sizeof(DataManifest))) }
	unsafe { *first = PlanEdit{}; *second = PlanEdit{}; *before = DataManifest{}; *after = DataManifest{} }
	defer { close_plan_edit(mut second) }; defer { close_plan_edit(mut first) }
	if !open_plan_edit(before_path, mut first, false) || !read_data_manifest(first.source, mut before)
		|| !open_plan_edit(after_path, mut second, false) || !read_data_manifest(second.source, mut after) { return 1 }
	mut summary := DataScrub{}
	if !compare_data_references(before, after, mut summary) { return plan_error(c'invalid data references or different saved metadata') }
	mut text := [32768]char{}; length := encode_data_reference_comparison(before, after, &text[0])
	if length == 0 || finish_bundle_report(C.printf(c'%s', &text[0]) >= 0) != 0 { return 1 }
	return if summary.changed == 0 { 0 } else { 2 }
}
