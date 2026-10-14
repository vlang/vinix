// SPDX-License-Identifier: GPL-2.0-or-later
module volumecli
import crypto.sha256
import encoding.hex

fn cipher_monitor_native_fixture(sector u64, kind u32, flags u64, mut disk DiskKey, mut row Request, expected &u8, reference &u8) {
	disk = DiskKey{bytes: u64(-1) & ~(sector - 1), sector: sector, kind: kind}; disk.id[0] = 1; disk.id[3] = 0x83; if kind == 2 { disk.id[15] = 0x9b }
	row = Request{slot: 63, offset: 8192, length: 73728, flags: flags}
	unsafe { for i in 0 .. 32 { expected[i] = u8(i * 7 + 3) } }; assert encode_volume_ciphertext(unsafe { &disk }, unsafe { &row }, expected, reference)
}
fn cipher_monitor_native_expected(reference &u8, disk &DiskKey, row &Request, observed &u8, recovery bool, sample u64, changed_samples u64) string {
	mut expected := [32]u8{}; mut actual := [32]u8{}; mut encoded := [128]u8{}; unsafe { for i in 0 .. 32 { expected[i] = reference[80 + i]; actual[i] = observed[i] }; for i in 0 .. 128 { encoded[i] = reference[i] } }
	changed := expected != actual; identity := if disk.kind == 1 { 'mbr:83000001' } else { 'gpt:83000001-0000-0000-0000-00000000009b' }
	return 'format=VINIXCM1 operation=monitored-ciphertext source=${if recovery { 'recovery' } else { 'volume' }} sample=${sample} changed_samples=${changed_samples} session_changed=${int(changed_samples != 0)}\n' +
		'format=VINIXCS1 operation=scrubbed-ciphertext mappings=1 matched=${int(!changed)} changed=${int(changed)} algorithm=sha256 reference_sha256=' + hex.encode(sha256.sum(encoded[..])) + '\n' +
		'disk_bytes=${disk.bytes} sector=${disk.sector} identity=${identity} slot=${row.slot} offset=${row.offset} bytes=${row.length} readonly=${row.flags} result=${if changed { 'changed' } else { 'match' }} expected_sha256=' + hex.encode(expected[..]) + ' actual_sha256=' + hex.encode(actual[..]) + '\n'
}
fn test_cipher_monitor_complete_eight_histories_eight_profiles_both_domains() {
	for sector in [u64(512), u64(4096)] { for kind in [u32(1), u32(2)] { for flags in [u64(0), u64(1)] {
		mut disk := DiskKey{}; mut row := Request{}; mut expected := [32]u8{}; mut reference := [128]u8{}; cipher_monitor_native_fixture(sector, kind, flags, mut disk, mut row, &expected[0], &reference[0])
		for recovery in [false, true] { for history in 0 .. 8 { mut changed_samples := u64(0); for sample in 1 .. 4 {
			mut observed := expected; if history & (1 << (sample - 1)) != 0 { observed[sample * 7] ^= 1; changed_samples++ }
			mut output := [2048]char{init: char(91)}; size := encode_ciphertext_monitor(&reference[0], &observed[0], recovery, u64(sample), changed_samples, &output[0]); wanted := cipher_monitor_native_expected(&reference[0], &disk, &row, &observed[0], recovery, u64(sample), changed_samples)
			assert size == wanted.len && unsafe { tos(&u8(&output[0]), size) } == wanted && output[size] == 0 && output[size + 1] == char(91)
		} } }
	} } }
}
fn test_cipher_monitor_invalid_reference_counters_and_full_width_geometry() {
	mut disk := DiskKey{}; mut row := Request{}; mut expected := [32]u8{}; mut reference := [128]u8{}; cipher_monitor_native_fixture(4096, 2, 1, mut disk, mut row, &expected[0], &reference[0]); mut observed := expected; observed[31] ^= 1
	for at in 0 .. 128 { mut bad := reference; bad[at] ^= 1; mut output := [2048]char{init: char(91)}; saved := output; assert encode_ciphertext_monitor(&bad[0], &observed[0], true, 1, 1, &output[0]) == 0 && output == saved }
	for pair in [[u64(0), u64(0)]!, [u64(1), u64(2)]!, [u64(1), u64(0)]!] { mut output := [2048]char{init: char(91)}; saved := output; assert encode_ciphertext_monitor(&reference[0], &observed[0], false, pair[0], pair[1], &output[0]) == 0 && output == saved }
	row.offset = (u64(0x7fffffffffffffff) & ~u64(4095)) - 4096; row.length = 4096; assert encode_volume_ciphertext(&disk, &row, &expected[0], &reference[0]); mut output := [2048]char{}; size := encode_ciphertext_monitor(&reference[0], &observed[0], true, u64(-1), u64(-1), &output[0]); assert size > 0 && size < 2048 && unsafe { tos(&u8(&output[0]), size) } == cipher_monitor_native_expected(&reference[0], &disk, &row, &observed[0], true, u64(-1), u64(-1))
}
fn test_cipher_monitor_cli_both_domains_arity_and_unsigned_bounds() {
	unsafe { mut args := [&char(c'vinix-volume'), &char(c'monitor-volume-auto'), &char(c'/missing-monitor-config'), &char(c'/missing-credential'), &char(c'/missing-reference'), &char(c'0'), &char(c'1'), &char(c'extra'), &char(nil)]!
		for verb in [&char(c'monitor-volume-auto'), &char(c'monitor-recovery-volume-auto')]! { args[1] = verb
			for argc in [2, 3, 4, 5, 6, 8, 9] { assert run(argc, &args[0]) == 2 }
			for at in 2 .. 7 { saved := args[at]; args[at] = &char(c''); assert run(7, &args[0]) == 2; args[at] = saved }
			for value in [&char(c'-1'), &char(c'86401'), &char(c'18446744073709551616')]! { args[5] = value; assert run(7, &args[0]) == 2 }; args[5] = &char(c'0'); args[6] = &char(c'0'); assert run(7, &args[0]) == 2
			args[6] = &char(c'18446744073709551616'); assert run(7, &args[0]) == 2; args[6] = &char(c'1'); assert run(7, &args[0]) == 1; args[5] = &char(c'86400'); args[6] = &char(c'0'); assert run(7, &args[0]) == 1; args[6] = &char(c'18446744073709551615'); assert run(7, &args[0]) == 1; args[5] = &char(c'0'); args[6] = &char(c'1')
		}
	}
}
