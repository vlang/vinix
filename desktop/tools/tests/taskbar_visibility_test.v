// SPDX-License-Identifier: GPL-2.0-or-later
module main

import ui2

fn visibility_element(root ui2.Element, id string) ?ui2.Element {
	if root.id == id { return root }
	for child in root.children {
		if element := visibility_element(child, id) { return element }
	}
	return none
}

fn test_optional_taskbar_buttons_start_hidden_and_settings_restore_them_independently() {
	mut desktop := Desktop{ canvas: Canvas{ width: 1024, height: 768 } }
	mut app := SettingsApp{ desktop: &desktop, category: .taskbar }
	initial := desktop.taskbar_layout(0)
	assert initial.workspace_width == 0
	defaults := desktop.build_tree()
	assert visibility_element(defaults, action_window_overview) == none
	for id in workspace_action_ids { assert visibility_element(defaults, id) == none }
	free_tree(defaults)

	app.handle('${settings_action_taskbar_overview}0')!
	overview := desktop.build_tree()
	assert visibility_element(overview, action_window_overview) != none
	assert visibility_element(overview, workspace_action_ids[0]) == none
	assert desktop.taskbar_layout(0).entries_left > initial.entries_left
	free_tree(overview)

	app.handle('${settings_action_taskbar_workspaces}0')!
	both := desktop.build_tree()
	assert visibility_element(both, action_window_overview) != none
	for id in workspace_action_ids[..4] {
		assert visibility_element(both, id) != none
	}
	assert desktop.taskbar_layout(0).entries_right < initial.entries_right
	free_tree(both)

	app.handle('${settings_action_taskbar_overview}1')!
	pager := desktop.build_tree()
	assert visibility_element(pager, action_window_overview) == none
	assert visibility_element(pager, workspace_action_ids[0]) != none
	assert desktop.taskbar_layout(0).entries_left == initial.entries_left
	free_tree(pager)
	app.handle('${settings_action_taskbar_workspaces}1')!
	assert desktop.taskbar_layout(0) == initial
	assert desktop.configure_workspaces(8)
	hidden_pages := desktop.build_tree()
	assert visibility_element(hidden_pages, 'session.workspace.previous') == none
	assert visibility_element(hidden_pages, 'session.workspace.next') == none
	free_tree(hidden_pages)
	// Hiding controls leaves their keyboard routes available.
	desktop.spawn('Welcome', .welcome, 120, 80, 400, 260)
	assert desktop.take_window_overview_keys(key_window_overview) == ''
	assert desktop.overview.active
	desktop.close_window_overview()
	assert desktop.take_window_shortcuts(key_super_workspaces[1]) == ''
	assert desktop.current_workspace == 1
}

fn test_taskbar_visibility_survives_app_protocol_and_legacy_app_replies() {
	for mode in [TaskbarMode.standard, .combined] {
		for bits in 0 .. 4 {
			state := AppWireState{ settings: Settings{
				taskbar_mode: mode
				taskbar_show_overview: bits & 1 != 0
				taskbar_show_workspaces: bits & 2 != 0
			} }
			mut encoded := []u8{}
			wire_put_state(mut encoded, state)
			mut reader := WireReader{ data: encoded }
			decoded := wire_take_state(mut reader)!
			assert decoded == state
			assert reader.index == encoded.len
			unsafe { encoded.free() }
			assert app_state_for_peer(state, app_features, app_extended) == state
			legacy := app_state_for_peer(state, app_features, app_extended_luna)
			assert wire_taskbar(legacy.settings) == int(mode)
			assert app_state_from_peer(legacy, app_features, app_extended_luna, state.settings) == state
			changed := AppWireState{ ...legacy, settings: Settings{ ...legacy.settings, button_side: .left } }
			answer := app_state_from_peer(changed, app_features, app_extended_luna, state.settings)
			assert answer.settings.button_side == .left
			assert answer.settings.taskbar_show_overview == state.settings.taskbar_show_overview
			assert answer.settings.taskbar_show_workspaces == state.settings.taskbar_show_workspaces
		}
	}
	assert !wire_taskbar_valid(-1)
	assert !wire_taskbar_valid(2)
	assert !wire_taskbar_valid(1 << 10)
}

fn test_settings_offers_visibility_choices_only_when_the_compositor_supports_them() {
	mut desktop := Desktop{}
	mut app := SettingsApp{ desktop: &desktop }
	defer { app_compositor_extended = app_extended }
	appearance := app.build(ui2.rect(0, 0, 720, 400))!
	assert visibility_element(appearance, 'settings.side.0') != none
	assert visibility_element(appearance, 'settings.taskbar.0') == none
	assert visibility_element(appearance, 'settings.overview.0') == none
	category_action := settings_category_actions[settings_categories.index(SettingsCategory.taskbar)]
	assert visibility_element(appearance, category_action) != none
	assert settings_category_actions[settings_categories.index(SettingsCategory.keyboard)] == 'settings.category.9'
	free_tree(appearance)
	app.handle(category_action)!
	assert app.category == .taskbar
	assert app.category_page == 0
	root := app.build(ui2.rect(0, 0, 720, 400))!
	assert visibility_element(root, 'settings.taskbar.0') != none
	assert visibility_element(root, 'settings.side.0') == none
	for id in ['settings.overview.1', 'settings.workspaces.1'] {
		choice := visibility_element(root, id) or { panic('missing visibility choice') }
		assert choice.checked
		assert choice.frame.y + choice.frame.height <= 400
	}
	free_tree(root)
	app_compositor_extended = app_extended_luna
	legacy := app.build(ui2.rect(0, 0, 720, 400))!
	assert visibility_element(legacy, 'settings.overview.0') == none
	assert visibility_element(legacy, 'settings.workspaces.0') == none
	free_tree(legacy)
	app.handle('${settings_action_taskbar_overview}0')!
	app.handle('${settings_action_taskbar_workspaces}0')!
	assert !desktop.settings.taskbar_show_overview
	assert !desktop.settings.taskbar_show_workspaces
}

fn test_taskbar_visibility_choices_are_translated_searchable_and_have_baked_glyphs() {
	defer { set_desktop_language(.en) }
	mut app := SettingsApp{}
	defer { app.close_app() }
	for language in desktop_languages {
		set_desktop_language(language)
		assert tr('settings.category.taskbar') == tr('settings.appearance.taskbar')
		for key in ['settings.appearance.overview', 'settings.appearance.workspaces', 'settings.appearance.taskbar'] {
			text := tr(key)
			assert text.len > 0 && text != key
			for point in text.runes() {
				if point > font_last_char { assert u32(point) in font_extra_runes }
			}
			app.key_input('\x06')
			app.paste_input(text)
			mut found := -1
			for i in 0 .. app.search_count {
				if settings_search_entries[app.search_results[i]].title == key { found = i }
			}
			assert found >= 0
			app.open_search_result(found)
			assert app.category == .taskbar
			assert app.category_page == 0
		}
	}
}
