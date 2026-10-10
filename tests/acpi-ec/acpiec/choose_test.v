// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// Which of firmware's two descriptions of the controller is believed.
module acpiec

fn described(data u64, command u64, gpe u64) Description {
	return Description{
		valid:   true
		data:    data
		command: command
		has_gpe: true
		gpe:     gpe
	}
}

fn test_no_description_is_no_controller() {
	choice := choose(Description{}, Description{}, false)
	assert choice.source == .none
	assert !usable(choice.found)
}

fn test_one_description_is_the_one_used() {
	table := choose(described(0x62, 0x66, 0x17), Description{}, false)
	assert table.source == .table
	assert table.found.data == 0x62
	assert table.found.command == 0x66
	assert table.found.gpe == 0x17
	device := choose(Description{}, described(0x62, 0x66, 0x11), false)
	assert device.source == .device
	assert device.found.gpe == 0x11
	assert !device.conflict
}

fn test_where_both_agree_the_table_names_the_event() {
	choice := choose(described(0x62, 0x66, 0x17), described(0x62, 0x66, 0x03), false)
	assert choice.source == .both
	assert choice.found.gpe == 0x17
	assert !choice.conflict
	// Unless the machine is known to have it the other way round.
	trusted := choose(described(0x62, 0x66, 0x17), described(0x62, 0x66, 0x03), true)
	assert trusted.found.gpe == 0x03
	// A device with no _GPE has nothing to be trusted with.
	mut silent := described(0x62, 0x66, 0)
	silent.has_gpe = false
	kept := choose(described(0x62, 0x66, 0x17), silent, true)
	assert kept.found.has_gpe
	assert kept.found.gpe == 0x17
}

fn test_where_they_disagree_the_device_is_believed() {
	// The table has the two ports the wrong way round.
	choice := choose(described(0x66, 0x62, 0x17), described(0x62, 0x66, 0x11), false)
	assert choice.source == .device
	assert choice.conflict
	assert choice.found.data == 0x62
	assert choice.found.command == 0x66
	assert choice.found.gpe == 0x11
}

fn test_a_description_of_nothing_is_not_used() {
	// Zeroes, as some firmware fills its table with.
	assert !usable(described(0, 0, 0))
	assert !usable(described(0x62, 0, 0))
	// Not I/O ports.
	assert !usable(described(0xfed00062, 0xfed00066, 0))
	// One register cannot be both.
	assert !usable(described(0x62, 0x62, 0))
	assert !usable(Description{
		data:    0x62
		command: 0x66
	})
	choice := choose(described(0, 0, 0x17), described(0x62, 0x66, 0x11), false)
	assert choice.source == .device
	assert !choice.conflict
	assert source_name(choice.source) == 'namespace'
}
