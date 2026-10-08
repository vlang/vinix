// SPDX-License-Identifier: GPL-2.0-or-later
module prepcore

fn test_elf_header_boundaries() {
	mut data := []u8{len: 64}
	data[0] = 0x7f
	data[1] = `E`
	data[2] = `L`
	data[3] = `F`
	data[4] = 2
	data[5] = 1
	data[6] = 1
	data[16] = 3
	data[18] = 62
	assert elf(data, true, true, 62)
	assert !elf(data[..63], false, true, 62)
	data << 1
	assert !elf(data, true, true, 62)
	assert elf(data, false, true, 62)
	data[16] = 2
	assert !elf(data, false, true, 62)
	assert elf(data, false, false, 62)
	data[17] = 1
	assert !elf(data, false, false, 62)
	data[17] = 0
	data[19] = 1
	assert !elf(data, false, false, 62)
}

fn test_environment_keeps_first_insertion_order() {
	mut values := [Setting{'HOME', '/home/dota2'}, Setting{'LP_NUM_THREADS', '2'}]
	set_environment(mut values, 'HOME', 'literal\n\x00')
	set_environment(mut values, 'EXTRA', 'new')
	assert values.len == 3
	assert values[0].name == 'HOME'
	assert values[0].value == 'literal\n\x00'
	assert values[1].name == 'LP_NUM_THREADS'
	assert values[2].name == 'EXTRA'
}

fn test_path_component_sort_order() {
	mut values := ['lib/a-z', 'lib/a/x', 'lib/a', 'lib/a!']
	values.sort_with_compare(path_compare)
	assert values == ['lib/a', 'lib/a/x', 'lib/a!', 'lib/a-z']
}
