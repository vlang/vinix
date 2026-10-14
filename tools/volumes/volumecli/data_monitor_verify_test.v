// SPDX-License-Identifier: GPL-2.0-or-later
module volumecli
import crypto.sha256
import encoding.hex

fn monitor_verify_prefix(frame string) int { return (frame.index('\n') or { panic('missing sample prefix') }) + 1 }

fn monitor_verify_fixture(sector u64, kind u32, flags u64, mut manifest DataManifest) {
	manifest = DataManifest{}
	for disk in 0 .. 2 { mut plan := Plan{count: 1, key: DiskKey{bytes: 1048576, sector: sector, kind: kind}}; plan.key.id[0] = u8(disk + 1); if kind == 2 { plan.key.id[15] = 0x83 }; plan.rows[0] = Request{slot: u32(63 - disk), offset: 8192, length: 4096, flags: if disk == 0 { flags } else { 1 - flags }}; assert append_plan(mut manifest.set, &plan); manifest.digests.disks[disk] = u32(disk); manifest.digests.slots[disk] = plan.rows[0].slot; for i in 0 .. 32 { manifest.digests.values[disk][i] = u8(i * 7 + disk * 11) }; manifest.digests.count++ }
}
fn monitor_verify_frame(manifest &DataManifest, states [2]int, sample u64, changed_samples u64) string {
	mut observed := manifest.digests; for i in 0 .. 2 { if states[i] > 0 { observed.values[i][31] ^= u8(states[i]) } }; mut output := [33024]char{}; size := encode_data_monitor(manifest, &observed, sample, changed_samples, &output[0]); assert size > 0; return unsafe { tos(&u8(&output[0]), size) }.clone()
}
fn monitor_verify_expected(manifest &DataManifest, transcript string, states [3][2]int) string {
	mut reference := [11392]u8{}; size := encode_data_manifest(manifest, &reference[0]); mut changed_samples := 0; mut final_changed := 0
	for sample in states { if sample[0] != 0 || sample[1] != 0 { changed_samples++ } }; for value in states[2] { if value != 0 { final_changed++ } }
	mut text := 'format=VINIXDM1 operation=verified-data-monitor disks=2 mappings=2 samples=3 changed_samples=${changed_samples} session_changed=${int(changed_samples != 0)} final_changed=${final_changed} algorithm=sha256 reference_sha256=' + hex.encode(sha256.sum(reference[..size])) + ' transcript_sha256=' + sha256.hexhash(transcript) + '\n'
	// Independent transition classification table: clean, corruption A/B.
	classes := [[0, 1, 1]!, [2, 0, 3]!, [2, 3, 0]!]!
	for disk in 0 .. 2 { key := manifest.set.plans[disk].key; identity := if key.kind == 1 { 'mbr:0000000${disk + 1}' } else { 'gpt:0000000${disk + 1}-0000-0000-0000-000000000083' }; row := manifest.set.plans[disk].rows[0]; mut counts := [4]int{}; mut changed := 0
		for sample in 0 .. 3 { if states[sample][disk] != 0 { changed++ }; if sample > 0 { counts[classes[states[sample - 1][disk]][states[sample][disk]]]++ } }; mut actual := manifest.digests.values[disk]; if states[2][disk] != 0 { actual[31] ^= u8(states[2][disk]) }
		text += 'disk=${disk} disk_bytes=${key.bytes} sector=${key.sector} identity=${identity}\ndisk=${disk} slot=${row.slot} offset=${row.offset} bytes=${row.length} readonly=${row.flags} changed_samples=${changed} stable=${counts[0]} new_changes=${counts[1]} restored=${counts[2]} changed_again=${counts[3]} final=${if states[2][disk] == 0 { 'match' } else { 'changed' }} expected_sha256=' + hex.encode(manifest.digests.values[disk][..]) + ' final_sha256=' + hex.encode(actual[..]) + '\n'
	}; return text
}
fn test_monitor_verify_all729_three_sample_histories_eight_profiles_exact_bound_summary() {
	for sector in [u64(512), u64(4096)] { for kind in [u32(1), u32(2)] { for flags in [u64(0), u64(1)] { mut manifest := DataManifest{}; monitor_verify_fixture(sector, kind, flags, mut manifest)
		for history in 0 .. 729 { mut sequence := history; mut states := [3][2]int{}; mut summary := DataMonitorHistory{}; mut transcript := ''; mut changed_samples := u64(0)
			for sample in 0 .. 3 { states[sample] = [sequence % 3, (sequence / 3) % 3]!; sequence /= 9; if states[sample][0] != 0 || states[sample][1] != 0 { changed_samples++ }; frame := monitor_verify_frame(&manifest, states[sample], u64(sample + 1), changed_samples); prefix := monitor_verify_prefix(frame); assert accept_data_monitor_sample(&manifest, frame.str, frame.len, prefix, mut summary); transcript += frame }
			mut digest := [32]u8{}; sum := sha256.sum(transcript.bytes()); for i in 0 .. 32 { digest[i] = sum[i] }; mut output := [49152]char{init: char(91)}; size := encode_data_monitor_history(&manifest, &summary, &digest, &output[0]); expected := monitor_verify_expected(&manifest, transcript, states)
			assert size == expected.len && unsafe { tos(&u8(&output[0]), size) } == expected && output[size] == 0 && output[size + 1] == char(91)
		}
	} } }
}
fn test_monitor_verify_invalid_prefix_reference_later_row_and_counter_preserve_summary() {
	mut manifest := DataManifest{}; monitor_verify_fixture(4096, 2, 1, mut manifest); first := monitor_verify_frame(&manifest, [1, 2]!, 1, 1); mut summary := DataMonitorHistory{}; assert accept_data_monitor_sample(&manifest, first.str, first.len, monitor_verify_prefix(first), mut summary); saved := summary
	second := monitor_verify_frame(&manifest, [0, 0]!, 2, 1)
	for pair in [['sample=2', 'sample=1'], ['sample=2', 'sample=3'], ['sample=2', 'sample=02'], ['sample=2', 'sample=18446744073709551616'], ['changed_samples=1', 'changed_samples=0'], ['session_changed=1', 'session_changed=0'], ['session_changed=1', 'session_changed=2'], ['slot=62', 'slot=61'], ['sector=4096', 'sector=512'], ['readonly=0', 'readonly=1']] {
		if !second.contains(pair[0]) { continue }; bad := second.replace(pair[0], pair[1]); assert !accept_data_monitor_sample(&manifest, bad.str, bad.len, monitor_verify_prefix(bad), mut summary) && summary == saved
	}
	for size in 0 .. second.len { assert !accept_data_monitor_sample(&manifest, second.str, size, monitor_verify_prefix(second), mut summary) && summary == saved }
	for byte in 0 .. second.len { if second[byte] >= `a` && second[byte] <= `f` { mut bad := second.bytes(); bad[byte] = `G`; assert !accept_data_monitor_sample(&manifest, bad.data, bad.len, monitor_verify_prefix(second), mut summary) && summary == saved } }
	mut unrelated := manifest; unrelated.set.plans[1].key.id[0] = 3; assert !accept_data_monitor_sample(&unrelated, second.str, second.len, monitor_verify_prefix(second), mut summary) && summary == saved
	assert accept_data_monitor_sample(&manifest, second.str, second.len, monitor_verify_prefix(second), mut summary) && summary.changed_samples == 1 && summary.restored[0] == 1 && summary.restored[1] == 1
}
fn test_monitor_verify_maximum_summary_width_empty_rows_and_cli() {
	mut manifest := DataManifest{}; mut history := DataMonitorHistory{samples: u64(-1), changed_samples: u64(-1)}
	for disk in 0 .. 64 { mut plan := Plan{count: 1, key: DiskKey{bytes: u64(-1) & ~u64(4095), sector: 4096, kind: 2}}; plan.key.id[0] = u8(disk + 1); plan.key.id[15] = 0x83; plan.rows[0] = Request{slot: u32(63 - disk), offset: u64(0x5ffffffffffff000), length: u64(0x1ffffffffffff000), flags: u64(disk & 1)}; assert append_plan(mut manifest.set, &plan); manifest.digests.disks[disk] = u32(disk); manifest.digests.slots[disk] = plan.rows[0].slot; manifest.digests.count++; history.changed[disk] = history.changed_samples / 2; piece := (history.samples - 1) / 4; history.new_changes[disk] = piece; history.restored[disk] = piece; history.changed_again[disk] = piece; history.stable[disk] = history.samples - 1 - 3 * piece; history.actual[disk][31] = 1 }
	mut digest := [32]u8{}; mut output := [49152]char{}; n := encode_data_monitor_history(&manifest, &history, &digest, &output[0]); assert n > 32768 && n < data_monitor_history_max && output[n] == 0
	history.restored[63] = history.samples - 1; assert encode_data_monitor_history(&manifest, &history, &digest, &output[0]) == 0
	for disk in 0 .. 64 { manifest.set.plans[disk].count = 0 }; manifest.set.slots = 0; manifest.digests = DataDigests{}; history = DataMonitorHistory{samples: 1}; assert encode_data_monitor_history(&manifest, &history, &digest, &output[0]) > 0
	unsafe { mut args := [&char(c'vinix-volume'), &char(c'verify-data-monitor'), &char(c'/missing-reference'), &char(c'/missing-transcript'), &char(c'extra'), &char(nil)]!; for count in [2, 3, 5, 6] { assert run(count, &args[0]) == 2 }; for at in [2, 3] { saved := args[at]; args[at] = &char(c''); assert run(4, &args[0]) == 2; args[at] = saved }; assert run(4, &args[0]) == 1 }
}
