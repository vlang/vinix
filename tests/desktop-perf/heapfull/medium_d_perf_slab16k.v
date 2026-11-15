// SPDX-License-Identifier: GPL-2.0-or-later
module heapfull

fn medium_controls(base string) !int {
	mut checks := 0
	identity := expected_identities()[0]
	before := fixture_counts()
	for i in 14 .. 18 {
		for backing in [false, true] {
			mut after := fixture_counts()
			if backing { after.pages[i]++ } else { after.objects[i]++ }
			text := replace_once(base, fixture_cohort(identity, before, before), fixture_cohort(identity, before, after))!
			refuse(text, 'medium allocation or backing page must prevent qualification')!
			observed := observe(text.bytes())!
			row := observed.pairs[0].classes[i]
			require(!observed.qualification && observed.nonzero_delta_cohorts == 1
				&& if backing { row.pages_delta == '+1' && row.objects_delta == '+0' }
				else { row.objects_delta == '+1' && row.pages_delta == '+0' }, 'medium observation omitted')!
			checks++
		}
		class := [2688, 4048, 5392, 8096]![i - 14]
		row := 'PERF-HEAP-DELTA ${identity} class=size-${class} objects=+0 pages=+0\n'
		refuse(replace_once(base, row, '')!, 'missing medium delta')!
		checks++
	}
	refuse(base.replace('vinix-slab-18-16k-v1', 'vinix-slab-14-4k-v1'), 'foreign schema')!
	checks++
	console := base.replace('\n', '\r\r\n')
	parsed := inspect(console.bytes())!
	observed := observe(console.bytes())!
	require(parsed.delta_rows == 800 && observed.delta_rows == 800 && !observed.qualification,
		'ARM console terminal sequence rejected')!
	checks++
	bad := base.replace('\n', '\r\r\r\n')
	refuse(bad, 'excess console carriage returns')!
	refuse_observation(bad)!
	checks++
	return checks
}
