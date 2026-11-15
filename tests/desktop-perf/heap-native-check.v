// SPDX-License-Identifier: GPL-2.0-or-later
// Captured native probe output only; process/input receipts remain separate.
module main

import os
import perfheap
import perfprotocol
import strconv

fn require(ok bool, message string) ! { if !ok { return error(message) } }

fn flat_pair(text string, zero bool) ! {
	parts := text.split('/')
	require(parts.len == 2 && parts[0] == parts[1], 'native storage changed')!
	for part in parts {
		require(part.len > 0 && part.bytes().all(it >= `0` && it <= `9`)
			&& (part.len == 1 || part[0] != `0`), 'invalid native counter')!
		value := strconv.parse_uint(part, 10, 64)!
		require(!zero || value == 0, 'written-after-free counter is nonzero')!
	}
}

fn verify(raw string) ! {
	text := raw
	for bad in ['KERNEL PANIC', 'FATAL EXCEPTION', 'V panic:', 'LINUX PERFHEAP FAIL:'] {
		require(!text.contains(bad), 'native failure marker')!
	}
	mut rows := []string{}
	lines := text.split('\n')
	for i, row in lines {
		if row.starts_with('LINUX PERFHEAP') {
			require(i < lines.len - 1, 'unterminated native row')!
			rows << perfprotocol.line(row)!
		}
	}
	require(rows.len == perfheap.class_count + 2, 'native row count differs')!
	for i, size in perfheap.class_sizes {
		prefix := 'LINUX PERFHEAP CLASS: size=${size} live='
		require(rows[i].starts_with(prefix), 'wrong or reordered native class')!
		parts := rows[i][prefix.len..].split(' pages=')
		require(parts.len == 2, 'missing native backing-page counters')!
		flat_pair(parts[0], false)!
		flat_pair(parts[1], false)!
	}
	prefix := 'LINUX PERFHEAP STORAGE: large='
	require(rows[perfheap.class_count].starts_with(prefix), 'missing native large pages')!
	parts := rows[perfheap.class_count][prefix.len..].split(' written=')
	require(parts.len == 2, 'missing native corruption counters')!
	flat_pair(parts[0], false)!
	flat_pair(parts[1], true)!
	require(rows.last() == 'LINUX PERFHEAP SUMMARY: schema=${perfheap.schema} pages=${perfheap.page_size} classes=${perfheap.class_count} reads=200 failures=0',
		'native schema or completion differs')!
}

fn run() ! {
	require(os.args.len == 3 && os.args[1] in ['check', 'controls'], 'usage: heap-native-check check|controls SERIAL')!
	require(os.file_size(os.args[2]) <= 32 * 1024 * 1024, 'native transcript exceeds bound')!
	raw := os.read_file(os.args[2])!
	verify(raw)!
	if os.args[1] == 'controls' {
		text := raw.replace('\r', '')
		verify(text)!
		verify(text.replace('\n', '\r\n'))!
		$if perf_slab16k ? { verify(text.replace('\n', '\r\r\n'))! }
		mut bad := [text + '\nKERNEL PANIC\n', text + '\nFATAL EXCEPTION\n', text + '\nV panic:\n',
			text.replace('failures=0', 'failures=1'), text.replace('reads=200', 'reads=199'),
			text.replace(perfheap.schema, 'unknown'), text.replace('written=0/0', 'written=1/1'),
			text.replace('written=0/0', 'written=0/1'), text.replace(' live=', ' live=\r'),
			text.replace(' written=', ' written=\x00'), text.replace('\n', '\r\r\r\n'),
			text.trim_right('\n')]
		for row in text.replace('\r', '').split_into_lines().filter(it.starts_with('LINUX PERFHEAP')) {
			bad << text.replace('\r', '').replace(row + '\n', '')
			bad << text + '\n' + row + '\n'
		}
		for candidate in bad {
			verify(candidate) or { continue }
			return error('invalid native transcript accepted')
		}
		println('Native heap checker controls PASS ' + bad.len.str())
	}
	println('Native slab profile and reader cleanup: PASS ' + perfheap.schema)
}

fn main() { run() or { eprintln(err); exit(1) } }
