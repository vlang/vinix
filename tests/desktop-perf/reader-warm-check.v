// SPDX-License-Identifier: GPL-2.0-or-later
// Warmup proof supplements the existing complete snapshot and flatness policy.
module main

import heapfull
import json2
import os
import perfprotocol

fn require(ok bool, message string) ! { if !ok { return error(message) } }
fn proof(identity string) string {
	return 'PERF-READER ${identity} mask=3 restored=3 reads_per_cpu=64'
}
fn footer(pair heapfull.ObservedCohort) string {
	return 'PERF-HEAP-DELTA ${pair.identity} written_before=${pair.written_before} written_after=${pair.written_after} written_after_free=${pair.written_delta}'
}

fn verify(raw string, strict bool) !heapfull.Observations {
	observed := heapfull.observe(raw.bytes())!
	if strict { _ := heapfull.inspect(raw.bytes())! }
	mut count := 0
	lines := raw.split('\n')
	for i, row in lines {
		if !row.starts_with('PERF-READER') { continue }
		require(i > 0 && i < lines.len - 1 && count < observed.pairs.len,
			'orphan, duplicated or unterminated reader proof')!
		pair := observed.pairs[count]
		require(perfprotocol.line(row)! == proof(pair.identity),
			'wrong reader identity, CPU mask, restoration or warm count')!
		require(perfprotocol.line(lines[i - 1])! == footer(pair),
			'reader proof must follow its complete measured pair')!
		count++
	}
	require(count == 40 && count == observed.cohorts, 'missing reader warmup proofs')!
	return observed
}

fn fixture() !string {
	mut text := heapfull.clean_fixture()!
	for pair in heapfull.observe(text.bytes())!.pairs {
		row := footer(pair) + '\n'
		text = text.replace(row, row + proof(pair.identity) + '\n')
	}
	return text
}

fn selfcheck() ! {
	text := fixture()!
	verify(text, true)!
	verify(text, false)!
	verify(text.replace('\n', '\r\n'), true)!
	$if perf_slab16k ? { verify(text.replace('\n', '\r\r\n'), true)! }
	mut bad := [text.replace('mask=3', 'mask=1'), text.replace('restored=3', 'restored=1'),
		text.replace('mask=3', 'mask=0'), text.replace('reads_per_cpu=64', 'reads_per_cpu=63'),
		text.replace('reads_per_cpu=64', 'reads_per_cpu=65'), text.replace('mask=3', 'mask=03'),
		text.replace('mask=3', 'mask=18446744073709551616'),
		text.replace(' restored=', ' restored=\r'), text.replace(' mask=', ' mask=\x00'),
		text.replace(' reads_per_cpu=64', ' reads_per_cpu=64 extra=1'),
		text.replace('\n', '\r\r\r\n')]
	rows := text.split_into_lines().filter(it.starts_with('PERF-READER'))
	for row in rows {
		bad << text.replace(row + '\n', '')
		bad << text + row + '\n'
	}
	bad << text.replace(rows[0] + '\n', '').replace(rows[1], rows[0] + '\n' + rows[1])
	bad << text.replace(rows.last() + '\n', '') + rows.last()
	$if !perf_slab16k ? { bad << text.replace('\n', '\r\r\n') }
	for candidate in bad {
		verify(candidate, false) or { continue }
		return error('invalid reader warmup proof accepted')
	}
	println('PERF READER WARM controls PASS ' + bad.len.str())
}

fn run() ! {
	if os.args.len == 2 && os.args[1] == 'selfcheck' { selfcheck()!; return }
	require(os.args.len == 3 && os.args[1] in ['check', 'observe'],
		'usage: reader-warm-check selfcheck | check|observe SERIAL')!
	require(os.file_size(os.args[2]) <= 32 * 1024 * 1024, 'reader transcript exceeds bound')!
	strict := os.args[1] == 'check'
	observed := verify(os.read_file(os.args[2])!, strict)!
	if strict { println('PERF READER warm proof and strict heap checks PASS 40 cohorts') }
	else {
		println(json2.encode({'qualification': json2.Any(false), 'reader_proofs': 40,
			'nonzero_object_rows': observed.nonzero_object_rows,
			'nonzero_page_rows': observed.nonzero_page_rows,
			'nonzero_large_rows': observed.nonzero_large_rows,
			'corruption_counter_cohorts': observed.corruption_counter_cohorts}, prettify: true))
	}
}

fn main() { run() or { eprintln(err); exit(1) } }
