// SPDX-License-Identifier: GPL-2.0-or-later
module volumecli

import crypto.sha256
import encoding.hex

fn monitor_native_fixture(sector u64, kind u32, flags u64, mut manifest DataManifest) {
	manifest = DataManifest{}
	for disk in 0 .. 2 {
		mut plan := Plan{count: 1, key: DiskKey{bytes: u64(-1) & ~(sector - 1), sector: sector, kind: kind}}; plan.key.id[0] = u8(disk + 1); if kind == 2 { plan.key.id[15] = 0x83 }
		plan.rows[0] = Request{slot: u32(disk * 63), offset: 8192, length: 73728, flags: if disk == 0 { flags } else { 1 - flags }}; assert append_plan(mut manifest.set, &plan)
		manifest.digests.disks[disk] = u32(disk); manifest.digests.slots[disk] = plan.rows[0].slot; for byte in 0 .. 32 { manifest.digests.values[disk][byte] = u8(disk * 11 + byte * 7) }
	}
	manifest.digests.count = 2
}
fn monitor_native_expected(manifest &DataManifest, observed &DataDigests, sample u64, changed_samples u64) string {
	mut bytes := [11392]u8{}; size := encode_data_manifest(manifest, &bytes[0]); mut changed := 0; for i in 0 .. observed.count { if manifest.digests.values[i] != observed.values[i] { changed++ } }
	mut text := 'format=VINIXDM1 operation=monitored-data sample=${sample} changed_samples=${changed_samples} session_changed=${int(changed_samples != 0)}\n' +
		'format=VINIXSR1 operation=scrubbed-data disks=${manifest.set.count} mappings=${observed.count} matched=${observed.count - changed} changed=${changed} algorithm=sha256 reference_sha256=' + hex.encode(sha256.sum(bytes[..size])) + '\n'
	mut record := 0
	for disk in 0 .. manifest.set.count { for at in 0 .. int(manifest.set.plans[disk].count) { row := manifest.set.plans[disk].rows[at]; text += 'disk=${disk} slot=${row.slot} offset=${row.offset} bytes=${row.length} readonly=${row.flags} result=${if observed.values[record] == manifest.digests.values[record] { 'match' } else { 'changed' }} expected_sha256=' + hex.encode(manifest.digests.values[record][..]) + ' actual_sha256=' + hex.encode(observed.values[record][..]) + '\n'; record++ } }
	return text
}
fn test_monitor_all_three_sample_histories_eight_profiles_latched_findings_exact_complete_output() {
	for sector in [u64(512), u64(4096)] { for kind in [u32(1), u32(2)] { for flags in [u64(0), u64(1)] {
		mut manifest := DataManifest{}; monitor_native_fixture(sector, kind, flags, mut manifest)
		for history in 0 .. 64 { mut changed_samples := u64(0); for sample in 1 .. 4 {
			mask := (history >> ((sample - 1) * 2)) & 3; mut observed := manifest.digests; for row in 0 .. 2 { if mask & (1 << row) != 0 { observed.values[row][sample * 7] ^= 1 } }; if mask != 0 { changed_samples++ }
			mut output := [33024]char{init: char(91)}; size := encode_data_monitor(&manifest, &observed, u64(sample), changed_samples, &output[0]); expected := monitor_native_expected(&manifest, &observed, u64(sample), changed_samples)
			assert size == expected.len && unsafe { tos(&u8(&output[0]), size) } == expected && output[size] == 0 && output[size + 1] == char(91)
		} }
	} } }
}
fn test_monitor_invalid_later_records_session_counters_and_maximum_snapshot() {
	mut manifest := DataManifest{}; monitor_native_fixture(4096, 2, 1, mut manifest); mut observed := manifest.digests; observed.values[1][31] ^= 1
	for fault in 0 .. 5 { mut bad := observed; if fault == 0 { bad.count-- } else if fault == 1 { bad.disks[1] = 0 } else if fault == 2 { bad.slots[1] = 62 }
		mut output := [33024]char{init: char(91)}; saved := output
		assert encode_data_monitor(&manifest, &bad, if fault == 3 { u64(0) } else { u64(1) }, if fault == 4 { u64(0) } else { u64(1) }, &output[0]) == 0 && output == saved
	}
	mut output := [33024]char{}; assert encode_data_monitor(&manifest, &observed, 1, 2, &output[0]) == 0
	size := encode_data_monitor(&manifest, &observed, u64(-1), u64(-1), &output[0]); assert size > 0 && unsafe { tos(&u8(&output[0]), size) } == monitor_native_expected(&manifest, &observed, u64(-1), u64(-1))
	manifest = DataManifest{}; observed = DataDigests{}
	for disk in 0 .. 64 { mut plan := Plan{count: 1, key: DiskKey{bytes: u64(-1) & ~u64(4095), sector: 4096, kind: 2}}; plan.key.id[0] = u8(disk + 1); plan.key.id[15] = 0x83; plan.rows[0] = Request{slot: u32(63 - disk), offset: (u64(0x7fffffffffffffff) & ~u64(4095)) - 4096, length: 4096, flags: u64(disk & 1)}; assert append_plan(mut manifest.set, &plan); manifest.digests.disks[disk] = u32(disk); manifest.digests.slots[disk] = plan.rows[0].slot; manifest.digests.count++ }
	observed = manifest.digests; for row in 0 .. 64 { observed.values[row][31] = 1 }; n := encode_data_monitor(&manifest, &observed, u64(-1), u64(-1), &output[0]); assert n > 15000 && n < data_monitor_report_max && unsafe { tos(&u8(&output[0]), n) } == monitor_native_expected(&manifest, &observed, u64(-1), u64(-1))
	for disk in 0 .. 64 { manifest.set.plans[disk].count = 0 }; manifest.set.slots = 0; manifest.digests = DataDigests{}; observed = manifest.digests; assert encode_data_monitor(&manifest, &observed, 1, 0, &output[0]) > 0
}
fn test_monitor_cli_arity_decimal_bounds_and_missing_reference_before_discovery() {
	unsafe { mut args := [&char(c'vinix-volume'), &char(c'monitor-data-auto'), &char(c'/missing-monitor-reference'), &char(c'0'), &char(c'1'), &char(c'extra'), &char(nil)]!
		for count in [2, 3, 4, 6, 7] { assert run(count, &args[0]) == 2 }
		for at in [2, 3, 4] { saved := args[at]; args[at] = &char(c''); assert run(5, &args[0]) == 2; args[at] = saved }
		for text in [&char(c'-1'), &char(c'86401'), &char(c'18446744073709551616')]! { args[3] = text; assert run(5, &args[0]) == 2 }; args[3] = &char(c'0'); args[4] = &char(c'0'); assert run(5, &args[0]) == 2; args[4] = &char(c'1'); assert run(5, &args[0]) == 1
		args[3] = &char(c'1'); args[4] = &char(c'0'); assert run(5, &args[0]) == 1; args[3] = &char(c'86400'); args[4] = &char(c'18446744073709551615'); assert run(5, &args[0]) == 1
	}
}
