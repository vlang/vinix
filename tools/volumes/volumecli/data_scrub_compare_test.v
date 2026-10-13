// SPDX-License-Identifier: GPL-2.0-or-later
module volumecli

import crypto.sha256
import encoding.hex

fn history_fixture(code int, mut report DataScrubReport) {
	report = DataScrubReport{disks: 2, count: 3}; mut state := code
	for i in 0 .. 3 {
		report.indices[i] = if i == 2 { 1 } else { 0 }
		report.rows[i] = Request{slot: u32([2, 5, 9][i]), offset: if i == 1 { u64(2097152) } else { u64(1048576) }, length: if i == 1 { u64(12288) } else { u64(8192) }, flags: if i == 1 { u64(1) } else { u64(0) }}
		for byte in 0 .. 32 { report.expected[i][byte] = u8((i + 1) * 17 + byte * 7) }
		report.actual[i] = report.expected[i]; report.actual[i][i] ^= u8(state % 3); state /= 3
	}
}

fn history_input(report &DataScrubReport) string {
	mut changed := 0; for i in 0 .. report.count { if report.expected[i] != report.actual[i] { changed++ } }
	mut text := 'format=VINIXSR1 operation=scrubbed-data disks=${report.disks} mappings=${report.count} matched=${report.count - changed} changed=${changed} algorithm=sha256 reference_sha256=' + hex.encode(report.reference[..]) + '\n'
	for i in 0 .. report.count {
		row := report.rows[i]
		text += 'disk=${report.indices[i]} slot=${row.slot} offset=${row.offset} bytes=${row.length} readonly=${row.flags} result=${if report.expected[i] == report.actual[i] { 'match' } else { 'changed' }} expected_sha256=' + hex.encode(report.expected[i][..]) + ' actual_sha256=' + hex.encode(report.actual[i][..]) + '\n'
	}
	return text
}

fn history_expected(before &DataScrubReport, after &DataScrubReport) string {
	mut counts := [4]int{}; mut results := []string{}
	for i in 0 .. before.count {
		category := if before.actual[i] == after.actual[i] { 0 } else if after.actual[i] == after.expected[i] { 2 } else if before.actual[i] == before.expected[i] { 1 } else { 3 }
		counts[category]++; results << ['stable', 'new-change', 'restored', 'changed-again'][category]
	}
	mut text := 'format=VINIXSR1 operation=compared-data-scrubs disks=${before.disks} mappings=${before.count} stable=${counts[0]} changed=${before.count - counts[0]} new_changes=${counts[1]} restored=${counts[2]} changed_again=${counts[3]} algorithm=sha256 reference_sha256=' + hex.encode(before.reference[..]) + ' before_report_sha256=' + sha256.hexhash(history_input(before)) + ' after_report_sha256=' + sha256.hexhash(history_input(after)) + '\n'
	for i in 0 .. before.count {
		row := before.rows[i]
		text += 'disk=${before.indices[i]} slot=${row.slot} offset=${row.offset} bytes=${row.length} readonly=${row.flags} before=${if before.actual[i] == before.expected[i] { 'match' } else { 'changed' }} after=${if after.actual[i] == after.expected[i] { 'match' } else { 'changed' }} result=${results[i]} expected_sha256=' + hex.encode(before.expected[i][..]) + ' before_sha256=' + hex.encode(before.actual[i][..]) + ' after_sha256=' + hex.encode(after.actual[i][..]) + '\n'
	}
	return text
}

fn test_scrub_history_all_729_three_row_histories_and_complete_exact_fingerprinted_reports() {
	for left in 0 .. 27 { for right in 0 .. 27 {
		mut before := DataScrubReport{}; mut after := DataScrubReport{}; history_fixture(left, mut before); history_fixture(right, mut after)
		mut history := DataScrubHistory{}; assert compare_data_scrubs(&before, &after, mut history)
		mut first := left; mut second := right; mut counts := [4]int{}; mut mask := u64(0)
		for i in 0 .. 3 {
			a := first % 3; b := second % 3; first /= 3; second /= 3
			category := if a == b { 0 } else if b == 0 { 2 } else if a == 0 { 1 } else { 3 }; counts[category]++; if a != b { mask |= u64(1) << i }
		}
		assert history.stable == counts[0] && history.new_changes == counts[1] && history.restored == counts[2] && history.changed_again == counts[3] && history.differences == mask
		mut output := [32768]char{init: char(91)}; size := encode_data_scrub_comparison(&before, &after, &output[0]); expected := history_expected(&before, &after)
		assert size == expected.len && unsafe { tos(&u8(&output[0]), size) } == expected && output[size] == 0 && output[size + 1] == char(91)
	} }
}

fn test_scrub_history_strict_private_decode_and_canonical_roundtrip() {
	mut sentinel := DataScrubReport{}; history_fixture(26, mut sentinel)
	for code in 0 .. 27 {
		mut fixture := DataScrubReport{}; history_fixture(code, mut fixture); text := history_input(&fixture)
		mut decoded := sentinel; assert decode_data_scrub_report(text.str, text.len, mut decoded) && decoded == fixture
		mut output := [32768]char{}; size := encode_data_scrub_snapshot(&decoded, &output[0]); assert size == text.len && unsafe { tos(&u8(&output[0]), size) } == text
		for length in 0 .. text.len { decoded = sentinel; assert !decode_data_scrub_report(text.str, length, mut decoded) && decoded == sentinel }
		for at in 0 .. text.len { mut bad := text.bytes(); bad[at] = 0; decoded = sentinel; assert !decode_data_scrub_report(bad.data, bad.len, mut decoded) && decoded == sentinel }
		bad := text + '\n'; decoded = sentinel; assert !decode_data_scrub_report(bad.str, bad.len, mut decoded) && decoded == sentinel
	}
}

fn test_scrub_history_reference_and_every_saved_metadata_expected_byte_bind_before_findings() {
	mut before := DataScrubReport{}; mut after := DataScrubReport{}; history_fixture(0, mut before); history_fixture(26, mut after)
	old := DataScrubHistory{stable: 77, differences: 0x91}; mut history := old
	for kind in 0 .. 10 {
		mut wrong := after
		match kind {
			0 { wrong.reference[31] ^= 1 }
			1 { wrong.disks = 3 }
			2 { wrong.count = 2 }
			3 { wrong.rows[2].slot = 10 }
			4 { wrong.rows[2].offset += 512 }
			5 { wrong.rows[2].length += 512 }
			6 { wrong.rows[2].flags = 1 }
			7 { wrong.expected[2][31] ^= 1 }
			8 { wrong.indices[2] = 2; wrong.disks = 3 }
			else { row := wrong.rows[0]; wrong.rows[0] = wrong.rows[1]; wrong.rows[1] = row; expected := wrong.expected[0]; wrong.expected[0] = wrong.expected[1]; wrong.expected[1] = expected; actual := wrong.actual[0]; wrong.actual[0] = wrong.actual[1]; wrong.actual[1] = actual }
		}
		assert data_scrub_records_valid(&wrong) && !compare_data_scrubs(&before, &wrong, mut history) && history == old
		mut output := [32768]char{init: char(91)}; saved := output; assert encode_data_scrub_comparison(&before, &wrong, &output[0]) == 0 && output == saved
	}
	for row in 0 .. 3 { for byte in 0 .. 32 {
		mut wrong := after; wrong.expected[row][byte] ^= 1; assert !compare_data_scrubs(&before, &wrong, mut history) && history == old
		mut changed := before; changed.actual[row][byte] ^= 1; assert compare_data_scrubs(&before, &changed, mut history) && history.new_changes == 1 && history.differences == u64(1) << row; history = old
	} }
	for kind in 0 .. 8 {
		mut wrong := after
		match kind {
			0 { wrong.count = 65 }
			1 { wrong.count = -1 }
			2 { wrong.rows[2].version = 2 }
			3 { wrong.rows[2].slot = 64 }
			4 { wrong.rows[2].length = 0 }
			5 { wrong.rows[2].offset = u64(0x7fffffffffffffff) }
			6 { wrong.rows[2].flags = 2 }
			else { wrong.indices[2] = 0 }
		}
		assert !data_scrub_records_valid(&wrong) && !compare_data_scrubs(&before, &wrong, mut history) && history == old
	}
}

fn test_scrub_history_full_width_64_rows_empty_sets_and_cli_syntax() {
	mut before := DataScrubReport{disks: 64, count: 64}; mut after := DataScrubReport{}
	for i in 0 .. 64 { before.indices[i] = u32(i); before.rows[i] = Request{slot: u32(63 - i), offset: 9223372036854774784, length: 512, flags: u64(i & 1)} }
	after = before; for i in 0 .. 64 { after.actual[i][31] = 1 }
	for report in [before, after] { text := history_input(&report); mut decoded := DataScrubReport{}; assert decode_data_scrub_report(text.str, text.len, mut decoded) && decoded == report; mut roundtrip := [32768]char{}; n := encode_data_scrub_snapshot(&decoded, &roundtrip[0]); assert n == text.len && unsafe { tos(&u8(&roundtrip[0]), n) } == text }
	mut history := DataScrubHistory{}; assert compare_data_scrubs(&before, &after, mut history) && history.new_changes == 64 && history.differences == u64(-1)
	mut output := [32768]char{}; size := encode_data_scrub_comparison(&before, &after, &output[0]); assert size > 20000 && size < 32768 && unsafe { tos(&u8(&output[0]), size) } == history_expected(&before, &after)
	for disks in 1 .. 65 { before = DataScrubReport{disks: disks}; after = before; text := history_input(&before); mut decoded := DataScrubReport{}; assert decode_data_scrub_report(text.str, text.len, mut decoded) && decoded == before; assert compare_data_scrubs(&before, &after, mut history) && history == DataScrubHistory{}; assert encode_data_scrub_comparison(&before, &after, &output[0]) > 0 }
	unsafe {
		mut args := [&char(c'vinix-volume'), &char(c'compare-data-scrubs'), &char(c'/missing-first'), &char(c'/missing-second'), &char(c'extra'), &char(nil)]!
		for count in [2, 3, 5, 6] { assert run(count, &args[0]) == 2 }
		for i in [2, 3] { saved := args[i]; args[i] = &char(c''); assert run(4, &args[0]) == 2; args[i] = saved }
		assert run(4, &args[0]) == 1
	}
}
