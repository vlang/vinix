// SPDX-License-Identifier: GPL-2.0-or-later
module pkglaunch

import authclient
import authproto
import crypto.rand
import os
import tools.packages.pkgadmin

pub fn run(arguments []string) !int {
	return run_with_socket(arguments, authclient.default_socket)
}

fn run_with_socket(arguments []string, socket_path string) !int {
	validate_arguments(arguments)!
	uid := u32(os.geteuid())
	if uid == 0 { return error('isolated launch transport requires an ordinary caller') }
	display := os.getenv('DISPLAY')
	authority := os.getenv('XAUTHORITY')
	defer { unsafe { display.free(); authority.free() } }
	// Refuse an ambient or incomplete display before contacting the service.
	shape := Request{ format: if display == '' && authority == '' { 1 } else { 2 }, arguments: arguments, display: display, authority: authority }
	shape.validate_display(uid)!
	mut describe_request := authproto.Frame{ code: authproto.op_describe, fields: [action.bytes()] }
	defer { describe_request.close() }
	mut description := authclient.ask_root(socket_path, describe_request.code, ...describe_request.fields)!
	defer { description.close() }
	if description.code != authproto.status_ok || description.fields.len != 3 || !reply_field(description, 1, '1') || !reply_field(description, 2, '0') {
		return error('the isolated package launch action is unavailable; ask the administrator to stage the account tools')
	}
	directory := pkgadmin.runtime_directory(uid)!
	defer { unsafe { directory.free() } }
	mut random := []u8{len: 16}
	defer { unsafe { random.free() } }
	rand.read(mut random)!
	nonce := random.hex()
	defer { unsafe { nonce.free() } }
	request := Request{ format: shape.format, nonce: nonce, arguments: arguments, display: display, authority: authority }
	mut listener := pkgadmin.listen_private(directory, uid, nonce)!
	defer { listener.close() }
	mut run_request := authproto.Frame{ code: authproto.op_run, fields: [action.bytes(), []u8{}, nonce.bytes()] }
	defer { run_request.close() }
	mut reply := authclient.ask_root(socket_path, run_request.code, ...run_request.fields)!
	defer { reply.close() }
	if reply.code != authproto.status_ok || reply.fields.len != 2 || !reply_field(reply, 0, '0') {
		return error('the account service refused the isolated application launch')
	}
	if !reply_invitation(reply, nonce) { return error('the account service returned another launch invitation') }
	// accept_root borrows this local only for its synchronous poll/accept.
	// An explicit stack borrow avoids V retaining a promoted Listener wrapper.
	fd := unsafe { &listener }.accept_root()!
	defer { C.close(fd) }
	send_request(fd, request)!
	send_streams(fd, [i32(0), 1, 2]!)!
	return receive_result(fd, request)
}

// Inspect borrowed reply bytes without allocating Frame.text() strings.
fn reply_field(reply authproto.Frame, index int, wanted string) bool {
	if index < 0 || index >= reply.fields.len || reply.fields[index].len != wanted.len { return false }
	for at in 0 .. wanted.len { if reply.fields[index][at] != wanted[at] { return false } }
	return true
}

fn reply_invitation(reply authproto.Frame, nonce string) bool {
	if reply.fields.len < 2 || reply.fields[1].len != nonce.len + 1 || reply.fields[1][nonce.len] != `\n` { return false }
	for at in 0 .. nonce.len { if reply.fields[1][at] != nonce[at] { return false } }
	return true
}
