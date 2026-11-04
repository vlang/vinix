// SPDX-License-Identifier: GPL-2.0-or-later
module perfflatness

import perfreport
import strconv

pub struct Report {
pub:
	ops int
	slab_rows int
	// Original physical/cache lines require separate interpretation.
	observations []string
}

fn require(ok bool, message string) ! {
	if !ok { return error(message) }
}

fn zero(text string, explicit_sign bool) ! {
	require(text.len > 0 && text.len <= 20, 'invalid signed integer')!
	signed := text[0] in [`+`, `-`]!
	require(!explicit_sign || signed, 'raw delta requires an explicit sign')!
	digits := if signed { text[1..] } else { text }
	require(digits.len > 0 && digits.bytes().all(it >= `0` && it <= `9`), 'invalid signed integer')!
	value := strconv.parse_int(text, 10, 64)!
	require(value == 0, 'nonzero exact allocation delta: ' + text)!
}

fn size_class(text string) ! {
	require(text.starts_with('size-'), 'unknown slab class')!
	digits := text[5..]
	require(digits.len > 0 && digits.len <= 10 && digits[0] != `0`
		&& digits.bytes().all(it >= `0` && it <= `9`), 'invalid slab size')!
	require(strconv.parse_int(digits, 10, 64)! > 0, 'invalid slab size')!
}

fn ops(line string) ! {
	require(line.starts_with('PERF-OPS variant=new scenario=ops round=1 op='), 'unexpected PERF-OPS identity')!
	parts := line.fields()
	require(parts.len >= 8 && parts[0] == 'PERF-OPS' && parts[1] == 'variant=new'
		&& parts[2] == 'scenario=ops' && parts[3] == 'round=1'
		&& parts[4].starts_with('op=') && parts[5].starts_with('dir=')
		&& parts[6] == 'count=200' && parts[7].starts_with('bytes_per_op='), 'unexpected PERF-OPS field order')!
	// Check exact counts before the derived rate: division and cancellation
	// can hide an allocation even when bytes_per_op is zero.
	mut seen := map[string]bool{}
	for part in parts[8..] {
		pair := part.split(':')
		require(pair.len == 2 && pair[0] !in seen, 'malformed or duplicate PERF-OPS delta')!
		if pair[0] != 'large_pages' { size_class(pair[0])! }
		seen[pair[0]] = true
		zero(pair[1], true)!
	}
	zero(parts[7].all_after('='), false)!
}

fn slab(line string) !string {
	// Parse the quoted program before fields; quoted text cannot supply a class.
	prefix := 'PERF-SLAB variant=new scenario=churn round=1 program="'
	require(line.starts_with(prefix), 'unexpected PERF-SLAB identity')!
	rest := line[prefix.len..]
	end := rest.index('" ') or { return error('unterminated PERF-SLAB program') }
	program := rest[..end]
	require(program in perfreport.churn_programs, 'unknown PERF-SLAB program')!
	parts := rest[end + 2..].fields()
	require(parts.len >= 2 && parts[0].starts_with('class='), 'missing PERF-SLAB class')!
	class := parts[0].all_after('=')
	if class == 'large' {
		require(parts.len == 2 && parts[1].starts_with('pages='), 'unexpected large PERF-SLAB fields')!
		zero(parts[1].all_after('='), true)!
	} else {
		size_class(class)!
		require(parts.len == 3 && parts[1].starts_with('objects=') && parts[2].starts_with('pages='),
			'unexpected sized PERF-SLAB fields')!
		zero(parts[1].all_after('='), true)!
		zero(parts[2].all_after('='), true)!
	}
	return program + '|' + class
}

// Fixed six-scenario, one-round new= transcript only. Process exit and input
// audit receipts are separate; no successful exit is inferred from this log.
pub fn inspect(transcript []u8) !Report {
	verdict := perfreport.inspect(transcript, ['new'], ['ops', 'churn', 'cache', 'idle', 'apps', 'drag'],
		1, false, none)
	require(verdict.errors.len == 0, 'incomplete or invalid performance transcript: ' + verdict.errors.join('; '))!
	mut operations := 0
	mut slabs := map[string]bool{}
	mut observations := []string{}
	for raw in transcript.bytestr().split_into_lines() {
		if at := raw.index('PERF-OPS') {
			ops(raw[at..].trim_space())!
			operations++
		}
		if at := raw.index('PERF-SLAB') {
			key := slab(raw[at..].trim_space())!
			require(key !in slabs, 'duplicate PERF-SLAB class row')!
			slabs[key] = true
		}
		if raw.contains('PERF-CHURN ') || raw.contains('PERF-CACHE ') {
			observations << raw.clone()
		}
	}
	require(operations == 36, 'expected 36 exact PERF-OPS rows')!
	return Report{ops: operations, slab_rows: slabs.len, observations: observations}
}
