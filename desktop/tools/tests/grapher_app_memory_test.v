// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os
import ui2

#include "@VMODROOT/heap_tracker.h"

fn C.vinix_heap_begin()
fn C.vinix_heap_end() u64

fn test_grapher_repeated_parse_evaluation_and_plot_release_owned_memory() {
	mut app := GrapherApp{}
	app.initialize()
	begin_frame_elements()
	free_tree(app.build(ui2.rect(0, 0, 840, 636))!)
	C.vinix_heap_begin()
	for _ in 0 .. 100 {
		for source in ['sin(x)*exp(-x^2/10)', '1/(x-.123)', 'sqrt(x)', 'floor(x)', '2^3^2', 'sin(',
			'']! {
			app.set_field(0, source)
			app.plot()
		}
		app.handle('grapher.expression')!
		app.paste_input('sin(x)')
		app.handle('grapher.zoom_in')!
		app.handle('grapher.zoom_out')!
		app.handle('grapher.reset')!
		for size in [ui2.rect(0, 0, 840, 636), ui2.rect(0, 0, 440, 410), ui2.rect(0, 0, 1600, 900)]! {
			begin_frame_elements()
			free_tree(app.build(size)!)
		}
	}
	app.close_app()
	app.close_app()
	assert C.vinix_heap_end() == 0
}

fn test_grapher_repeated_csv_export_and_existing_destination_release_owned_memory() {
	temporary := os.join_path(os.temp_dir(), 'vinix-grapher-memory-${os.getpid()}')
	os.mkdir_all(temporary)!
	root := os.real_path(temporary)
	path := disk_utility_join_path(root, 'graph-Ж.csv')
	defer {
		os.rmdir_all(root) or {}
		unsafe {
			temporary.free()
			root.free()
			path.free()
		}
	}
	mut app := GrapherApp{}
	app.initialize()
	app.set_field(5, path)
	C.vinix_heap_begin()
	for _ in 0 .. 50 {
		app.handle('grapher.expression')!
		app.paste_input('sqrt(x)')
		app.export_csv()
		assert app.export_status == 'grapher.export_saved'
		app.export_csv()
		assert app.export_status == 'grapher.export_exists'
		assert C.unlink(&char(path.str)) == 0
	}
	app.close_app()
	assert C.vinix_heap_end() == 0
}

fn test_grapher_repeated_initialize_close_releases_owned_buffers() {
	mut app := GrapherApp{}
	app.initialize()
	app.close_app()
	C.vinix_heap_begin()
	for _ in 0 .. 100 {
		app.initialize()
		app.initialize()
		app.key_input('\x0c\x01x^2\r')
		assert app.plotted
		app.close_app()
		app.close_app()
	}
	assert C.vinix_heap_end() == 0
}

fn test_grapher_registered_home_alias_resolution_and_default_export_release_owned_memory() {
	temporary := os.join_path(os.temp_dir(), 'vinix-grapher-home-memory-${os.getpid()}')
	os.mkdir_all(temporary)!
	root := os.real_path(temporary)
	alias := disk_utility_join_path(root, 'registered-home')
	path := disk_utility_join_path(root, 'graph.csv')
	os.symlink(root, alias)!
	previous := desktop_user_home
	desktop_user_home = alias
	defer {
		desktop_user_home = previous
		os.rmdir_all(root) or {}
		unsafe {
			temporary.free()
			root.free()
			alias.free()
			path.free()
		}
	}
	mut app := GrapherApp{}
	app.initialize()
	app.close_app()
	C.vinix_heap_begin()
	for _ in 0 .. 50 {
		app.initialize()
		assert app.field_text(5) == path
		app.export_csv()
		assert app.export_status == 'grapher.export_saved'
		assert C.unlink(&char(path.str)) == 0
		app.close_app()
	}
	assert C.vinix_heap_end() == 0
}
