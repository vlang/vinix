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

fn test_grapher_repeated_document_parser_and_serialization_release_owned_memory() {
	fields := ['sin(x)+x^2', '-pi', 'pi', '-e', 'e']!
	C.vinix_heap_begin()
	for _ in 0 .. 1000 {
		bytes := grapher_document_bytes(fields)
		data := editor_bytes_text(bytes)
		document := grapher_document_parse(data) or { panic('expected document') }
		assert document.fields == fields
		assert grapher_document_parse(unsafe { tos(data.str, data.len - 1) }) == none
		assert grapher_document_parse('VINIX-GRAPH 1\nexpression=sin(\nxmin=-1\nxmax=1\nymin=-1\nymax=1\n') == none
		unsafe { bytes.free() }
	}
	assert C.vinix_heap_end() == 0
}

fn test_grapher_repeated_document_open_save_and_failures_release_owned_memory() {
	temporary := os.join_path(os.temp_dir(), 'vinix-grapher-doc-memory-${os.getpid()}')
	os.mkdir_all(temporary)!
	root := os.real_path(temporary)
	path := disk_utility_join_path(root, 'graph-Ж.vgraph')
	bad_path := disk_utility_join_path(root, 'invalid.vgraph')
	missing := disk_utility_join_path(root, 'missing.vgraph')
	os.write_file(bad_path, 'VINIX-GRAPH 1\nexpression=sin(\nxmin=-1\nxmax=1\nymin=-1\nymax=1\n')!
	defer {
		os.rmdir_all(root) or {}
		unsafe { temporary.free() root.free() path.free() bad_path.free() missing.free() }
	}
	mut app := GrapherApp{}
	app.initialize()
	app.close_app()
	C.vinix_heap_begin()
	for _ in 0 .. 100 {
		app.initialize()
		app.set_field(0, 'sqrt(x)+sin(x)')
		app.set_field(1, '-pi')
		app.set_field(2, 'pi')
		app.set_field(6, path)
		app.save_graph_document()
		assert app.document_status == 'grapher.document_saved'
		app.save_graph_document()
		assert app.document_status == 'grapher.document_exists'
		app.set_field(0, 'x')
		app.open_graph_document()
		assert app.document_status == 'grapher.document_opened'
		assert app.field_text(0) == 'sqrt(x)+sin(x)' && app.plotted
		app.set_field(6, bad_path)
		app.open_graph_document()
		assert app.document_status == 'grapher.document_invalid'
		assert app.field_text(0) == 'sqrt(x)+sin(x)' && app.plotted
		app.set_field(6, missing)
		app.open_graph_document()
		assert app.document_status == 'grapher.document_open_failed'
		app.set_field(6, 'relative.vgraph')
		app.save_graph_document()
		assert app.document_status == 'grapher.document_invalid_path'
		begin_frame_elements()
		free_tree(app.build(ui2.rect(0, 0, 840, 636))!)
		assert C.unlink(&char(path.str)) == 0
		app.close_app()
		app.close_app()
	}
	assert C.vinix_heap_end() == 0
}

fn test_grapher_repeated_png_render_failed_stream_and_stale_model_release_owned_memory() {
	long_expression := 'x+'.repeat(120) + 'x'
	defer { unsafe { long_expression.free() } }
	mut app := GrapherApp{}
	app.initialize()
	app.write_graph_png(-1)
	C.vinix_heap_begin()
	for _ in 0 .. 40 {
		for expression in ['x', 'sqrt(x)', '1/(x-.123)', 'sqrt(-1)']! {
			app.set_field(0, expression)
			assert app.plot()
			assert !app.write_graph_png(-1)
		}
		app.set_field(0, long_expression)
		assert app.plot()
		assert !app.write_graph_png(-1)
		app.set_field(0, 'sin(')
		assert !app.write_graph_png(-1)
	}
	app.close_app()
	assert C.vinix_heap_end() == 0
}

fn test_grapher_repeated_png_exports_and_path_failures_release_owned_memory() {
	temporary := os.join_path(os.temp_dir(), 'vinix-grapher-png-memory-${os.getpid()}')
	os.mkdir_all(temporary)!
	root := os.real_path(temporary)
	path := disk_utility_join_path(root, 'graph-Ж.png')
	link := disk_utility_join_path(root, 'link.png')
	parent := disk_utility_join_path(root, 'parent')
	through := disk_utility_join_path(parent, 'graph.png')
	os.symlink(path, link)!
	os.symlink(root, parent)!
	defer {
		os.rmdir_all(root) or {}
		unsafe { temporary.free() root.free() path.free() link.free() parent.free() through.free() }
	}
	mut app := GrapherApp{}
	app.initialize()
	app.close_app()
	C.vinix_heap_begin()
	for _ in 0 .. 30 {
		app.initialize()
		app.set_field(7, path)
		app.handle('grapher.expression')!
		app.paste_input('sqrt(x)')
		app.handle('grapher.export_png')!
		assert app.export_status == 'grapher.png_saved'
		app.handle('grapher.png_path')!
		app.key_input('\r')
		assert app.export_status == 'grapher.png_exists'
		app.set_field(7, link)
		app.export_png()
		assert app.export_status == 'grapher.png_exists'
		app.set_field(7, through)
		app.export_png()
		assert app.export_status == 'grapher.png_failed'
		app.set_field(7, 'relative.png')
		app.export_png()
		assert app.export_status == 'grapher.png_invalid'
		begin_frame_elements()
		free_tree(app.build(ui2.rect(0, 0, 840, 636))!)
		assert C.unlink(&char(path.str)) == 0
		app.close_app()
		app.close_app()
	}
	assert C.vinix_heap_end() == 0
}

fn test_grapher_complete_compact_paging_keyboard_resize_and_languages_release_all_owned_memory() {
	previous := desktop_language
	defer { set_desktop_language(previous) }
	mut app := GrapherApp{}
	app.initialize()
	for size in [ui2.rect(0, 0, 840, 626), ui2.rect(0, 0, 280, 320), ui2.rect(0, 0, 180, 96)]! {
		for page in ['grapher.page.graph', 'grapher.page.document', 'grapher.page.csv', 'grapher.page.png']! {
			app.handle(page)!
			begin_frame_elements()
			free_tree(app.build(size)!)
		}
	}
	app.close_app()
	C.vinix_heap_begin()
	for _ in 0 .. 30 {
		app.initialize()
		for language in desktop_languages {
			set_desktop_language(language)
			for size in [ui2.rect(0, 0, 840, 626), ui2.rect(0, 0, 599, 452),
				ui2.rect(0, 0, 600, 451), ui2.rect(0, 0, 280, 320), ui2.rect(0, 0, 180, 96),
				ui2.rect(0, 0, 32, 32), ui2.rect(0, 0, 0, 0)]! {
				for page in ['grapher.page.graph', 'grapher.page.document', 'grapher.page.csv', 'grapher.page.png']! {
					app.handle(page)!
					begin_frame_elements()
					free_tree(app.build(size)!)
				}
			}
			begin_frame_elements()
			free_tree(app.build(ui2.rect(0, 0, 280, 320))!)
			app.key_input('\x0c')
			for _ in 0 .. 8 {
				app.key_input('\t')
				begin_frame_elements()
				free_tree(app.build(ui2.rect(0, 0, 280, 320))!)
				assert app.compact_page == grapher_page_for_field(app.focus)
			}
		}
		app.close_app()
		app.close_app()
		assert app.compact_page == .graph && !app.compact_layout && !app.tiny_layout
	}
	assert C.vinix_heap_end() == 0
}
