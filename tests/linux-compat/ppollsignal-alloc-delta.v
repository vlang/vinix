// SPDX-License-Identifier: GPL-2.0-or-later
// Compare the full call-chain groups from the diagnostic before/after dumps.
module main

import os
import strconv

fn number(value string) !i64 {
	if value.len == 0 || !value.bytes().all(it >= `0` && it <= `9`) { return error('Invalid count') }
	return strconv.parse_int(value,10,64)
}

fn run() ! {
	if os.args.len != 2 { return error('Usage: ppollsignal-alloc-delta SERIAL-LOG') }
	mut groups := map[string]map[string]i64{}
	mut headers := map[string]int{}
	mut live := map[string]i64{}
	mut totals := map[string]i64{}
	for line in os.read_file(os.args[1])!.split_into_lines() {
		if !line.contains('PERF-SITE ppollsignal phase=') { continue }
		fields := line.all_after('PERF-SITE ppollsignal phase=').trim_space().fields()
		if fields.len < 2 || fields[0] !in ['before','after'] { return error('Invalid phase') }
		phase := fields[0]
		if fields[1] == 'live' {
			if fields.len != 5 || fields[3] != 'dropped' || number(fields[4])! != 0 { return error('Incomplete allocation groups') }
			live[phase] = number(fields[2])!
			if live[phase] > 65536 { return error('Invalid live table count') }
			headers[phase]++
			continue
		}
		if fields.len != 13 { return error('Truncated call chain') }
		count := number(fields[1])!
		size := number(fields[2])!
		if count <= 0 || count > 65536 || size <= 0 { return error('Invalid allocation group') }
		for pc in fields[3..] { strconv.parse_uint(pc,16,64)! }
		key := fields[2..].join(' ')
		mut entries := groups[phase].clone()
		if key in entries { return error('Repeated allocation group') }
		entries[key] = count
		groups[phase] = entries
		totals[phase] += count
		if totals[phase] > 65536 { return error('Allocation table overflow') }
	}
	if headers['before'] != 1 || headers['after'] != 1 { return error('Missing/repeated dump') }
	for phase in ['before','after'] {
		if totals[phase] != live[phase] { return error('Missing allocation groups') }
	}
	mut keys := groups['before'].keys()
	for key in groups['after'].keys() { if key !in keys { keys << key } }
	keys.sort()
	for key in keys {
		before := groups['before'][key]
		after := groups['after'][key]
		if before == after { continue }
		println('PERF-SITE ppollsignal before='+before.str()+' after='+after.str()+' delta='+(after-before).str()+' '+after.str()+' '+key)
	}
}

fn main() { run() or { eprintln(err.msg()); exit(1) } }
