// SPDX-License-Identifier: GPL-2.0-or-later
module winecutfixture

fn test_names_are_unique_sorted_and_keep_small_fixture() {
	assert names(false) == ['a.dll', 'b.dll', 'c.dll']
	large := names(true)
	assert large.len == 741
	assert large[2] == 'builtin-0002.dll'
	assert large[739] == 'builtin-0739.dll'
	assert large.last() == 'z.dll'
	for i in 1 .. large.len { assert large[i - 1] < large[i] }
}

fn test_each_replacement_has_stage_then_rename_then_source_sync() {
	for old_count in [2, 740] {
		for index in 0 .. old_count {
			stage := boundary(index * 3 + 1, old_count)!
			assert stage == Boundary{replaced: index, staged: true}
			for offset in [2, 3] {
				assert boundary(index * 3 + offset, old_count)! == Boundary{replaced: index + 1}
			}
		}
		for offset in [1, 2] {
			assert boundary(old_count * 3 + offset, old_count)! == Boundary{replaced: old_count, added: true}
		}
		for point in [0, old_count * 3 + 3] {
			if _ := boundary(point, old_count) { assert false }
		}
	}
}

fn test_selected_large_cuts_cover_middle_last_and_both_completion_syncs() {
	assert points(false, false) == [1, 2, 3]
	assert points(false, true) == [1, 2, 3, 4, 5, 6, 7, 8]
	assert points(true, false) == [1112, 2219, 2221, 2222]
	assert boundary(1112, 740)! == Boundary{replaced: 371}
	assert boundary(2219, 740)! == Boundary{replaced: 740}
	assert boundary(2221, 740)! == Boundary{replaced: 740, added: true}
	assert boundary(2222, 740)! == Boundary{replaced: 740, added: true}
}
