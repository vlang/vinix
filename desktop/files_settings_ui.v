// SPDX-License-Identifier: GPL-2.0-or-later
// Files' preferences sheet and the tag picker for a selected item.
module main

import ui2

const files_settings_close = 'files.settings.close'
const files_settings_general = 'files.settings.general'
const files_settings_tags = 'files.settings.tags'
const files_settings_hidden = 'files.settings.hidden'
const files_settings_tint = 'files.settings.tint'
const files_settings_add = 'files.settings.add'
const files_settings_remove = 'files.settings.remove'
const files_settings_rename = 'files.settings.rename'
const files_settings_scroll_up = 'files.settings.scroll.up'
const files_settings_scroll_down = 'files.settings.scroll.down'
const files_settings_select_prefix = 'files.settings.select.'
const files_settings_sidebar_prefix = 'files.settings.sidebar.'
const files_settings_favorite_prefix = 'files.settings.favorite.'
const files_settings_color_prefix = 'files.settings.color.'
const files_settings_colors = [u32(0xff595e), 0xffa044, 0xffd84a, 0x59cc74, 0x4896f2, 0xc864dc,
	0xa0a1a6]
const files_picker_close = 'files.tags.close'
const files_picker_toggle_prefix = 'files.tags.toggle.'

fn files_settings_checkbox(id string, title string, checked bool, x int, y int, width int) ui2.Element {
	mut contents := frame_elements(2)
	contents << ui2.view('', ui2.rect(0, 4, 17, 17), ui2.BoxStyle{
		bg:            if checked { app_accent } else { app_surface }
		radius:        4
		border_color:  if checked { app_accent } else { body_muted }
		border_left:   1
		border_right:  1
		border_top:    1
		border_bottom: 1
	}, frame_child(ui2.label('', if checked { '✓' } else { '' }, ui2.rect(1, 0, 15, 16), ui2.TextStyle{
		color: app_on_accent
		size:  12
		align: .center
	})))
	if width > 27 {
		contents << ui2.label('', title, ui2.rect(27, 0, f64(width - 27), 26), ui2.TextStyle{
			color: body_text
			size:  13
		})
	}
	return ui2.Element{
		...ui2.clickable_view(id, ui2.rect(f64(x), f64(y), f64(width), 26), ui2.BoxStyle{
			transparent: true
		}, contents)
		accessibility_role:  'checkbox'
		accessibility_label: title
		checked:             checked
	}
}

fn (a &FilesContextApp) settings_overlay(size ui2.Rect) ui2.Element {
	width := int(size.width)
	height := int(size.height)
	panel_width := if width > 500 { 480 } else { width - 20 }
	panel_height := if height > 490 { 460 } else { height - 16 }
	x := (width - panel_width) / 2
	y := (height - panel_height) / 2
	mut rows := frame_elements(24)
	rows << ui2.label('', 'Files Settings', ui2.rect(18, 12, f64(panel_width - 70), 27), ui2.TextStyle{
		color: body_heading
		size:  16
		bold:  true
	})
	rows << ui2.button(files_settings_close, 'Done', ui2.rect(f64(panel_width - 68), 12, 54, 25), ui2.BoxStyle{
		bg:     body_panel
		radius: 5
	}, ui2.TextStyle{
		color: body_text
		size:  12
		align: .center
	})
	rows << settings_choice(files_settings_general, 'General', 15, 48, 100, a.settings_tab == 0)
	rows << settings_choice(files_settings_tags, 'Tags', 120, 48, 100, a.settings_tab == 1)
	rows << ui2.view('', ui2.rect(0, 84, f64(panel_width), 1), ui2.BoxStyle{
		bg: body_rule
	}, [])
	if a.settings_tab == 0 {
		rows << ui2.label('', 'File visibility', ui2.rect(20, 105, f64(panel_width - 40), 22), ui2.TextStyle{
			color: body_heading
			size:  14
			bold:  true
		})
		rows << files_settings_checkbox(files_settings_hidden, 'Show hidden files and folders', a.files.settings.show_hidden,
			22, 139, panel_width - 44)
		rows << ui2.label('', 'Includes names beginning with a dot, such as .local.',
			ui2.rect(49, 169, f64(panel_width - 65), 38), ui2.TextStyle{
				color: body_muted
				size:  11
				lines: 2
			})
	} else {
		rows << ui2.label('', 'Show these tags in the sidebar:', ui2.rect(20, 91, f64(panel_width - 40), 20), ui2.TextStyle{
			color: body_heading
			size:  13
		})
		list_bottom := panel_height - 111
		mut visible := (list_bottom - 116) / 25
		if visible < 1 { visible = 1 }
		for slot := 0; slot < visible; slot++ {
			index := slot + a.settings_scroll
			if index >= a.files.settings.tags.len { break }
			tag := a.files.settings.tags[index]
			row_y := 116 + slot * 25
			selected := a.settings_selected == index
			mut row := frame_elements(2)
			row << ui2.view('', ui2.rect(9, 5, 15, 15), ui2.BoxStyle{
				bg:     tag.color
				radius: 8
			}, [])
			row << ui2.label('', tag.name, ui2.rect(34, 0, f64(panel_width - 110), 25), ui2.TextStyle{
				color: if selected { app_on_accent } else { body_text }
				size:  13
			})
			rows << ui2.clickable_view('${files_settings_select_prefix}${index}', ui2.rect(19, f64(row_y), f64(panel_width - 38), 25), ui2.BoxStyle{
				bg: if selected {
					app_accent
				} else if index % 2 == 0 {
					body_panel
				} else {
					app_surface
				}
			}, row)
			rows << ui2.Element{
				...files_settings_checkbox('${files_settings_sidebar_prefix}${index}', '', tag.sidebar,
					panel_width - 55, row_y, 26)
				accessibility_label: 'Show ${tag.name} in sidebar'
			}
		}
		rows << ui2.button(files_settings_scroll_up, '↑', ui2.rect(f64(panel_width - 53), 90, 19, 21), ui2.BoxStyle{
			bg:     body_panel
			radius: 4
		}, ui2.TextStyle{ color: body_text, size: 13, align: .center })
		rows << ui2.button(files_settings_scroll_down, '↓', ui2.rect(f64(panel_width - 30), 90, 19, 21), ui2.BoxStyle{
			bg:     body_panel
			radius: 4
		}, ui2.TextStyle{ color: body_text, size: 13, align: .center })
		buttons_y := panel_height - 108
		rows << ui2.button(files_settings_add, '+', ui2.rect(20, f64(buttons_y), 28, 25), ui2.BoxStyle{
			bg:     body_panel
			radius: 5
		}, ui2.TextStyle{ color: body_text, size: 18, align: .center })
		rows << ui2.button(files_settings_remove, '−', ui2.rect(50, f64(buttons_y), 28, 25), ui2.BoxStyle{
			bg:     body_panel
			radius: 5
		}, ui2.TextStyle{ color: body_text, size: 18, align: .center })
		rows << ui2.button(files_settings_rename, 'Rename', ui2.rect(84, f64(buttons_y), 66, 25), ui2.BoxStyle{
			bg:     body_panel
			radius: 5
		}, ui2.TextStyle{ color: body_text, size: 11, align: .center })
		if a.settings_editing {
			rows << ui2.text_field('', '', rename_buffer_text(a.settings_name), ui2.rect(156, f64(buttons_y), f64(panel_width - 176), 25), ui2.BoxStyle{
				bg:     editor_path_focus
				radius: 4
			}, ui2.TextStyle{ color: body_text, size: 12 }, 0)
		} else {
			for color_index, color in files_settings_colors {
				rows << ui2.clickable_view('${files_settings_color_prefix}${color_index}', ui2.rect(f64(158 + color_index * 22), f64(buttons_y + 4), 17, 17), ui2.BoxStyle{
					bg:     color
					radius: 9
				}, [])
			}
		}
		rows << ui2.label('', 'Favorite tags (click to toggle):', ui2.rect(20, f64(panel_height - 78), f64(panel_width - 40), 18), ui2.TextStyle{
			color: body_muted
			size:  11
		})
		for index, tag in a.files.settings.tags {
			if index >= 12 { break }
			color := if tag.favorite { tag.color } else { body_rule }
			rows << ui2.clickable_view('${files_settings_favorite_prefix}${index}', ui2.rect(f64(22 + index * 31), f64(panel_height - 57), 20, 20), ui2.BoxStyle{
				bg:     color
				radius: 10
			}, [])
		}
		rows << files_settings_checkbox(files_settings_tint, 'Tint folders based on tags', a.files.settings.tint_folders,
			20, panel_height - 31, panel_width - 40)
	}
	mut outer := frame_elements(2)
	outer << ui2.clickable_view(files_settings_close, ui2.rect(0, 0, f64(width), f64(height)), ui2.BoxStyle{
		transparent: true
	}, [])
	outer << ui2.clickable_view('files.settings.panel', ui2.rect(f64(x), f64(y), f64(panel_width), f64(panel_height)), ui2.BoxStyle{
		bg:            app_surface
		radius:        9
		border_color:  body_rule
		border_left:   1
		border_right:  1
		border_top:    1
		border_bottom: 1
	}, rows)
	return ui2.view('', ui2.rect(0, 0, f64(width), f64(height)), ui2.BoxStyle{
		transparent: true
	}, outer)
}

fn (a &FilesContextApp) tag_picker_overlay(size ui2.Rect) ui2.Element {
	width := int(size.width)
	height := int(size.height)
	panel_width := if width > 320 { 280 } else { width - 20 }
	mut panel_height := a.files.settings.tags.len * 25 + 77
	if panel_height > height - 20 { panel_height = height - 20 }
	x := (width - panel_width) / 2
	y := (height - panel_height) / 2
	mut rows := frame_elements(a.files.settings.tags.len + 3)
	rows << ui2.label('', 'Tags', ui2.rect(14, 12, f64(panel_width - 80), 24), ui2.TextStyle{
		color: body_heading
		size:  15
		bold:  true
	})
	rows << ui2.button(files_picker_close, 'Done', ui2.rect(f64(panel_width - 68), 11, 55, 25), ui2.BoxStyle{
		bg:     body_panel
		radius: 5
	}, ui2.TextStyle{ color: body_text, size: 12, align: .center })
	assigned := a.files.settings.assignments[a.context_path] or { []int{} }
	for index := a.tag_picker_scroll; index < a.files.settings.tags.len; index++ {
		tag := a.files.settings.tags[index]
		row_y := 43 + (index - a.tag_picker_scroll) * 25
		if row_y + 25 > panel_height - 10 { break }
		mut item := frame_elements(3)
		item << ui2.view('', ui2.rect(10, 5, 15, 15), ui2.BoxStyle{ bg: tag.color, radius: 8 }, [])
		item << ui2.label('', tag.name, ui2.rect(34, 0, f64(panel_width - 78), 25), ui2.TextStyle{
			color: body_text
			size:  12
		})
		item << ui2.label('', if assigned.contains(tag.id) { '✓' } else { '' }, ui2.rect(f64(panel_width - 54), 0, 24, 25), ui2.TextStyle{
			color: app_accent
			size:  14
			align: .center
		})
		rows << ui2.clickable_view('${files_picker_toggle_prefix}${tag.id}', ui2.rect(12, f64(row_y), f64(panel_width - 24), 25), ui2.BoxStyle{
			bg: if index % 2 == 0 { body_panel } else { app_surface }
		}, item)
	}
	mut outer := frame_elements(2)
	outer << ui2.clickable_view(files_picker_close, ui2.rect(0, 0, f64(width), f64(height)), ui2.BoxStyle{ transparent: true }, [])
	outer << ui2.clickable_view('files.tags.panel', ui2.rect(f64(x), f64(y), f64(panel_width), f64(panel_height)), ui2.BoxStyle{
		bg:     app_surface
		radius: 8
	}, rows)
	return ui2.view('', ui2.rect(0, 0, f64(width), f64(height)), ui2.BoxStyle{ transparent: true }, outer)
}

fn (mut a FilesContextApp) start_settings_rename() {
	if a.settings_selected < 0 || a.settings_selected >= a.files.settings.tags.len {
		return
	}
	a.settings_name.clear()
	rename_buffer_set(mut a.settings_name, a.files.settings.tags[a.settings_selected].name)
	a.settings_editing = true
	a.settings_select_all = true
}

fn (mut a FilesContextApp) settings_key_input(input string) {
	if !a.settings_editing {
		if input == '\x1b' { a.settings_open = false }
		return
	}
	result := apply_rename_input(mut a.settings_name, a.settings_select_all, input)
	a.settings_select_all = result.select_all
	match result.state {
		.editing {}
		.cancel { a.settings_editing = false }
		.commit {
			name := rename_buffer_text(a.settings_name).trim_space()
			if name.len > 0 && name.len <= 64 && a.settings_selected >= 0
				&& a.settings_selected < a.files.settings.tags.len {
				a.files.settings.tags[a.settings_selected].name = name.clone()
				a.files.settings.save(desktop_home)
			}
			a.settings_editing = false
		}
	}
}

fn (mut a FilesContextApp) handle_settings(action string) {
	match action {
		files_settings_close { a.settings_open = false }
		files_settings_general { a.settings_tab = 0 }
		files_settings_tags { a.settings_tab = 1 }
		files_settings_hidden {
			a.files.settings.show_hidden = !a.files.settings.show_hidden
			a.files.browser.show_hidden = a.files.settings.show_hidden
			path := a.files.current_path().clone()
			a.files.navigate_to(path)
			unsafe { path.free() }
			a.files.settings.save(desktop_home)
		}
		files_settings_tint {
			a.files.settings.tint_folders = !a.files.settings.tint_folders
			a.files.settings.save(desktop_home)
		}
		files_settings_add {
			if a.files.settings.tags.len < files_tag_limit {
				id := a.files.settings.next_tag_id
				a.files.settings.next_tag_id++
				a.files.settings.tags << FilesTag{
					id:    id
					name:  'New Tag'
					color: 0x989aa0
				}
				a.settings_selected = a.files.settings.tags.len - 1
				a.settings_scroll = if a.settings_selected > 5 {
					a.settings_selected - 5
				} else {
					0
				}
				a.files.settings.save(desktop_home)
				a.start_settings_rename()
			}
		}
		files_settings_remove {
			a.files.settings.remove_tag(a.settings_selected)
			if a.settings_selected >= a.files.settings.tags.len {
				a.settings_selected = a.files.settings.tags.len - 1
			}
			a.settings_scroll = files_clamp(a.settings_scroll,
				if a.files.settings.tags.len > 0 { a.files.settings.tags.len - 1 } else { 0 })
			a.settings_editing = false
			a.files.settings.save(desktop_home)
		}
		files_settings_rename { a.start_settings_rename() }
		files_settings_scroll_up {
			a.settings_scroll = files_clamp(a.settings_scroll - 1, if a.files.settings.tags.len > 0 {
				a.files.settings.tags.len - 1
			} else {
				0
			})
		}
		files_settings_scroll_down {
			a.settings_scroll = files_clamp(a.settings_scroll + 1, if a.files.settings.tags.len > 0 {
				a.files.settings.tags.len - 1
			} else {
				0
			})
		}
		else {
			if action.starts_with(files_settings_select_prefix) {
				a.settings_selected = action[files_settings_select_prefix.len..].int()
				a.settings_editing = false
			} else if action.starts_with(files_settings_sidebar_prefix) {
				index := action[files_settings_sidebar_prefix.len..].int()
				if index >= 0 && index < a.files.settings.tags.len {
					a.files.settings.tags[index].sidebar = !a.files.settings.tags[index].sidebar
					a.files.settings.save(desktop_home)
				}
			} else if action.starts_with(files_settings_favorite_prefix) {
				index := action[files_settings_favorite_prefix.len..].int()
				if index >= 0 && index < a.files.settings.tags.len {
					a.files.settings.tags[index].favorite = !a.files.settings.tags[index].favorite
					a.files.settings.save(desktop_home)
				}
			} else if action.starts_with(files_settings_color_prefix) {
				color_index := action[files_settings_color_prefix.len..].int()
				if color_index >= 0 && color_index < files_settings_colors.len && a.settings_selected >= 0
					&& a.settings_selected < a.files.settings.tags.len {
					a.files.settings.tags[a.settings_selected].color = files_settings_colors[color_index]
					a.files.settings.save(desktop_home)
				}
			}
		}
	}
}
