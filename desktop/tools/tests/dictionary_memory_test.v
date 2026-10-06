// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os
import ui2

#include "@VMODROOT/heap_tracker.h"
fn C.vinix_heap_begin()
fn C.vinix_heap_end() u64

// Independent tiny VNXDICT1 record: one eight-byte key and three-byte gloss.
fn dictionary_memory_pack() []u8 {
	return [u8(`V`), `N`, `X`, `D`, `I`, `C`, `T`, `1`, 1, 0, 0, 0,
		8, 0, 0, 0, 3, 0, 0, 0, 0, 0, 0, 0,
		0, 0, 0, 0, 8, 0, 0, 0, 0, 0, 0, 0, 3, 0, 0, 0,
		`c`, `o`, `m`, `p`, `u`, `t`, `e`, `r`, `o`, `n`, `e`]
}

fn test_dictionary_copy_complete_entry_ack_and_queued_close_release_owned_bytes() {
	saved_features := app_compositor_features
	app_compositor_features = app_features
	defer { app_compositor_features = saved_features }
	base := reminders_canonical_home(os.temp_dir())
	defer { unsafe { base.free() } }
	path := os.join_path(base, 'vinix-dictionary-copy-cycle-${os.getpid()}.vnd')
	defer { os.rm(path) or {}; unsafe { path.free() } }
	bytes := dictionary_memory_pack()
	defer { unsafe { bytes.free() } }
	os.write_file(path, editor_bytes_text(bytes))!
	mut warm := new_dictionary_app(path, '')
	for size in [ui2.rect(0, 0, 860, 666), ui2.rect(0, 0, 640, 420)]! {
		begin_frame_elements()
		free_tree(warm.build(size)!)
	}
	warm.close_app()
	C.vinix_heap_begin()
	for _ in 0 .. 100 {
		mut app := new_dictionary_app(path, '')
		mut native := NativeApp(unsafe { &app })
		app.handle('dictionary.copy')!
		packet := native_app_text_copy_request(mut native)
		assert packet.len == text_copy_header_size + 'computer\n\none'.len
		ack := text_copy_reply(app.copy_client.sequence, true)
		native_app_receive_text_copy(mut native, editor_bytes_text(ack))
		assert app.copy_client.status == .copied
		unsafe { packet.free(); ack.free() }
		for size in [ui2.rect(0, 0, 860, 666), ui2.rect(0, 0, 640, 420)]! {
			begin_frame_elements()
			free_tree(app.build(size)!)
		}
		app.key_input('\x03')
		app.close_app()
		app.close_app()
	}
	assert C.vinix_heap_end() == 0
}

fn test_dictionary_owned_source_reload_history_export_and_frames_keep_heap_flat() {
	base := reminders_canonical_home(os.temp_dir())
	defer { unsafe { base.free() } }
	home := os.join_path(base, 'vinix-dictionary-heap-${os.getpid()}')
	os.mkdir(home)!
	defer { os.rmdir_all(home) or {}; unsafe { home.free() } }
	path := join_path(home, 'dictionary.vnd')
	export_path := join_path(home, 'definition.txt')
	defer { unsafe { path.free(); export_path.free() } }
	bytes := dictionary_memory_pack()
	defer { unsafe { bytes.free() } }
	os.write_file(path, editor_bytes_text(bytes))!
	mut app := new_dictionary_app(path, export_path)
	begin_frame_elements()
	warm := app.build(ui2.rect(0, 0, 860, 666))!
	free_tree(warm)
	C.vinix_heap_begin()
	for _ in 0 .. 100 {
		assert app.load_source()
		app.handle('dictionary.query')!
		app.key_input('\x01 COMPUTER \n')
		assert app.definition == 'one'
		app.visit(-1); app.visit(1)
		app.export_definition()
		assert app.status == 'dictionary.exported'
		assert desktop_unlink(export_path) == 0
		app.path.clear(); editor_append(mut app.path, '/dev/null')
		assert !app.load_source()
		app.path.clear(); editor_append(mut app.path, path)
		begin_frame_elements()
		tree := app.build(ui2.rect(0, 0, 860, 666))!
		free_tree(tree)
	}
	app.close_app()
	app.close_app()
	assert C.vinix_heap_end() == 0
}

fn test_dictionary_complete_init_resize_close_and_invalid_source_release_every_owner() {
	base := reminders_canonical_home(os.temp_dir())
	defer { unsafe { base.free() } }
	path := os.join_path(base, 'vinix-dictionary-cycle-${os.getpid()}.vnd')
	defer { os.rm(path) or {}; unsafe { path.free() } }
	bytes := dictionary_memory_pack()
	defer { unsafe { bytes.free() } }
	os.write_file(path, editor_bytes_text(bytes))!
	mut warm := new_dictionary_app(path, '')
	begin_frame_elements()
	tree := warm.build(ui2.rect(0, 0, 1100, 800))!
	free_tree(tree)
	warm.close_app()
	C.vinix_heap_begin()
	for _ in 0 .. 80 {
		mut app := new_dictionary_app(path, '')
		for bounds in [ui2.rect(0, 0, 860, 666), ui2.rect(0, 0, 700, 450), ui2.rect(0, 0, 1100, 800)]! {
			begin_frame_elements()
			next := app.build(bounds)!
			free_tree(next)
		}
		app.close_app()
		mut invalid := new_dictionary_app('/dev/null', '')
		assert invalid.source.fd == -1
		invalid.close_app()
	}
	assert C.vinix_heap_end() == 0
}

fn test_dictionary_malformed_header_and_index_cleanup_keeps_heap_flat() {
	base := reminders_canonical_home(os.temp_dir())
	defer { unsafe { base.free() } }
	path := os.join_path(base, 'vinix-dictionary-invalid-${os.getpid()}.vnd')
	defer { os.rm(path) or {}; unsafe { path.free() } }
	mut bytes := dictionary_memory_pack()
	defer { unsafe { bytes.free() } }
	C.vinix_heap_begin()
	for _ in 0 .. 80 {
		for offset in [0, 8, 12, 16, 20, 24, 28, 32, 36]! {
			original := bytes[offset]; bytes[offset] = 0xff
			terminated := path.clone()
			fd := C.open(&char(terminated.str), C.O_CREAT | C.O_TRUNC | C.O_WRONLY | C.O_CLOEXEC, 0o600)
			unsafe { terminated.free() }
			assert fd >= 0
			assert desktop_write_all(fd, bytes.data, u64(bytes.len))
			assert desktop_close(fd) == 0
			assert dictionary_read_source(path) == none
			bytes[offset] = original
		}
	}
	assert C.vinix_heap_end() == 0
}

fn dictionary_history_fixture_u32(mut bytes []u8, value u32) {
	for shift in [0, 8, 16, 24]! { bytes << u8(value >> shift) }
}

fn dictionary_history_fixture_pack(words []string, definitions []string) []u8 {
	mut bytes := []u8{cap: 4096}
	unsafe { bytes.flags |= .noslices }
	editor_append(mut bytes, 'VNXDICT1')
	mut key_size := 0
	mut definition_size := 0
	for word in words { key_size += word.len }
	for definition in definitions { definition_size += definition.len }
	dictionary_history_fixture_u32(mut bytes, u32(words.len))
	dictionary_history_fixture_u32(mut bytes, u32(key_size))
	dictionary_history_fixture_u32(mut bytes, u32(definition_size))
	dictionary_history_fixture_u32(mut bytes, 0)
	mut key_offset := 0
	mut definition_offset := 0
	for index, word in words {
		dictionary_history_fixture_u32(mut bytes, u32(key_offset))
		dictionary_history_fixture_u32(mut bytes, u32(word.len))
		dictionary_history_fixture_u32(mut bytes, u32(definition_offset))
		dictionary_history_fixture_u32(mut bytes, u32(definitions[index].len))
		key_offset += word.len
		definition_offset += definitions[index].len
	}
	for word in words { editor_append(mut bytes, word) }
	for definition in definitions { editor_append(mut bytes, definition) }
	return bytes
}

fn dictionary_history_fixture_path(name string) string {
	base := reminders_canonical_home(os.temp_dir())
	defer { unsafe { base.free() } }
	return os.join_path(base, 'vinix-dictionary-${name}-${os.getpid()}.vnd')
}


fn test_dictionary_history_eviction_branch_reload_and_close_keeps_heap_flat() {
    path := dictionary_history_fixture_path('review-history')
    defer { os.rm(path) or {}; unsafe { path.free() } }
    mut words := []string{cap: 40}
    mut definitions := []string{cap: 40}
    for index in 0 .. 40 { words << 'prefix${index:02}'; definitions << 'definition' }
    defer { unsafe { words.free(); definitions.free() } }
    bytes := dictionary_history_fixture_pack(words, definitions)
    defer { unsafe { bytes.free() } }
    os.write_file(path, editor_bytes_text(bytes))!
    C.vinix_heap_begin()
    for _ in 0 .. 100 {
        mut app := new_dictionary_app(path, '')
        for index in 0 .. 40 { assert app.show(index, true) }
        assert app.history.len == 32
        assert app.history[0] == 'prefix08'
        assert app.history_index == 31
        app.visit(-1); app.visit(-1); app.visit(-1)
        assert app.history_index == 28
        assert app.show(1, true)
        assert app.history.len == 30
        assert app.history.last() == 'prefix01'
        assert app.load_source()
        assert app.history.len == 1
        assert app.history[0] == 'prefix36'
        for index in 0 .. 40 { assert app.show(index, true) }
        app.close_app()
        app.close_app()
    }
    assert C.vinix_heap_end() == 0
}
