// SPDX-License-Identifier: GPL-2.0-or-later
module wineproc

import os

fn test_command_line_requires_readable_surviving_entry() {
	root := os.join_path(os.temp_dir(), 'vinix-wineproc-' + os.getpid().str())
	os.mkdir(root)!
	defer { os.rmdir_all(root) or {} }
	assert command_line(root + '/gone')! == ''
	if _ := command_line(root) {
		assert false, 'missing cmdline in a surviving entry was accepted'
	} else {
		assert err.msg().contains('cannot inspect surviving process command line:')
	}
	os.write_file(root + '/cmdline', '')!
	assert command_line(root)! == ''
	line := '/runtime/wine\x00program.exe\x00'
	os.write_file(root + '/cmdline', line)!
	assert command_line(root)! == line
}
