// SPDX-License-Identifier: GPL-2.0-or-later
module main

// Row action names are static: frames borrow them and the entry names.
const archive_row_actions = [
	'archive.row.0',
	'archive.row.1',
	'archive.row.2',
	'archive.row.3',
	'archive.row.4',
	'archive.row.5',
	'archive.row.6',
	'archive.row.7',
	'archive.row.8',
	'archive.row.9',
	'archive.row.10',
	'archive.row.11',
	'archive.row.12',
	'archive.row.13',
	'archive.row.14',
	'archive.row.15',
	'archive.row.16',
	'archive.row.17',
	'archive.row.18',
	'archive.row.19',
	'archive.row.20',
	'archive.row.21',
	'archive.row.22',
	'archive.row.23',
	'archive.row.24',
	'archive.row.25',
	'archive.row.26',
	'archive.row.27',
	'archive.row.28',
	'archive.row.29',
	'archive.row.30',
	'archive.row.31',
]

fn (mut a ArchiveApp) set_entry_selection(selected bool) {
	if a.operation != .idle || a.loaded_path.len == 0 { return }
	for mut entry in a.entries { entry.selected = selected }
	a.focus = -1
	a.select_all = false
}

fn (mut a ArchiveApp) toggle_entry(index int) {
	if a.operation != .idle || a.loaded_path.len == 0 || index < 0 || index >= a.entries.len {
		return
	}
	selected := !a.entries[index].selected
	name := a.entries[index].name
	directory := a.entries[index].directory
	a.entries[index].selected = selected
	for mut entry in a.entries {
		if directory && archive_is_parent(name, entry.name) {
			entry.selected = selected
		} else if !selected && entry.directory && archive_is_parent(entry.name, name) {
			// Removing a member turns its containing folder into individual
			// selections. The other members keep their existing flags.
			entry.selected = false
		}
	}
	a.focus = -1
	a.select_all = false
}
