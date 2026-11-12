// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

import os

fn test_stage_leaf_names_survive_closed_stream_and_another_enumeration() {
	root := os.join_path(os.temp_dir(), 'vinix-stage-leaf-names-${os.getpid()}')
	os.mkdir_all(root + '/first')!
	os.mkdir_all(root + '/second')!
	defer { os.rmdir_all(root) or {} }
	for name in ['alpha00', 'alpha01', 'alpha02'] {
		os.write_file(root + '/first/' + name, 'first')!
	}
	for name in ['bravo00', 'bravo01', 'bravo02'] {
		os.write_file(root + '/second/' + name, 'second')!
	}
	first := C.open((root + '/first').str, C.O_RDONLY | C.O_DIRECTORY | C.O_CLOEXEC)
	second := C.open((root + '/second').str, C.O_RDONLY | C.O_DIRECTORY | C.O_CLOEXEC)
	assert first >= 0 && second >= 0
	defer { C.close(first); C.close(second) }
	names := stage_leaf_names(first)!
	defer { unsafe { for name in names { name.free() }; (&array(&names)).free() } }
	others := stage_leaf_names(second)!
	defer { unsafe { for name in others { name.free() }; (&array(&others)).free() } }
	assert names.len == 3 && others.len == 3
	assert 'alpha00' in names && 'alpha01' in names && 'alpha02' in names
	assert 'bravo00' in others && 'bravo01' in others && 'bravo02' in others
	remove_retirement_leaves(first, '')!
	assert os.ls(root + '/first')!.len == 0
	assert os.ls(root + '/second')!.len == 3
}
