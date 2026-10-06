// SPDX-License-Identifier: GPL-2.0-or-later
module main

import ui2

#include "@VMODROOT/heap_tracker.h"

fn C.vinix_heap_begin()
fn C.vinix_heap_end() u64

fn settings_search_heap_frame(mut app SettingsApp, width int, height int) ! {
	begin_frame_elements()
	tree := app.build(ui2.rect(0, 0, f64(width), f64(height)))!
	free_tree(tree)
}

fn settings_search_heap_warm() ! {
	mut desktop := Desktop{}
	mut app := &SettingsApp{ desktop: unsafe { &desktop } }
	for query in ['a', 'keyboard', 'not found', '']! {
		app.key_input('\x06')
		app.paste_input(query)
		if query.len == 0 { app.handle('settings.search.clear')! }
		for size in [ui2.rect(0, 0, 620, 376), ui2.rect(0, 0, 900, 700), ui2.rect(0, 0, 320, 200)]! {
			settings_search_heap_frame(mut app, int(size.width), int(size.height))!
		}
	}
	app.close_app()
	unsafe {
		free(app)
		desktop.native_asset_icons.free()
	}
}

fn test_settings_search_repeated_localized_query_render_navigation_and_resize_retain_zero_bytes() {
	settings_search_heap_warm()!
	mut desktop := Desktop{}
	mut app := &SettingsApp{ desktop: unsafe { &desktop } }
	defer {
		app.close_app()
		unsafe {
			free(app)
			desktop.native_asset_icons.free()
		}
		set_desktop_language(.en)
	}
	C.vinix_heap_begin()
	for index in 0 .. 200 {
		set_desktop_language(desktop_languages[index % desktop_languages.len])
		app.key_input('\x06')
		app.paste_input('a')
		settings_search_heap_frame(mut app, 620, 376)!
		app.key_input('\x1b')
		app.key_input('[6')
		app.key_input('~')
		settings_search_heap_frame(mut app, 900, 700)!
		app.handle('settings.search.previous')!
		app.key_input('\x06')
		app.paste_input('not found')
		settings_search_heap_frame(mut app, 320, 200)!
		app.handle('settings.search.clear')!
		settings_search_heap_frame(mut app, 620, 376)!
	}
	app.close_app()
	assert C.vinix_heap_end() == 0
}

fn test_settings_search_full_query_and_input_lifetimes_release_owned_storage() {
	settings_search_heap_warm()!
	C.vinix_heap_begin()
	for _ in 0 .. 100 {
		mut app := &SettingsApp{}
		app.key_input('\x06')
		app.paste_input('a\n\x1bbé')
		app.key_input('\x01\x7f')
		app.key_input('\xd1')
		app.key_input('\x8f')
		assert editor_bytes_text(app.search) == 'я'
		app.key_input('\x1b[1;5C')
		settings_search_heap_frame(mut app, 620, 376)!
		app.key_input('\x1b')
		assert app.expire_search_escape(app.search_escape_ms + 100)
		app.close_app()
		app.close_app()
		unsafe { free(app) }
	}
	assert C.vinix_heap_end() == 0
}

fn test_settings_search_keyboard_and_paste_native_interface_dispatch_retain_zero_bytes() {
	mut app := &SettingsApp{}
	mut native := NativeApp(app)
	mut desktop := Desktop{ focus: 71 }
	desktop.apps << native
	desktop.windows << Window{ id: 71, page: .app, app_index: 0 }
	defer {
		app.close_app()
		unsafe {
			free(app)
			desktop.apps.free()
			desktop.windows.free()
			desktop.native_asset_icons.free()
		}
	}
	C.vinix_heap_begin()
	for _ in 0 .. 200 {
		desktop.send_keys_to_focused('\x06')
		desktop.send_paste_to_focused('brightness')
		assert app.search_count > 0
		desktop.send_keys_to_focused('\x01\x7f')
		assert app.search.len == 0
	}
	app.close_app()
	assert C.vinix_heap_end() == 0
}
