// SPDX-License-Identifier: GPL-2.0-or-later
module volumecli

const scrub_report_max = 32768

struct DataScrub {
mut:
	changed int
	bits u64
}

// Compare only complete canonical digest lists. A malformed later record must
// preserve the caller just as a failed device scan preserves the saved report.
@[direct_array_access]
fn compare_scrub_digests(manifest &DataManifest, observed &DataDigests, mut summary DataScrub) bool {
	if !data_manifest_valid(manifest) || observed.count != manifest.digests.count { return false }
	mut candidate := DataScrub{}
	for i in 0 .. observed.count {
		if observed.disks[i] != manifest.digests.disks[i] || observed.slots[i] != manifest.digests.slots[i] { return false }
		mut changed := false
		for byte in 0 .. 32 { if observed.values[i][byte] != manifest.digests.values[i][byte] { changed = true } }
		if changed { candidate.bits |= u64(1) << i; candidate.changed++ }
	}
	summary = candidate; return true
}

@[direct_array_access]
fn scrub_digest_text(value &[32]u8, output &char) bool {
	for byte in 0 .. 32 {
		if C.snprintf(unsafe { output + byte * 2 }, usize(65 - byte * 2), c'%02x', u32(value[byte])) != 2 { return false }
	}
	return true
}

// The largest canonical 64-row report fits the fixed caller-owned workspace.
// A formatting failure returns no publishable length, including after rows.
@[direct_array_access]
fn encode_scrub_report(manifest &DataManifest, observed &DataDigests, output &char) int {
	mut summary := unsafe { &DataScrub(C.alloca(sizeof(DataScrub))) }; unsafe { *summary = DataScrub{} }
	if !compare_scrub_digests(manifest, observed, mut summary) { return 0 }
	mut bytes := [11392]u8{}; size := encode_data_manifest(manifest, &bytes[0]); if size == 0 { return 0 }
	mut context := unsafe { &DataSha256(C.alloca(sizeof(DataSha256))) }; unsafe { *context = DataSha256{} }
	data_sha_init(mut context); mut digest := [32]u8{}; mut fingerprint := [65]char{}
	if !data_sha_update(mut context, &bytes[0], usize(size)) || !data_sha_finish(context, unsafe { &digest })
		|| !scrub_digest_text(unsafe { &digest }, &fingerprint[0]) { return 0 }
	mut length := int(C.snprintf(output, usize(scrub_report_max),
		c'format=VINIXSR1 operation=scrubbed-data disks=%d mappings=%d matched=%d changed=%d algorithm=sha256 reference_sha256=%s\n',
		manifest.set.count, observed.count, observed.count - summary.changed, summary.changed, &fingerprint[0]))
	if length <= 0 || length >= scrub_report_max { return 0 }
	mut record := 0; mut expected := [65]char{}; mut actual := [65]char{}
	for disk in 0 .. manifest.set.count { for at := u32(0); at < manifest.set.plans[disk].count; at++ {
		row := manifest.set.plans[disk].rows[at]
		if !scrub_digest_text(unsafe { &manifest.digests.values[record] }, &expected[0]) || !scrub_digest_text(unsafe { &observed.values[record] }, &actual[0]) { return 0 }
		result := if summary.bits & (u64(1) << record) != 0 { unsafe { &char(c'changed') } } else { unsafe { &char(c'match') } }
		written := int(C.snprintf(unsafe { output + length }, usize(scrub_report_max - length),
			c'disk=%u slot=%u offset=%lu bytes=%lu readonly=%lu result=%s expected_sha256=%s actual_sha256=%s\n',
			u32(disk), row.slot, row.offset, row.length, row.flags, result, &expected[0], &actual[0]))
		if written <= 0 || written >= scrub_report_max - length { return 0 }; length += written; record++
	} }
	return length
}

// Mismatches are findings, not an incomplete scan: read every desired extent
// before comparing, recheck every pin, then publish one durable complete report.
// Exit 0 means clean, 2 means changed data, and 1 means execution/report failure.
@[direct_array_access]
fn scrub_manifest_data(path &char, report &char, devices &DataDevices) i32 {
	mut source := unsafe { &PlanEdit(C.alloca(sizeof(PlanEdit))) }; mut destination := unsafe { &PlanEdit(C.alloca(sizeof(PlanEdit))) }
	mut manifest := unsafe { &DataManifest(C.alloca(sizeof(DataManifest))) }; mut pins := unsafe { &DataPins(C.alloca(sizeof(DataPins))) }
	mut observed := unsafe { &DataDigests(C.alloca(sizeof(DataDigests))) }; mut summary := unsafe { &DataScrub(C.alloca(sizeof(DataScrub))) }
	unsafe { *source = PlanEdit{}; *destination = PlanEdit{}; *manifest = DataManifest{}; *pins = DataPins{}; *observed = DataDigests{}; *summary = DataScrub{} }
	defer { close_plan_edit(mut destination) }; defer { close_plan_edit(mut source) }; defer { close_data_pins(mut pins) }
	if !open_plan_destination(report, mut destination, true) || !data_destination_valid(destination) || !open_plan_edit(path, mut source, false)
		|| !distinct_data_destination(source, destination) || !read_data_manifest(source.source, mut manifest)
		|| !data_devices_valid(unsafe { &manifest.set }, devices) { return 1 }
	if !open_data_pins(unsafe { &manifest.set }, devices, mut pins) || !recheck_data_pins(unsafe { &manifest.set }, pins)
		|| !read_data_digests(unsafe { &manifest.set }, pins, unsafe { nil }, mut observed)
		|| !recheck_data_pins(unsafe { &manifest.set }, pins) || !compare_scrub_digests(manifest, observed, mut summary) { return 1 }
	mut text := [32768]char{}; length := encode_scrub_report(manifest, observed, &text[0])
	if length == 0 || !data_destination_valid(destination)
		|| (pins.automatic && !recheck_data_pins(unsafe { &manifest.set }, pins))
		|| !publish_edit_bytes(destination, unsafe { &u8(&text[0]) }, length) { return 1 }
	if finish_bundle_report(C.printf(c'%s', &text[0]) >= 0) != 0 { return 1 }
	return if summary.changed == 0 { 0 } else { 2 }
}
