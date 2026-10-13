// SPDX-License-Identifier: GPL-2.0-or-later
module pkgadmin

import os

fn test_private_socket_admits_only_its_account_and_never_removes_existing_names() {
	directory := os.temp_dir() + '/vinix-package-admin-socket-' + os.getpid().str()
	os.mkdir(directory, mode: 0o700)!
	defer { os.rmdir_all(directory) or {} }
	uid := u32(os.geteuid())
	nonce := 'a'.repeat(32)
	mut listener := listen_private(directory, uid, nonce)!
	defer { listener.close() }
	assert os.lstat(listener.path)!.get_filetype() == .socket
	fd := connect_private(directory, uid, nonce)!
	C.close(fd)
	mut existing := false
	listen_private(directory, uid, nonce) or { existing = true; unsafe { err.free() } }
	assert existing && os.exists(listener.path)
	os.chmod(directory, 0o755)!
	mut unsafe_directory := false
	connect_private(directory, uid, nonce) or { unsafe_directory = true; unsafe { err.free() } }
	assert unsafe_directory
	os.chmod(directory, 0o700)!
	alias := directory + '-link'
	os.symlink(directory, alias)!
	defer { os.rm(alias) or {} }
	mut linked := false
	listen_private(alias, uid, nonce) or { linked = true; unsafe { err.free() } }
	assert linked
}
