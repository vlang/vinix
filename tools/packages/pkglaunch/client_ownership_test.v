// SPDX-License-Identifier: GPL-2.0-or-later
module pkglaunch

import os
import time
import authproto
import tools.packages.pkgadmin

#include <sys/socket.h>
#include <sys/un.h>
#include <sys/wait.h>
#include <unistd.h>
#include <grp.h>
fn C.socket(int, int, int) int
fn C.bind(int, voidptr, u32) int
fn C.listen(int, int) int
fn C.accept(int, voidptr, voidptr) int
fn C.unlink(&char) int
fn C.fork() int
fn C.waitpid(int, &i32, int) int
fn C.setgroups(usize, voidptr) int
fn C.setgid(u32) int
fn C.setuid(u32) int
fn C._exit(int)
fn C.kill(int, int) int
fn C.usleep(u32) int
struct C.sockaddr_un { mut: sun_family u16 sun_path [108]char }

$if track_heap ? {
	#include "@VMODROOT/../../../desktop/tools/tests/heap_tracker.h"
	fn C.vinix_heap_begin()
	fn C.vinix_heap_end() u64
}
fn launch_client_cycles() int { $if launch_client_baseline ? { return 5 }; return 1000 }
fn launch_client_error(err IError) string {
	message := err.msg(); unsafe { err.free() }; return message
}
fn launch_client_window(label string) {
	$if track_heap ? {
		kept := C.vinix_heap_end()
		println('LAUNCH CLIENT ' + label + ' retained ' + kept.str() + ' bytes')
		$if !launch_client_baseline ? { assert kept == 0, kept.str() }
	}
}
fn launch_client_fds() int {
	mut count := 0
	for fd in 0 .. 128 { if C.fcntl(fd, C.F_GETFD) >= 0 { count++ } }
	return count
}
fn launch_client_settle() {
	$if launch_client_guest ? { $if !launch_client_baseline ? { assert C.usleep(7_000_000) == 0 } }
}
fn test_launch_client_local_refusals_retire_owned_authentication_inputs() {
	arguments := ['run', 'example.app']
	defer { unsafe { arguments.free() } }
	directory := os.temp_dir() + '/vinix-launch-local-' + os.getpid().str()
	os.mkdir(directory, mode: 0o700)!
	defer { os.rmdir_all(directory) or {}; unsafe { directory.free() } }
	path := directory + '/auth.sock'; defer { unsafe { path.free() } }
	before := launch_client_fds()
	$if track_heap ? { C.vinix_heap_begin() }
	for _ in 0 .. launch_client_cycles() {
		if code := run_with_socket(arguments, path) { assert code < 0; assert false }
		else {
			message := launch_client_error(err)
			assert message == if os.geteuid() == 0 { 'isolated launch transport requires an ordinary caller' } else { 'the authentication service is not running' }
			unsafe { message.free() }
		}
	}
	launch_client_window('unavailable authentication')
	assert launch_client_fds() == before
	launch_client_settle()
}

fn launch_fixture_accept(listener int) !int {
	ready(listener, time.sys_mono_now() + 30_000_000_000)!
	fd := C.accept(listener, unsafe { nil }, unsafe { nil })
	if fd < 0 { return error('fixture accept failed') }
	return fd
}
fn launch_fixture_reply(fd int, code u16, fields []string) ! {
	mut reply := authproto.text_frame(code, ...fields)
	defer { reply.close() }
	authproto.write_frame(fd, reply)!
}
fn launch_fixture_serve(listener int, mode int, arguments []string, directory string) ! {
	describe_fd := launch_fixture_accept(listener)!
	mut described := authproto.read_frame(describe_fd) or { C.close(describe_fd); return err }
	defer { described.close() }
	value := described.text(0); defer { unsafe { value.free() } }
	if described.code != authproto.op_describe || described.fields.len != 1 || value != action {
		C.close(describe_fd); return error('fixture got another action description')
	}
	if mode == 11 { os.chmod(directory, 0o755)! }
	fields := if mode == 2 { ['description', '1'] } else if mode == 3 { ['description', '0', '0'] }
		else if mode == 4 { ['description', '1', '1'] } else { ['description', '1', '0'] }
	defer { unsafe { (&array(&fields)).free() } }
	launch_fixture_reply(describe_fd, if mode == 1 { authproto.status_denied } else { authproto.status_ok }, fields) or { C.close(describe_fd); return err }
	C.close(describe_fd)
	if mode in [1, 2, 3, 4, 11]! { return }
	fd := launch_fixture_accept(listener)!
	defer { C.close(fd) }
	mut request := authproto.read_frame(fd)!; defer { request.close() }
	name := request.text(0); nonce := request.text(2)
	defer { unsafe { name.free(); nonce.free() } }
	if request.code != authproto.op_run || request.fields.len != 3 || name != action
		|| request.fields[1].len != 0 || !valid_nonce(nonce) { return error('fixture got another launch approval') }
	if mode == 9 { return }
	if mode in [5, 6, 7, 8]! {
		invitation := nonce + if mode == 8 { '\nextra' } else { '\n' }
		defer { unsafe { invitation.free() } }
		result := if mode == 6 { ['0'] } else if mode == 7 { ['01', invitation] } else { ['0', invitation] }
		defer { unsafe { (&array(&result)).free() } }
		launch_fixture_reply(fd, if mode == 5 { authproto.status_denied } else { authproto.status_ok }, result)!
		return
	}
	channel := pkgadmin.connect_private(directory, 1000, nonce)!
	defer { C.close(channel) }
	invitation := nonce + '\n'; defer { unsafe { invitation.free() } }
	result := ['0', invitation]; defer { unsafe { (&array(&result)).free() } }
	launch_fixture_reply(fd, authproto.status_ok, result)!
	mut launch := receive_request(channel)!; defer { launch.close() }
	if launch.nonce != nonce || launch.arguments != arguments { return error('fixture lost literal launch input') }
	streams := receive_streams(channel)!
	defer { for stream in streams { C.close(stream) } }
	for stream in streams { if C.fcntl(stream, C.F_GETFD) & C.FD_CLOEXEC == 0 { return error('fixture received an unprotected stream') } }
	if mode == 10 {
		text := launch.receipt(37); mut bytes := text.bytes(); bytes[0] = `X`
		defer { unsafe { text.free(); bytes.free() } }
		write_exact(channel, bytes.data, bytes.len)!
	} else { send_result(channel, launch, if mode == 12 { 0 } else { 37 })! }
}
fn launch_case_name(mode int) string {
	return match mode {
		0 { 'status 37' } 1 { 'description denied' } 2 { 'description fields' }
		3 { 'account denied' } 4 { 'password required' } 5 { 'approval denied' }
		6 { 'approval fields' } 7 { 'approval status' } 8 { 'invitation mismatch' }
		9 { 'approval interrupted' } 10 { 'receipt mismatch' } 11 { 'unsafe runtime' } else { 'status 0' }
	}
}
fn launch_case_error(mode int) string {
	return match mode {
		1, 2, 3, 4 { 'the isolated package launch action is unavailable; ask the administrator to stage the account tools' }
		5, 6, 7 { 'the account service refused the isolated application launch' }
		8 { 'the account service returned another launch invitation' }
		9 { 'the authentication service is busy or refused the request' }
		10 { 'isolated package completion receipt is invalid' }
		11 { 'package administration requires the caller\'s private runtime directory' }
		else { '' }
	}
}
fn launch_fixture_worker(socket string, arguments []string, mode int) {
	before := launch_client_fds()
	$if track_heap ? { C.vinix_heap_begin() }
	for cycle in 0 .. launch_client_cycles() {
		if code := run_with_socket(arguments, socket) {
			if (mode == 0 && code != 37) || (mode == 12 && code != 0) || mode !in [0, 12]! { C._exit(81) }
		} else {
			message := launch_client_error(err)
			if message != launch_case_error(mode) { eprintln(message); C._exit(82) }
			unsafe { message.free() }
		}
		// Complete launches create several endpoints per call. Pace the test
		// below the deferred kernel socket budget; production never retries.
		if mode in [0, 5, 6, 7, 8, 9, 10, 12]! && (cycle + 1) % 250 == 0 && cycle + 1 < launch_client_cycles() { launch_client_settle() }
	}
	launch_client_window(launch_case_name(mode))
	if launch_client_fds() != before { C._exit(83) }
	C._exit(0)
}

fn test_root_service_exercises_complete_ordinary_launch_callers() {
	$if !launch_client_guest ? { return }
	if os.geteuid() != 0 { return }
	directory := '/run/user/1000'
	os.mkdir_all(directory, mode: 0o700)!
	os.chown(directory, 1000, 1000)!
	root := os.temp_dir() + '/vinix-launch-service-' + os.getpid().str()
	os.mkdir(root, mode: 0o755)!
	defer { os.rmdir_all(root) or {}; unsafe { root.free() } }
	path := root + '/auth.sock'; defer { unsafe { path.free() } }
	mut address := C.sockaddr_un{ sun_family: u16(C.AF_UNIX) }
	unsafe { vmemcpy(&address.sun_path[0], path.str, path.len) }
	listener := C.socket(C.AF_UNIX, C.SOCK_STREAM, 0)
	assert listener >= 0
	defer { C.close(listener) }
	assert C.bind(listener, unsafe { &address }, u32(sizeof(C.sockaddr_un))) == 0
	assert C.listen(listener, 8) == 0
	os.chmod(path, 0o666)!
	arguments := ['run-args', 'example.app', '--file', '/home/a space.txt', '--', '', '--literal=a space; $(data)', '💡']
	defer { unsafe { arguments.free() } }
	// JSON's per-type encoder metadata is persistent and shared with future
	// calls. Initialize it before forking each measured client process.
	warm := Request{ nonce: '0123456789abcdef0123456789abcdef', arguments: arguments }.receipt(0)
	unsafe { warm.free() }
	before := launch_client_fds()
	for mode in 0 .. 13 {
		pid := C.fork(); assert pid >= 0
		if pid == 0 {
			C.close(listener)
			if C.setgroups(0, unsafe { nil }) != 0 || C.setgid(1000) != 0 || C.setuid(1000) != 0 { C._exit(80) }
			launch_fixture_worker(path, arguments, mode)
		}
		mut passed := true
		for _ in 0 .. launch_client_cycles() {
			launch_fixture_serve(listener, mode, arguments, directory) or {
				eprintln(err); C.kill(pid, 15); passed = false; break
			}
		}
		mut status := i32(0)
		assert C.waitpid(pid, unsafe { &status }, 0) == pid && passed && status == 0, status.str()
		os.chmod(directory, 0o700)!
		entries := os.ls(directory)!
		assert entries.len == 0
		unsafe { entries.free() }
		assert launch_client_fds() == before
		launch_client_settle()
	}
	println('LAUNCH CLIENT root service and ordinary caller preserve literal input, three protected streams, status, cleanup and diagnostics PASS')
}

fn test_launch_reply_checks_borrow_exact_bytes_without_allocating() {
	$if !launch_client_baseline ? {
		nonce := '0123456789abcdef0123456789abcdef'
		inputs := [nonce + '\n', nonce, nonce + '\nextra', nonce + '\x00', 'x' + nonce + '\n', '\n', nonce + '\r\n']
		defer { unsafe { inputs.free() } }
		mut replies := []authproto.Frame{cap: inputs.len}
		defer { unsafe { for mut reply in replies { reply.close() }; (&array(&replies)).free() } }
		for input in inputs {
			fields := ['0', input]
			frame := authproto.text_frame(authproto.status_ok, ...fields)
			unsafe { replies.push_many(&frame, 1); (&array(&fields)).free() }
		}
		$if track_heap ? { C.vinix_heap_begin() }
		for _ in 0 .. launch_client_cycles() {
			for index, reply in replies {
				assert reply_field(reply, 0, '0') && reply_field(reply, 1, inputs[index])
				assert !reply_field(reply, -1, '0') && !reply_field(reply, 2, '0') && !reply_field(reply, 0, '00')
				assert reply_invitation(reply, nonce) == (index == 0)
			}
		}
		launch_client_window('borrowed reply checks')
	}
}
