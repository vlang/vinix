// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os
import ui2

fn dictionary_fixture_u32(mut bytes []u8, value u32) {
	for shift in [0, 8, 16, 24]! { bytes << u8(value >> shift) }
}

fn dictionary_fixture_pack(words []string, definitions []string) []u8 {
	mut bytes := []u8{cap: 4096}
	unsafe { bytes.flags |= .noslices }
	editor_append(mut bytes, 'VNXDICT1')
	mut key_size := 0
	mut definition_size := 0
	for word in words { key_size += word.len }
	for definition in definitions { definition_size += definition.len }
	dictionary_fixture_u32(mut bytes, u32(words.len))
	dictionary_fixture_u32(mut bytes, u32(key_size))
	dictionary_fixture_u32(mut bytes, u32(definition_size))
	dictionary_fixture_u32(mut bytes, 0)
	mut key_offset := 0
	mut definition_offset := 0
	for index, word in words {
		dictionary_fixture_u32(mut bytes, u32(key_offset))
		dictionary_fixture_u32(mut bytes, u32(word.len))
		dictionary_fixture_u32(mut bytes, u32(definition_offset))
		dictionary_fixture_u32(mut bytes, u32(definitions[index].len))
		key_offset += word.len
		definition_offset += definitions[index].len
	}
	for word in words { editor_append(mut bytes, word) }
	for definition in definitions { editor_append(mut bytes, definition) }
	return bytes
}

fn dictionary_fixture_path(name string) string {
	base := reminders_canonical_home(os.temp_dir())
	defer { unsafe { base.free() } }
	return os.join_path(base, 'vinix-dictionary-${name}-${os.getpid()}.vnd')
}

fn test_dictionary_exact_prefix_case_space_history_and_export() {
	path := dictionary_fixture_path('lookup')
	export_path := dictionary_fixture_path('export')
	defer { os.rm(path) or {}; os.rm(export_path) or {}; unsafe { path.free(); export_path.free() } }
	bytes := dictionary_fixture_pack(['café', 'computer', 'computing', 'data structure'],
		['a café\nSecond line.', 'an electronic machine', 'the act of computing', 'an organized collection'])
	defer { unsafe { bytes.free() } }
	os.write_file(path, editor_bytes_text(bytes))!
	mut app := new_dictionary_app(path, export_path)
	defer { app.close_app() }
	assert app.source.count == 4
	assert app.selected == 1
	assert app.definition == 'an electronic machine'
	app.handle('dictionary.query')!
	app.key_input('\x01  DATA_structure  \n')
	assert editor_bytes_text(app.key) == 'data structure'
	assert app.selected == 3
	app.visit(-1)
	assert app.selected == 1
	app.visit(1)
	assert app.selected == 3
	app.key_input('\x01caf')
	app.key_input('\xc3')
	app.key_input('\xa9\n')
	assert app.selected == 0
	assert app.definition.starts_with('a café')
	app.export_definition()
	assert app.status == 'dictionary.exported'
	data := os.read_file(export_path)!
	defer { unsafe { data.free() } }
	assert data == 'café\n\na café\nSecond line.'
	app.export_definition()
	assert app.status == 'dictionary.export_exists'
	app.key_input('\x01absent\n')
	assert app.status == 'dictionary.no_match'
	assert app.definition.starts_with('a café')
}

fn test_dictionary_rejects_malformed_indexes_without_replacing_loaded_source() {
	path := dictionary_fixture_path('validation')
	bad_path := dictionary_fixture_path('bad')
	defer { os.rm(path) or {}; os.rm(bad_path) or {}; unsafe { path.free(); bad_path.free() } }
	bytes := dictionary_fixture_pack(['computer'], ['valid definition'])
	defer { unsafe { bytes.free() } }
	os.write_file(path, editor_bytes_text(bytes))!
	mut app := new_dictionary_app(path, '')
	defer { app.close_app() }
	mut bad := bytes.clone()
	defer { unsafe { bad.free() } }
	for offset in [0, 8, 12, 16, 20, 24, 28, 32, 36]! {
		original := bad[offset]
		bad[offset] = 0xff
		os.write_file(bad_path, editor_bytes_text(bad))!
		app.path.clear(); editor_append(mut app.path, bad_path)
		assert !app.load_source()
		assert app.source.count == 1
		assert app.definition == 'valid definition'
		bad[offset] = original
	}
	unordered := dictionary_fixture_pack(['zebra', 'alpha'], ['last', 'first'])
	defer { unsafe { unordered.free() } }
	os.write_file(bad_path, editor_bytes_text(unordered))!
	assert !app.load_source()
	assert dictionary_read_source('relative.vnd') == none
	assert dictionary_read_source('/dev/null') == none
}

fn test_dictionary_rejects_source_links_and_changed_or_invalid_definition_data() {
	path := dictionary_fixture_path('changed')
	link := dictionary_fixture_path('link')
	defer { os.rm(link) or {}; os.rm(path) or {}; unsafe { path.free(); link.free() } }
	bytes := dictionary_fixture_pack(['computer'], ['valid definition'])
	defer { unsafe { bytes.free() } }
	os.write_file(path, editor_bytes_text(bytes))!
	os.symlink(path, link)!
	assert dictionary_read_source(link) == none
	mut source := dictionary_read_source(path) or { panic('fixture did not load') }
	defer { source.close() }
	os.write_file(path, 'truncated')!
	assert source.read_definition(0) == none
	invalid := dictionary_fixture_pack(['computer'], ['bad\xffdefinition'])
	defer { unsafe { invalid.free() } }
	os.write_file(path, editor_bytes_text(invalid))!
	mut corrupt := dictionary_read_source(path) or { panic('fixture index did not load') }
	defer { corrupt.close() }
	assert corrupt.read_definition(0) == none
	assert !dictionary_valid_text('word\x00', true)
	assert !dictionary_valid_text('\xc0\x80', true)
	assert !dictionary_valid_text('\xc2\x85', false)
}

fn test_dictionary_prefix_pages_fragmented_navigation_and_word_wrapping() {
	path := dictionary_fixture_path('pages')
	defer { os.rm(path) or {}; unsafe { path.free() } }
	mut words := []string{cap: 40}
	mut definitions := []string{cap: 40}
	for index in 0 .. 40 { words << 'prefix${index:02}'; definitions << 'one two three four 日本語 😀\nnext' }
	defer { unsafe { words.free(); definitions.free() } }
	bytes := dictionary_fixture_pack(words, definitions)
	defer { unsafe { bytes.free() } }
	os.write_file(path, editor_bytes_text(bytes))!
	mut app := new_dictionary_app(path, '')
	defer { app.close_app() }
	app.handle('dictionary.query')!
	app.key_input('\x01prefix\n')
	assert app.selected == 0
	app.key_input('\x1b['); app.key_input('6~')
	assert app.page == 16
	app.handle('dictionary.result.15')!
	assert app.selected == 31
	app.key_input('\x1b[6~')
	assert app.match_count == 8
	app.lookup(true)
	assert app.selected == 32
	app.key_input('\x1b['); app.key_input('B')
	assert app.selected == 33
	assert editor_bytes_text(app.query) == 'prefix'
	app.key_input('\x1b[5~')
	assert app.page == 16
	app.wrap(8)
	assert app.lines.len >= 5
	for line in app.lines {
		text := console_borrow(app.definition, line.start, line.end)
		assert dictionary_valid_text(text, false) || text.len == 0
		mut at := 0
		mut count := 0
		for at < text.len { at += editor_utf8_length(text[at]); count++ }
		assert count <= 8
	}
	begin_frame_elements()
	tree := app.build(ui2.rect(0, 0, 860, 666))!
	free_tree(tree)
	assert app.list_rows == 16
	begin_frame_elements()
	small := app.build(ui2.rect(0, 0, 700, 450))!
	free_tree(small)
	assert app.list_rows == 7
	assert app.page == 0
}

fn test_dictionary_complete_prepared_wordnet_contains_real_definitions() {
	path := os.getenv('VINIX_DICTIONARY_TEST_DATA')
	defer { unsafe { path.free() } }
	if path.len == 0 { return }
	mut app := new_dictionary_app(path, '')
	defer { app.close_app() }
	assert app.source.count == 147306
	for word in ['aardvark', 'computer', 'dictionary', 'run', 'zymurgy']! {
		app.query.clear(); editor_append(mut app.query, word); app.refilter()
		assert app.lookup(true)
		assert app.source.word(app.selected) == word
		assert app.definition.len > 20
		assert app.definition.contains('Related:')
	}
}
