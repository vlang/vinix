// SPDX-License-Identifier: GPL-2.0-or-later
module main

import ui2

#include "@VMODROOT/heap_tracker.h"

fn C.vinix_heap_begin()

fn C.vinix_heap_end() u64

fn C.vinix_heap_count() u32

fn C.vinix_heap_size_at(index u32) u64

fn memory_fixture_desktop() Desktop {
	mut desktop := Desktop{
		canvas: new_canvas(1024, 768)
		fonts: load_fonts()
	}
	desktop.spawn('Welcome', .welcome, 150, 60, 396, 244)
	desktop.spawn('System', .system, 580, 60, 372, 232)

	mut browser := &FileBrowserApp{}
	browser.browser.entries = [
		FileEntry{ name: 'src', is_dir: true },
		FileEntry{ name: 'README.md', size: 32_768 },
	]
	desktop.apps << browser
	id := desktop.spawn('Files', .app, 120, 112, 460, 360)
	index := desktop.window_index(id) or { panic('missing Files window') }
	desktop.windows[index].app_index = desktop.apps.len - 1
	desktop.windows[index].icon = 'builtin:folder'

	mut activity := &ActivityApp{
		monitor: ActivityMonitor{
			rows: [
				ActivityRow{
					pid: 7
					name: 'vinix-desktop'
					pid_text: '7'
					cpu_text: '0'
					mem_text: '1.0'
				},
			]
			summary: '4 processes   12 MB of 256 MB used'
		}
	}
	desktop.apps << activity
	id2 := desktop.spawn('Activity', .app, 146, 138, 520, 400)
	index2 := desktop.window_index(id2) or { panic('missing Activity window') }
	desktop.windows[index2].app_index = desktop.apps.len - 1
	desktop.windows[index2].icon = 'builtin:activity'
	return desktop
}

fn render_and_release(mut desktop Desktop) {
	desktop.frames++
	tree := desktop.build_tree()
	desktop.render(tree)
	free_tree(tree)
}

fn measured_frame(mut desktop Desktop) u64 {
	C.vinix_heap_begin()
	render_and_release(mut desktop)
	return C.vinix_heap_end()
}

fn print_heap_sizes(label string) {
	mut sizes := map[u64]int{}
	for i in u32(0) .. C.vinix_heap_count() {
		size := C.vinix_heap_size_at(i)
		sizes[size]++
	}
	eprintln('${label}: ${sizes}')
}

fn test_an_idle_redraw_releases_all_temporary_allocations() {
	mut desktop := memory_fixture_desktop()
	// Allocate the wallpaper and hit-target capacity before measurement; both
	// are persistent buffers, not frame temporaries.
	render_and_release(mut desktop)
	render_and_release(mut desktop)
	for visible in 0 .. 5 {
		for i := 0; i < desktop.windows.len; i++ {
			desktop.windows[i].minimized = i >= visible
		}
		eprintln('visible ${visible}: ${measured_frame(mut desktop)} bytes')
		print_heap_sizes('visible ${visible}')
	}
	for i := 0; i < desktop.windows.len; i++ {
		desktop.windows[i].minimized = false
	}

	C.vinix_heap_begin()
	for _ in 0 .. 8 {
		render_and_release(mut desktop)
	}
	live := C.vinix_heap_end()
	print_heap_sizes('live allocations by size')
	assert live == 0, 'idle redraws retained ${live} bytes'
}

fn test_start_menu_search_and_redraw_release_temporary_allocations() {
	mut desktop := memory_fixture_desktop()
	// Warm the persistent frame pools for both menu layouts before measuring.
	desktop.toggle_start_menu()
	render_and_release(mut desktop)
	desktop.start_menu_key_input('term')
	render_and_release(mut desktop)
	desktop.close_start_menu()

	desktop.toggle_start_menu()
	C.vinix_heap_begin()
	desktop.start_menu_key_input('term')
	for _ in 0 .. 8 {
		render_and_release(mut desktop)
	}
	desktop.start_menu_key_input('\x7f')
	render_and_release(mut desktop)
	desktop.close_start_menu()
	live := C.vinix_heap_end()
	if live != 0 {
		print_heap_sizes('Start menu allocations by size')
	}
	assert live == 0, 'Start menu retained ${live} bytes'
}

fn test_idle_compositor_poll_releases_all_temporary_allocations() {
	mut desktop := memory_fixture_desktop()
	// The production loop executes these calls even when no redraw is needed.
	// Keep them under the heap tracker independently from tree construction so
	// a quiet desktop cannot leak through interface dispatch or window scans.
	desktop.update_clock_at(1_789_000_000, 73)
	desktop.poll_apps()
	C.vinix_heap_begin()
	for _ in 0 .. 100 {
		desktop.update_clock_at(1_789_000_000, 73)
		desktop.poll_apps()
		desktop.update_switcher()
	}
	live := C.vinix_heap_end()
	if live != 0 {
		print_heap_sizes('idle compositor poll allocations by size')
	}
	assert live == 0, 'idle compositor polls retained ${live} bytes'
}

fn test_unchanged_clock_update_does_not_allocate() {
	mut desktop := Desktop{}
	// The production helper is deterministic here; unlike waiting for wall
	// clock ticks this cannot cross a second while the test is running.
	desktop.update_clock_at(1_789_000_000, 73)
	C.vinix_heap_begin()
	for _ in 0 .. 100 {
		desktop.update_clock_at(1_789_000_000, 73)
	}
	live := C.vinix_heap_end()
	assert live == 0, 'unchanged clock updates retained ${live} bytes'
}

fn test_changing_clock_releases_replaced_strings() {
	mut desktop := Desktop{}
	desktop.update_clock_at(1_789_000_000, 73)
	C.vinix_heap_begin()
	for offset in 1 .. 101 {
		desktop.update_clock_at(1_789_000_000 + offset, 73)
	}
	unsafe {
		desktop.clock_time.free()
		desktop.clock_date.free()
	}
	live := C.vinix_heap_end()
	assert live == 0, 'changing clock updates retained ${live} bytes'
}

fn test_once_per_second_redraw_releases_clock_and_frame_allocations() {
	mut desktop := memory_fixture_desktop()
	// This is the production idle cadence: the clock changes, marks the
	// compositor dirty, and the complete visible desktop is rebuilt once.
	// Testing the clock and frame separately can miss an ownership error at
	// their boundary.
	render_and_release(mut desktop)
	desktop.update_clock_at(1_789_000_000, 73)
	C.vinix_heap_begin()
	for offset in 1 .. 101 {
		desktop.update_clock_at(1_789_000_000 + offset, 73)
		render_and_release(mut desktop)
	}
	unsafe {
		desktop.clock_time.free()
		desktop.clock_date.free()
	}
	live := C.vinix_heap_end()
	if live != 0 {
		print_heap_sizes('once-per-second redraw allocations by size')
	}
	assert live == 0, 'once-per-second redraws retained ${live} bytes'
}

fn test_activity_samples_release_replaced_rows() {
	mut monitor := ActivityMonitor{}
	mut header := ActivityTable{
		total: 1
		total_memory: 256 * 1024 * 1024
		free_memory: 192 * 1024 * 1024
		sample_ns: 1_000_000_000
	}
	mut record := ActivitySample{
		pid: 7
		memory_bytes: 1024 * 1024
		cpu_time_ns: 10_000_000
	}
	name := '/bin/vinix-desktop[7]'
	for index := 0; index < name.len && index < activity_name_len - 1; index++ {
		record.name[index] = name[index]
	}
	monitor.apply_snapshot(&header, &record, 1)
	assert monitor.rows[0].mem_text == '1 MB'

	C.vinix_heap_begin()
	for _ in 0 .. 100 {
		header.sample_ns += 1_000_000_000
		record.cpu_time_ns += 25_000_000
		monitor.apply_snapshot(&header, &record, 1)
	}
	monitor.free_rows()
	live := C.vinix_heap_end()
	if live != 0 {
		print_heap_sizes('activity allocations by size')
	}
	assert live == 0, 'activity samples retained ${live} bytes'
}

fn test_remote_application_trees_release_copied_strings_and_arrays() {
	root := ui2.screen(0x102030, [
		ui2.view('panel', ui2.rect(0, 0, 320, 200), ui2.BoxStyle{
			bg: 0xffffff
		}, [
			ui2.label('title', 'Separate process', ui2.rect(8, 8, 200, 20), ui2.TextStyle{
				color: 0x111111
				font_family: 'mono'
			}),
		]),
	])
	mut encoded := []u8{}
	encode_app_element(root, mut encoded)!
	free_tree(root)

	C.vinix_heap_begin()
	for _ in 0 .. 100 {
		decoded := decode_app_tree(encoded)!
		free_tree(decoded)
	}
	live := C.vinix_heap_end()
	if live != 0 {
		print_heap_sizes('remote application tree allocations by size')
	}
	assert live == 0, 'remote application trees retained ${live} bytes'
	unsafe { encoded.free() }
}

fn test_compiled_calculator_vml_releases_every_frame_allocation() {
	mut calculator := new_calculator_app()
	warm := calculator.build(ui2.rect(0, 0, window_width, window_height))!
	free_tree(warm)

	C.vinix_heap_begin()
	for _ in 0 .. 100 {
		frame := calculator.build(ui2.rect(0, 0, window_width, window_height))!
		free_tree(frame)
	}
	live := C.vinix_heap_end()
	if live != 0 {
		print_heap_sizes('compiled Calculator VML allocations by size')
	}
	assert live == 0, 'compiled Calculator VML retained ${live} bytes'
	calculator.close_app()
}

fn element_exists(root ui2.Element, id string) bool {
	if root.id == id {
		return true
	}
	for child in root.children {
		if element_exists(child, id) {
			return true
		}
	}
	return false
}
