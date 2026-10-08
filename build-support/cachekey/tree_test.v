// SPDX-License-Identifier: GPL-2.0-or-later
module cachekey

import os

#include <utime.h>
#include <stdlib.h>

fn C.mkdtemp(&u8) &char

struct C.utimbuf {
mut:
	actime  i64
	modtime i64
}

fn C.utime(&char, &C.utimbuf) i32

fn temporary_tree(label string) string {
	mut pattern := (os.temp_dir().trim_right('/') + '/vinix-cache-' + label + '-XXXXXX\x00').bytes()
	if isnil(C.mkdtemp(pattern.data)) { panic(file_error(pattern.bytestr())) }
	return pattern[..pattern.len - 1].bytestr()
}

fn test_ignores_mtime_but_tracks_content_and_mode() {
	work := temporary_tree('content')
	defer { os.rmdir_all(work) or { panic(err) } }
	root := work + '/tree'
	os.mkdir(root)!
	file := root + '/app'
	os.write_file(file, 'one\n')!
	os.chmod(file, 0o644)!
	first := content_key([root], false)!
	mut stamp := C.utimbuf{1000000000, 1000000000}
	assert C.utime(&char(file.str), &stamp) == 0
	assert first == content_key([root], false)!
	os.write_file(file, 'two\n')!
	second := content_key([root], false)!
	assert first != second
	os.chmod(file, 0o755)!
	assert second != content_key([root], false)!
}

fn test_metadata_mode_tracks_in_place_tree_changes() {
	work := temporary_tree('metadata')
	defer { os.rmdir_all(work) or { panic(err) } }
	root := work + '/tree'
	nested := root + '/usr/lib'
	os.mkdir_all(nested)!
	file := nested + '/libexample.so'
	os.write_file(file, 'same-sized-a\n')!
	first := content_key([root], true)!
	mut stamp := C.utimbuf{1000000000, 1000000000}
	assert C.utime(&char(file.str), &stamp) == 0
	assert first != content_key([root], true)!
}

fn test_tracks_symlink_targets_and_missing_paths() {
	work := temporary_tree('links')
	defer { os.rmdir_all(work) or { panic(err) } }
	root := work + '/tree'
	os.mkdir(root)!
	os.write_file(root + '/one', 'same\n')!
	os.write_file(root + '/two', 'same\n')!
	link := root + '/current'
	os.symlink('one', link)!
	missing := work + '/missing'
	first := content_key([root, missing], false)!
	os.rm(link)!
	os.symlink('two', link)!
	assert first != content_key([root, missing], false)!
}

fn test_root_location_is_not_part_of_the_content_key() {
	left := temporary_tree('left')
	right := temporary_tree('right')
	defer {
		os.rmdir_all(left) or { panic(err) }
		os.rmdir_all(right) or { panic(err) }
	}
	os.mkdir(left + '/tree')!
	os.mkdir(right + '/tree')!
	os.write_file(left + '/tree/value', 'identical\n')!
	os.write_file(right + '/tree/value', 'identical\n')!
	assert content_key([left + '/tree'], false)! == content_key([right + '/tree'], false)!
}

fn test_nanoseconds_keep_full_signed_width() {
	assert nanoseconds(i64(9223372036854775807), 999999999) == '9223372036854775807999999999'
	assert nanoseconds(i64(-9223372036854775807) - 1, 0) == '-9223372036854775808000000000'
	assert nanoseconds(-1, 999999999) == '-1'
}

fn test_literal_backslash_names_remain_unix_components() {
	work := temporary_tree('literal')
	path := work + '/literal\\name'
	defer {
		os.rm(path) or { panic(err) }
		os.rmdir(work) or { panic(err) }
	}
	os.write_file(path, 'first')!
	first := content_key([work], false)!
	os.write_file(path, 'other')!
	assert first != content_key([work], false)!
	assert join_path('/', 'name') == '/name'
	assert join_path('.', 'name') == 'name'
	assert join_path('literal\\base', '\\name') == 'literal\\base/\\name'
}
