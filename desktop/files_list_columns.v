// SPDX-License-Identifier: GPL-2.0-or-later
// Metadata and table layout for Files' list view.
module main

import ui2

const files_action_sort_name = 'files.list.sort.name'
const files_action_sort_modified = 'files.list.sort.modified'
const files_action_sort_size = 'files.list.sort.size'
const files_action_sort_kind = 'files.list.sort.kind'

enum FilesListSortColumn {
	name
	modified
	size
	kind
}

fn files_list_sort_column_for_action(action string) ?FilesListSortColumn {
	match action {
		files_action_sort_name { return .name }
		files_action_sort_modified { return .modified }
		files_action_sort_size { return .size }
		files_action_sort_kind { return .kind }
		else { return none }
	}
}

fn files_list_compare_entries(a &FileEntry, b &FileEntry, column FilesListSortColumn,
	descending bool) int {
	// Keep folders together at the top in every ordering, as in the existing list.
	if a.is_dir != b.is_dir {
		return if a.is_dir { -1 } else { 1 }
	}
	mut result := 0
	match column {
		.name { result = compare_strings(a.name, b.name) }
		.modified {
			if a.modified < b.modified { result = -1 }
			if a.modified > b.modified { result = 1 }
		}
		.size {
			if !a.is_dir {
				if a.size < b.size { result = -1 }
				if a.size > b.size { result = 1 }
			}
		}
		.kind {
			if !a.is_dir { result = compare_strings(a.kind_text, b.kind_text) }
		}
	}
	if result != 0 {
		return if descending { -result } else { result }
	}
	return compare_strings(a.name, b.name)
}

fn (mut b FileBrowser) apply_list_sort() {
	selected_name := if b.selected_row >= 0 && b.selected_row < b.entries.len {
		b.entries[b.selected_row].name.clone()
	} else {
		''
	}
	hover_name := if b.hover_row >= 0 && b.hover_row < b.entries.len {
		b.entries[b.hover_row].name.clone()
	} else {
		''
	}
	defer {
		unsafe {
			if selected_name.len > 0 { selected_name.free() }
			if hover_name.len > 0 { hover_name.free() }
		}
	}
	column := b.sort_column
	descending := b.sort_descending
	b.entries.sort_with_compare(fn [column, descending] (a &FileEntry, b &FileEntry) int {
		return files_list_compare_entries(a, b, column, descending)
	})
	b.selected_row = -1
	b.hover_row = -1
	for index in 0 .. b.entries.len {
		if b.entries[index].name == selected_name { b.selected_row = index }
		if b.entries[index].name == hover_name { b.hover_row = index }
		if b.entries[index].row_action.len > 0 {
			unsafe { b.entries[index].row_action.free() }
			b.entries[index].row_action = ''
		}
	}
	prefix := if b.action_prefix.len > 0 { b.action_prefix } else { files_action_row }
	prepare_file_rows(mut b.entries, prefix)
	b.scroll = 0
}

fn (mut b FileBrowser) set_list_sort(column FilesListSortColumn) {
	if b.sort_column == column {
		b.sort_descending = !b.sort_descending
	} else {
		b.sort_column = column
		b.sort_descending = false
	}
	b.apply_list_sort()
}

struct FilesListLayout {
	name_end       int
	modified_x     int
	modified_width int
	size_x         int
	size_width     int
	kind_x         int
	kind_width     int
	show_modified  bool
	show_kind      bool
}

fn files_list_layout(width int) FilesListLayout {
	show_modified := width >= 360
	show_kind := width >= 500
	modified_width := if show_modified { 140 } else { 0 }
	kind_width := if show_kind { 90 } else { 0 }
	size_width := 65
	right := width - files_padding - 2
	kind_x := right - kind_width
	size_x := kind_x - size_width
	modified_x := size_x - modified_width
	return FilesListLayout{
		name_end:       modified_x
		modified_x:     modified_x
		modified_width: modified_width
		size_x:         size_x
		size_width:     size_width
		kind_x:         kind_x
		kind_width:     kind_width
		show_modified:  show_modified
		show_kind:      show_kind
	}
}

fn files_list_modified_text(epoch i64, tz_offset_seconds i64) string {
	if epoch < 0 {
		return '—'.clone()
	}
	civil := civil_from_epoch(epoch + tz_offset_seconds)
	day := pad2(civil.day)
	year := civil.year.str()
	hour := pad2(civil.hour)
	minute := pad2(civil.minute)
	result := '${day} ${date_month_short(civil.month)} ${year} ${hour}:${minute}'
	unsafe {
		day.free()
		year.free()
		hour.free()
		minute.free()
	}
	return result
}

fn files_list_kind_text(name string, is_dir bool) string {
	if is_dir {
		return tr('files.kind.folder').clone()
	}
	lower := name.to_lower()
	defer { unsafe { lower.free() } }
	if lower.ends_with('.png') { return tr('files.kind.png').clone() }
	if lower.ends_with('.jpg') || lower.ends_with('.jpeg') || lower.ends_with('.jpe') {
		return tr('files.kind.jpeg').clone()
	}
	if lower.ends_with('.gif') { return tr('files.kind.gif').clone() }
	if lower.ends_with('.bmp') { return tr('files.kind.bmp').clone() }
	if lower.ends_with('.py') { return tr('files.kind.python').clone() }
	if lower.ends_with('.txt') { return tr('files.kind.plain_text').clone() }
	// A format's own name, the same in every language.
	if lower.ends_with('.md') { return 'Markdown'.clone() }
	if lower.ends_with('.log') { return tr('files.kind.log').clone() }
	if lower.ends_with('.tar') { return tr('files.kind.tar').clone() }
	if lower.ends_with('.json') { return tr('files.kind.json').clone() }
	if lower.ends_with('.conf') { return tr('files.kind.document').clone() }
	if lower.ends_with('.v') { return tr('files.kind.v_source').clone() }
	if lower.ends_with('.c') { return tr('files.kind.c_source').clone() }
	if lower.ends_with('.h') { return tr('files.kind.c_header').clone() }
	dot := lower.last_index('.') or { return tr('files.kind.document').clone() }
	if dot == 0 || dot + 1 >= lower.len {
		return tr('files.kind.document').clone()
	}
	upper := lower[dot + 1..].to_upper()
	result := tr_fill('files.kind.extension_file', upper)
	unsafe { upper.free() }
	return result
}

// relabel_entries remakes the date, kind and size text each entry has kept
// since its directory was read, and the error, for a listing that outlived a
// change of language.
fn (mut b FileBrowser) relabel_entries() {
	b.language = desktop_language
	for index in 0 .. b.entries.len {
		unsafe {
			if b.entries[index].modified_text.len > 0 { b.entries[index].modified_text.free() }
			if b.entries[index].kind_text.len > 0 { b.entries[index].kind_text.free() }
			if b.entries[index].size_text.len > 0 { b.entries[index].size_text.free() }
		}
		b.entries[index].modified_text = files_list_modified_text(b.entries[index].modified,
			b.tz_offset_seconds)
		b.entries[index].kind_text = files_list_kind_text(b.entries[index].name, b.entries[index].is_dir)
		// As prepare_file_rows makes them: folders show no size.
		b.entries[index].size_text = if b.entries[index].is_dir {
			''
		} else {
			human_size(b.entries[index].size)
		}
	}
	if b.error.len > 0 && b.error_path.len > 0 {
		unsafe { b.error.free() }
		b.error = tr_fill('files.cannot_open', b.error_path)
	}
	// Kinds sort differently in another language.
	if b.sort_column == .kind {
		b.apply_list_sort()
	}
}

fn (mut b FileBrowser) follow_language() {
	if b.language != desktop_language {
		b.relabel_entries()
	}
}

// follow_language brings every listing the window keeps into the desktop's
// language, which an application process learns with each request.
fn (mut a FileBrowserApp) follow_language() {
	a.browser.follow_language()
	a.dual_left.follow_language()
	a.dual_right.follow_language()
	for index in 0 .. a.columns.len {
		a.columns[index].browser.follow_language()
	}
}

fn files_list_separator(x int) ui2.Element {
	return ui2.view('', ui2.rect(f64(x), files_header_height() + 5, 1,
		files_list_header_height() - 10), ui2.BoxStyle{ bg: body_rule }, [])
}

// label says what clicking does ("Sort by Size"). It belongs to the
// translation table: the tree is rebuilt for every frame the window is drawn
// in, and nothing frees the strings it holds. Each column has its own key
// because languages decline the column's name after "by".
fn files_list_header_sort_target(mut children []ui2.Element, action string, label string,
	x int, width int, selected bool, descending bool) {
	if selected {
		children << ui2.Element{
			...ui2.image('', if descending { 'builtin:arrow_down' } else { 'builtin:arrow_up' },
				ui2.rect(f64(x + width - 19), files_header_height() + if files_catalina {
				3
			} else {
				9
			}, 11, 11))
			text_style: ui2.TextStyle{ color: body_heading }
		}
	}
	children << ui2.Element{
		...ui2.clickable_view(action, ui2.rect(f64(x), files_header_height(), f64(width),
			files_list_header_height()), ui2.BoxStyle{ transparent: true }, [])
		tooltip:             label
		accessibility_label: label
		accessibility_value: if selected {
			if descending { tr('files.list.descending') } else { tr('files.list.ascending') }
		} else {
			''
		}
	}
}

fn files_list_header(mut children []ui2.Element, x int, width int, layout FilesListLayout,
	sort_column FilesListSortColumn, descending bool) {
	y := files_header_height()
	children << ui2.view('', ui2.rect(f64(x), y, f64(width), files_list_header_height()),
		ui2.BoxStyle{ bg: body_panel }, [])
	children << ui2.label('files.list.header.name', tr('files.list.name'), ui2.rect(f64(x + files_padding + 24),
		y + 2, f64(layout.name_end - files_padding - 32), files_list_header_height() - 4), ui2.TextStyle{
		color: if sort_column == .name { body_heading } else { body_muted }
		size:  12
		bold:  sort_column == .name
	})
	if layout.show_modified {
		children << ui2.label('files.list.header.modified', tr('files.list.modified'),
			ui2.rect(f64(x + layout.modified_x + 7), y + 2,
				f64(layout.modified_width - 12), files_list_header_height() - 4), ui2.TextStyle{
				color: if sort_column == .modified { body_heading } else { body_muted }
				size:  12
				bold:  sort_column == .modified
			})
	}
	children << ui2.label('files.list.header.size', tr('files.list.size'), ui2.rect(f64(x + layout.size_x + 6),
		y + 2, f64(layout.size_width - 10), files_list_header_height() - 4), ui2.TextStyle{
		color: if sort_column == .size { body_heading } else { body_muted }
		size:  12
		bold:  sort_column == .size
	})
	if layout.show_kind {
		children << ui2.label('files.list.header.kind', tr('files.list.kind'), ui2.rect(f64(x + layout.kind_x + 7),
			y + 2, f64(layout.kind_width - 10), files_list_header_height() - 4), ui2.TextStyle{
			color: if sort_column == .kind { body_heading } else { body_muted }
			size:  12
			bold:  sort_column == .kind
		})
	}
	children << files_list_separator(x + layout.size_x)
	if layout.show_modified { children << files_list_separator(x + layout.modified_x) }
	if layout.show_kind { children << files_list_separator(x + layout.kind_x) }
	children << ui2.view('', ui2.rect(f64(x), y + files_list_header_height() - 1,
		f64(width), 1), ui2.BoxStyle{ bg: body_rule }, [])
	files_list_header_sort_target(mut children, files_action_sort_name, tr('files.list.sort_by_name'), x,
		layout.name_end, sort_column == .name, descending)
	if layout.show_modified {
		files_list_header_sort_target(mut children, files_action_sort_modified,
			tr('files.list.sort_by_modified'),
			x + layout.modified_x, layout.modified_width, sort_column == .modified, descending)
	}
	files_list_header_sort_target(mut children, files_action_sort_size, tr('files.list.sort_by_size'),
		x + layout.size_x, layout.size_width, sort_column == .size, descending)
	if layout.show_kind {
		files_list_header_sort_target(mut children, files_action_sort_kind, tr('files.list.sort_by_kind'),
			x + layout.kind_x, layout.kind_width, sort_column == .kind, descending)
	}
}

fn files_list_row_children(entry &FileEntry, settings &FilesSettings, tag_color u32,
	layout FilesListLayout) []ui2.Element {
	mut row := frame_elements(5)
	row << ui2.button_with_image('', '', if entry.is_dir {
		'builtin:folder'
	} else {
		'builtin:file'
	},
		ui2.rect(files_padding, 4, 16, 16), ui2.BoxStyle{ transparent: true }, ui2.TextStyle{
			color: if entry.is_dir && settings.tint_folders && tag_color != 0 {
				tag_color
			} else if entry.is_dir {
				files_folder_icon
			} else {
				files_file_icon
			}
		})
	name_x := files_padding + 24
	mut name_width := layout.name_end - name_x - 8
	if tag_color != 0 { name_width -= 12 }
	if name_width < 1 { name_width = 1 }
	row << ui2.label('', entry.name, ui2.rect(f64(name_x), 0, f64(name_width), files_row_height()),
		ui2.TextStyle{
			color: if entry.is_dir { body_heading } else { body_text }
			size:  13
		})
	if tag_color != 0 {
		row << ui2.view('', ui2.rect(f64(layout.name_end - 15), 9, 7, 7), ui2.BoxStyle{
			bg:     tag_color
			radius: 4
		}, [])
	}
	if layout.show_modified {
		row << ui2.label('', entry.modified_text, ui2.rect(f64(layout.modified_x + 7), 0,
			f64(layout.modified_width - 12), files_row_height()), ui2.TextStyle{
			color: body_muted
			size:  11
		})
	}
	row << ui2.label('', if entry.is_dir { '—' } else { entry.size_text },
		ui2.rect(f64(layout.size_x + 3), 0, f64(layout.size_width - 10), files_row_height()),
		ui2.TextStyle{ color: body_muted, size: 11, align: .right })
	if layout.show_kind {
		row << ui2.label('', entry.kind_text, ui2.rect(f64(layout.kind_x + 7), 0,
			f64(layout.kind_width - 10), files_row_height()), ui2.TextStyle{
			color: body_muted
			size:  11
		})
	}
	return row
}
