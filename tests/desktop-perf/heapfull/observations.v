// SPDX-License-Identifier: GPL-2.0-or-later
// Diagnostic observation only. The existing strict admission API is unchanged.
module heapfull

import math.big
import perfheap
import perfreport

pub struct ObservedClass {
pub:
	size u64
	objects_before string
	objects_after string
	objects_delta string
	pages_before string
	pages_after string
	pages_delta string
}

pub struct ObservedCohort {
pub:
	sequence int
	identity string
	before_bytes int
	after_bytes int
	classes []ObservedClass
	large_pages_before string
	large_pages_after string
	large_pages_delta string
	written_before string
	written_after string
	written_delta string
	object_bytes_delta string
	reported_pages_before string
	reported_pages_after string
	reported_pages_delta string
	nonzero_delta bool
	corruption_counter_observed bool
}

pub struct Observations {
pub:
	qualification bool
	measurements int
	cohorts int
	snapshots int
	delta_rows int
	class_rows int
	nonzero_delta_cohorts int
	nonzero_object_rows int
	nonzero_page_rows int
	nonzero_large_rows int
	corruption_counter_cohorts int
	physical_and_cache_observations []string
	pairs []ObservedCohort
}

// Sum the reported fourteen slab classes and large pages exactly, even when
// individually valid u64 counters exceed u64 storage after addition.
fn reported_pages(snapshot &perfheap.Snapshot) !big.Integer {
	mut total := big.integer_from_string(snapshot.large_pages.str())!
	for row in snapshot.classes {
		total += big.integer_from_string(row.pages.str())!
	}
	return total
}

// Validate framing, the complete measurement table and every canonical raw
// delta, then preserve all values. No zero-delta or corruption policy is run.
// Success proves observation consistency only; qualification is always false.
pub fn observe(transcript []u8) !Observations {
	require(transcript.len > 0 && transcript.len <= max_transcript_bytes,
		'captured serial transcript must contain at most 32 MiB')!
	summary := perfreport.inspect(transcript, ['new'], ['ops', 'churn', 'cache', 'idle', 'apps', 'drag'],
		1, false, none)
	require(summary.errors.len == 0 && summary.rows.len == 44,
		'incomplete or invalid performance observations: ' + summary.errors.join('; '))!
	identities := expected_identities()
	require(identities.len == 40, 'observation cohort table must contain exactly 40 identities')!
	mut known := map[string]bool{}
	for identity in identities {
		require(identity !in known, 'duplicate observation cohort table identity')!
		known[identity] = true
	}
	mut seen := map[string]bool{}
	mut pairs := []ObservedCohort{cap: 40}
	text := transcript.bytestr()
	mut offset := 0
	mut snapshots := 0
	mut deltas := 0
	mut object_rows := 0
	mut page_rows := 0
	mut large_rows := 0
	mut changed := 0
	mut corruption := 0
	for offset < text.len {
		line := line_at(text, offset)!
		offset = line.next
		if !line.text.contains(protocol_marker) { continue }
		begin := parse_begin(protocol_line(line)!, known)!
		require(begin.phase == 'before' && begin.identity !in seen,
			'orphan, reordered or duplicate observation cohort')!
		mut before := perfheap.Snapshot{}
		mut after := perfheap.Snapshot{}
		read_snapshot(text, begin, unsafe { &offset }, unsafe { &before })!
		after_line := line_at(text, offset)!
		after_begin := parse_begin(protocol_line(after_line)!, known)!
		require(after_begin.identity == begin.identity && after_begin.phase == 'after',
			'interleaved, missing or reordered observation pair')!
		offset = after_line.next
		read_snapshot(text, after_begin, unsafe { &offset }, unsafe { &after })!
		deltas += read_deltas(text, begin.identity, unsafe { &before }, unsafe { &after },
			unsafe { &offset })!
		mut delta := perfheap.Delta{}
		perfheap.compare(unsafe { &before }, unsafe { &after }, unsafe { &delta })!
		mut rows := []ObservedClass{cap: 14}
		mut nonzero := delta.large_pages != 0 || delta.written_after_free != 0
		for index, row in delta.classes {
			if row.objects != 0 { object_rows++; nonzero = true }
			if row.pages != 0 { page_rows++; nonzero = true }
			rows << ObservedClass{size: row.size,
				objects_before: before.classes[index].objects.str(),
				objects_after: after.classes[index].objects.str(), objects_delta: signed(row.objects),
				pages_before: before.classes[index].pages.str(),
				pages_after: after.classes[index].pages.str(), pages_delta: signed(row.pages)}
		}
		if nonzero { changed++ }
		if delta.large_pages != 0 { large_rows++ }
		written := before.written_after_free != 0 || after.written_after_free != 0
		if written { corruption++ }
		before_pages := reported_pages(unsafe { &before })!
		after_pages := reported_pages(unsafe { &after })!
		pairs << ObservedCohort{sequence: pairs.len + 1, identity: begin.identity,
			before_bytes: before.raw_len, after_bytes: after.raw_len, classes: rows,
			large_pages_before: before.large_pages.str(), large_pages_after: after.large_pages.str(),
			large_pages_delta: signed(delta.large_pages), written_before: before.written_after_free.str(),
			written_after: after.written_after_free.str(), written_delta: signed(delta.written_after_free),
			object_bytes_delta: signed(delta.bytes), reported_pages_before: before_pages.str(),
			reported_pages_after: after_pages.str(), reported_pages_delta: (after_pages - before_pages).str(),
			nonzero_delta: nonzero, corruption_counter_observed: written}
		seen[begin.identity] = true
		snapshots += 2
	}
	require(seen.len == 40 && pairs.len == 40 && snapshots == 80 && deltas == 640,
		'observations require 40 complete pairs, 80 snapshots and 640 canonical delta rows')!
	mut physical := []string{}
	for line in text.split_into_lines() {
		if line.contains('PERF-CHURN ') || line.contains('PERF-CACHE ') { physical << line.clone() }
	}
	return Observations{qualification: false, measurements: summary.rows.len, cohorts: pairs.len,
		snapshots: snapshots, delta_rows: deltas, class_rows: pairs.len * 14,
		nonzero_delta_cohorts: changed, nonzero_object_rows: object_rows,
		nonzero_page_rows: page_rows, nonzero_large_rows: large_rows,
		corruption_counter_cohorts: corruption, physical_and_cache_observations: physical, pairs: pairs}
}
