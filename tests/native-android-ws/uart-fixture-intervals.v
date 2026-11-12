// SPDX-License-Identifier: GPL-2.0-or-later
// Select complete, untouched fixture frame intervals from a retained snapshot.
// The independent reconstructor validates each interval; no repairs/removals.
module main

import crypto.sha256
import json2
import os

fn main() {
	if os.args.len != 3 { panic('usage: uart-fixture-intervals SNAPSHOT_FULL_LOG FRESH_OUTPUT') }
	input, root := os.abs_path(os.args[1]), os.abs_path(os.args[2])
	if os.exists(root) || os.file_size(input) > 8 * 1024 * 1024 { panic('bounded input and fresh output required') }
	raw := os.read_file(input)!
	if raw == '' || !raw.ends_with('\n') { panic('complete snapshot required') }
	os.mkdir_all(root)!
	prefix := 'VINIX-SERVICE-QUERY-RESULTS-1 '
	mut start := -1
	mut header := ''
	mut offset := 0
	mut intervals := []json2.Any{}
	for part in raw[..raw.len - 1].split('\n') {
		line := part + '\n'
		if line.starts_with(prefix + 'BEGIN ') {
			if start >= 0 { panic('nested export') }
			start = offset
			header = line.trim_right('\r\n').all_after(prefix + 'BEGIN ')
		} else if line.starts_with(prefix + 'END ') {
			if start < 0 || line.trim_right('\r\n').all_after(prefix + 'END ') != header { panic('unmatched export end') }
			end := offset + line.len
			selected := raw[start..end]
			name := 'export-' + intervals.len.str() + '.log'
			os.write_file(root + '/' + name, selected)!
			intervals << json2.Any({
				'path': json2.Any(name), 'offset': json2.Any(start), 'bytes': json2.Any(selected.len),
				'sha256': json2.Any(sha256.sum(selected.bytes()).hex())
			})
			start = -1
		}
		offset += line.len
	}
	if start >= 0 || intervals.len == 0 || offset != raw.len { panic('incomplete export or byte accounting') }
	os.write_file(root + '/receipt.json', json2.encode({
		'source': json2.Any(input), 'source_sha256': json2.Any(sha256.sum(raw.bytes()).hex()),
		'source_bytes': json2.Any(raw.len), 'intervals': json2.Any(intervals)
	}, prettify: true))!
	println('UART-FIXTURE-INTERVALS count=' + intervals.len.str())
}
