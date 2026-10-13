// SPDX-License-Identifier: GPL-2.0-or-later
module pkglaunch

import authclient
import authproto
import crypto.rand
import os
import tools.packages.pkgadmin

fn free_reply(mut reply authproto.Frame) {
	reply.wipe()
	unsafe { for field in reply.fields { field.free() }; (&array(&reply.fields)).free() }
}

pub fn run(arguments []string) !int {
	validate_arguments(arguments)!
	uid := u32(os.geteuid())
	if uid == 0 { return error('isolated launch transport requires an ordinary caller') }
	mut description := authclient.ask_root(authclient.default_socket, authproto.op_describe, action.bytes())!
	defer { free_reply(mut description) }
	if description.code != authproto.status_ok || description.fields.len != 3 || description.text(1) != '1' || description.text(2) != '0' {
		return error('the isolated package launch action is unavailable; ask the administrator to stage the account tools')
	}
	directory := pkgadmin.runtime_directory(uid)!
	defer { unsafe { directory.free() } }
	random := rand.bytes(16)!
	nonce := random.hex()
	defer { unsafe { random.free(); nonce.free() } }
	request := Request{ nonce: nonce, arguments: arguments }
	mut listener := pkgadmin.listen_private(directory, uid, nonce)!
	defer { listener.close() }
	mut reply := authclient.ask_root(authclient.default_socket, authproto.op_run, action.bytes(), []u8{}, nonce.bytes())!
	defer { free_reply(mut reply) }
	if reply.code != authproto.status_ok || reply.fields.len != 2 || reply.text(0) != '0' {
		return error('the account service refused the isolated application launch')
	}
	approved := reply.text(1)
	defer { unsafe { approved.free() } }
	if approved != nonce + '\n' { return error('the account service returned another launch invitation') }
	fd := listener.accept_root()!
	defer { C.close(fd) }
	send_request(fd, request)!
	send_streams(fd, [i32(0), 1, 2]!)!
	return receive_result(fd, request)
}
