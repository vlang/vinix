// SPDX-License-Identifier: GPL-2.0-or-later
module pkgadmin
import authclient
import authproto
import crypto.rand
import os
import tools.packages.pkgprotocol
#include <termios.h>
fn C.tcgetattr(int, voidptr) int
fn C.tcsetattr(int, int, voidptr) int
struct C.termios { mut: c_lflag u32 }
// Run only the fixed, peer-checked administrator transport. Arguments are
// borrowed for this synchronous call; credentials and frames are owned here.
pub fn run(arguments []string) !int {
	return run_with_socket(arguments, authclient.default_socket)
}

$if macos {
	fn C.memset_s(voidptr, usize, int, usize) int
} $else {
	fn C.explicit_bzero(voidptr, usize)
}
fn erase_password(data voidptr, length int) {
	if length == 0 { return }
	$if macos { C.memset_s(data, usize(length), 0, usize(length)) }
	$else { C.explicit_bzero(data, usize(length)) }
}
fn read_password(input int) ![]u8 {
	mut saved := C.termios{}
	typed := C.isatty(input) == 1
	if typed {
		if C.tcgetattr(input, unsafe { &saved }) != 0 { return error('cannot protect password input') }
		mut quiet := saved
		quiet.c_lflag &= ~u32(C.ECHO)
		if C.tcsetattr(input, C.TCSAFLUSH, unsafe { &quiet }) != 0 { return error('cannot disable password echo') }
		eprint('Your administrator password: ')
	}
	defer { if typed { C.tcsetattr(input, C.TCSAFLUSH, unsafe { &saved }); eprintln('') } }
	mut password := []u8{cap: password_limit}
	unsafe { password.flags |= .noslices }
	mut accepted := false
	defer { if !accepted { erase_password(password.data, password.len); unsafe { password.free() } } }
	mut byte := u8(0)
	defer { erase_password(unsafe { &byte }, 1) }
	for {
		count := C.read(input, unsafe { &byte }, 1)
		if count < 0 && C.errno == C.EINTR { continue }
		if count < 0 { return error('password input is unavailable') }
		if count == 0 || byte == `\n` { break }
		if password.len == password_limit || byte < 32 || byte == 127 { return error('password exceeds 256 bytes or contains a control character') }
		password << byte
	}
	if password.len == 0 { return error('administrator password is required') }
	accepted = true
	return password
}

fn run_with_socket(arguments []string, socket_path string) !int {
	validate_arguments(arguments)!
	uid := u32(os.geteuid())
	if uid == 0 { return error('root runs reviewed package commands directly') }
	mut describe_request := authproto.Frame{ code: authproto.op_describe, fields: [action.bytes()] }
	defer { describe_request.close() }
	mut described := authclient.ask_root(socket_path, describe_request.code, ...describe_request.fields)!
	defer { described.close() }
	if described.code != authproto.status_ok || described.fields.len != 3 { return error('package administrator authentication action is unavailable') }
	if !reply_field(described, 1, '1') { return error('this account cannot approve package changes; use an administrator account') }
	directory := runtime_directory(uid)!
	defer { unsafe { directory.free() } }
	mut random := []u8{len: 16}
	defer { unsafe { random.free() } }
	rand.read(mut random)!
	nonce := random.hex()
	defer { unsafe { nonce.free() } }
	request := Request{ nonce: nonce, arguments: arguments }
	text := request.encode()!
	defer { unsafe { text.free() } }
	mut listener := listen_private(directory, uid, nonce)!
	defer { listener.close() }
	password := read_password(0)!
	// Transfer the password owner to this frame. The client wipes borrowed
	// fields during the exchange; close wipes again and retires every owner.
	mut run_request := authproto.Frame{ code: authproto.op_run, fields: [action.bytes(), password, text.bytes()] }
	defer { run_request.close() }
	mut reply := authclient.ask_root(socket_path, run_request.code, ...run_request.fields)!
	defer { reply.close() }
	if reply.code == authproto.status_wait {
		seconds := reply.text(0)
		defer { unsafe { seconds.free() } }
		return error('authentication is throttled; retry in ' + seconds + ' seconds')
	}
	if reply.code == authproto.status_denied { return error('administrator password was rejected or this account\'s access was revoked') }
	if reply.code != authproto.status_ok || reply.fields.len != 2 || !reply_field(reply, 0, '0') {
		diagnostic := if reply.fields.len == 2 { reply.text(1) } else { 'administrator approval was refused or its package worker could not start'.clone() }
		defer { unsafe { diagnostic.free() } }
		return error(diagnostic)
	}
	if !reply_invitation(reply, nonce) { return error('authentication returned a different package request') }
	fd := unsafe { &listener }.accept_root()!
	defer { C.close(fd) }
	return receive_output(fd, request)
}

// These comparisons borrow frame fields and require exact invitation bytes.
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

fn receive_output(fd int, request Request) !int {
	mut pending := []u8{cap: 16384}
	unsafe { pending.flags |= .noslices }
	defer { unsafe { pending.free() } }
	mut bytes := [8192]u8{}
	mut code := -1
	mut skip := false
	for {
		count := C.read(fd, &bytes[0], usize(bytes.len))
		if count < 0 && C.errno == C.EINTR { continue }
		if count < 0 { return error('administrator package output failed; check package state before retrying') }
		if count == 0 { break }
		for index in 0 .. int(count) {
			byte := bytes[index]
			if code >= 0 { return error('data followed the administrator package completion receipt') }
			if byte == `\n` {
				if skip { println('Package diagnostic line exceeded 16 KiB and was omitted.'); flush_stdout(); skip = false; continue }
				line := unsafe { tos(pending.data, pending.len) }
				if line.starts_with(result_prefix) { code = request.result(line)! }
				else {
					print(line); println(''); flush_stdout()
				}
				pending.clear()
			} else {
				if skip { continue }
				if pending.len == pending.cap {
					line := unsafe { tos(pending.data, pending.len) }
					if line.starts_with(result_prefix) || line.starts_with(pkgprotocol.progress_prefix) { return error('administrator protocol output exceeds its bound') }
					pending.clear(); skip = true; continue
				}
				pending << byte
			}
		}
	}
	if pending.len != 0 || code < 0 { return error('administrator package completion was lost; check package state before retrying') }
	return code
}

