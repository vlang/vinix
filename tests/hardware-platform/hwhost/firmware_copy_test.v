// SPDX-License-Identifier: GPL-2.0-or-later
module hwhost

import os

fn firmware_need(ok bool, message string) { if !ok { panic(message) } }

fn test_firmware_copies_have_independent_identity_and_writes() {
	root := os.join_path(os.temp_dir(), 'vinix-firmware-copy-' + os.getpid().str())
	os.mkdir(root)!
	defer { os.rmdir_all(root) or {} }
	source := root + '/source.fd'; first := root + '/first.fd'; second := root + '/second.fd'
	os.write_file(source, 'initial variables')!
	copy_firmware_variables(source, first)!
	copy_firmware_variables(source, second)!
	firmware_need(os.read_file(first)! == 'initial variables' && os.read_file(second)! == 'initial variables', 'firmware copy bytes differ')
	original := os.stat(source)!; a := os.stat(first)!; b := os.stat(second)!
	firmware_need(original.inode != a.inode && original.inode != b.inode && a.inode != b.inode, 'firmware copies share file identity')
	os.write_file(first, 'guest boot order')!
	firmware_need(os.read_file(source)! == 'initial variables' && os.read_file(second)! == 'initial variables', 'guest write changed source/other boot')
	os.write_file(source, 'updated input')!
	firmware_need(os.read_file(first)! == 'guest boot order' && os.read_file(second)! == 'initial variables', 'source write changed a retained boot')
	mut rejected := false
	copy_firmware_variables(source, first) or { rejected = true; unsafe { err.free() } }
	firmware_need(rejected && os.read_file(first)! == 'guest boot order', 'existing variable store overwritten')
	os.symlink(source, root + '/link.fd')!
	rejected = false
	copy_firmware_variables(source, root + '/link.fd') or { rejected = true; unsafe { err.free() } }
	firmware_need(rejected && os.read_file(source)! == 'updated input', 'symlink target overwritten')
}
