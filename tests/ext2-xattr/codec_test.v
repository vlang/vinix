module ext2

fn rebuilt(old voidptr, index u8, name string, value []u8, removing bool) []u8 {
	mut output := []u8{len: 4096}
	ea_rebuild(old, output.data, output.len, index, name, value.data, value.len, removing) or { panic('rebuild failed') }
	assert ea_validate(output.data, output.len)
	return output
}

fn test_sorted_entries_round_trip_and_removal() {
	first := rebuilt(unsafe { nil }, 6, 'capability', [u8(1), 0, 2], false)
	second := rebuilt(first.data, 1, 'long-name', [u8(7)], false)
	third := rebuilt(second.data, 1, 'a', []u8{}, false)
	assert ea_find(third.data, 1, 'a') == 32
	assert ea_find(third.data, 1, 'long-name') == 52
	cap := ea_entry(third.data, ea_find(third.data, 6, 'capability'))
	assert cap.value_size == 3
	assert third[int(cap.value_offset)] == 1
	assert third[int(cap.value_offset) + 2] == 2
	removed := rebuilt(third.data, 1, 'long-name', []u8{}, true)
	assert ea_find(removed.data, 1, 'long-name') == -1
	assert ea_find(removed.data, 6, 'capability') >= 0
	assert unsafe { &EAHeader(removed.data) }.hash != 0
}

fn test_replacement_capacity_failure_preserves_original() {
	first := rebuilt(unsafe { nil }, 1, 'a', [u8(4)], false)
	second := rebuilt(first.data, 1, 'a', [u8(5), 6], false)
	entry := ea_entry(second.data, ea_find(second.data, 1, 'a'))
	assert entry.value_size == 2
	assert second[int(entry.value_offset)] == 5
	mut output := []u8{len: 4096}
	large := []u8{len: 4096}
	mut failed := false
	ea_rebuild(first.data, output.data, output.len, 1, 'a', large.data, large.len, false) or { failed = true }
	assert failed
	assert ea_validate(first.data, first.len)
	assert first[int(ea_entry(first.data, 32).value_offset)] == 4
}

fn test_malformed_blocks_are_rejected() {
	valid := rebuilt(unsafe { nil }, 1, 'a', [u8(1), 2, 3, 4], false)
	mut bad := valid.clone()
	mut header := unsafe { &EAHeader(bad.data) }
	header.refs = 0
	assert !ea_validate(bad.data, bad.len)
	bad = valid.clone()
	mut entry := ea_entry(bad.data, 32)
	entry.value_offset = 32
	assert !ea_validate(bad.data, bad.len)
	bad = valid.clone()
	entry = ea_entry(bad.data, 32)
	entry.value_size = u32(-1)
	assert !ea_validate(bad.data, bad.len)
	bad = valid.clone()
	entry = ea_entry(bad.data, 32)
	entry.value_block = 1
	assert !ea_validate(bad.data, bad.len)
	bad = valid.clone()
	bad[48] = 0
	assert !ea_validate(bad.data, bad.len)
	assert !ea_validate(valid.data, 31)
	second := rebuilt(valid.data, 4, 'b', [u8(5)], false)
	bad = second.clone()
	entry = ea_entry(bad.data, 52)
	entry.value_offset = ea_entry(bad.data, 32).value_offset
	assert !ea_validate(bad.data, bad.len)
}

fn test_shared_header_and_unknown_indexes_survive() {
	mut old := rebuilt(unsafe { nil }, 5, 'private', [u8(9)], false)
	mut header := unsafe { &EAHeader(old.data) }
	header.refs = 2
	assert ea_validate(old.data, old.len)
	new := rebuilt(old.data, 1, 'visible', [u8(7)], false)
	assert unsafe { &EAHeader(old.data) }.refs == 2
	assert unsafe { &EAHeader(new.data) }.refs == 1
	assert ea_find(new.data, 5, 'private') >= 0
}
