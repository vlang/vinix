// SPDX-License-Identifier: GPL-2.0-or-later
// Independent diagnostic outcomes using the existing complete producer fixtures.
module heapfull

import perfreport

fn refuse_observation(text string) ! {
	mut refused := false
	observe(text.bytes()) or { refused = true }
	require(refused, 'malformed or incomplete transcript was observed as complete')!
}

pub fn observation_selfcheck() !int {
	base := fixture('clean')!
	clean := observe(base.bytes())!
	require(!clean.qualification && clean.measurements == 44 && clean.cohorts == 40
		&& clean.snapshots == 80 && clean.delta_rows == 640 && clean.class_rows == 560
		&& clean.nonzero_delta_cohorts == 0 && clean.corruption_counter_cohorts == 0,
		'complete diagnostic counts or nonqualification marker differ')!
	require(clean.pairs[0].classes.len == 14 && clean.pairs[0].reported_pages_before == '65'
		&& clean.pairs[0].reported_pages_after == '65' && clean.pairs[0].reported_pages_delta == '0',
		'complete diagnostic class rows or exact total-page values differ')!
	mut checks := 1
	for change in ['object', 'page', 'cancel', 'large', 'reclaim', 'footer-new',
		'footer-preexisting', 'footer-decrease'] {
		text := fixture(change)!
		observed := observe(text.bytes())!
		require(!observed.qualification && observed.pairs.len == 40 && observed.snapshots == 80,
			'nonzero observation stopped early or became qualification: ' + change)!
		first := observed.pairs[0]
		match change {
			'object' { require(first.classes[0].objects_delta == '+1' && first.object_bytes_delta == '+16', 'hidden object delta omitted')! }
			'page' { require(first.classes[0].pages_before == '4' && first.classes[0].pages_after == '5'
				&& first.classes[0].pages_delta == '+1' && first.reported_pages_delta == '1', 'backing-page change omitted')! }
			'cancel' { require(first.classes[0].objects_delta == '+2' && first.classes[1].objects_delta == '-1'
				&& first.object_bytes_delta == '+0' && observed.nonzero_object_rows == 2, 'cancelling exact rows omitted')! }
			'large' { require(first.large_pages_before == '9' && first.large_pages_after == '10'
				&& first.large_pages_delta == '+1', 'large-page change omitted')! }
			'reclaim' { require(first.classes[0].objects_delta == '-1', 'negative object delta omitted')! }
			'footer-new' { require(first.written_before == '0' && first.written_after == '1'
				&& first.written_delta == '+1' && first.corruption_counter_observed, 'new corruption counter omitted')! }
			'footer-preexisting' { require(first.written_before == '1' && first.written_after == '1'
				&& first.written_delta == '+0' && first.corruption_counter_observed, 'preexisting counter hidden by zero delta')! }
			else { require(first.written_before == '1' && first.written_after == '0'
				&& first.written_delta == '-1' && first.corruption_counter_observed, 'decreasing counter hid earlier corruption')! }
		}
		// The strict API remains required to refuse this exact same transcript.
		refuse(text, 'diagnostic observation must not alter strict refusal')!
		checks++
	}
	identities := expected_identities()
	counts := fixture_counts()
	mut changed := fixture_counts()
	changed.objects[0]++
	changed.pages[7]++
	mut every := ''
	for identity in identities { every += fixture_cohort(identity, counts, changed) }
	every += fixture_summaries()
	all := observe(every.bytes())!
	require(!all.qualification && all.nonzero_delta_cohorts == 40 && all.nonzero_object_rows == 40
		&& all.nonzero_page_rows == 40 && all.pairs.last().classes[7].pages_delta == '+1',
		'all-cohort changes were omitted or observation stopped at the first change')!
	refuse(every, 'all nonzero cohorts remain strict failures')!
	checks++
	mut late := fixture_counts()
	late.large++
	late.written = 2
	last_pair := fixture_cohort(identities.last(), counts, counts)
	late_text := replace_once(fixture('page')!, last_pair, fixture_cohort(identities.last(), counts, late))!
	observed_late := observe(late_text.bytes())!
	require(observed_late.nonzero_delta_cohorts == 2 && observed_late.corruption_counter_cohorts == 1
		&& observed_late.pairs.last().written_after == '2' && observed_late.pairs.last().large_pages_delta == '+1',
		'late corruption or large-page change disappeared after an earlier page delta')!
	checks++
	// A literal oracle prevents total-page addition from silently wrapping u64.
	mut maximum := fixture_counts()
	for index in 0 .. 14 { maximum.pages[index] = u64(18446744073709551615) }
	wide := replace_once(base, fixture_cohort(identities[0], counts, counts),
		fixture_cohort(identities[0], maximum, maximum))!
	wide_report := observe(wide.bytes())!
	require(wide_report.pairs[0].classes[0].pages_before == '18446744073709551615'
		&& wide_report.pairs[0].reported_pages_before == '258254417031933722619'
		&& wide_report.pairs[0].reported_pages_delta == '0', 'full-width counters or aggregate pages lost precision')!
	checks++
	crlf := observe(late_text.replace('\n', '\r\n').bytes())!
	require(crlf.pairs.len == 40 && crlf.pairs.last().written_after == '2', 'CRLF observation differs')!
	checks++
	before := fixture_block(identities[0], 'before', counts)
	after := fixture_block(identities[0], 'after', counts)
	cohort := fixture_cohort(identities[0], counts, counts)
	delta := 'PERF-HEAP-DELTA ' + identities[0] + ' class=size-16 objects=+0 pages=+0\n'
	end := 'PERF-HEAP-END ' + identities[0] + ' phase=after\n'
	for malformed in [
		'',
		replace_once(base, before, '')!,
		replace_once(base, after, '')!,
		replace_once(base, cohort, '')!,
		replace_once(base, after, before)!,
		replace_once(base, after, fixture_block(identities[1], 'after', counts))!,
		replace_once(base, '# written after free 0\n', '# written after free 0')!,
		replace_once(base, end, '')!,
		replace_once(base, delta, '')!,
		replace_once(base, delta, delta + delta)!,
		replace_once(base, delta, delta.replace('pages=+0', 'pages=+1'))!,
		replace_once(base, delta, delta.replace('objects=+0', 'objects=-1'))!,
		replace_once(base, 'size-16 16 20 4\n', 'size-16 16 20 5\n')!,
		replace_once(base, 'size-16 16 20 4\n', 'size-16 16 20')!,
		replace_once(base, perfreport.done, '')!,
		base + perfreport.done + '\n',
		base + cohort,
		base + 'PERF-HEAP-UNKNOWN\n',
		base + 'PERF-HEAP-BEGIN',
		base + 'PERF-ERROR diagnostic must not hide producer failure\n',
	] {
		refuse_observation(malformed)!
		checks++
	}
	return checks
}
