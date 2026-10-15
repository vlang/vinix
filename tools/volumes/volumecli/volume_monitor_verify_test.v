// SPDX-License-Identifier: GPL-2.0-or-later
module volumecli
import crypto.sha256
import encoding.hex

fn cipher_verify_fixture(sector u64, kind u32, flags u64, mut disk DiskKey, mut row Request, mut reference [128]u8) {
	disk = DiskKey{bytes: u64(-1) & ~(sector - 1), sector: sector, kind: kind}; disk.id[0] = 1; disk.id[3] = 0x83; if kind == 2 { disk.id[15] = 0x9b }
	row = Request{slot: 63, offset: 8192, length: 73728, flags: flags}; mut expected := [32]u8{}; for i in 0 .. 32 { expected[i] = u8(i * 7 + 3) }; assert encode_volume_ciphertext(&disk, &row, &expected[0], &reference[0])
}
fn cipher_verify_observed(reference [128]u8, state int) [32]u8 { mut actual := [32]u8{}; for i in 0 .. 32 { actual[i] = reference[80 + i] }; actual[31] ^= u8(state); return actual }
fn cipher_verify_frame(reference [128]u8, disk &DiskKey, row &Request, state int, recovery bool, sample int, changed int) string {
	actual := cipher_verify_observed(reference, state); expected := cipher_verify_observed(reference, 0); identity := if disk.kind == 1 { 'mbr:83000001' } else { 'gpt:83000001-0000-0000-0000-00000000009b' }
	return 'format=VINIXCM1 operation=monitored-ciphertext source=${if recovery { 'recovery' } else { 'volume' }} sample=${sample} changed_samples=${changed} session_changed=${int(changed != 0)}\nformat=VINIXCS1 operation=scrubbed-ciphertext mappings=1 matched=${int(state == 0)} changed=${int(state != 0)} algorithm=sha256 reference_sha256=' + hex.encode(sha256.sum(reference[..])) + '\ndisk_bytes=${disk.bytes} sector=${disk.sector} identity=${identity} slot=${row.slot} offset=${row.offset} bytes=${row.length} readonly=${row.flags} result=${if state == 0 { 'match' } else { 'changed' }} expected_sha256=' + hex.encode(expected[..]) + ' actual_sha256=' + hex.encode(actual[..]) + '\n'
}
fn cipher_verify_wanted(reference [128]u8, disk &DiskKey, row &Request, states []int, recovery bool, transcript string) string {
	mut changed := 0; mut classes := [4]int{}; table := [[0, 1, 1]!, [2, 0, 3]!, [2, 3, 0]!]!; for i, state in states { if state != 0 { changed++ }; if i != 0 { classes[table[states[i - 1]][state]]++ } }
	actual := cipher_verify_observed(reference, states.last()); expected := cipher_verify_observed(reference, 0); identity := if disk.kind == 1 { 'mbr:83000001' } else { 'gpt:83000001-0000-0000-0000-00000000009b' }
	return 'format=VINIXCM1 operation=verified-ciphertext-monitor source=${if recovery { 'recovery' } else { 'volume' }} mappings=1 samples=${states.len} changed_samples=${changed} session_changed=${int(changed != 0)} final_changed=${int(states.last() != 0)} stable=${classes[0]} new_changes=${classes[1]} restored=${classes[2]} changed_again=${classes[3]} algorithm=sha256 reference_sha256=' + hex.encode(sha256.sum(reference[..])) + ' transcript_sha256=' + sha256.hexhash(transcript) + '\ndisk_bytes=${disk.bytes} sector=${disk.sector} identity=${identity} slot=${row.slot} offset=${row.offset} bytes=${row.length} readonly=${row.flags} result=${if states.last() == 0 { 'match' } else { 'changed' }} expected_sha256=' + hex.encode(expected[..]) + ' final_sha256=' + hex.encode(actual[..]) + '\n'
}
fn cipher_verify_prefix(frame string) int { return (frame.index('\n') or { panic('missing prefix') }) + 1 }
fn test_cipher_verify_all27_histories_eight_profiles_both_domains_complete_independent_summaries() {
	for sector in [u64(512), u64(4096)] { for kind in [u32(1), u32(2)] { for flags in [u64(0), u64(1)] { mut disk := DiskKey{}; mut row := Request{}; mut reference := [128]u8{}; cipher_verify_fixture(sector, kind, flags, mut disk, mut row, mut reference)
		for recovery in [false, true] { for sequence in 0 .. 27 { states := [sequence % 3, (sequence / 3) % 3, sequence / 9]; mut history := CipherMonitorHistory{}; mut transcript := ''; mut changed := 0
			for i, state in states { if state != 0 { changed++ }; frame := cipher_verify_frame(reference, &disk, &row, state, recovery, i + 1, changed); assert accept_ciphertext_monitor(&reference[0], frame.str, frame.len, cipher_verify_prefix(frame), mut history); transcript += frame }
			sum := sha256.sum(transcript.bytes()); mut digest := [32]u8{}; for i in 0 .. 32 { digest[i] = sum[i] }; mut text := [2048]char{init: char(91)}; size := encode_ciphertext_monitor_history(&reference[0], &history, &digest, &text[0]); wanted := cipher_verify_wanted(reference, &disk, &row, states, recovery, transcript)
			assert size == wanted.len && unsafe { tos(&u8(&text[0]), size) } == wanted && text[size] == 0 && text[size + 1] == char(91)
		} }
	} } }
}
fn test_cipher_verify_later_mutations_domain_changes_reference_and_partial_frames_preserve_state() {
	mut disk := DiskKey{}; mut row := Request{}; mut reference := [128]u8{}; cipher_verify_fixture(4096, 2, 1, mut disk, mut row, mut reference); first := cipher_verify_frame(reference, &disk, &row, 1, true, 1, 1); second := cipher_verify_frame(reference, &disk, &row, 0, true, 2, 1); mut history := CipherMonitorHistory{}; assert accept_ciphertext_monitor(&reference[0], first.str, first.len, cipher_verify_prefix(first), mut history); saved := history
	for at in 0 .. second.len { mut bad := second.bytes(); bad[at] = `~`; assert !accept_ciphertext_monitor(&reference[0], bad.data, bad.len, cipher_verify_prefix(second), mut history) && history == saved }
	for size in 0 .. second.len { assert !accept_ciphertext_monitor(&reference[0], second.str, size, cipher_verify_prefix(second), mut history) && history == saved }
	for at in 0 .. 128 { mut bad := reference; bad[at] ^= 1; assert !accept_ciphertext_monitor(&bad[0], second.str, second.len, cipher_verify_prefix(second), mut history) && history == saved }
	for pair in [['source=recovery', 'source=volume'], ['sample=2', 'sample=1'], ['sample=2', 'sample=3'], ['sample=2', 'sample=02'], ['sample=2', 'sample=18446744073709551616'], ['changed_samples=1', 'changed_samples=0'], ['session_changed=1', 'session_changed=0'], ['readonly=1', 'readonly=0'], ['sector=4096', 'sector=512']] { bad := second.replace(pair[0], pair[1]); assert !accept_ciphertext_monitor(&reference[0], bad.str, bad.len, cipher_verify_prefix(bad), mut history) && history == saved }
	disk.id[0] = 2; mut unrelated := reference; expected := cipher_verify_observed(reference, 0); assert encode_volume_ciphertext(&disk, &row, &expected[0], &unrelated[0]); assert !accept_ciphertext_monitor(&unrelated[0], second.str, second.len, cipher_verify_prefix(second), mut history) && history == saved
	assert accept_ciphertext_monitor(&reference[0], second.str, second.len, cipher_verify_prefix(second), mut history) && history.restored == 1 && history.changed_samples == 1
}
fn test_cipher_verify_summary_full_width_and_cli_bounds() {
	mut disk := DiskKey{}; mut row := Request{}; mut reference := [128]u8{}; cipher_verify_fixture(4096, 2, 1, mut disk, mut row, mut reference); expected := cipher_verify_observed(reference, 0); row.offset = (u64(0x7fffffffffffffff) & ~u64(4095)) - 4096; row.length = 4096; assert encode_volume_ciphertext(&disk, &row, &expected[0], &reference[0])
	piece := (u64(-1) - 1) / 4; mut history := CipherMonitorHistory{samples: u64(-1), changed_samples: u64(-1), new_changes: piece, restored: piece, changed_again: piece, stable: u64(-1) - 1 - 3 * piece, recovery: true, actual: expected}; mut digest := [32]u8{}; mut text := [2048]char{}; n := encode_ciphertext_monitor_history(&reference[0], &history, &digest, &text[0]); assert n > 800 && n < 2048 && text[n] == 0
	history.restored = u64(-1) - 1; assert encode_ciphertext_monitor_history(&reference[0], &history, &digest, &text[0]) == 0
	unsafe { mut args := [&char(c'vinix-volume'), &char(c'verify-volume-monitor'), &char(c'/missing-reference'), &char(c'/missing-transcript'), &char(c'extra'), &char(nil)]!; for count in [2, 3, 5, 6] { assert run(count, &args[0]) == 2 }; for at in [2, 3] { old := args[at]; args[at] = &char(c''); assert run(4, &args[0]) == 2; args[at] = old }; assert run(4, &args[0]) == 1 }
}
