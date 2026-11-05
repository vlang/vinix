// SPDX-License-Identifier: GPL-2.0-or-later
// Captured serial evidence only. No guest is launched and no exit is inferred.
module heapfull

import perfheap
import perfflatness
import perfreport
import strconv

pub const max_transcript_bytes = 32 * 1024 * 1024
const schema = 'vinix-slab-14-4k-v1'
const protocol_marker = 'PERF-HEAP'

pub struct Report {
pub:
	cohorts int
	snapshots int
	delta_rows int
	ops int
	slab_rows int
	// Physical and cache observations need interpretation separate from heap
	// flatness. Their original serial bytes remain in the caller's evidence.
	observations []string
}

struct Line {
	text string
	next int
	terminated bool
}

struct Begin {
	identity string
	phase string
	bytes int
}

fn require(ok bool, message string) ! {
	if !ok { return error(message) }
}

fn expected_identities() []string {
	mut identities := []string{}
	for op in perfreport.general_ops {
		identities << 'variant=new scenario=ops round=1 op="' + op + '" dir=/tmp'
	}
	for directory in ['/tmp', '/root'] {
		for op in perfreport.file_ops {
			identities << 'variant=new scenario=ops round=1 op="' + op + '" dir=' + directory
		}
	}
	for program in perfreport.churn_programs {
		identities << 'variant=new scenario=churn round=1 op="' + program + '" dir=-'
	}
	return identities
}

fn line_at(text string, offset int) !Line {
	require(offset >= 0 && offset < text.len, 'full heap protocol ended prematurely')!
	mut end := offset
	for end < text.len && text[end] != `\n` { end++ }
	terminated := end < text.len
	return Line{text: text[offset..end], next: if terminated { end + 1 } else { end },
		terminated: terminated}
}

// This conversion is deliberately confined to the declared ASCII protocol.
// The original transcript is passed unchanged to the summary gate and SHA.
fn protocol_line(line Line) !string {
	require(line.terminated, 'unterminated full heap protocol line')!
	text := if line.text.ends_with('\r') { line.text[..line.text.len - 1] } else { line.text }
	for byte in text {
		require(byte >= 32 && byte <= 126, 'non-ASCII or control byte in full heap protocol')!
	}
	return text
}

fn parse_begin(line string, known map[string]bool) !Begin {
	prefix := 'PERF-HEAP-BEGIN '
	require(line.starts_with(prefix), 'expected full heap BEGIN line')!
	rest := line[prefix.len..]
	phase_at := rest.index(' phase=') or { return error('missing full heap phase') }
	identity := rest[..phase_at]
	require(identity in known, 'unknown or malformed full heap cohort identity')!
	tail := rest[phase_at + 7..]
	separator := ' schema=' + schema + ' bytes='
	length_at := tail.index(separator) or { return error('unknown or malformed full heap schema') }
	phase := tail[..length_at]
	require(phase in ['before', 'after'], 'unknown full heap phase')!
	digits := tail[length_at + separator.len..]
	require(digits.len > 0 && digits.len <= 4 && digits[0] != `0`
		&& digits.bytes().all(it >= `0` && it <= `9`), 'invalid full heap declared byte length')!
	length := strconv.parse_int(digits, 10, 32)!
	require(length > 0 && length <= perfheap.raw_capacity, 'full heap payload exceeds snapshot storage')!
	return Begin{identity: identity, phase: phase, bytes: int(length)}
}

// The caller owns offset. Exactly the normalized declared payload and its
// matching END must be present; a next block can never complete this block.
fn read_snapshot(text string, begin Begin, offset &int, out &perfheap.Snapshot) ! {
	mut payload := []u8{cap: begin.bytes}
	for payload.len < begin.bytes {
		line := line_at(text, unsafe { *offset })!
		body := protocol_line(line)!
		require(!body.contains(protocol_marker), 'interleaved, missing or truncated full heap block')!
		require(payload.len + body.len + 1 <= begin.bytes, 'full heap payload exceeds declared byte length')!
		payload << body.bytes()
		payload << u8(`\n`)
		unsafe { *offset = line.next }
	}
	ending := line_at(text, unsafe { *offset })!
	require(protocol_line(ending)! == 'PERF-HEAP-END ' + begin.identity + ' phase=' + begin.phase,
		'missing, mismatched or malformed full heap END line')!
	unsafe { *offset = ending.next }
	perfheap.parse_snapshot(unsafe { &payload[0] }, payload.len, out)!
}

fn signed(value i64) string {
	return if value >= 0 { '+' + value.str() } else { value.str() }
}

fn delta_lines(identity string, before &perfheap.Snapshot, after &perfheap.Snapshot,
	delta &perfheap.Delta) []string {
	prefix := 'PERF-HEAP-DELTA ' + identity + ' '
	mut lines := []string{cap: 16}
	for row in delta.classes {
		lines << prefix + 'class=size-' + row.size.str() + ' objects=' + signed(row.objects)
			+ ' pages=' + signed(row.pages)
	}
	lines << prefix + 'class=large pages=' + signed(delta.large_pages)
	lines << prefix + 'written_before=' + before.written_after_free.str()
		+ ' written_after=' + after.written_after_free.str()
		+ ' written_after_free=' + signed(delta.written_after_free)
	return lines
}

// Require the complete current producer sequence, not just the sparse legacy
// rows. Comparing canonical rows verifies identities, all classes, signs,
// original footer counters and every arithmetic result against raw snapshots.
fn read_deltas(text string, identity string, before &perfheap.Snapshot,
	after &perfheap.Snapshot, offset &int) !int {
	mut delta := perfheap.Delta{}
	perfheap.compare(before, after, unsafe { &delta })!
	mut count := 0
	for expected in delta_lines(identity, before, after, unsafe { &delta }) {
		line := line_at(text, unsafe { *offset })!
		require(protocol_line(line)! == expected,
			'incomplete, reordered or inconsistent full heap DELTA row: ' + expected)!
		unsafe { *offset = line.next }
		count++
	}
	return count
}

// Fixed new=, one-round ops/churn/cache/idle/apps/drag evidence. The unchanged
// summary gate checks all 44 measurements and DONE; exact full observations add
// 40 unique cohorts, 80 admitted raw snapshots and 640 consistent delta rows.
pub fn inspect(transcript []u8) !Report {
	require(transcript.len > 0 && transcript.len <= max_transcript_bytes,
		'captured serial transcript must contain at most 32 MiB')!
	summary := perfflatness.inspect(transcript)!
	identities := expected_identities()
	require(identities.len == 40, 'full heap cohort table differs from the fixed 40-cohort policy')!
	mut known := map[string]bool{}
	for identity in identities {
		require(identity !in known, 'duplicate identity in full heap cohort table')!
		known[identity] = true
	}
	mut seen := map[string]bool{}
	text := transcript.bytestr()
	mut offset := 0
	mut snapshots := 0
	mut deltas := 0
	for offset < text.len {
		line := line_at(text, offset)!
		offset = line.next
		if !line.text.contains(protocol_marker) { continue }
		before_begin := parse_begin(protocol_line(line)!, known)!
		require(before_begin.phase == 'before', 'orphan or reordered full heap after block')!
		require(before_begin.identity !in seen, 'duplicate full heap cohort')!
		mut before := perfheap.Snapshot{}
		mut after := perfheap.Snapshot{}
		read_snapshot(text, before_begin, unsafe { &offset }, unsafe { &before })!
		after_line := line_at(text, offset)!
		after_begin := parse_begin(protocol_line(after_line)!, known)!
		require(after_begin.identity == before_begin.identity && after_begin.phase == 'after',
			'interleaved, missing or reordered full heap pair')!
		offset = after_line.next
		read_snapshot(text, after_begin, unsafe { &offset }, unsafe { &after })!
		deltas += read_deltas(text, before_begin.identity, unsafe { &before }, unsafe { &after },
			unsafe { &offset })!
		perfheap.qualify_flatness(unsafe { &before }, unsafe { &after })!
		seen[before_begin.identity] = true
		snapshots += 2
	}
	require(seen.len == identities.len, 'missing full heap cohorts: expected 40, received ' + seen.len.str())!
	require(snapshots == 80 && deltas == 640, 'incomplete full heap snapshot or DELTA counts')!
	return Report{cohorts: seen.len, snapshots: snapshots, delta_rows: deltas, ops: summary.ops,
		slab_rows: summary.slab_rows, observations: summary.observations}
}
