// SPDX-License-Identifier: GPL-2.0-or-later
module main

#include "@VMODROOT/heap_tracker.h"
fn C.vinix_heap_begin()
fn C.vinix_heap_end() u64

fn start_paging_memory_frames(mut d Desktop, paint bool) {
	d.toggle_start_menu()
	d.handle_start_action(action_start_all)
	for _ in 0 .. d.start_menu_current_page().pages {
		begin_frame_elements()
		tree := d.start_menu_element()
		if paint { d.render(tree) }
		free_tree(tree)
		d.handle_start_action(action_start_next)
	}
	d.start_menu_key_input('a')
	for _ in 0 .. d.start_menu_current_page().pages {
		begin_frame_elements()
		tree := d.start_menu_element()
		if paint { d.render(tree) }
		free_tree(tree)
		d.start_menu_key_input('\x1b[6~')
	}
	d.start_menu_key_input('zzzzzz')
	begin_frame_elements()
	missing := d.start_menu_element()
	if paint { d.render(missing) }
	free_tree(missing)
	d.close_start_menu()
}

fn test_start_menu_paging_repeated_open_query_pages_and_close_release_owned_bytes() {
	mut warm := Desktop{ canvas: Canvas{ width: 640, height: 480 } }
	start_paging_memory_frames(mut warm, false)
	unsafe { warm.native_asset_icons.free() }
	C.vinix_heap_begin()
	for _ in 0 .. 50 {
		mut d := Desktop{ canvas: Canvas{ width: 640, height: 480 } }
		start_paging_memory_frames(mut d, false)
		unsafe { d.native_asset_icons.free() }
	}
	live := C.vinix_heap_end()
	assert live == 0, 'Start menu paging lifecycles retained ${live} bytes'
}

fn test_start_menu_paged_rendering_releases_frame_text_and_reuses_hit_targets() {
	mut d := Desktop{ canvas: new_canvas(640, 480), fonts: load_fonts() }
	defer {
		d.close_start_menu()
		d.clear_hit_targets()
		d.free_wallpaper()
		free_fonts(mut d.fonts)
		for _, icon in d.native_asset_icons {
			unsafe { icon.pixels.free() free(icon) }
		}
		unsafe { free(d.canvas.pixels) d.targets.free() d.cursor_backing.pixels.free() d.native_asset_icons.free() }
	}
	start_paging_memory_frames(mut d, true)
	C.vinix_heap_begin()
	for _ in 0 .. 10 { start_paging_memory_frames(mut d, true) }
	live := C.vinix_heap_end()
	assert live == 0, 'Rendered Start menu pages retained ${live} bytes'
}
