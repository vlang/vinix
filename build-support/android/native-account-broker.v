// SPDX-License-Identifier: GPL-2.0-or-later
// Root launcher and bounded authenticator broker. This is opt-in deployment;
// it supplies no fake account, token, permission grant or signature trust.
module main

import accountbroker
import accountinteraction
import accountmanifest
import accountuifd
import nativeaccountauth
import os
import strconv
import time

#include <errno.h>
#include <fcntl.h>
#include <poll.h>
#include <signal.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/un.h>
#include <sys/wait.h>
#include <unistd.h>

struct BrokerPoll {
mut:
	fd      i32
	events  i16
	revents i16
}

fn C.lstat(&u8, voidptr) i32
fn C.socket(i32, i32, i32) i32
fn C.bind(i32, voidptr, u32) i32
fn C.listen(i32, i32) i32
fn C.accept(i32, voidptr, voidptr) i32
fn C.socketpair(i32, i32, i32, &i32) i32
fn C.close(i32) i32
fn C.fcntl(i32, i32, ...i32) i32
fn C.poll(voidptr, uint , i32 ) i32
fn C.fork() i32
fn C.setsid() i32
fn C.execv(&u8, &&u8) i32
fn C._exit(i32)
fn C.getuid() u32
fn C.geteuid() u32
fn C.kill(i32, i32) i32
fn C.waitpid(i32, &i32, i32) i32

fn protected_directory(path string) ! {
	if !path.starts_with('/') || path.ends_with('/') || path.len > 80 || path.contains('\x00') {
		return error('invalid broker directory')
	}
	mut current := ''
	for part in path.split('/')[1..] {
		if part in ['', '.', '..'] { return error('broker directory must be canonical') }
		current += '/' + part
		mut info := C.stat{}
		if C.lstat(current.str, &info) != 0 || info.st_uid != 0 || u32(info.st_mode) & u32(C.S_IFMT) != u32(C.S_IFDIR)
			|| info.st_mode & 0o022 != 0 {
			return error('broker directory must have root-protected ancestors')
		}
	}
}

fn listener(path string) !int {
	if os.exists(path) || os.is_link(path) {
		return error('broker never replaces an existing socket path')
	}
	fd := C.socket(C.AF_UNIX, C.SOCK_STREAM, 0)
	if fd < 0 { return error('cannot create broker listener') }
	mut ok := false
	mut bound := false
	defer {
		if !ok {
			C.close(fd)
			if bound { os.rm(path) or {} }
		}
	}
	flags := C.fcntl(fd, C.F_GETFD)
	status := C.fcntl(fd, C.F_GETFL)
	if flags < 0 || status < 0 || C.fcntl(fd, C.F_SETFD, flags | C.FD_CLOEXEC) != 0
		|| C.fcntl(fd, C.F_SETFL, status | C.O_NONBLOCK) != 0 {
		return error('cannot protect broker listener')
	}
	mut address := C.sockaddr_un{}
	address.sun_family = C.AF_UNIX
	unsafe { C.memcpy(&address.sun_path[0], path.str, uint(path.len)) }
	$if macos {
		address.sun_len = u8(sizeof(C.sockaddr_un))
	}
	if C.bind(fd, voidptr(&address), u32(sizeof(C.sockaddr_un))) != 0 {
		return error('cannot bind account broker socket')
	}
	bound = true
	os.chmod(path, 0o666)!
	if C.listen(fd, 32) != 0 { return error('cannot listen on account broker socket') }
	ok = true
	return int(fd)
}

fn stop_child(pid i32) {
	mut status := i32(0)
	if C.waitpid(pid, &status, C.WNOHANG) != 0 { return }
	C.kill(-pid, C.SIGTERM)
	deadline := time.sys_mono_now() + 3 * time.second
	for time.sys_mono_now() < deadline {
		if C.waitpid(pid, &status, C.WNOHANG) == pid { return }
		time.sleep(10 * time.millisecond)
	}
	C.kill(-pid, C.SIGKILL)
	C.waitpid(pid, &status, 0)
}

fn run() ! {
	if os.args.len !in [12, 13, 18] || C.getuid() != 0 || C.geteuid() != 0 {
		return error('usage (root): native-account-broker REGISTRY RUNTIME_ROOT APK UID GID SERVICE ACTION DIRECTORY DATA_DIRECTORY HOME_DIRECTORY PACKAGE [INTERACTION_ACTIVITY [--ui UID GID ABS_HELPER ABS_WINDOW_SOCKET]]')
	}
	registry_path, runtime, apk := os.args[1], os.args[2], os.args[3]
	uid_text, gid_text := os.args[4], os.args[5]
	if uid_text.len != 5 || gid_text.len != 5 || !uid_text.bytes().all(it >= `0` && it <= `9`)
		|| !gid_text.bytes().all(it >= `0` && it <= `9`) {
		return error('invalid service IDs')
	}
	uid, gid := uid_text.u32(), gid_text.u32()
	registry := nativeaccountauth.load(registry_path)!
	entry := registry.verify_service(apk, uid, gid, os.args[6], os.args[7])!
	if os.args.len >= 13 {
		accountmanifest.verify_activity(apk, entry.package_name, os.args[12])!
	}
	mut ui := &accountuifd.Controller(unsafe { nil })
	mut ui_owned := false
	mut ui_pair := [i32(-1), i32(-1)]!
	mut ui_child_owned := false
	defer {
		if ui_owned {
			ui.close()
			unsafe { free(ui) }
		}
		if ui_child_owned { C.close(ui_pair[1]) }
	}
	if os.args.len == 18 {
		if os.args[13] != '--ui' { return error('invalid account UI option') }
		desktop_uid := strconv.parse_uint(os.args[14], 10, 32)!
		desktop_gid := strconv.parse_uint(os.args[15], 10, 32)!
		if desktop_uid.str() != os.args[14] || desktop_gid.str() != os.args[15] {
			return error('desktop IDs must be canonical unsigned decimal')
		}
		ui_pair = accountuifd.socket_pair()!
		ui_child_owned = true
		ui = accountuifd.create(int(ui_pair[0]), accountuifd.Config{
			helper:        os.args[16]
			window_socket: os.args[17]
			uid:           u32(desktop_uid)
			gid:           u32(desktop_gid)
		}) or {
			C.close(ui_pair[0])
			return err
		}
		ui_owned = true
		nativeaccountauth.inherit_ui_channel(int(ui_pair[1]))!
	}
	directory := os.args[8]
	protected_directory(directory)!
	client_path, service_path := directory + '/accounts.sock', directory + '/authenticator.sock'
	clients := listener(client_path)!
	defer {
		C.close(i32(clients))
		os.rm(client_path) or {}
	}
	services := listener(service_path)!
	defer {
		C.close(i32(services))
		os.rm(service_path) or {}
	}
	pair := accountuifd.socket_pair()!
	mut root_lifetime_owned := true
	defer { if root_lifetime_owned { C.close(pair[0]) } }
	mut child_lifetime_owned := true
	defer { if child_lifetime_owned { C.close(pair[1]) } }
	nativeaccountauth.inherit_root_channel(int(pair[1]))!
	launcher := runtime + '/usr/bin/run-android'
	mut launch_args := [launcher, apk, '--service-fd', pair[1].str(), '--authenticator-socket',
		service_path]
	if ui_owned { launch_args << ['--ui-fd', ui_pair[1].str()] }
	mut argv := []&u8{cap: launch_args.len + 1}
	for arg in launch_args { argv << arg.str }
	argv << unsafe { &u8(nil) }
	os.setenv('VINIX_ANDROID_ROOT', runtime, true)
	os.setenv('VINIX_ANDROID_ACCOUNT_REGISTRY', registry_path, true)
	os.setenv('VINIX_ANDROID_UID', uid_text, true)
	os.setenv('VINIX_ANDROID_GID', gid_text, true)
	os.setenv('ANDROID_APP_DATA_DIR', os.args[9], true)
	os.setenv('VINIX_ANDROID_HOME', os.args[10], true)
	// Explicit data/home are administrator provisioning, not app-supplied paths.
	// The last argument pins the root-selected package to guard CLI mistakes.
	if os.args[11] != entry.package_name {
		return error('selected package does not match registry')
	}
	pid := C.fork()
	if pid < 0 {
		return error('cannot fork selected account service')
	}
	if pid == 0 {
		if ui_owned { C.close(ui_pair[0]) }
		C.close(pair[0])
		C.close(i32(clients))
		C.close(i32(services))
		if C.setsid() < 0 { C._exit(125) }
		C.execv(launcher.str, argv.data)
		C._exit(126)
	}
	C.close(pair[1])
	child_lifetime_owned = false
	if ui_child_owned {
		C.close(ui_pair[1])
		ui_child_owned = false
	}
	defer { stop_child(pid) }
	frame := 'vinix-android-service-host-v1\t${entry.package_name}\t${os.args[6]}\t${os.args[7]}\t${entry.apk_sha256}\n'
	mut send_flags := i32(0)
	$if linux {
		send_flags = C.MSG_NOSIGNAL
	}
	$if macos {
		one := i32(1)
		if C.setsockopt(pair[0], C.SOL_SOCKET, C.SO_NOSIGPIPE, &one, u32(sizeof(i32))) != 0 {
			return error('cannot suppress service lifetime SIGPIPE')
		}
	}
	if C.send(pair[0], frame.str, uint(frame.len), send_flags) != frame.len {
		return error('cannot send selected service launch')
	}
	mut broker := accountbroker.create(registry, entry, int(pid), int(pair[0]))!
	root_lifetime_owned = false
	defer { broker.close() }
	if os.args.len >= 13 {
		broker.allow_interactions([accountinteraction.Target{entry.package_name, os.args[12]}])!
	}
	if ui_owned {
		broker.configure_ui(ui)!
		ui_owned = false
	}
	println('ANDROID-ACCOUNT-BROKER-LISTENING pid=${pid} clients=${client_path} service=${service_path}')
	C.fflush(unsafe { nil })
	mut attached := false
	startup_deadline := time.sys_mono_now() + 30 * time.second
	for {
		mut child_status := i32(0)
		if C.waitpid(pid, &child_status, C.WNOHANG) == pid {
			return error('selected authenticator process exited')
		}
		if !attached && time.sys_mono_now() > startup_deadline {
			return error('authenticator connection deadline expired')
		}
		mut ready := [BrokerPoll{ fd: i32(clients), events: i16(C.POLLIN) },
			BrokerPoll{ fd: i32(services), events: i16(C.POLLIN) }]!
		polled := C.poll(&ready[0], 2, 10)
		if polled < 0 && C.errno != C.EINTR { return error('broker listener poll failed') }
		for index in 0 .. 2 {
			if ready[index].revents & C.POLLIN == 0 { continue }
			fd := C.accept(ready[index].fd, unsafe { nil }, unsafe { nil })
			if fd < 0 { continue }
			if index == 1 {
				broker.attach_service(int(fd)) or {
					C.close(fd)
					continue
				}
				attached = true
				println('ANDROID-ACCOUNT-BROKER-SERVICE package=${entry.package_name} pid=${pid}')
				C.fflush(unsafe { nil })
			} else {
				broker.accept_client(int(fd)) or { C.close(fd) }
			}
		}
		broker.pump(0)!
	}
}

fn main() {
	run() or {
		eprintln('ANDROID-ACCOUNT-BROKER-FAILED ${err.msg()}')
		exit(1)
	}
}
