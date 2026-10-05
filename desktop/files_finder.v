// Copyright (c) 2026 Alexander Medvednikov. All rights reserved.
// Use of this source code is governed by a GPL v2 license
// that can be found in the LICENSE file.

// SPDX-License-Identifier: GPL-2.0-or-later
// Files as Finder in Catalina, which is how it looks under the desktop's macOS
// theme: Back, Forward, the views and a search field in a toolbar the window
// draws into its title bar, Finder's grey sidebar, and its columns, each with
// its own scroller. The measurements are in theme.v.
module main

import ui2

const files_action_back = 'files.back'
const files_action_forward = 'files.forward'
const files_action_search = 'files.search'
// Back reaches this many folders; the oldest go first.
const files_history_limit = 64
const finder_segment_width = 28
const finder_button_width = 40
const finder_gap = 7
// The toolbar's views start where Finder's do, once the window is wide
// enough to have them there.
const finder_views_x = 151
const finder_search_min_width = 90
const finder_search_max_length = 255

// ── Back and Forward ───────────────────────────────────────────────

// note_location keeps Back and Forward. Every way of moving -- a click, a key,
// a Jump List, a sidebar location -- ends in a rebuild, so the history is kept
// here rather than in each of them. Moving also ends a search: it was for the
// folder that was there.
fn (mut a FileBrowserApp) note_location() {
	current := a.current_path()
	if current == a.history_path {
		return
	}
	if a.history_path.len > 0 {
		files_history_push(mut a.history_back, a.history_path)
		files_history_clear(mut a.history_forward)
	}
	a.history_path = current.clone()
	a.end_search()
}

// files_history_push takes ownership of path. The list is made at its full
// size once, so it never outgrows its buffer.
fn files_history_push(mut paths []string, path string) {
	if paths.cap == 0 {
		paths = []string{cap: files_history_limit}
	}
	if paths.len >= files_history_limit {
		unsafe { paths[0].free() }
		for index in 1 .. paths.len {
			paths[index - 1] = paths[index]
		}
		unsafe {
			paths.len = paths.len - 1
		}
	}
	paths << path
}

fn files_history_clear(mut paths []string) {
	for path in paths {
		unsafe { path.free() }
	}
	paths.clear()
}

fn (mut a FileBrowserApp) go_back() {
	if a.history_back.len == 0 {
		return
	}
	target := a.history_back.pop()
	files_history_push(mut a.history_forward, a.history_path)
	a.history_path = target
	a.move_through_history()
}

fn (mut a FileBrowserApp) go_forward() {
	if a.history_forward.len == 0 {
		return
	}
	target := a.history_forward.pop()
	files_history_push(mut a.history_back, a.history_path)
	a.history_path = target
	a.move_through_history()
}

// move_through_history shows history_path. A folder that has gone since keeps
// its place in the history, but the window stays where it is, and so does
// history_path.
fn (mut a FileBrowserApp) move_through_history() {
	a.end_search()
	a.navigate_to(a.history_path)
	current := a.current_path()
	if current != a.history_path {
		unsafe { a.history_path.free() }
		a.history_path = current.clone()
	}
}

// ── Search ─────────────────────────────────────────────────────────

// search_key_input edits the search text while its field has the keyboard.
// Return and Tab leave the field with the folder still narrowed; Escape
// clears it and shows the whole folder again.
fn (mut a FileBrowserApp) search_key_input(input string) {
	a.note_location()
	if a.search.cap == 0 {
		a.search = []u8{cap: finder_search_max_length + 1}
	}
	mut changed := false
	mut index := 0
	for index < input.len {
		ch := input[index]
		if ch == 0x1b {
			if index + 1 >= input.len {
				a.end_search()
				return
			}
			// A key with no text, such as an arrow: ESC, [ or O, and whatever
			// parameters come before its final letter.
			index += 2
			for index < input.len && (input[index] < 0x40 || input[index] > 0x7e) {
				index++
			}
			index++
			continue
		}
		if ch == `\r` || ch == `\n` || ch == `\t` {
			a.search_focused = false
		} else if ch == 8 || ch == 127 {
			// A whole character: the lead byte and any continuation bytes.
			for a.search.len > 0 {
				last := a.search[a.search.len - 1]
				a.search.delete_last()
				changed = true
				if last & 0xc0 != 0x80 {
					break
				}
			}
		} else if ch >= 0x20 && ch != `/` && a.search.len < finder_search_max_length {
			a.search << ch
			changed = true
		}
		index++
	}
	if changed {
		a.apply_search()
	}
}

// apply_search narrows the folder being shown -- the list, the last column,
// or the active pane -- to the names containing the search text.
fn (mut a FileBrowserApp) apply_search() {
	query := rename_buffer_text(a.search)
	match a.view_mode {
		.list {
			if a.active_tag_id >= 0 {
				return
			}
			files_reread_narrowed(mut a.browser, query)
			a.search_column = -1
		}
		.columns {
			if a.columns.len == 0 {
				return
			}
			a.search_column = a.replace_miller_column(a.columns.len - 1, query)
		}
		.commander {
			if a.active_pane == 0 {
				files_reread_narrowed(mut a.dual_left, query)
				a.search_column = -3
			} else {
				files_reread_narrowed(mut a.dual_right, query)
				a.search_column = -4
			}
		}
	}
	if query.len == 0 {
		a.search_column = -2
	}
}

// end_search empties the search field and shows all of whatever it narrowed.
fn (mut a FileBrowserApp) end_search() {
	a.search_focused = false
	narrowed := a.search_column
	a.search_column = -2
	a.search.clear()
	match narrowed {
		-1 {
			files_reread_narrowed(mut a.browser, '')
		}
		-3 {
			files_reread_narrowed(mut a.dual_left, '')
		}
		-4 {
			files_reread_narrowed(mut a.dual_right, '')
		}
		else {
			for index in 0 .. a.columns.len {
				if narrowed >= 0 && a.columns[index].id == narrowed {
					a.replace_miller_column(index, '')
					break
				}
			}
		}
	}
}

// files_narrow_entries keeps the entries whose names contain query, ignoring
// case, and numbers their rows again.
fn files_narrow_entries(mut entries []FileEntry, query string, action_prefix string) {
	if query.len == 0 {
		return
	}
	needle := query.to_lower()
	mut kept := 0
	for index in 0 .. entries.len {
		name := entries[index].name.to_lower()
		matches := name.contains(needle)
		unsafe { name.free() }
		if matches {
			entries[kept] = entries[index]
			kept++
			continue
		}
		unsafe {
			entries[index].name.free()
			entries[index].row_action.free()
			entries[index].size_text.free()
			entries[index].modified_text.free()
			entries[index].kind_text.free()
		}
	}
	unsafe {
		entries.len = kept
		needle.free()
	}
	for index in 0 .. entries.len {
		unsafe { entries[index].row_action.free() }
		entries[index].row_action = ''
	}
	prepare_file_rows(mut entries, action_prefix)
}

fn files_entry_named(entries []FileEntry, name string) int {
	if name.len == 0 {
		return -1
	}
	for index, entry in entries {
		if entry.name == name {
			return index
		}
	}
	return -1
}

// files_reread_narrowed reads a listing's folder again, narrowed to query,
// and keeps the selected entry selected if it is still there.
fn files_reread_narrowed(mut b FileBrowser, query string) {
	selected := if b.selected_row >= 0 && b.selected_row < b.entries.len {
		b.entries[b.selected_row].name.clone()
	} else {
		''
	}
	path := b.path.clone()
	b.read(path)
	if b.error.len > 0 {
		unsafe { path.free() }
	}
	prefix := if b.action_prefix.len > 0 { b.action_prefix } else { files_action_row }
	files_narrow_entries(mut b.entries, query, prefix)
	b.selected_row = files_entry_named(b.entries, selected)
	if selected.len > 0 {
		unsafe { selected.free() }
	}
}

// replace_miller_column reads a column's folder again, narrowed to query, and
// returns the new column's id. Its selection stays, and stays in view.
fn (mut a FileBrowserApp) replace_miller_column(index int, query string) int {
	old := &a.columns[index]
	selected := if old.selected_row >= 0 && old.selected_row < old.browser.entries.len {
		old.browser.entries[old.selected_row].name.clone()
	} else {
		''
	}
	mut column := a.new_miller_column(old.browser.path.clone())
	if query.len > 0 {
		id_text := column.id.str()
		prefix := '${files_action_column_row}${id_text}.'
		files_narrow_entries(mut column.browser.entries, query, prefix)
		unsafe {
			id_text.free()
			prefix.free()
		}
	}
	column.selected_row = files_entry_named(column.browser.entries, selected)
	if column.selected_row >= a.visible_rows {
		column.browser.scroll = column.selected_row - a.visible_rows + 1
	}
	if selected.len > 0 {
		unsafe { selected.free() }
	}
	a.columns[index].release()
	a.columns[index] = column
	return column.id
}

fn files_rune_count(bytes []u8) int {
	mut count := 0
	for b in bytes {
		if b & 0xc0 != 0x80 {
			count++
		}
	}
	return count
}

// ── Layout ─────────────────────────────────────────────────────────

// build_finder lays Files out as Finder. Columns keep Finder's fixed width,
// leaving the window's spare width empty, and each has its scroller.
fn (mut a FileBrowserApp) build_finder(size ui2.Rect) !ui2.Element {
	width := int(size.width)
	height := int(size.height)
	content_left := files_content_left(width)
	content_width := width - content_left
	if a.view_mode == .columns && a.columns.len == 0 {
		a.reset_miller_columns(a.browser.path)
	}
	a.viewport_width = content_width
	a.column_width = finder_column_width + finder_scroller_width
	// The folder is named in the title bar; there is no path strip to scroll.
	a.path_viewport_width = 0
	a.path_content_width = 0
	a.path_offset = 0
	a.reveal_path_end = false
	column_max := a.max_column_offset()
	if a.reveal_last_column {
		a.column_offset = column_max
		a.reveal_last_column = false
	} else {
		a.column_offset = files_clamp(a.column_offset, column_max)
	}
	a.rows_top = files_header_height()
	if a.view_mode == .commander {
		a.rows_top += files_pane_header_height
	} else if a.view_mode == .list && a.active_tag_id < 0 {
		a.rows_top += files_list_header_height()
	} else if a.view_mode == .columns {
		// Finder's first row sits a pixel below the toolbar's edge.
		a.rows_top++
	}
	bar_height := if a.view_mode == .columns && column_max > 0 { finder_scroller_width } else { 0 }
	a.rows_height = height - a.rows_top - bar_height
	if a.rows_height < files_row_height() {
		a.rows_height = files_row_height()
	}
	a.visible_rows = a.rows_height / files_row_height()
	if a.visible_rows < 1 {
		a.visible_rows = 1
	}
	a.hbar_x = content_left + 2
	a.hbar_width = content_width - 4
	a.hbar_top = height - finder_scroller_width
	a.hbar_bottom = height
	if a.view_mode == .list {
		a.clamp_scroll()
	}
	shown_columns := content_width / a.column_width + 2
	mut children := frame_elements(shown_columns * (a.visible_rows + 10) + a.visible_rows + 48)
	children << a.finder_toolbar(width)
	if a.view_mode == .columns {
		return a.build_finder_columns(width, height, mut children)
	}
	if a.view_mode == .commander {
		return a.build_commander(width, height, mut children)
	}
	if a.active_tag_id >= 0 {
		return a.build_tag_results(width, height, mut children)
	}
	return a.build_finder_list(width, height, mut children)
}

// ── Toolbar ────────────────────────────────────────────────────────

// finder_bezel is a toolbar control's rounded bezel: a darker bottom edge, a
// lighter edge round the rest, and the face. Finder's face runs from white to
// #f3f3f3, too little for a flat one to look any different.
fn finder_bezel(mut items []ui2.Element, x int, width int) {
	top := finder_control_top
	height := finder_control_height
	items << ui2.view('', ui2.rect(f64(x), f64(top), f64(width), f64(height)), ui2.BoxStyle{
		bg:     finder_control_bottom
		radius: 5
	}, [])
	items << ui2.view('', ui2.rect(f64(x), f64(top), f64(width), f64(height - 1)), ui2.BoxStyle{
		bg:     finder_control_edge
		radius: 5
	}, [])
	items << ui2.view('', ui2.rect(f64(x + 1), f64(top + 1), f64(width - 2), f64(height - 2)),
		ui2.BoxStyle{
		bg:     finder_control_face
		radius: 4
	}, [])
}

// finder_segment_fill paints one segment of a segmented control, rounded only
// at the control's own ends.
fn finder_segment_fill(mut items []ui2.Element, x int, width int, height int, color u32, first bool, last bool) {
	top := finder_control_top
	items << ui2.view('', ui2.rect(f64(x), f64(top), f64(width), f64(height)), ui2.BoxStyle{
		bg:     color
		radius: if first || last { 5 } else { 0 }
	}, [])
	if first != last {
		square_x := if first { x + width - 5 } else { x }
		items << ui2.view('', ui2.rect(f64(square_x), f64(top), 5, f64(height)), ui2.BoxStyle{
			bg: color
		}, [])
	}
}

// finder_segments draws a segmented control with the given segment dark.
fn finder_segments(mut items []ui2.Element, x int, count int, selected int) {
	finder_bezel(mut items, x, count * finder_segment_width)
	for index in 1 .. count {
		if index == selected || index == selected + 1 {
			continue
		}
		items << ui2.view('', ui2.rect(f64(x + index * finder_segment_width - 1),
			f64(finder_control_top + 1), 1, f64(finder_control_height - 2)), ui2.BoxStyle{
			bg: finder_control_divider
		}, [])
	}
	if selected >= 0 && selected < count {
		segment_x := x + selected * finder_segment_width
		first := selected == 0
		last := selected == count - 1
		finder_segment_fill(mut items, segment_x, finder_segment_width, finder_control_height,
			finder_control_selected_bottom, first, last)
		finder_segment_fill(mut items, segment_x, finder_segment_width, finder_control_height - 1,
			finder_control_selected, first, last)
	}
}

// finder_control puts a glyph in a bezel drawn beforehand and makes the area
// a button. The glyph is its own element so it keeps Finder's size whatever
// the button's.
fn finder_control(mut items []ui2.Element, action string, label string, icon string, x int, width int,
	enabled bool, color u32) {
	glyph := 16
	items << ui2.Element{
		...ui2.image('', icon, ui2.rect(f64(x + (width - glyph) / 2), f64(finder_control_top +
			(finder_control_height - glyph) / 2), f64(glyph), f64(glyph)))
		text_style: ui2.TextStyle{
			color: if enabled { color } else { finder_control_disabled }
		}
	}
	items << ui2.Element{
		...ui2.button(action, '', ui2.rect(f64(x), f64(finder_control_top), f64(width),
			f64(finder_control_height)), ui2.BoxStyle{
			transparent: true
		}, ui2.TextStyle{})
		enabled:             enabled
		tooltip:             label
		accessibility_label: label
	}
}

// folder_title is what the title bar calls the folder being shown, as Finder
// does: its name, or the computer's for `/`. It is kept, not remade for every
// frame, and made again when the folder or the language changes.
fn (mut a FileBrowserApp) folder_title() string {
	current := a.current_path()
	if current == a.title_path && a.title_language == desktop_language {
		return a.title
	}
	unsafe {
		a.title.free()
		a.title_path.free()
	}
	index := current.last_index('/') or { -1 }
	a.title = if current == '/' {
		tr('files.location.computer').clone()
	} else if index >= 0 && index + 1 < current.len {
		current[index + 1..]
	} else {
		current.clone()
	}
	a.title_path = current.clone()
	a.title_language = desktop_language
	return a.title
}

// has_selection says whether an item is selected for Edit Tags to act on.
fn (a &FileBrowserApp) has_selection() bool {
	return match a.view_mode {
		.list {
			a.browser.selected_row >= 0
		}
		.commander {
			if a.active_pane == 0 {
				a.dual_left.selected_row >= 0
			} else {
				a.dual_right.selected_row >= 0
			}
		}
		.columns {
			a.columns.len > 0 && a.columns.last().selected_row >= 0
		}
	}
}

fn (mut a FileBrowserApp) finder_toolbar(width int) ui2.Element {
	mut items := frame_elements(40)
	// Back and Forward share one bezel.
	back_x := finder_control_inset
	half := finder_button_width * 2 / 3
	finder_bezel(mut items, back_x, 2 * half + 1)
	items << ui2.view('', ui2.rect(f64(back_x + half), f64(finder_control_top + 1), 1,
		f64(finder_control_height - 2)), ui2.BoxStyle{
		bg: finder_control_edge
	}, [])
	finder_control(mut items, files_action_back, tr('files.toolbar.back'), 'builtin:chevron_left',
		back_x, half, a.history_back.len > 0, finder_control_glyph)
	finder_control(mut items, files_action_forward, tr('files.toolbar.forward'), 'builtin:chevron_right',
		back_x + half + 1, half, a.history_forward.len > 0, finder_control_glyph)

	// The views, as one segmented control, then the settings and Edit Tags.
	after_back := back_x + 2 * half + 1 + finder_gap + 1
	group_width := 3 * finder_segment_width + 3 * (finder_gap + finder_button_width)
	views_x := if width - finder_search_width - finder_control_inset - 24 - group_width >= finder_views_x {
		finder_views_x
	} else {
		after_back
	}
	selected := match a.view_mode {
		.list { 0 }
		.columns { 1 }
		.commander { 2 }
	}
	finder_segments(mut items, views_x, 3, selected)
	views := [files_action_view_list, files_action_view_columns, files_action_view_commander]!
	labels := [tr('files.toolbar.list'), tr('files.toolbar.columns'), tr('files.toolbar.commander')]!
	icons := ['builtin:finder_list', 'builtin:column_view', 'builtin:dual_pane']!
	for index in 0 .. 3 {
		finder_control(mut items, views[index], labels[index], icons[index], views_x +
			index * finder_segment_width, finder_segment_width, true, if index == selected {
			finder_on_selection
		} else {
			finder_control_glyph
		})
	}
	settings_x := views_x + 3 * finder_segment_width + finder_gap
	finder_bezel(mut items, settings_x, finder_button_width)
	finder_control(mut items, files_action_settings, tr('files.toolbar.settings'), 'builtin:finder_gear',
		settings_x, finder_button_width, true, finder_control_glyph)
	tags_x := settings_x + finder_button_width + finder_gap
	finder_bezel(mut items, tags_x, finder_button_width)
	finder_control(mut items, file_context_tags, tr('files.toolbar.tags'), 'builtin:tag', tags_x,
		finder_button_width, a.has_selection(), finder_control_glyph)
	info_x := tags_x + finder_button_width + finder_gap
	finder_bezel(mut items, info_x, finder_button_width)
	items << ui2.Element{
		...ui2.button(files_action_info, tr('files.info.symbol'), ui2.rect(f64(info_x), f64(finder_control_top), finder_button_width, finder_control_height), ui2.BoxStyle{ transparent: true }, ui2.TextStyle{ color: finder_control_glyph, size: 14, bold: true, align: .center })
		tooltip:             tr('files.info.title')
		accessibility_label: tr('files.info.title')
	}

	// Search, at the far end, as wide as Finder's or as the window leaves.
	search_left := info_x + finder_button_width + 24
	mut search_width := width - finder_control_inset - search_left
	if search_width > finder_search_width {
		search_width = finder_search_width
	}
	if search_width >= finder_search_min_width {
		count := files_rune_count(a.search)
		items << ui2.Element{
			...ui2.text_field(files_action_search, tr('files.toolbar.search'), rename_buffer_text(a.search),
				ui2.rect(f64(width - finder_control_inset - search_width), f64(finder_control_top),
				f64(search_width), f64(finder_control_height)), ui2.BoxStyle{
				bg:     0xffffff
				radius: 5
			}, ui2.TextStyle{
				color: finder_text
				size:  13
			}, 0)
			// A text field with a leading image is a search field to the
			// compositor: rounded, with the magnifier before the text.
			image_path:     'builtin:finder_search'
			focused:        a.search_focused
			text_selection: ui2.TextSelection{
				anchor: count
				caret:  count
			}
		}
	}

	title := if a.active_tag_id >= 0 {
		index := a.settings.tag_index(a.active_tag_id)
		if index >= 0 { a.settings.tags[index].display_name() } else { a.folder_title() }
	} else {
		a.folder_title()
	}
	return ui2.Element{
		...ui2.view(app_toolbar_id, ui2.rect(0, 0, f64(width), f64(finder_toolbar_height)),
			ui2.BoxStyle{
			bg: finder_toolbar_fallback
		}, items)
		text:       title
		image_path: if a.active_tag_id >= 0 {
			''
		} else if a.current_path() == '/' {
			'builtin:drive'
		} else {
			'builtin:finder_folder'
		}
		text_style: ui2.TextStyle{
			color: if a.current_path() == '/' { finder_sidebar_icon } else { finder_folder_icon }
		}
	}
}

// ── Sidebar ────────────────────────────────────────────────────────

// tag_action is a sidebar tag's action, made once per tag rather than for
// every frame the sidebar is drawn in.
fn (mut a FileBrowserApp) tag_action(id int) string {
	if action := a.tag_actions[id] {
		return action
	}
	id_text := id.str()
	action := files_action_tag_prefix + id_text
	unsafe { id_text.free() }
	a.tag_actions[id] = action
	return action
}

// Section headings sit ten pixels below the section before and nineteen
// above their first row, whose selection leaves a pixel above and below it.
const finder_heading_gap = 10
const finder_heading_to_row = 19

fn finder_sidebar_heading(mut rows []ui2.Element, text string, y int) {
	rows << ui2.label('', text, ui2.rect(10, f64(y), finder_sidebar_width - 20, 20), ui2.TextStyle{
		color: finder_sidebar_heading
		size:  11
		bold:  true
	})
}

fn finder_sidebar_row(mut rows []ui2.Element, action string, y int, selected bool, contents []ui2.Element) {
	rows << ui2.clickable_view(action, ui2.rect(0, f64(y + 1), finder_sidebar_width,
		finder_sidebar_row_height - 2), ui2.BoxStyle{
		bg:          finder_sidebar_selected
		transparent: !selected
	}, contents)
}

// finder_sidebar_height is how tall the sidebar's contents are, for scrolling.
fn (a &FileBrowserApp) finder_sidebar_height() int {
	favorites := files_locations.len - 1
	mut height := 5 + finder_heading_to_row + favorites * finder_sidebar_row_height
	height += finder_heading_gap + finder_heading_to_row + finder_sidebar_row_height
	mut tags := 0
	for tag in a.settings.tags {
		if tag.sidebar {
			tags++
		}
	}
	if tags > 0 {
		height += finder_heading_gap + finder_heading_to_row + tags * finder_sidebar_row_height
	}
	return height + 4
}

fn (mut a FileBrowserApp) finder_sidebar(height int) ui2.Element {
	mut rows := frame_elements(files_locations.len + a.settings.tags.len + 4)
	mut heading_y := 5 - a.sidebar_scroll
	finder_sidebar_heading(mut rows, tr('files.sidebar.favorites'), heading_y)
	mut y := heading_y + finder_heading_to_row
	current := a.current_path()
	for index, location in files_locations {
		if index == files_locations.len - 1 {
			heading_y = y + finder_heading_gap
			finder_sidebar_heading(mut rows, tr('files.sidebar.locations'), heading_y)
			y = heading_y + finder_heading_to_row
		}
		if y + finder_sidebar_row_height > 0 && y < height {
			mut contents := frame_elements(2)
			contents << ui2.Element{
				...ui2.image('', location.icon, ui2.rect(17, 3, 18, 18))
				text_style: ui2.TextStyle{
					color: finder_sidebar_icon
				}
			}
			contents << ui2.label('', location.display_title(), ui2.rect(40, 0, finder_sidebar_width - 44,
				finder_sidebar_row_height - 2), ui2.TextStyle{
				color: finder_text
				size:  13
			})
			finder_sidebar_row(mut rows, location.action, y, a.active_tag_id < 0
				&& current == location.path, contents)
		}
		y += finder_sidebar_row_height
	}
	mut first_tag := true
	for tag in a.settings.tags {
		if !tag.sidebar {
			continue
		}
		if first_tag {
			heading_y = y + finder_heading_gap
			finder_sidebar_heading(mut rows, tr('files.settings.tags'), heading_y)
			y = heading_y + finder_heading_to_row
			first_tag = false
		}
		if y + finder_sidebar_row_height > 0 && y < height {
			mut contents := frame_elements(2)
			contents << ui2.view('', ui2.rect(21, 6, 12, 12), ui2.BoxStyle{
				bg:     tag.color
				radius: 6
			}, [])
			contents << ui2.label('', tag.display_name(), ui2.rect(41, 0, finder_sidebar_width - 45,
				finder_sidebar_row_height - 2), ui2.TextStyle{
				color: finder_text
				size:  13
			})
			finder_sidebar_row(mut rows, a.tag_action(tag.id), y, a.active_tag_id == tag.id, contents)
		}
		y += finder_sidebar_row_height
	}
	return ui2.clickable_view('files.sidebar', ui2.rect(0, f64(files_header_height()), finder_sidebar_width,
		f64(height)), ui2.BoxStyle{
		bg: finder_sidebar_bg
	}, rows)
}

// ── Columns ────────────────────────────────────────────────────────

// finder_scroller is a column's always-visible scroller: a pale track between
// two rules, the thumb when there is more than fits, and at its foot the grip
// Finder resizes the column by.
fn finder_scroller(mut children []ui2.Element, x int, top int, height int, rows_top int, rows_height int,
	visible int, total int, scroll int) {
	children << ui2.view('', ui2.rect(f64(x), f64(top), 1, f64(height)), ui2.BoxStyle{
		bg: finder_scroller_left
	}, [])
	children << ui2.view('', ui2.rect(f64(x + 1), f64(top), finder_scroller_width - 2, f64(height)),
		ui2.BoxStyle{
		bg: finder_scroller_track
	}, [])
	children << ui2.view('', ui2.rect(f64(x + finder_scroller_width - 1), f64(top), 1, f64(height)),
		ui2.BoxStyle{
		bg: finder_scroller_right
	}, [])
	if total > visible {
		position, thumb := files_scroll_thumb(rows_height, visible, total, scroll)
		children << ui2.clickable_view(files_action_scrollbar, ui2.rect(f64(x + 4), f64(rows_top +
			position), 7, f64(thumb)), ui2.BoxStyle{
			bg:     finder_scroller_thumb
			radius: 3
		}, [])
	}
	grip_top := top + height - 13
	if grip_top > top {
		for offset in [5, 9]! {
			children << ui2.view('', ui2.rect(f64(x + offset), f64(grip_top), 1, 8), ui2.BoxStyle{
				bg: finder_scroller_grip
			}, [])
		}
	}
}

// finder_vertical_scroller is the scroller at the right of a list or a pane:
// a column's, without the grip, since nothing there resizes.
fn finder_vertical_scroller(x int, y int, height int, visible int, total int, scroll int) ui2.Element {
	position, thumb := files_scroll_thumb(height, visible, total, scroll)
	mut parts := frame_elements(4)
	parts << ui2.view('', ui2.rect(0, 0, 1, f64(height)), ui2.BoxStyle{
		bg: finder_scroller_left
	}, [])
	parts << ui2.view('', ui2.rect(finder_scroller_width - 1, 0, 1, f64(height)), ui2.BoxStyle{
		bg: finder_scroller_right
	}, [])
	parts << ui2.view('', ui2.rect(4, f64(position), 7, f64(thumb)), ui2.BoxStyle{
		bg:     finder_scroller_thumb
		radius: 3
	}, [])
	return ui2.clickable_view(files_action_scrollbar, ui2.rect(f64(x), f64(y), finder_scroller_width,
		f64(height)), ui2.BoxStyle{
		bg: finder_scroller_track
	}, parts)
}

// finder_row_style is a row's fill and text colours: Finder's blue for the
// selection the keyboard would move, grey for a selection that led elsewhere.
fn finder_row_style(selected bool, active bool) (u32, u32, u32) {
	if !selected {
		return u32(0), finder_text, finder_text_muted
	}
	if active {
		return finder_selection, finder_on_selection, finder_on_selection
	}
	return finder_selection_inactive, finder_text, finder_text_muted
}

fn (mut a FileBrowserApp) build_finder_columns(width int, height int, mut children []ui2.Element) !ui2.Element {
	column_width := a.column_width
	content_left := width - a.viewport_width
	top := files_header_height()
	bar := if a.max_column_offset() > 0 { finder_scroller_width } else { 0 }
	column_height := height - top - bar
	// The deepest selection is the one the keyboard moves, and the only one
	// Finder draws in blue.
	mut active_column := -1
	for index in 0 .. a.columns.len {
		if a.columns[index].selected_row >= 0 {
			active_column = index
		}
	}
	icon_y := (files_row_height() - 16) / 2
	for column_index := 0; column_index < a.columns.len; column_index++ {
		local_x := column_index * column_width - a.column_offset
		if local_x + column_width <= 0 || local_x >= a.viewport_width {
			continue
		}
		x := content_left + local_x
		a.clamp_column_scroll(column_index)
		column := &a.columns[column_index]
		if column.browser.error != '' {
			children << ui2.label('', column.browser.error, ui2.rect(f64(x + files_padding), f64(a.rows_top + 8),
				f64(finder_column_width - 2 * files_padding), 36), ui2.TextStyle{
				color: files_error
				size:  11
				lines: 2
			})
		} else if column.browser.entries.len == 0 {
			children << ui2.label('', tr('files.column.empty'), ui2.rect(f64(x + files_padding),
				f64(a.rows_top + 8), f64(finder_column_width - 2 * files_padding), 20), ui2.TextStyle{
				color: finder_text_muted
				size:  13
			})
		}
		mut row_slot := 0
		for entry_index := column.browser.scroll; entry_index < column.browser.entries.len
			&& row_slot < a.visible_rows; entry_index++ {
			entry := &column.browser.entries[entry_index]
			entry_path := join_path(column.browser.path, entry.name)
			tag_color := a.settings.first_color(entry_path)
			unsafe { entry_path.free() }
			selected := column.selected_row == entry_index
			fill, text_color, _ := finder_row_style(selected, column_index == active_column)
			mut row := frame_elements(4)
			row << finder_entry_icon(entry, &a.settings, tag_color, 6)
			name_width := finder_column_width - 27 - if tag_color != 0 { 28 } else { 16 }
			row << ui2.label('', entry.name, ui2.rect(27, 0, f64(name_width), f64(files_row_height() - 1)),
				ui2.TextStyle{
				color: text_color
				size:  13
			})
			if tag_color != 0 {
				row << ui2.view('', ui2.rect(finder_column_width - 26, f64(icon_y + 4), 8, 8),
					ui2.BoxStyle{
					bg:     tag_color
					radius: 4
				}, [])
			}
			if entry.is_dir {
				row << ui2.Element{
					...ui2.image('', 'builtin:disclosure_right', ui2.rect(finder_column_width - 10, 0, 8,
						f64(files_row_height() - 1)))
					text_style: ui2.TextStyle{
						color: if selected && column_index == active_column {
							finder_on_selection
						} else {
							finder_chevron
						}
					}
				}
			}
			children << ui2.clickable_view(entry.row_action, ui2.rect(f64(x), f64(a.rows_top +
				row_slot * files_row_height()), finder_column_width, f64(files_row_height() - 1)),
				ui2.BoxStyle{
				bg:          fill
				transparent: !selected
			}, row)
			row_slot++
		}
		finder_scroller(mut children, x + finder_column_width, top, column_height, a.rows_top,
			a.rows_height, a.visible_rows, column.browser.entries.len, column.browser.scroll)
	}
	if bar > 0 {
		// The columns' own scroller, along the bottom when they overflow.
		bar_y := height - bar
		children << ui2.view('', ui2.rect(f64(content_left), f64(bar_y), f64(a.viewport_width), 1),
			ui2.BoxStyle{
			bg: finder_scroller_left
		}, [])
		children << ui2.view('', ui2.rect(f64(content_left), f64(bar_y + 1), f64(a.viewport_width),
			f64(bar - 1)), ui2.BoxStyle{
			bg: finder_scroller_track
		}, [])
		thumb_x, thumb_width := files_scroll_thumb(a.hbar_width, a.viewport_width, a.columns.len * column_width,
			a.column_offset)
		children << ui2.view('', ui2.rect(f64(a.hbar_x + thumb_x), f64(bar_y + 4), f64(thumb_width), 7),
			ui2.BoxStyle{
			bg:     finder_scroller_thumb
			radius: 3
		}, [])
	}
	return a.screen_with_sidebar(width, height, mut children)
}

// ── List ───────────────────────────────────────────────────────────

fn finder_list_header(mut children []ui2.Element, x int, width int, layout FilesListLayout,
	sort_column FilesListSortColumn, descending bool) {
	y := files_header_height()
	height := files_list_header_height()
	children << ui2.view('', ui2.rect(f64(x), f64(y), f64(width), f64(height)), ui2.BoxStyle{
		bg: 0xffffff
	}, [])
	children << ui2.view('', ui2.rect(f64(x), f64(y + height - 1), f64(width), 1), ui2.BoxStyle{
		bg: finder_list_rule
	}, [])
	mut columns := [4]int{}
	mut widths := [4]int{}
	mut shown := [4]bool{}
	columns[0], widths[0], shown[0] = 0, layout.name_end, true
	columns[1], widths[1], shown[1] = layout.modified_x, layout.modified_width, layout.show_modified
	columns[2], widths[2], shown[2] = layout.size_x, layout.size_width, true
	columns[3], widths[3], shown[3] = layout.kind_x, layout.kind_width, layout.show_kind
	titles := [tr('files.list.name'), tr('files.list.modified'), tr('files.list.size'),
		tr('files.list.kind')]!
	ids := ['files.list.header.name', 'files.list.header.modified', 'files.list.header.size',
		'files.list.header.kind']!
	sorts := [FilesListSortColumn.name, .modified, .size, .kind]!
	for index in 0 .. 4 {
		if !shown[index] {
			continue
		}
		left := x + columns[index]
		if index > 0 {
			children << ui2.view('', ui2.rect(f64(left), f64(y + 2), 1, f64(height - 5)), ui2.BoxStyle{
				bg: finder_list_rule
			}, [])
		}
		inset := if index == 0 { files_padding + 24 } else { 6 }
		children << ui2.label(ids[index], titles[index], ui2.rect(f64(left + inset), f64(y), f64(widths[index] - inset - 16),
			f64(height - 1)), ui2.TextStyle{
			color: finder_text
			size:  11
			bold:  sort_column == sorts[index]
		})
	}
	actions := [files_action_sort_name, files_action_sort_modified, files_action_sort_size,
		files_action_sort_kind]!
	sort_labels := [tr('files.list.sort_by_name'), tr('files.list.sort_by_modified'),
		tr('files.list.sort_by_size'), tr('files.list.sort_by_kind')]!
	for index in 0 .. 4 {
		if shown[index] {
			files_list_header_sort_target(mut children, actions[index], sort_labels[index], x +
				columns[index], widths[index], sort_column == sorts[index], descending)
		}
	}
}

// finder_entry_icon is a row's folder or document, a folder in its tag's
// colour when Files tints them.
fn finder_entry_icon(entry &FileEntry, settings &FilesSettings, tag_color u32, x int) ui2.Element {
	return ui2.Element{
		...ui2.image('', if entry.is_dir { 'builtin:finder_folder' } else { 'builtin:finder_document' },
			ui2.rect(f64(x), f64((files_row_height() - 16) / 2), 16, 16))
		text_style: ui2.TextStyle{
			color: if entry.is_dir && settings.tint_folders && tag_color != 0 {
				tag_color
			} else if entry.is_dir {
				finder_folder_icon
			} else {
				finder_file_icon
			}
		}
	}
}

fn finder_list_row_children(entry &FileEntry, settings &FilesSettings, tag_color u32,
	layout FilesListLayout, selected bool) []ui2.Element {
	_, text_color, muted := finder_row_style(selected, true)
	height := files_row_height()
	mut row := frame_elements(5)
	row << finder_entry_icon(entry, settings, tag_color, files_padding)
	name_x := files_padding + 24
	mut name_width := layout.name_end - name_x - 8
	if tag_color != 0 {
		name_width -= 12
	}
	if name_width < 1 {
		name_width = 1
	}
	row << ui2.label('', entry.name, ui2.rect(f64(name_x), 0, f64(name_width), f64(height)),
		ui2.TextStyle{
		color: text_color
		size:  13
	})
	if tag_color != 0 {
		row << ui2.view('', ui2.rect(f64(layout.name_end - 16), f64((height - 8) / 2), 8, 8),
			ui2.BoxStyle{
			bg:     tag_color
			radius: 4
		}, [])
	}
	if layout.show_modified {
		row << ui2.label('', entry.modified_text, ui2.rect(f64(layout.modified_x + 6), 0,
			f64(layout.modified_width - 10), f64(height)), ui2.TextStyle{
			color: muted
			size:  13
		})
	}
	row << ui2.label('', if entry.is_dir { '--' } else { entry.size_text }, ui2.rect(f64(layout.size_x + 3),
		0, f64(layout.size_width - 10), f64(height)), ui2.TextStyle{
		color: muted
		size:  13
		align: .right
	})
	if layout.show_kind {
		row << ui2.label('', entry.kind_text, ui2.rect(f64(layout.kind_x + 6), 0,
			f64(layout.kind_width - 10), f64(height)), ui2.TextStyle{
			color: muted
			size:  13
		})
	}
	return row
}

fn (mut a FileBrowserApp) build_finder_list(width int, height int, mut children []ui2.Element) !ui2.Element {
	content_left := files_content_left(width)
	content_width := width - content_left
	layout := files_list_layout(content_width)
	finder_list_header(mut children, content_left, content_width, layout, a.browser.sort_column,
		a.browser.sort_descending)
	files_zebra_background(mut children, content_left, a.rows_top, content_width, height - a.rows_top,
		a.browser.scroll)
	if a.browser.error != '' {
		children << ui2.label('', a.browser.error, ui2.rect(f64(content_left + files_padding),
			f64(a.rows_top + 8), f64(content_width - 2 * files_padding), 20), ui2.TextStyle{
			color: files_error
			size:  13
		})
		return a.screen_with_sidebar(width, height, mut children)
	}
	if a.browser.entries.len == 0 {
		children << ui2.label('', tr('files.empty_directory'), ui2.rect(f64(content_left + files_padding),
			f64(a.rows_top + 8), f64(content_width - 2 * files_padding), 20), ui2.TextStyle{
			color: finder_text_muted
			size:  13
		})
		return a.screen_with_sidebar(width, height, mut children)
	}
	mut row := 0
	for index := a.browser.scroll; index < a.browser.entries.len && row < a.visible_rows; index++ {
		entry := &a.browser.entries[index]
		entry_path := join_path(a.browser.path, entry.name)
		tag_color := a.settings.first_color(entry_path)
		unsafe { entry_path.free() }
		selected := a.browser.selected_row == index
		children << ui2.clickable_view(entry.row_action, ui2.rect(f64(content_left), f64(a.rows_top +
			row * files_row_height()), f64(content_width), f64(files_row_height())), ui2.BoxStyle{
			bg:          finder_selection
			transparent: !selected
		}, finder_list_row_children(entry, &a.settings, tag_color, layout, selected))
		row++
	}
	if a.browser.entries.len > a.visible_rows {
		children << files_vertical_scrollbar(width - files_scrollbar_width - 2, a.rows_top,
			a.rows_height, a.visible_rows, a.browser.entries.len, a.browser.scroll)
	}
	return a.screen_with_sidebar(width, height, mut children)
}
