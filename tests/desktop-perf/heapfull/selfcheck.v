// SPDX-License-Identifier: GPL-2.0-or-later
// Production-active captured-log fixtures. All counters here are small, so
// fixture arithmetic is independent of the observer's checked comparison.
module heapfull

import perfheap
import perfreport

struct FixtureCounts {
mut:
	objects [14]u64
	pages [14]u64
	large u64
	written u64
}

fn fixture_counts() FixtureCounts {
	mut counts := FixtureCounts{large: 9}
	for index in 0 .. 14 {
		counts.objects[index] = 20
		counts.pages[index] = 4
	}
	return counts
}

fn fixture_snapshot(counts FixtureCounts) string {
	mut text := '# class      size    objects   pages\n'
	for index, size in perfheap.class_sizes {
		text += 'size-' + size.str() + ' ' + size.str() + ' ' + counts.objects[index].str()
			+ ' ' + counts.pages[index].str() + '\n'
	}
	return text + 'large - - ' + counts.large.str() + '\n# written after free ' + counts.written.str() + '\n'
}

fn fixture_block(identity string, phase string, counts FixtureCounts) string {
	body := fixture_snapshot(counts)
	return fixture_raw_block(identity, phase, body)
}

fn fixture_raw_block(identity string, phase string, body string) string {
	return 'PERF-HEAP-BEGIN ' + identity + ' phase=' + phase + ' schema=vinix-slab-14-4k-v1 bytes='
		+ body.len.str() + '\n' + body + 'PERF-HEAP-END ' + identity + ' phase=' + phase + '\n'
}

fn fixture_deltas(identity string, before FixtureCounts, after FixtureCounts) string {
	prefix := 'PERF-HEAP-DELTA ' + identity + ' '
	mut text := ''
	for index, size in perfheap.class_sizes {
		text += prefix + 'class=size-' + size.str() + ' objects='
			+ signed(i64(after.objects[index]) - i64(before.objects[index]))
			+ ' pages=' + signed(i64(after.pages[index]) - i64(before.pages[index])) + '\n'
	}
	text += prefix + 'class=large pages=' + signed(i64(after.large) - i64(before.large)) + '\n'
	return text + prefix + 'written_before=' + before.written.str() + ' written_after=' + after.written.str()
		+ ' written_after_free=' + signed(i64(after.written) - i64(before.written)) + '\n'
}

fn fixture_cohort(identity string, before FixtureCounts, after FixtureCounts) string {
	return fixture_block(identity, 'before', before) + fixture_block(identity, 'after', after)
		+ fixture_deltas(identity, before, after)
}

fn fixture_summaries() string {
	mut lines := []string{}
	for op in perfreport.general_ops {
		lines << 'PERF-OPS variant=new scenario=ops round=1 op=' + op + ' dir=/tmp count=200 bytes_per_op=0'
	}
	for directory in ['/tmp', '/root'] {
		for op in perfreport.file_ops {
			lines << 'PERF-OPS variant=new scenario=ops round=1 op=' + op + ' dir=' + directory + ' count=200 bytes_per_op=0'
		}
	}
	for program in perfreport.churn_programs {
		lines << 'PERF-CHURN variant=new scenario=churn round=1 program="' + program + '" runs=300 retained_kb=0 per_run_bytes=0'
	}
	lines << 'PERF-CACHE variant=new scenario=cache round=1 written_mb=32 used_mb=32 cached_kb=32768 slab_kb=256'
	for scenario in ['idle', 'apps', 'drag'] {
		lines << 'PERF-RESULT variant=new scenario=' + scenario + ' round=1 seconds=5 processes=4 desktop_cpu=1 apps_cpu=0 total_cpu=1 desktop_mb=2 apps_mb=0 total_mb=2 system_used_mb=20 physical_mb=2'
	}
	return lines.join('\n') + '\n' + perfreport.done + '\n'
}

// Only the first cohort is changed; its full delta rows remain arithmetically
// correct and the legacy derived rate stays zero. Rejection must use the raw
// per-class/page/footer policy, including +16 bytes hidden by division by 200.
fn fixture(change string) !string {
	mut text := ''
	for index, identity in expected_identities() {
		mut before := fixture_counts()
		mut after := fixture_counts()
		if index == 0 {
			match change {
				'clean' {}
				'object' {
					after.objects[0]++
					require((i64(after.objects[0]) - i64(before.objects[0])) * 16 == 16
						&& 16 / 200 == 0, 'hidden object fixture no longer hides its derived rate')!
				}
				'page' { after.pages[0]++ }
				'cancel' {
					after.objects[0] += 2
					after.objects[1]--
					require((i64(after.objects[0]) - i64(before.objects[0])) * 16
						+ (i64(after.objects[1]) - i64(before.objects[1])) * 32 == 0,
						'cancelling fixture no longer cancels its object bytes')!
				}
				'large' { after.large++ }
				'reclaim' { after.objects[0]-- }
				'footer-new' { after.written = 1 }
				'footer-preexisting' { before.written = 1; after.written = 1 }
				'footer-decrease' { before.written = 1 }
				else { return error('unknown full heap fixture mutation') }
			}
		}
		text += fixture_cohort(identity, before, after)
	}
	return text + fixture_summaries()
}

fn replace_once(text string, old string, replacement string) !string {
	at := text.index(old) or { return error('full heap fixture replacement target missing') }
	return text[..at] + replacement + text[at + old.len..]
}

fn refuse(text string, label string) ! {
	mut refused := false
	inspect(text.bytes()) or { refused = true }
	require(refused, 'accepted invalid full heap fixture: ' + label)!
}

// Returns completed controls; no assert or required call can disappear with
// -prod. A fresh complete 40-cohort fixture backs each refusal.
pub fn selfcheck() !int {
	base := fixture('clean')!
	mut checks := 0
	valid := inspect(base.bytes())!
	require(valid.cohorts == 40 && valid.snapshots == 80 && valid.delta_rows == 640
		&& valid.ops == 36 && valid.slab_rows == 0 && valid.observations.len == 5,
		'complete full heap fixture counts or observation preservation differ')!
	require(fixture_summaries().split_into_lines().len == 45,
		'fixture must retain exactly 44 measurements plus DONE')!
	checks++
	crlf := inspect(base.replace('\n', '\r\n').bytes())!
	require(crlf.cohorts == 40 && crlf.delta_rows == 640, 'CRLF serial protocol was rejected')!
	checks++
	physical := base.replace('retained_kb=0 per_run_bytes=0', 'retained_kb=4 per_run_bytes=13')
		.replace('used_mb=32 cached_kb=32768', 'used_mb=40 cached_kb=40960')
	observed := inspect(physical.bytes())!
	require(observed.observations.any(it.contains('retained_kb=4'))
		&& observed.observations.any(it.contains('cached_kb=40960')),
		'physical/cache observations were rejected or omitted')!
	checks++
	for change in ['object', 'page', 'cancel', 'large', 'reclaim', 'footer-new',
		'footer-preexisting', 'footer-decrease'] {
		refuse(fixture(change)!, change)!
		checks++
	}
	identities := expected_identities()
	identity := identities[0]
	counts := fixture_counts()
	before := fixture_block(identity, 'before', counts)
	after := fixture_block(identity, 'after', counts)
	deltas := fixture_deltas(identity, counts, counts)
	cohort := before + after + deltas
	body := fixture_snapshot(counts)
	begin := 'PERF-HEAP-BEGIN ' + identity + ' phase=before schema=vinix-slab-14-4k-v1 bytes=' + body.len.str() + '\n'
	end := 'PERF-HEAP-END ' + identity + ' phase=before\n'
	delta := 'PERF-HEAP-DELTA ' + identity + ' class=size-16 objects=+0 pages=+0\n'
	delta32 := 'PERF-HEAP-DELTA ' + identity + ' class=size-32 objects=+0 pages=+0\n'
	footer := 'PERF-HEAP-DELTA ' + identity + ' written_before=0 written_after=0 written_after_free=+0\n'
	for bad in [
		replace_once(base, after, '')!,
		replace_once(base, before, '')!,
		replace_once(base, cohort, '')!,
		replace_once(base, end, '')!,
		replace_once(base, '# written after free 0\n', '# written after free 0')!,
		replace_once(base, 'size-16 16 20 4\n', '')!,
		replace_once(base, before, fixture_raw_block(identity, 'before', body.replace('size-16 16 20 4\n', '')))!,
		replace_once(base, before, fixture_raw_block(identity, 'before', body[..body.len - 1]))!,
		replace_once(base, 'size-16 16 20 4\nsize-32 32 20 4\n', 'size-32 32 20 4\nsize-16 16 20 4\n')!,
		replace_once(base, 'size-32 32 20 4\n', 'size-16 16 20 4\n')!,
		replace_once(base, begin, begin.replace('bytes=' + body.len.str(), 'bytes=' + (body.len + 1).str()))!,
		replace_once(base, begin, begin.replace('bytes=' + body.len.str(), 'bytes=' + (body.len - 1).str()))!,
		replace_once(base, begin, begin.replace('bytes=' + body.len.str(), 'bytes=0' + body.len.str()))!,
		replace_once(base, begin, begin.replace('bytes=' + body.len.str(), 'bytes=4097'))!,
		replace_once(base, begin, begin.replace('op="stat"', 'op="unknown"'))!,
		replace_once(base, begin, begin.replace('round=1', 'round=2'))!,
		replace_once(base, begin, begin.replace('variant=new', 'variant=new variant=new'))!,
		replace_once(base, begin, begin.replace('schema=vinix-slab-14-4k-v1', 'schema=unknown'))!,
		replace_once(base, begin, begin.replace('phase=before', 'phase=other'))!,
		replace_once(base, begin, 'serial-prefix ' + begin)!,
		replace_once(base, after, before)!,
		replace_once(base, after, fixture_block(identities[1], 'after', counts))!,
		replace_once(base, 'size-16 16 20 4\n', 'size-16 16 20 4\n' + begin)!,
		replace_once(base, end, end.replace('phase=before', 'phase=after'))!,
		replace_once(base, 'size-16 16 20 4\n', 'size-16 16 20\r4\n')!,
		replace_once(base, 'size-16 16 20 4\n', 'size-16 16 20 \x80\n')!,
		replace_once(base, delta, '')!,
		replace_once(base, delta, delta + delta)!,
		replace_once(base, delta + delta32, delta32 + delta)!,
		replace_once(base, delta, delta.replace('objects=+0', 'objects=+1'))!,
		replace_once(base, delta, delta.replace('pages=+0', 'pages=+1'))!,
		replace_once(base, delta, delta.replace('size-16', 'size-17'))!,
		replace_once(base, delta, delta.replace('objects=+0', 'objects=0'))!,
		replace_once(base, delta, delta.replace('objects=+0', 'objects=+9223372036854775808'))!,
		replace_once(base, footer, '')!,
		replace_once(base, footer, footer.replace('written_before=0', 'written_before=1'))!,
		replace_once(base, footer, footer.replace('written_after=0', 'written_after=1'))!,
		replace_once(base, footer, footer.replace('written_after_free=+0', 'written_after_free=+1'))!,
		replace_once(base, perfreport.done, '')!,
		base + cohort,
		base + end,
		base + delta,
		base + 'PERF-HEAP-UNKNOWN\n',
		base + 'PERF-HEAP-BEGIN',
		base + 'PERF-ERROR fixture failure\n',
		base + perfreport.done + '\n',
	] {
		refuse(bad, 'framing, schema, identity, length, completeness or arithmetic control')!
		checks++
	}
	return checks
}
