// SPDX-License-Identifier: GPL-2.0-or-later
module authclient

import authproto
import os
import tools.packages.pkgadmin

fn test_root_guard_sends_no_secret_to_an_ordinary_listener() {
	if os.geteuid() == 0 { return }
	directory := os.temp_dir() + '/vinix-auth-root-peer-' + os.getpid().str()
	os.mkdir(directory, mode: 0o700)!
	defer { os.rmdir_all(directory) or {} }
	mut listener := pkgadmin.listen_private(directory, u32(os.geteuid()), 'a'.repeat(32))!
	defer { listener.close() }
	secret := 'must not reach the socket'.bytes()
	mut refused := false
	ask_root(listener.path, authproto.op_verify, secret) or { refused = err.msg().contains('not root'); unsafe { err.free() } }
	assert refused && secret.all(it == 0)
	fd := C.accept(listener.fd, unsafe { nil }, unsafe { nil })
	assert fd >= 0
	defer { C.close(fd) }
	mut byte := u8(0)
	assert C.read(fd, &byte, 1) == 0
	unsafe { secret.free() }
}
