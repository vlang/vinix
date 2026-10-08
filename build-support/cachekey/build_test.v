// SPDX-License-Identifier: GPL-2.0-or-later
module cachekey

import crypto.sha256
import os

#include <stdlib.h>

fn C.mkdtemp(&u8) &char

fn build_temporary() !string {
	mut pattern := (os.temp_dir().trim_right('/') + '/vinix-build-key-XXXXXX\x00').bytes()
	if isnil(C.mkdtemp(pattern.data)) { return file_error(pattern.bytestr()) }
	return pattern[..pattern.len - 1].bytestr()
}

fn test_build_key_follows_targets_and_stops_directory_cycles() {
	work := build_temporary()!
	defer { os.rmdir_all(work) or { panic(err) } }
	os.mkdir(work + '/source')!
	os.write_file(work + '/payload', 'before')!
	os.symlink('../payload', work + '/source/link')!
	os.symlink('.', work + '/source/cycle')!
	inputs := [BuildInput{work + '/source', 'source', false, ''}]
	first := build_tree_key('fixture-v1', []string{}, inputs)!
	os.write_file(work + '/payload', 'after!')!
	assert first != build_tree_key('fixture-v1', []string{}, inputs)!
}

fn test_ignored_artifacts_do_not_change_recursive_vlib_metadata() {
	work := build_temporary()!
	defer { os.rmdir_all(work) or { panic(err) } }
	os.mkdir(work + '/vlib')!
	os.mkdir(work + '/vlib/v')!
	os.write_file(work + '/vlib/library.v', 'module library')!
	inputs := [BuildInput{work + '/vlib', 'vlib', true, 'vlib'}]
	first := build_tree_key('fixture-v1', []string{}, inputs)!
	os.write_file(work + '/vlib/generated.bin', 'artifact')!
	os.write_file(work + '/vlib/v/compiler.v', 'compiler source')!
	assert first == build_tree_key('fixture-v1', []string{}, inputs)!
	os.chmod(work + '/vlib/library.v', 0o600)!
	assert first != build_tree_key('fixture-v1', []string{}, inputs)!
}

fn test_office_transitive_modules_keep_cycles_and_ignore_tests() {
	work := build_temporary()!
	defer { os.rmdir_all(work) or { panic(err) } }
	for name in ['cmd/excel', 'one', 'two', 'ignored'] { os.mkdir_all(work + '/' + name)! }
	os.write_file(work + '/cmd/excel/main.v', 'import office.one\nimport office.two')!
	os.write_file(work + '/one/lib.v', 'import office.two')!
	os.write_file(work + '/two/lib.v', 'import office.one')!
	os.write_file(work + '/two/lib_test.v', 'import office.ignored')!
	assert office_modules(work, 'calc')! == ['one', 'two']
	first := office_key(work, 'shared', 'calc')!
	os.write_file(work + '/ignored/lib.v', 'changed ignored module')!
	assert first == office_key(work, 'shared', 'calc')!
	os.write_file(work + '/one/lib.v', 'import office.two\nchanged included module')!
	assert first != office_key(work, 'shared', 'calc')!
}

fn test_subdir_and_import_parsers_keep_unicode_word_boundaries() {
	assert subdirs_text('αsubdirs: [\'skip\']\n·subdirs: [\'one\',"two"]') == ['one', 'two']
	assert office_imports('αoffice.skip ·office.one office._two office.3skip') == [
		'one',
		'_two',
	]
}

fn test_unicode13_word_and_space_properties_match_every_valid_scalar() {
	mut words := sha256.new()
	mut spaces := sha256.new()
	for point in 0 .. 0x110000 {
		if point >= 0xd800 && point <= 0xdfff { continue }
		word := [u8(if source_word(rune(point)) { 1 } else { 0 })]!
		space := [u8(if regex_space(rune(point)) { 1 } else { 0 })]!
		words.write(word[..])!
		spaces.write(space[..])!
	}
	// Independent original CPython3.9/Unicode13 property stream digests.
	assert words.sum([]u8{}).hex() == '4cbed24417d31e964dbcf865865dbc1071d2422756527429e71dc0fdb31b8f8b'
	assert spaces.sum([]u8{}).hex() == '88c564e99693061ab01f87b51191b3e33e015b2b616c57dd6194a24cc94e4132'
}

fn test_staging_completion_preserves_required_and_alternative_executables() {
	work := build_temporary()!
	defer { os.rmdir_all(work) or { panic(err) } }
	os.write_file(work + '/present', 'data')!
	os.write_file(work + '/program', 'program')!
	os.chmod(work + '/program', 0o755)!
	assert staging_complete(work, ['present'], ['program'], ['missing', 'program'])!
	assert !staging_complete(work, ['missing'], ['program'], []string{})!
	assert !staging_complete(work, ['present'], ['present'], []string{})!
}

fn test_source_decode_and_directory_failures_close_every_reader() {
	work := build_temporary()!
	defer { os.rmdir_all(work) or { panic(err) } }
	path := work + '/bad.v'
	os.write_file(path, [u8(0xff)].bytestr())!
	mut before := os.ls('/dev/fd')!
	before.sort()
	for _ in 0 .. 200 {
		if _ := source_text(path) { assert false } else { assert err is TextDecodeError }
		if _ := source_text(work) { assert false } else { assert err is FileError }
	}
	mut after := os.ls('/dev/fd')!
	after.sort()
	assert before == after
}
