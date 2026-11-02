// SPDX-License-Identifier: GPL-2.0-or-later
module linuxcheck

import os

fn test_cxx_static_sanitizer_selection_copy_and_mutation() {
	root := os.join_path(os.temp_dir(), 'vinix-cxx-sanitizer-${os.getpid()}')
	os.mkdir_all(root + '/capture/payload') or { panic(err) }
	defer { os.rmdir_all(root) or {} }
	archive := root + '/selected.a'
	os.write_file(archive, '!<arch>\nsynthetic selection payload\n') or { panic(err) }
	sanitizer := cxx_sanitizer_at(archive) or { panic(err) }
	cxx_sanitizer_copy(sanitizer, root + '/capture') or { panic(err) }
	assert os.read_bytes(root + '/capture/payload/cxx-sanitizer/libubsan.a') or { panic(err) } ==
		os.read_bytes(archive) or { panic(err) }
	assert cxx_sanitizer_link_flags(sanitizer, root + '/capture') ==
		['-static-libubsan', '-L' + root + '/capture/payload/cxx-sanitizer']
	assert cxx_sanitizer_link_flags(CxxSanitizer{}, root).len == 0
	os.write_file(root + '/capture/payload/cxx-sanitizer/libubsan.a', '!<arch>\nchanged copy\n') or { panic(err) }
	mut copy_refused := false
	cxx_sanitizer_copy_unchanged(sanitizer, root + '/capture') or { copy_refused = err.msg().contains('differs from') }
	assert copy_refused
	os.write_file(archive, '!<arch>\nmodified runtime\n') or { panic(err) }
	mut refused := false
	cxx_sanitizer_unchanged(sanitizer) or { refused = err.msg().contains('changed during') }
	assert refused
}

fn test_cxx_static_sanitizer_refuses_missing_empty_and_nonarchive_inputs() {
	root := os.join_path(os.temp_dir(), 'vinix-cxx-sanitizer-reject-${os.getpid()}')
	os.mkdir_all(root) or { panic(err) }
	defer { os.rmdir_all(root) or {} }
	for value in ['', root, root + '/missing'] {
		mut refused := false
		cxx_sanitizer_at(value) or { refused = true }
		assert refused
	}
	for text in ['!<arch>\n', 'not an archive\n'] {
		os.write_file(root + '/invalid.a', text) or { panic(err) }
		mut refused := false
		cxx_sanitizer_at(root + '/invalid.a') or { refused = true }
		assert refused
	}
}
