// SPDX-License-Identifier: GPL-2.0-or-later
// Linux/Vinix root fixture for the native account caller boundary. No ART/GMS.
module main

import crypto.sha256
import nativeaccountauth
import net as _
import os
import time

#include <grp.h>
#include <signal.h>
#include <poll.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/un.h>
#include <sys/wait.h>
#include <unistd.h>

$if linux {
	fn C.setresgid(u32, u32, u32) i32
	fn C.setresuid(u32, u32, u32) i32
	#flag -D_GNU_SOURCE
}

fn C.getuid() u32
fn C.geteuid() u32
fn C.getpid() i32
fn C.fork() i32
fn C.setgroups(uint, voidptr) i32
fn C.close(i32) i32
fn C.poll(&C.pollfd, uint, i32) i32
fn C.write(i32, voidptr, uint) int
fn C.waitpid(i32, &i32, i32) i32
fn C.kill(i32, i32) i32
fn C._exit(i32)

fn check(condition bool, stage string) ! {
	if !condition { return error('account authority fixture: ' + stage) }
}

fn expect_load_failure(path string, stage string) ! {
	mut rejected := false
	nativeaccountauth.load(path) or { rejected = true }
	check(rejected, stage)!
}

fn record(package string, uid string, apk string, digest string) string {
	return [package, uid, uid, apk, digest, 'b'.repeat(64), '-'].join('\t') + '\n'
}

fn socket_address(path string) !C.sockaddr_un {
	mut address := C.sockaddr_un{}
	check(path.len < address.sun_path.len, 'socket path length')!
	address.sun_family = C.AF_UNIX
	unsafe { vmemcpy(&address.sun_path[0], path.str, path.len) }
	return address
}

fn child_connect(path string) {
	$if linux {
		if C.setgroups(0, unsafe { nil }) != 0 || C.setresgid(10000, 10000, 10000) != 0
			|| C.setresuid(10000, 10000, 10000) != 0 { C._exit(2) }
		address := socket_address(path) or { C._exit(3); return }
		fd := C.socket(C.AF_UNIX, C.SOCK_STREAM, 0)
		if fd < 0 { C._exit(4) }
		if C.connect(fd, voidptr(&address), u32(sizeof(C.sockaddr_un))) != 0 { C._exit(5) }
		byte := u8(1)
		if C.write(fd, &byte, 1) != 1 { C._exit(6) }
		C.close(fd)
		C._exit(0)
	}
}

fn peer_case(registry nativeaccountauth.Registry, root string) ! {
	socket_path := root + '/broker'
	address := socket_address(socket_path)!
	fd := C.socket(C.AF_UNIX, C.SOCK_STREAM, 0)
	check(fd >= 0, 'listener')!
	defer { C.close(fd) }
	check(C.bind(fd, voidptr(&address), u32(sizeof(C.sockaddr_un))) == 0, 'bind')!
	os.chmod(socket_path, 0o666)!
	check(C.listen(fd, 1) == 0, 'listen')!
	child := C.fork()
	check(child >= 0, 'fork')!
	if child == 0 { C.close(fd); child_connect(socket_path); C._exit(7) }
	mut status := i32(-1)
	mut reaped := false
	defer {
		if !reaped {
			// The unreaped child cannot have its PID recycled. Terminate only
			// this fixture's child, with a bounded reap loop for guest failures.
			C.kill(child, C.SIGKILL)
			deadline := time.now().unix_milli() + 1000
			mut cleaned := false
			for !cleaned && time.now().unix_milli() < deadline {
				cleaned = C.waitpid(child, &status, C.WNOHANG) == child
				time.sleep(10 * time.millisecond)
			}
		}
	}
	mut readiness := C.pollfd{fd: i32(fd), events: C.POLLIN}
	check(C.poll(&readiness, 1, 5000) == 1 && readiness.revents & C.POLLIN != 0, 'child connect deadline')!
	connection := C.accept(fd, unsafe { nil }, unsafe { nil })
	check(connection >= 0, 'accept')!
	defer { C.close(connection) }
	caller := registry.authenticate(connection, nativeaccountauth.Claims{})!
	check(caller.uid == 10000 && caller.gid == 10000 && caller.pid == int(child)
		&& caller.package_name == 'org.vinix.authority.client', 'kernel child identity')!
	for claims in [nativeaccountauth.Claims{package_name: 'org.vinix.authority.auth'},
		nativeaccountauth.Claims{uid: 10001}, nativeaccountauth.Claims{uid: 0},
		nativeaccountauth.Claims{pid: int(C.getpid())}] {
		mut rejected := false
		registry.authenticate(connection, claims) or { rejected = true }
		check(rejected, 'forged package or UID or PID')!
	}
	deadline := time.now().unix_milli() + 5000
	for time.now().unix_milli() < deadline {
		if C.waitpid(child, &status, C.WNOHANG) == child { reaped = true; break }
		time.sleep(10 * time.millisecond)
	}
	check(reaped && status == 0, 'child clean exit')!
}

fn run() ! {
	$if !linux { return error('account authority fixture requires Linux/Vinix') }
	check(C.getuid() == 0 && C.geteuid() == 0, 'root fixture launcher')!
	root := '/vinix-account-authority-fixture-${C.getpid()}'
	check(!os.exists(root), 'fresh root')!
	os.mkdir(root, mode: 0o755)!
	defer { os.rmdir_all(root) or {} }
	apk := root + '/client.apk'
	auth := root + '/auth.apk'
	registry_path := root + '/registry'
	os.write_file(apk, 'synthetic client; no signed APK or account')!
	os.write_file(auth, 'synthetic authenticator; no signed APK or account')!
	for path in [apk, auth] { os.chmod(path, 0o444)! }
	apk_digest := sha256.sum(os.read_bytes(apk)!).hex()
	text := 'vinix-android-account-authority-v1\n' +
		record('org.vinix.authority.client', '10000', apk, apk_digest) +
		record('org.vinix.authority.auth', '10001', auth, sha256.sum(os.read_bytes(auth)!).hex())
	os.write_file(registry_path, text)!
	os.chmod(registry_path, 0o444)!
	registry := nativeaccountauth.load(registry_path)!
	entry := registry.verify_launch(apk, 10000, 10000)!
	check(entry.package_name == 'org.vinix.authority.client', 'protected launch')!
	mut rejected := false
	registry.verify_launch(apk, 10001, 10001) or { rejected = true }
	check(rejected, 'different registered UID cannot claim APK')!
	os.chmod(registry_path, 0o644)!
	expect_load_failure(registry_path, 'writable registry')!
	os.chmod(registry_path, 0o444)!
	os.chmod(apk, 0o644)!
	expect_load_failure(registry_path, 'writable APK')!
	os.chmod(apk, 0o444)!
	os.chmod(root, 0o777)!
	expect_load_failure(registry_path, 'writable ancestor')!
	os.chmod(root, 0o755)!
	alias := root + '/alias'
	os.symlink(root, alias)!
	expect_load_failure(alias + '/registry', 'ancestor symlink')!
	os.rm(alias)!
	os.symlink(registry_path, alias)!
	expect_load_failure(alias, 'registry symlink')!
	os.rm(alias)!
	check(C.link(apk.str, alias.str) == 0, 'hard link setup')!
	expect_load_failure(registry_path, 'APK hardlink')!
	os.rm(alias)!
	os.chmod(apk, 0o644)!
	os.write_file(apk, 'different synthetic bytes')!
	os.chmod(apk, 0o444)!
	expect_load_failure(registry_path, 'APK digest mismatch')!
	os.chmod(apk, 0o644)!
	os.write_file(apk, 'synthetic client; no signed APK or account')!
	os.chmod(apk, 0o444)!
	check(C.chown(apk.str, 10000, 10000) == 0, 'untrusted owner setup')!
	expect_load_failure(registry_path, 'untrusted APK owner')!
	check(C.chown(apk.str, 0, 0) == 0, 'restore owner')!
	peer_case(registry, root)!
	println('ACCOUNT-AUTHORITY-PASS protected-launch wrong-uid writable-registry writable-apk writable-ancestor ancestor-symlink file-symlink hardlink digest owner unix-peer child-uid forged-package forged-uid forged-pid no-account-dispatch')
}

fn main() {
	run() or {
		eprintln(err)
		exit(1)
	}
}
