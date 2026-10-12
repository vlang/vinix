// SPDX-License-Identifier: GPL-2.0-or-later
module identitycore

import os

#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

fn C.mkstemp(&u8) i32

const os_release = 'NAME="Vinix"\nID=vinix\nVERSION_ID="0.1.0"\nPRETTY_NAME="Vinix 0.1.0"\n'
const lsb_release = 'DISTRIB_ID=Vinix\nDISTRIB_RELEASE=0.1.0\nDISTRIB_DESCRIPTION="Vinix 0.1.0"\n'
const issue = 'Welcome to Vinix\nKernel \\r on an \\m (\\l)\n\n'
const motd = 'Welcome to Vinix!\n\n'

fn install(target string, data string, mode int) ! {
	mut pattern := (os.dir(target) + '/.identity.XXXXXX\x00').bytes()
	fd := C.mkstemp(pattern.data)
	if fd < 0 { return os.error_posix() }
	C.close(fd)
	temporary := pattern.bytestr().all_before('\x00')
	defer { os.rm(temporary) or {} }
	os.write_file(temporary, data)!
	os.chmod(temporary, mode)!
	// Replace the leaf, including BusyBox links and Alpine's os-release link.
	// Never follow an absolute guest link into the host filesystem.
	if unsafe { C.rename(temporary.str, target.str) } != 0 { return os.error_posix() }
}

pub fn stage(path string, uname_source string) ! {
	if path == '' || !os.is_dir(path) { return error('staging must be an existing directory') }
	root := os.real_path(path)
	if root == '/' { return error('refusing to stage over the host root') }
	uname := os.read_file(uname_source)!
	for name in ['bin', 'usr', 'usr/bin', 'usr/lib', 'etc'] {
		directory := root + '/' + name
		if os.is_link(directory) { return error('staging directory is a symlink: ' + name) }
		os.mkdir_all(directory)!
	}
	install(root + '/bin/uname', uname, 0o755)!
	mut pattern := (root + '/usr/bin/.identity.XXXXXX\x00').bytes()
	fd := C.mkstemp(pattern.data)
	if fd < 0 { return os.error_posix() }
	C.close(fd)
	temporary := pattern.bytestr().all_before('\x00')
	defer { os.rm(temporary) or {} }
	os.rm(temporary)!
	os.symlink('../../bin/uname', temporary)!
	if unsafe { C.rename(temporary.str, (root + '/usr/bin/uname').str) } != 0 { return os.error_posix() }
	for name in ['etc/os-release', 'usr/lib/os-release'] { install(root + '/' + name, os_release, 0o644)! }
	install(root + '/etc/lsb-release', lsb_release, 0o644)!
	install(root + '/etc/issue', issue, 0o644)!
	install(root + '/etc/motd', motd, 0o644)!
}
