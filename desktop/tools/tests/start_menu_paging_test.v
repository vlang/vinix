// SPDX-License-Identifier: GPL-2.0-or-later
module main

import ui2

fn start_paging_element(element ui2.Element, id string) ?ui2.Element {
	if element.id == id { return element }
	for child in element.children {
		if found := start_paging_element(child, id) { return found }
	}
	return none
}

fn start_paging_assert_readable_rows(tree ui2.Element) int {
	pane := start_paging_element(tree, 'start.programs') or { panic('missing programs') }
	search := start_paging_element(pane, action_start_search) or { panic('missing search') }
	mut count := 0
	mut previous_bottom := 0.0
	for child in pane.children {
		if !child.id.starts_with(action_start_launch_prefix) { continue }
		assert child.frame.height == start_menu_row_height
		assert child.frame.width > 0
		assert child.frame.y >= previous_bottom
		assert child.frame.y + child.frame.height <= search.frame.y - 5
		previous_bottom = child.frame.y + child.frame.height
		count++
	}
	if previous := start_paging_element(pane, action_start_previous) {
		next := start_paging_element(pane, action_start_next) or { panic('missing Next') }
		assert previous.frame.y >= previous_bottom
		assert previous.frame.x + previous.frame.width <= next.frame.x
		assert next.frame.x + next.frame.width <= pane.frame.width
		assert previous.frame.height == start_menu_page_height
		assert previous.frame.y + previous.frame.height <= search.frame.y - 5
		assert previous.text == tr('start.previous_page')
		assert next.text == tr('start.next_page')
	}
	return count
}

fn test_start_menu_page_geometry_bounds_and_preserves_readable_rows() {
	assert available_apps.len <= 64
	assert app_start_jump_actions.len >= available_apps.len
	for count in [0, 1, 40, 41, 64]! {
		for bottom in [0, 40, 74, 140, 489]! {
			for requested in [-1, 0, 1, 999_999_999]! {
				page := start_menu_page_layout(40, bottom, count, requested)
				assert page.capacity >= 1
				assert page.pages >= 1
				assert page.page >= 0 && page.page < page.pages
				assert page.first >= 0 && page.first <= count
				assert page.end >= page.first && page.end <= count
				assert page.end - page.first <= page.capacity
			}
		}
	}
	page := start_menu_page_layout(40, 489, available_apps.len, 0)
	assert page.pages > 1
	assert page.capacity * start_menu_row_height <= page.rows_bottom - 40
}

fn test_start_menu_all_program_pages_reach_every_app_at_readable_size() {
	for screen_height in [300, 480, 768]! {
		mut d := Desktop{ canvas: Canvas{ width: 640, height: screen_height } }
		d.toggle_start_menu()
		d.handle_start_action(action_start_all)
		mut seen := [64]bool{}
		mut shown := 0
		for _ in 0 .. available_apps.len {
			begin_frame_elements()
			tree := d.start_menu_element()
			shown += start_paging_assert_readable_rows(tree)
			for index in 0 .. available_apps.len {
				if start_paging_element(tree, app_start_actions[index]) != none {
					assert !seen[index]
					seen[index] = true
				}
			}
			free_tree(tree)
			page := d.start_menu_current_page()
			if page.page == page.pages - 1 { break }
			d.handle_start_action(action_start_next)
		}
		assert shown == available_apps.len
		for index in 0 .. available_apps.len { assert seen[index] }
		last := d.start_menu_page
		d.handle_start_action(action_start_next)
		assert d.start_menu_page == last
		d.close_start_menu()
		assert d.start_menu_page == 0
		unsafe { d.native_asset_icons.free() }
	}
}

fn test_start_menu_large_search_pages_preserve_filter_order_and_query() {
	mut d := Desktop{ canvas: Canvas{ width: 640, height: 300 } }
	d.toggle_start_menu()
	d.start_menu_key_input('a')
	assert d.start_menu_result_count() > d.start_menu_current_page().capacity
	mut seen := [64]bool{}
	mut previous_index := -1
	for _ in 0 .. available_apps.len {
		begin_frame_elements()
		tree := d.start_menu_element()
		assert start_paging_assert_readable_rows(tree) > 0
		for index in 0 .. available_apps.len {
			if start_paging_element(tree, app_start_actions[index]) != none {
				assert app_matches(available_apps[index].title, 'a')
				assert index > previous_index
				assert !seen[index]
				seen[index] = true
				previous_index = index
			}
		}
		free_tree(tree)
		page := d.start_menu_current_page()
		if page.page == page.pages - 1 { break }
		d.start_menu_key_input('\x1b[6~')
		assert d.start_menu_open
		assert d.start_menu_query_text() == 'a'
	}
	for index, factory in available_apps { assert seen[index] == app_matches(factory.title, 'a') }
	d.start_menu_key_input('\x1b[5~')
	assert d.start_menu_open && d.start_menu_query_text() == 'a'
	assert d.start_menu_page == d.start_menu_current_page().pages - 2
	d.close_start_menu()
	unsafe { d.native_asset_icons.free() }
}

fn test_start_menu_page_keys_query_edits_back_and_reopen_reset_state() {
	mut d := Desktop{ canvas: Canvas{ width: 640, height: 480 } }
	d.toggle_start_menu()
	d.start_menu_key_input('\x1b[6~')
	assert d.start_menu_open && d.start_menu_page == 0
	d.handle_start_action(action_start_all)
	d.start_menu_key_input('\x1b[6~\x1b[6~')
	assert d.start_menu_open && d.start_menu_page == 2
	d.start_menu_key_input('\x1b[5~')
	assert d.start_menu_page == 1
	d.start_menu_key_input('a')
	assert d.start_menu_page == 0 && !d.start_menu_all_apps
	d.start_menu_key_input('\x1b[6~')
	assert d.start_menu_page == 1
	d.start_menu_key_input('z')
	assert d.start_menu_page == 0
	d.start_menu_key_input('\x7f')
	assert d.start_menu_query_text() == 'a' && d.start_menu_page == 0
	d.start_menu_key_input('\x7f')
	assert d.start_menu_query.len == 0 && d.start_menu_page == 0
	d.handle_start_action(action_start_all)
	d.handle_start_action(action_start_next)
	assert d.start_menu_page == 1
	d.handle_start_action(action_start_back)
	assert !d.start_menu_all_apps && d.start_menu_page == 0
	d.handle_start_action(action_start_all)
	assert d.start_menu_page == 0
	d.handle_start_action(action_start_next)
	d.start_menu_key_input('\x1b')
	assert !d.start_menu_open && d.start_menu_page == 0
	d.toggle_start_menu()
	assert !d.start_menu_all_apps && d.start_menu_query.len == 0 && d.start_menu_page == 0
	d.start_menu_key_input('a')
	d.handle_start_action(action_start_next)
	d.handle_start_action(action_start_all)
	assert d.start_menu_all_apps && d.start_menu_query.len == 0 && d.start_menu_page == 0
	d.close_start_menu()
	unsafe { d.native_asset_icons.free() }
}

fn test_start_menu_resize_clamps_pages_and_missing_search_results() {
	mut d := Desktop{ canvas: Canvas{ width: 640, height: 300 } }
	d.toggle_start_menu()
	d.handle_start_action(action_start_all)
	d.start_menu_page = 999_999_999
	begin_frame_elements()
	free_tree(d.start_menu_element())
	assert d.start_menu_page == d.start_menu_current_page().pages - 1
	d.canvas.height = 768
	begin_frame_elements()
	tree := d.start_menu_element()
	assert d.start_menu_page == d.start_menu_current_page().pages - 1
	assert start_paging_element(tree, app_start_actions[available_apps.len - 1]) != none
	assert start_paging_assert_readable_rows(tree) > 0
	free_tree(tree)
	d.start_menu_key_input('qqqqqqqqqqqq')
	d.start_menu_page = 999_999_999
	begin_frame_elements()
	missing := d.start_menu_element()
	assert d.start_menu_page == 0
	assert start_paging_element(missing, 'start.no_results') != none
	assert start_paging_element(missing, action_start_next) == none
	free_tree(missing)
	d.start_menu_key_input('\n')
	assert d.start_menu_open && d.windows.len == 0
	d.canvas.height = 64
	d.handle_start_action(action_start_all)
	begin_frame_elements()
	free_tree(d.start_menu_element())
	assert d.start_menu_page >= 0
	d.close_start_menu()
	unsafe { d.native_asset_icons.free() }
}

fn test_start_menu_page_buttons_dispatch_through_desktop_pointer_targets() {
	mut d := Desktop{ canvas: Canvas{ width: 640, height: 480 } }
	defer { d.close_start_menu() d.clear_hit_targets() unsafe { d.targets.free() d.native_asset_icons.free() } }
	d.toggle_start_menu()
	d.handle_start_action(action_start_all)
	for action in [action_start_next, action_start_previous]! {
		begin_frame_elements()
		tree := d.start_menu_element()
		d.clear_hit_targets()
		d.record_subtree_targets(&tree, int(tree.frame.x), int(tree.frame.y), int(tree.frame.width), int(tree.frame.height))
		free_tree(tree)
		target := d.hit_target_named(action) or { panic('missing paging pointer target') }
		assert d.hit_action(target.x + 8, target.y + 8) == action
		d.on_pointer_down(target.x + 8, target.y + 8)
		d.on_pointer_up(target.x + 8, target.y + 8)
		assert d.start_menu_open
		assert d.start_menu_page == if action == action_start_next { 1 } else { 0 }
	}
}
