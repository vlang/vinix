// SPDX-License-Identifier: GPL-2.0-or-later
module sessioncore

import authclient
import accountcore
import os
import time

#include <fcntl.h>
#include <sys/file.h>

fn C.flock(int, int) int
fn C.fstat(int, &C.stat) int

fn graphical_lock() !int {
	for directory in ['/run', '/run/vinix'] {
		if !os.exists(directory) { os.mkdir(directory, mode: 0o755)! }
		info := os.lstat(directory)!
		if info.mode & 0o170000 != 0o040000 || info.uid != 0 || info.mode & 0o022 != 0 {
			return error('the authentication directory is not controlled by root')
		}
	}
	fd := C.open(c'/run/vinix/graphical-manager.lock', C.O_CREAT | C.O_RDWR | C.O_NOFOLLOW | C.O_CLOEXEC, 0o600)
	if fd < 0 { return error('cannot open the graphical manager lock') }
	info := os.lstat('/run/vinix/graphical-manager.lock') or { C.close(fd); return err }
	mut held := C.stat{}
	if C.fstat(fd, &held) != 0 || u64(held.st_dev) != info.dev || u64(held.st_ino) != info.inode
		|| info.mode & 0o170000 != 0o100000 || info.uid != 0 || info.mode & 0o077 != 0 {
		C.close(fd)
		return error('the graphical manager lock is not private to root')
	}
	if C.flock(fd, C.LOCK_EX | C.LOCK_NB) != 0 { C.close(fd); return error('a graphical manager already owns the seat') }
	return fd
}

fn run_setup(command string, arguments []string) ! {
	mut child := os.new_process(command)
	defer { child.close() }
	child.set_args(arguments)
	child.wait()
	if child.code != 0 { return error('initial account setup did not complete') }
}

fn has_person(db accountcore.Database) bool {
	for user in db.users { if accountcore.is_person(user) { return true } }
	return false
}

pub fn graphical(desktop string) ! {
	if !desktop.starts_with('/') || !os.is_executable(desktop) {
		return error('the compositor must be an installed absolute executable')
	}
	held_fd := graphical_lock()!
	defer { C.close(held_fd) }
	// Import a valid existing registration first. On a clean image no person
	// exists yet: root runs only its exclusive registration screen, then the
	// account tool imports that hash and owns the home before login begins.
	run_setup('/usr/sbin/vinix-account', ['init'])!
	mut db := load_accounts()!
	needs_registration := !has_person(db)
	db.close()
	if needs_registration {
		run_setup(desktop, ['--register-only'])!
		run_setup('/usr/sbin/vinix-account', ['init'])!
		mut initialized := load_accounts()!
		created := has_person(initialized)
		initialized.close()
		if !created { return error('no person account was created; refusing an unusable login screen') }
	}
	mut authd := os.new_process('/usr/sbin/vinix-authd')
	mut owned := false
	defer {
		if owned {
			if authd.is_alive() {
				authd.signal_term()
				deadline := time.sys_mono_now() + 2 * time.second
				for authd.is_alive() && time.sys_mono_now() < deadline { C.usleep(10_000) }
				if authd.is_alive() { authd.signal_kill() }
			}
			authd.wait()
		}
		authd.close()
	}
	if !authclient.root_service_ready(authclient.default_socket) {
		if authclient.root_service_listening(authclient.default_socket)! {
			return error('the existing root authentication service is not ready; refusing to replace it')
		}
		// A live service is reused, never unlinked by a second daemon. A stale
		// node may be replaced only within the root-owned service directory.
		if os.exists(authclient.default_socket) || os.is_link(authclient.default_socket) {
			info := os.lstat(authclient.default_socket)!
			if info.uid != 0 || info.mode & 0o170000 != 0o140000 {
				return error('refusing an untrusted authentication socket')
			}
		}
		authd.run()
		owned = true
		mut ready := false
		deadline := time.sys_mono_now() + 10 * time.second
		for time.sys_mono_now() < deadline {
			if !authd.is_alive() { break }
			if authclient.root_service_ready(authclient.default_socket) { ready = true; break }
			C.usleep(100_000)
		}
		if !ready { return error('the root authentication service did not become ready') }
	}
	run_manager(greeter: [desktop, '--greeter'], desktop: [desktop])
}
