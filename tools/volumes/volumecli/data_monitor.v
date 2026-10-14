// SPDX-License-Identifier: GPL-2.0-or-later
module volumecli

const data_monitor_report_max = scrub_report_max + 256

// A monitor sample contains a complete ordinary scrub snapshot after its
// session prefix. Construct everything privately before sending it to stdout.
@[direct_array_access]
fn encode_data_monitor(manifest &DataManifest, observed &DataDigests, sample u64, changed_samples u64, output &char) int {
	mut summary := DataScrub{}
	if sample == 0 || changed_samples > sample || !compare_scrub_digests(manifest, observed, mut summary)
		|| (summary.changed != 0 && changed_samples == 0) { return 0 }
	length := int(C.snprintf(output, usize(256), c'format=VINIXDM1 operation=monitored-data sample=%lu changed_samples=%lu session_changed=%lu\n', sample, changed_samples, u64(changed_samples != 0)))
	if length <= 0 || length >= 256 { return 0 }
	report := encode_scrub_report(manifest, observed, unsafe { output + length })
	return if report > 0 { length + report } else { 0 }
}

// Workspaces and owners are allocated once, outside the sample loop. Never
// rediscover a replacement device or reload a different reference mid-session.
@[direct_array_access]
fn monitor_manifest_data(path &char, interval u32, samples u64) i32 {
	if interval > 86400 || (interval == 0 && samples == 0) { return plan_error(c'invalid checksum monitor interval or sample count') }
	mut source := unsafe { &PlanEdit(C.alloca(sizeof(PlanEdit))) }; mut manifest := unsafe { &DataManifest(C.alloca(sizeof(DataManifest))) }
	mut pins := unsafe { &DataPins(C.alloca(sizeof(DataPins))) }; mut observed := unsafe { &DataDigests(C.alloca(sizeof(DataDigests))) }
	mut summary := unsafe { &DataScrub(C.alloca(sizeof(DataScrub))) }
	unsafe { *source = PlanEdit{}; *manifest = DataManifest{}; *pins = DataPins{}; *observed = DataDigests{}; *summary = DataScrub{} }
	defer { close_plan_edit(mut source) }; defer { close_data_pins(mut pins) }
	if !open_plan_edit(path, mut source, false) || !read_data_manifest(source.source, mut manifest)
		|| !open_data_pins(unsafe { &manifest.set }, unsafe { nil }, mut pins) { return 1 }
	mut text := [33024]char{}; mut sample := u64(1); mut changed_samples := u64(0)
	for {
		if !recheck_data_pins(unsafe { &manifest.set }, pins)
			|| !read_data_digests(unsafe { &manifest.set }, pins, unsafe { nil }, mut observed)
			|| !recheck_data_pins(unsafe { &manifest.set }, pins) || !compare_scrub_digests(manifest, observed, mut summary) { return 1 }
		if summary.changed != 0 && changed_samples != u64(-1) { changed_samples++ }
		if encode_data_monitor(manifest, observed, sample, changed_samples, &text[0]) == 0
			|| !recheck_data_pins(unsafe { &manifest.set }, pins) || finish_bundle_report(C.printf(c'%s', &text[0]) >= 0) != 0 { return 1 }
		if samples != 0 && sample == samples { return if changed_samples == 0 { 0 } else { 2 } }
		if sample != u64(-1) { sample++ }
		mut remaining := interval; for remaining != 0 { remaining = C.sleep(remaining) }
	}
	return 1
}
