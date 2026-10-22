// SPDX-License-Identifier: GPL-2.0-or-later
module sessioncore

import authproto
import os
import tools.packages.pkgadmin

fn test_both_login_paths_refuse_ordinary_authentication_service_before_sending_password() {
	if os.geteuid() == 0 { return }
	directory := os.temp_dir() + '/vinix-session-root-peer-' + os.getpid().str()
	os.mkdir(directory, mode: 0o700)!
	defer { os.rmdir_all(directory) or {} }
	mut listener := pkgadmin.listen_private(directory, u32(os.geteuid()), 'a'.repeat(32))!
	defer { listener.close() }
	// Exercise the actual manager request handler, including its borrowed
	// password. A forged status_ok from this peer can never reach account lookup.
	mut manager := Manager{ config: ManagerConfig{ socket: listener.path } }
	mut request := authproto.text_frame(op_login, 'somebody', 'manager secret')
	defer { request.close() }
	mut answer, user := manager.check_login(mut request)
	defer { answer.close() }
	assert answer.code == authproto.status_failed
	assert user == none
	assert request.fields[1].all(it == 0)
	check_no_login_bytes(listener.fd)
	// The console calls the same guarded entry point.
	password := 'console secret'.bytes()
	defer { unsafe { password.free() } }
	mut refused := false
	verify_login(listener.path, 'somebody', password) or {
		refused = err.msg().contains('not root')
	}
	assert refused && password.all(it == 0)
	check_no_login_bytes(listener.fd)
}

fn check_no_login_bytes(listener int) {
	fd := C.accept(listener, unsafe { nil }, unsafe { nil })
	assert fd >= 0
	defer { C.close(fd) }
	mut byte := u8(0)
	assert C.read(fd, &byte, 1) == 0
}
