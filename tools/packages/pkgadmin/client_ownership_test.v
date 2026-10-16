// SPDX-License-Identifier: GPL-2.0-or-later
module pkgadmin

import authproto
import os
import tools.packages.pkgprotocol

#include <sys/wait.h>
#include <grp.h>
fn C.pipe(&i32) int
fn C.dup(int) int
fn C.dup2(int, int) int
fn C.lseek(int, i64, int) i64
fn C.fork() int
fn C.waitpid(int, &i32, int) int
fn C.setgroups(usize, voidptr) int
fn C.setgid(u32) int
fn C.setuid(u32) int
fn C._exit(int)
fn C.kill(int, int) int
fn C.usleep(u32) int
$if track_heap ? {
	#include "@VMODROOT/../../../desktop/tools/tests/heap_tracker.h"
	fn C.vinix_heap_begin()
	fn C.vinix_heap_end() u64
}
fn admin_client_cycles() int { $if admin_client_baseline ? { return 5 }; return 1000 }
fn admin_client_error(err IError) string { message := err.msg(); unsafe { err.free() }; return message }
fn admin_client_window(label string) {
	$if track_heap ? {
		kept := C.vinix_heap_end()
		println('ADMIN CLIENT ' + label + ' retained ' + kept.str() + ' bytes')
		$if !admin_client_baseline ? { assert kept == 0, kept.str() }
	}
}
fn admin_client_fds() int {
	mut count := 0
	for fd in 0 .. 128 { if C.fcntl(fd, C.F_GETFD) >= 0 { count++ } }
	return count
}
fn admin_client_settle() {
	$if admin_client_guest ? { $if !admin_client_baseline ? { assert C.usleep(7_000_000) == 0 } }
}
fn admin_fixture_input(text string) int {
	mut pipes := [2]i32{}
	assert C.pipe(unsafe { &pipes[0] }) == 0
	assert C.write(pipes[1], text.str, usize(text.len)) == text.len
	C.close(pipes[1]); return pipes[0]
}
fn test_admin_password_owners_and_refusals() {
	long := 'p'.repeat(256); over := long + 'p\n'
	defer { unsafe { long.free(); over.free() } }
	inputs := ['secret\n', 'secret', long + '\n', '', '\n', 'bad\x01\n', 'bad\x7f\n', over]
	defer { unsafe { inputs[2].free(); (&array(&inputs)).free() } }
	for index, text in inputs {
		before := admin_client_fds()
		$if track_heap ? { C.vinix_heap_begin() }
		for _ in 0 .. admin_client_cycles() {
			fd := admin_fixture_input(text)
			if mut password := read_password(fd) {
				assert index < 3 && password.len == if index == 2 { 256 } else { 6 }
				mut owner := authproto.Frame{ fields: [password] }; owner.close()
			} else {
				message := admin_client_error(err)
				assert index >= 3
				assert message == if index in [3, 4]! { 'administrator password is required' } else { 'password exceeds 256 bytes or contains a control character' }
				unsafe { message.free() }
			}
			C.close(fd)
		}
		admin_client_window('password input success/refusal')
		assert admin_client_fds() == before
	}
}
fn test_admin_client_unavailable_service_retires_inputs() {
	arguments := ['update']; defer { unsafe { (&array(&arguments)).free() } }
	root := os.temp_dir() + '/vinix-admin-local-' + os.getpid().str()
	os.mkdir(root, mode: 0o700)!
	defer { os.rmdir_all(root) or {}; unsafe { root.free() } }
	path := root + '/auth.sock'; defer { unsafe { path.free() } }
	before := admin_client_fds()
	$if track_heap ? { C.vinix_heap_begin() }
	for _ in 0 .. admin_client_cycles() {
		if _ := run_with_socket(arguments, path) { assert false } else {
			message := admin_client_error(err)
			assert message == if os.geteuid() == 0 { 'root runs reviewed package commands directly' } else { 'the authentication service is not running' }
			unsafe { message.free() }
		}
	}
	admin_client_window('unavailable authentication')
	assert admin_client_fds() == before
	admin_client_settle()
}

fn test_admin_output_requires_bound_receipt_and_exact_eof() {
	arguments := ['update']; defer { unsafe { (&array(&arguments)).free() } }
	request := Request{ nonce: '0123456789abcdef0123456789abcdef', arguments: arguments }
	receipt := request.receipt(37); defer { unsafe { receipt.free() } }
	oversized := 'x'.repeat(16385); defer { unsafe { oversized.free() } }
	inputs := [receipt + '\n', 'diagnostic\nVINIX-PACKAGE-PROGRESS {"phase":"check"}\n' + receipt + '\n',
		oversized + '\n' + receipt + '\n', receipt.replace(request.nonce, 'ffffffffffffffffffffffffffffffff') + '\n',
		receipt + '\nextra', receipt.clone(), 'diagnostic\n', '', receipt + '\n\n',
		result_prefix + oversized + '\n', pkgprotocol.progress_prefix + oversized + '\n', receipt + 'x\n']
	defer { unsafe { inputs.free() } }
	path := os.temp_dir() + '/vinix-admin-stream-' + os.getpid().str(); defer { unsafe { path.free() } }
	before := admin_client_fds()
	for index, input in inputs {
		os.write_file(path, input)!
		fd := C.open(path.str, C.O_RDONLY); assert fd >= 0
		output := C.dup(1); assert output >= 0
		null := C.open(c'/dev/null', C.O_WRONLY); assert null >= 0; assert C.dup2(null, 1) == 1; C.close(null)
		$if track_heap ? { C.vinix_heap_begin() }
		for _ in 0 .. admin_client_cycles() {
			assert C.lseek(fd, 0, C.SEEK_SET) == 0
			if status := receive_output(fd, request) { assert index < 3 && status == 37 } else {
				message := admin_client_error(err)
				wanted := if index == 3 { 'administrator package completion receipt is invalid' }
					else if index == 11 { 'invalid administrator package result code' }
					else if index in [4, 8]! { 'data followed the administrator package completion receipt' }
					else if index in [9, 10]! { 'administrator protocol output exceeds its bound' }
					else { 'administrator package completion was lost; check package state before retrying' }
				assert index >= 3 && message == wanted
				unsafe { message.free() }
			}
		}
		// Restore stdout before the tracker marker without allocating V storage.
		assert C.dup2(output, 1) == 1; C.close(output); C.close(fd)
		admin_client_window('bounded output, receipt and EOF')
		assert admin_client_fds() == before
	}
	os.rm(path)!
	println('ADMIN CLIENT streamed diagnostics, oversized omissions, protocol bounds and exact completion refusals PASS')
}

fn test_admin_reply_checks_borrow_fields_and_invitation() {
	$if !admin_client_baseline ? {
		nonce := '0123456789abcdef0123456789abcdef'
		inputs := [nonce + '\n', nonce, nonce + '\nextra', nonce + '\x00', 'x' + nonce + '\n', '\n', nonce + '\r\n']
		defer { unsafe { inputs.free() } }
		mut frames := []authproto.Frame{cap: inputs.len}
		defer { unsafe { for mut frame in frames { frame.close() }; (&array(&frames)).free() } }
		for input in inputs {
			fields := ['0', input]; frame := authproto.text_frame(authproto.status_ok, ...fields)
			unsafe { frames.push_many(&frame, 1); (&array(&fields)).free() }
		}
		$if track_heap ? { C.vinix_heap_begin() }
		for _ in 0 .. admin_client_cycles() {
			for index, frame in frames {
				assert reply_field(frame, 0, '0') && reply_field(frame, 1, inputs[index])
				assert !reply_field(frame, -1, '0') && !reply_field(frame, 2, '0') && !reply_field(frame, 0, '00')
				assert reply_invitation(frame, nonce) == (index == 0)
			}
		}
		admin_client_window('borrowed reply checks')
	}
}

fn test_admin_approval_errors_own_their_diagnostics_after_reply_retirement() {
	$if !admin_client_baseline ? {
		nonce := '0123456789abcdef0123456789abcdef'
		invitation := nonce + '\n'; defer { unsafe { invitation.free() } }
		for mode in 0 .. 7 {
			$if track_heap ? { C.vinix_heap_begin() }
			for _ in 0 .. admin_client_cycles() {
				fields := if mode == 0 { ['0', invitation] } else if mode == 1 { ['7'] }
					else if mode == 2 { ['0', invitation] } else if mode == 3 { ['1', 'review was refused'] }
					else if mode == 4 { ['0'] } else if mode == 5 { ['01', 'review was refused'] } else { ['0', 'another\n'] }
				status := if mode == 1 { authproto.status_wait } else if mode == 2 { authproto.status_denied }
					else if mode == 3 { authproto.status_failed } else { authproto.status_ok }
				mut reply := authproto.text_frame(status, ...fields)
				unsafe { (&array(&fields)).free() }
				if _ := check_approval(reply, nonce) { reply.close(); assert mode == 0 }
				else {
					reply.close()
					// The diagnostic must survive destruction of both the helper's
					// temporary string and the reply that supplied its original bytes.
					message := admin_client_error(err)
					wanted := match mode {
						1 { 'authentication is throttled; retry in 7 seconds' }
						2 { 'administrator password was rejected or this account\'s access was revoked' }
						3, 5 { 'review was refused' }
						4 { 'administrator approval was refused or its package worker could not start' }
						else { 'authentication returned a different package request' }
					}
					assert mode != 0 && message == wanted
					unsafe { message.free() }
				}
			}
			admin_client_window('owned approval diagnostics')
		}
	}
}
fn admin_fixture_accept(listener int) !int {
	mut readiness := Poll{ fd: i32(listener), events: 1 }
	if C.vinix_package_admin_poll(unsafe { &readiness }, 1, 30000) <= 0 { return error('fixture accept timeout') }
	fd := C.accept(listener, unsafe { nil }, unsafe { nil })
	if fd < 0 { return error('fixture accept failed') }
	return fd
}
fn admin_fixture_reply(fd int, code u16, fields []string) ! {
	mut reply := authproto.text_frame(code, ...fields); defer { reply.close() }
	authproto.write_frame(fd, reply)!
}
fn admin_fixture_serve(listener int, mode int, arguments []string, directory string) ! {
	describe_fd := admin_fixture_accept(listener)!
	mut described := authproto.read_frame(describe_fd) or { C.close(describe_fd); return err }
	defer { described.close() }
	value := described.text(0); defer { unsafe { value.free() } }
	if described.code != authproto.op_describe || described.fields.len != 1 || value != action { C.close(describe_fd); return error('fixture got another description') }
	if mode == 12 { os.chmod(directory, 0o755)! }
	fields := if mode == 2 { ['description', '1'] } else if mode == 3 { ['description', '0', '1'] } else { ['description', '1', '1'] }
	defer { unsafe { (&array(&fields)).free() } }
	admin_fixture_reply(describe_fd, if mode == 1 { authproto.status_denied } else { authproto.status_ok }, fields) or { C.close(describe_fd); return err }
	C.close(describe_fd)
	if mode in [1, 2, 3, 12]! { return }
	fd := admin_fixture_accept(listener)!; defer { C.close(fd) }
	mut approved := authproto.read_frame(fd)!; defer { approved.close() }
	name := approved.text(0); password := approved.text(1); encoded := approved.text(2)
	defer { unsafe { name.free(); password.free(); encoded.free() } }
	if approved.code != authproto.op_run || approved.fields.len != 3 || name != action || password != 'fixture-password' { return error('fixture lost authentication input') }
	mut request := decode(encoded)!; defer { request.close() }
	if request.arguments != arguments { return error('fixture lost literal reviewed input') }
	if mode == 10 { return }
	if mode in [4, 5, 6, 7, 8, 9]! {
		invitation := request.nonce + if mode == 9 { '\nextra' } else { '\n' }; defer { unsafe { invitation.free() } }
		result := if mode == 4 { ['7'] } else if mode == 7 { ['0'] } else if mode == 6 || mode == 8 { [if mode == 8 { '01' } else { '1' }, 'review was refused'] } else { ['0', invitation] }
		defer { unsafe { (&array(&result)).free() } }
		status := if mode == 4 { authproto.status_wait } else if mode == 5 { authproto.status_denied } else if mode == 6 { authproto.status_failed } else { authproto.status_ok }
		admin_fixture_reply(fd, status, result)!
		return
	}
	channel := connect_private(directory, 1000, request.nonce)!; defer { C.close(channel) }
	invitation := request.nonce + '\n'; defer { unsafe { invitation.free() } }
	result := ['0', invitation]; defer { unsafe { (&array(&result)).free() } }
	admin_fixture_reply(fd, authproto.status_ok, result)!
	receipt := request.receipt(if mode == 13 { 0 } else { 37 }); defer { unsafe { receipt.free() } }
	line := if mode == 11 { 'X' + receipt + '\n' } else { receipt + '\n' }; defer { unsafe { line.free() } }
	if C.write(channel, line.str, usize(line.len)) != line.len { return error('fixture receipt write failed') }
}
fn admin_case_name(mode int) string {
	return match mode { 0 { 'status 37' } 1 { 'description denied' } 2 { 'description fields' } 3 { 'account denied' }
		4 { 'throttled' } 5 { 'approval denied' } 6 { 'approval diagnostic' } 7 { 'approval fields' } 8 { 'approval status' }
		9 { 'invitation mismatch' } 10 { 'approval interrupted' } 11 { 'receipt lost' } 12 { 'unsafe runtime' } else { 'status 0' } }
}
fn admin_case_error(mode int) string {
	return match mode {
		1, 2 { 'package administrator authentication action is unavailable' }
		3 { 'this account cannot approve package changes; use an administrator account' }
		4 { 'authentication is throttled; retry in 7 seconds' }
		5 { 'administrator password was rejected or this account\'s access was revoked' }
		6, 8 { 'review was refused' }
		7 { 'administrator approval was refused or its package worker could not start' }
		9 { 'authentication returned a different package request' }
		10 { 'the authentication service is busy or refused the request' }
		11 { 'administrator package completion was lost; check package state before retrying' }
		12 { 'package administration requires the caller\'s private runtime directory' }
		else { '' }
	}
}
fn admin_fixture_worker(socket string, arguments []string, mode int) {
	before := admin_client_fds()
	output := C.dup(1); assert output >= 0
	null := C.open(c'/dev/null', C.O_WRONLY); assert null >= 0; assert C.dup2(null, 1) == 1; C.close(null)
	$if track_heap ? { C.vinix_heap_begin() }
	for cycle in 0 .. admin_client_cycles() {
		input := admin_fixture_input('fixture-password\n'); assert C.dup2(input, 0) == 0; C.close(input)
		if code := run_with_socket(arguments, socket) {
			if (mode == 0 && code != 37) || (mode == 13 && code != 0) || mode !in [0, 13]! { C._exit(81) }
		} else {
			message := admin_client_error(err)
			if message != admin_case_error(mode) { eprintln(message); C._exit(82) }
			unsafe { message.free() }
		}
		if mode !in [1, 2, 3, 12]! && (cycle + 1) % 250 == 0 && cycle + 1 < admin_client_cycles() { admin_client_settle() }
	}
	assert C.dup2(output, 1) == 1; C.close(output)
	admin_client_window(admin_case_name(mode))
	if admin_client_fds() != before { C._exit(83) }
	C._exit(0)
}
fn test_root_service_exercises_complete_ordinary_administration_callers() {
	$if !admin_client_guest ? { return }
	if os.geteuid() != 0 { return }
	directory := '/run/user/1000'; os.mkdir_all(directory, mode: 0o700)!; os.chown(directory, 1000, 1000)!
	root := os.temp_dir() + '/vinix-admin-service-' + os.getpid().str(); os.mkdir(root, mode: 0o755)!
	defer { os.rmdir_all(root) or {}; unsafe { root.free() } }
	path := root + '/auth.sock'; defer { unsafe { path.free() } }
	location := address(path)!; listener := C.socket(C.AF_UNIX, C.SOCK_STREAM, 0); assert listener >= 0
	defer { C.close(listener) }
	assert C.bind(listener, unsafe { &location }, u32(sizeof(C.vinix_package_admin_address))) == 0
	assert C.listen(listener, 8) == 0; os.chmod(path, 0o666)!
	arguments := ['--progress', '--offline', 'policy-apply', 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa', '/etc/a space; $literal "quote" \\ 💡.json']
	defer { unsafe { (&array(&arguments)).free() } }
	warm := Request{ nonce: '0123456789abcdef0123456789abcdef', arguments: arguments }.receipt(0); unsafe { warm.free() }
	before := admin_client_fds()
	for mode in 0 .. 14 {
		pid := C.fork(); assert pid >= 0
		if pid == 0 {
			C.close(listener)
			if C.setgroups(0, unsafe { nil }) != 0 || C.setgid(1000) != 0 || C.setuid(1000) != 0 { C._exit(80) }
			admin_fixture_worker(path, arguments, mode)
		}
		mut passed := true
		mut calls := admin_client_cycles()
		$if admin_client_baseline ? { if mode in [6, 7, 8]! { calls = 1 } }
		for _ in 0 .. calls {
			admin_fixture_serve(listener, mode, arguments, directory) or { eprintln(err); C.kill(pid, 15); passed = false; break }
		}
		mut status := i32(0)
		assert C.waitpid(pid, unsafe { &status }, 0) == pid && passed, status.str()
		$if admin_client_baseline ? {
			if mode in [6, 7, 8]! { assert status == 11, status.str(); println('ADMIN CLIENT baseline approval diagnostic use-after-free SIGSEGV confirmed') }
			else { assert status == 0, status.str() }
		} $else { assert status == 0, status.str() }
		os.chmod(directory, 0o700)!
		entries := os.ls(directory)!; assert entries.len == 0; unsafe { entries.free() }
		assert admin_client_fds() == before
		admin_client_settle()
	}
	$if admin_client_baseline ? { println('ADMIN CLIENT baseline diagnostic crashes confirmed; remaining outcomes and cleanup PASS') }
	$else { println('ADMIN CLIENT root service and ordinary caller preserve reviewed input, passwords, status, cleanup and exact diagnostics PASS') }
}
