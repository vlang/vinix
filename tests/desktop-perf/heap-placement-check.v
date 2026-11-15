// SPDX-License-Identifier: GPL-2.0-or-later
// Completeness and corruption checks only; changed storage remains visible.
module main

import json2
import os
import perfheap
import perfprotocol
import strconv

struct Observation {
	qualification bool
mut:
	class_rows int
	object_changes int
	page_changes int
	large_changes int
}

fn require(ok bool, message string) ! { if !ok { return error(message) } }

fn pair(text string) ![]u64 {
	parts := text.split('/')
	require(parts.len == 2, 'counter pair required')!
	mut values := []u64{}
	for part in parts {
		require(part.len > 0 && part.bytes().all(it >= `0` && it <= `9`)
			&& (part.len == 1 || part[0] != `0`), 'noncanonical counter')!
		values << strconv.parse_uint(part, 10, 64)!
	}
	return values
}

fn verify(raw string) !Observation {
	for bad in ['HEAP-PLACEMENT FAIL', 'KERNEL PANIC', 'FATAL EXCEPTION', 'V panic:'] {
		require(!raw.contains(bad), 'failure marker')!
	}
	mut rows := []string{}
	lines := raw.split('\n')
	for i, row in lines {
		if row.starts_with('HEAP-PLACEMENT') {
			require(i < lines.len - 1, 'unterminated placement row')!
			rows << perfprotocol.line(row)!
		}
	}
	require(rows.len == 2 + 4 * (perfheap.class_count + 2), 'placement row count differs')!
	require(rows[0] == 'HEAP-PLACEMENT BEGIN schema=${perfheap.schema} allowed=3 cases=4 qualification=false',
		'wrong placement schema or CPU mask')!
	mut result := Observation{}
	for id in 0 .. 4 {
		offset := 1 + id * (perfheap.class_count + 2)
		first := if id == 2 { 1 } else { 0 }
		last := if id == 3 { 0 } else { 1 - first }
		warm := if id == 0 { 1 } else { 2 }
		require(rows[offset] == 'HEAP-PLACEMENT CASE id=${id} before_cpu=${first} after_cpu=${last} warm_cpus=${warm} reads=200',
			'wrong, missing or reordered placement case')!
		for i, size in perfheap.class_sizes {
			prefix := 'HEAP-PLACEMENT CLASS id=${id} size=${size} objects='
			row := rows[offset + 1 + i]
			require(row.starts_with(prefix), 'wrong, missing or reordered placement class')!
			parts := row[prefix.len..].split(' pages=')
			require(parts.len == 2, 'class backing pages missing')!
			objects, pages := pair(parts[0])!, pair(parts[1])!
			if objects[0] != objects[1] { result.object_changes++ }
			if pages[0] != pages[1] { result.page_changes++ }
			result.class_rows++
		}
		prefix := 'HEAP-PLACEMENT STORAGE id=${id} large='
		row := rows[offset + perfheap.class_count + 1]
		require(row.starts_with(prefix), 'missing placement storage')!
		parts := row[prefix.len..].split(' written=')
		require(parts.len == 2, 'missing corruption counters')!
		large, written := pair(parts[0])!, pair(parts[1])!
		if large[0] != large[1] { result.large_changes++ }
		require(written == [u64(0), 0], 'nonzero written-after-free counter')!
	}
	require(rows.last() == 'HEAP-PLACEMENT SUMMARY cases=4 restored=3 qualification=false',
		'affinity restoration or completion missing')!
	return result
}

fn fixture() string {
	mut rows := ['HEAP-PLACEMENT BEGIN schema=${perfheap.schema} allowed=3 cases=4 qualification=false']
	for id in 0 .. 4 {
		first := if id == 2 { 1 } else { 0 }
		last := if id == 3 { 0 } else { 1 - first }
		warm := if id == 0 { 1 } else { 2 }
		rows << 'HEAP-PLACEMENT CASE id=${id} before_cpu=${first} after_cpu=${last} warm_cpus=${warm} reads=200'
		for size in perfheap.class_sizes {
			rows << 'HEAP-PLACEMENT CLASS id=${id} size=${size} objects=10/10 pages=1/1'
		}
		rows << 'HEAP-PLACEMENT STORAGE id=${id} large=0/0 written=0/0'
	}
	rows << 'HEAP-PLACEMENT SUMMARY cases=4 restored=3 qualification=false'
	return rows.join('\n') + '\n'
}

fn controls() ! {
	text := fixture()
	verify(text)!
	verify('boot noise\n' + text + 'monitor exit\n')!
	verify(text.replace('\n', '\r\n'))!
	$if perf_slab16k ? { verify(text.replace('\n', '\r\r\n'))! }
	changed := verify(text.replace('objects=10/10 pages=1/1', 'objects=10/11 pages=2/1')
		.replace('large=0/0', 'large=0/1'))!
	require(changed.object_changes == 4 * perfheap.class_count
		&& changed.page_changes == changed.object_changes && changed.large_changes == 4
		&& !changed.qualification, 'changed storage was hidden or qualified')!
	mut bad := [text + 'KERNEL PANIC\n', text + 'FATAL EXCEPTION\n', text + 'V panic:\n',
		text + 'HEAP-PLACEMENT FAIL test\n', text.replace('qualification=false', 'qualification=true'),
		text.replace(perfheap.schema, 'foreign'), text.replace('allowed=3', 'allowed=1'),
		text.replace('restored=3', 'restored=1'), text.replace('reads=200', 'reads=199'),
		text.replace('before_cpu=1', 'before_cpu=0'), text.replace('warm_cpus=2', 'warm_cpus=1'),
		text.replace('objects=10/10', 'objects=01/1'), text.replace('objects=10/10', 'objects=-1/1'),
		text.replace('objects=10/10', 'objects=18446744073709551616/1'),
		text.replace('objects=10/10', 'objects=1/1/1'), text.replace('pages=1/1', 'pages=1/x'),
		text.replace('written=0/0', 'written=1/1'), text.replace('written=0/0', 'written=0/1'),
		text.replace(' pages=', ' pages=\r'), text.replace(' written=', ' written=\x00'),
		text.replace('\n', '\r\r\r\n'), text.trim_right('\n')]
	for row in text.split_into_lines() {
		bad << text.replace(row + '\n', '')
		bad << text + row + '\n'
	}
	// Reject reordered rows even when every expected row is present.
	mut swapped := text.split_into_lines()
	swapped[2], swapped[3] = swapped[3], swapped[2]
	bad << swapped.join('\n') + '\n'
	$if !perf_slab16k ? { bad << text.replace('\n', '\r\r\n') }
	for candidate in bad {
		verify(candidate) or { continue }
		return error('invalid placement transcript accepted')
	}
	println('Placement checker controls PASS ' + bad.len.str())
}

fn run() ! {
	if os.args.len == 2 && os.args[1] == 'selfcheck' { controls()!; return }
	require(os.args.len == 3 && os.args[1] == 'check', 'usage: heap-placement-check selfcheck | check SERIAL')!
	require(os.file_size(os.args[2]) <= 32 * 1024 * 1024, 'placement transcript exceeds bound')!
	result := verify(os.read_file(os.args[2])!)!
	println(json2.encode(result, prettify: true))
}

fn main() { run() or { eprintln(err); exit(1) } }
