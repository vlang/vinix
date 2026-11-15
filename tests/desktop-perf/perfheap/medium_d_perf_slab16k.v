// SPDX-License-Identifier: GPL-2.0-or-later
module perfheap

fn medium_controls(base string, before &Snapshot, after &Snapshot, delta &Delta) !int {
	mut checks := 0
	clean := fixture('20', '4', '9', '0')
	old_sizes := [u64(2704), 4064, 5424, 8144]!
	for i in 14 .. 18 {
		size := class_sizes[i]
		row := 'size-${size} ${size} 20 4\n'
		for bad in [base.replace(row, ''), base.replace(row, row + row),
			base.replace(row, 'size-${old_sizes[i - 14]} ${old_sizes[i - 14]} 20 4\n')] {
			refuse_parse(bad, after)!
			checks++
		}
		parse_snapshot(clean.str, clean.len, before)!
		parse_snapshot(clean.str, clean.len, after)!
		unsafe { after.classes[i] = ClassSnapshot{size: size, objects: 21, pages: 4} }
		compare(before, after, delta)!
		require(delta.bytes == i64(size) && delta.classes[i].objects == 1,
			'medium-class object bytes lost')!
		refuse_flatness(before, after)!
		checks++
		unsafe { after.classes[i] = ClassSnapshot{size: size, objects: 20, pages: 5} }
		compare(before, after, delta)!
		require(delta.bytes == 0 && delta.classes[i].pages == 1, 'medium backing pages lost')!
		refuse_flatness(before, after)!
		checks++
	}
	mut legacy := base
	for size in [2688, 4048, 5392, 8096]! { legacy = legacy.replace('size-${size} ${size} 20 4\n', '') }
	refuse_parse(legacy, after)!
	checks++
	require_page_size(16384)!
	checks++
	for wrong in [0, 4096, 8192, 65536]! {
		mut refused := false
		require_page_size(wrong) or { refused = true }
		require(refused, 'wrong allocation page size admitted')!
		checks++
	}
	return checks
}
