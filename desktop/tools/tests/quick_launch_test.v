// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
module main

import ui2

fn quick_launch_tree_has_text(element ui2.Element, text string) bool {
	if element.text == text {
		return true
	}
	for child in element.children {
		if quick_launch_tree_has_text(child, text) {
			return true
		}
	}
	return false
}

fn quick_launch_element_named(element ui2.Element, id string) ?ui2.Element {
	if element.id == id {
		return element
	}
	for child in element.children {
		found := quick_launch_element_named(child, id) or { continue }
		return found
	}
	return none
}

fn quick_launch_fixture() Desktop {
	return Desktop{
		canvas: Canvas{
			width: 1024
			height: 768
		}
	}
}

fn test_cmd_space_opens_spotlight_style_app_search_and_owns_typing() {
	mut desktop := quick_launch_fixture()

	assert desktop.take_switcher_keys(quick_launch_key) == ''
	assert desktop.switcher.active
	assert desktop.switcher.shown
	assert desktop.switcher.quick_launch
	assert desktop.switcher.quick_launch_chord_held

	root := desktop.build_tree()
	assert quick_launch_element_named(root, quick_launch_panel_action) != none
	assert quick_launch_tree_has_text(root, 'Search applications')
	assert quick_launch_tree_has_text(root, 'Files')
	assert !quick_launch_tree_has_text(root, 'Shut down')
	free_tree(root)

	// Releasing Cmd must leave Spotlight open. Unlike Cmd-Tab, selecting an
	// application is an explicit Return or click after the user has searched.
	assert desktop.take_switcher_keys(quick_launch_cmd_release) == ''
	assert desktop.switcher.quick_launch
	assert !desktop.switcher.quick_launch_chord_held

	assert desktop.take_switcher_keys('term') == ''
	assert desktop.quick_launch_query_text() == 'term'
	assert desktop.quick_launch_match_count() == 1
	app_index := desktop.quick_launch_app_index(0) or { panic('missing Terminal result') }
	assert available_apps[app_index].title == 'Terminal'

	results := desktop.build_tree()
	assert quick_launch_tree_has_text(results, 'Terminal')
	assert !quick_launch_tree_has_text(results, 'Calculator')
	free_tree(results)

	assert desktop.take_switcher_keys('\x1b') == ''
	assert !desktop.switcher.active
	assert !desktop.switcher.quick_launch
	assert desktop.switcher.query.len == 0
}

fn test_quick_launch_filters_only_available_apps_and_moves_selection() {
	mut desktop := quick_launch_fixture()
	desktop.toggle_quick_launch()
	assert desktop.take_switcher_keys('cal') == ''
	assert desktop.quick_launch_match_count() == 3

	first := desktop.quick_launch_app_index(0) or { panic('missing first Calculator result') }
	second := desktop.quick_launch_app_index(1) or { panic('missing second Calculator result') }
	third := desktop.quick_launch_app_index(2) or { panic('missing third Calculator result') }
	assert available_apps[first].title == 'Calculator'
	assert available_apps[second].title == 'Cocoa Calculator'
	assert available_apps[third].title == 'Wine Calculator'

	assert desktop.take_switcher_keys('\x1b[B') == ''
	assert desktop.switcher.index == 1
	assert desktop.take_switcher_keys('\x1b[A') == ''
	assert desktop.switcher.index == 0

	// The panel itself consumes clicks; its backdrop dismisses the overlay.
	desktop.switcher_select(-1)
	assert desktop.switcher.quick_launch
	desktop.switcher_select(-2)
	assert !desktop.switcher.active
}

fn test_quick_launch_cmd_space_handles_split_sequences_and_key_repeat() {
	mut desktop := quick_launch_fixture()

	// Keyboard reads may divide a CSI-u sequence. The switcher's existing
	// pending-sequence path must still recognise Cmd-Space when that happens.
	assert desktop.take_switcher_keys('\x1b[') == ''
	assert desktop.switcher.pending == '\x1b['
	assert desktop.take_switcher_keys('32;9u') == ''
	assert desktop.switcher.quick_launch

	// A repeated Cmd-Space while the same Cmd press is held is key repeat, not
	// another toggle. Releasing Cmd arms the next deliberate chord.
	assert desktop.take_switcher_keys(quick_launch_key) == ''
	assert desktop.switcher.quick_launch
	assert desktop.take_switcher_keys(quick_launch_cmd_release) == ''
	assert desktop.take_switcher_keys(quick_launch_key) == ''
	assert !desktop.switcher.active
	assert desktop.take_switcher_keys(quick_launch_cmd_release) == ''
	assert !desktop.switcher.quick_launch_chord_held
}

fn test_quick_launch_replaces_an_open_start_menu() {
	mut desktop := quick_launch_fixture()
	desktop.toggle_start_menu()
	assert desktop.start_menu_open

	assert desktop.take_switcher_keys(quick_launch_key) == ''
	assert !desktop.start_menu_open
	assert desktop.switcher.quick_launch

	desktop.switcher_close()
}
