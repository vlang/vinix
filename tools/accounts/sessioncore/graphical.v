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

fn run_setup(arguments []string, fallback []string) ! {
	environment := inherited_environment()
	defer { unsafe { environment.free() } }
	child := C.fork()
	if child < 0 { return error('cannot fork initial account setup') }
	if child == 0 {
		exec_as_fallback(accountcore.User{home: '/root'}, arguments, fallback, environment, false)
		C._exit(127)
	}
	if wait(child) != 0 { return error('initial account setup did not complete') }
}

fn has_person(db accountcore.Database) bool {
	for user in db.users { if accountcore.is_person(user) { return true } }
	return false
}

// The argument strings remain owned by the caller. The runtime must retire
// the array storage: managed arrays need not start at their allocation address.
fn retire_graphical_arguments(arguments []string) {
	unsafe { (&array(&arguments)).free() }
}

pub fn graphical(desktop string, fallback string) ! {
	if !desktop.starts_with('/') || !os.is_executable(desktop) {
		return error('the compositor must be an installed absolute executable')
	}
	if fallback != '' && (!fallback.starts_with('/') || !os.is_executable(fallback) || fallback == desktop) {
		return error('the fallback compositor must be a different installed absolute executable')
	}
	greeter_fallback := if fallback == '' { []string{} } else { [fallback, '--greeter'] }
	desktop_fallback := if fallback == '' { []string{} } else { [fallback] }
	greeter_command := [desktop, '--greeter']
	desktop_command := [desktop]
	account_command := ['/usr/sbin/vinix-account', 'init']
	// These headers borrow command strings and permanent arguments. Retire
	// only their buffers after the synchronous manager and all children finish.
	defer {
		retire_graphical_arguments(greeter_fallback)
		retire_graphical_arguments(desktop_fallback)
		retire_graphical_arguments(greeter_command)
		retire_graphical_arguments(desktop_command)
		retire_graphical_arguments(account_command)
	}
	held_fd := graphical_lock()!
	defer { C.close(held_fd) }
	// Import a valid existing registration first. On a clean image no person
	// exists yet: root runs only its exclusive registration screen, then the
	// account tool imports that hash and owns the home before login begins.
	run_setup(account_command, []string{})!
	mut db := load_accounts()!
	needs_registration := !has_person(db)
	db.close()
	if needs_registration {
		registration_fallback := if fallback == '' { []string{} } else { [fallback, '--register-only'] }
		registration_command := [desktop, '--register-only']
		defer {
			retire_graphical_arguments(registration_fallback)
			retire_graphical_arguments(registration_command)
		}
		run_setup(registration_command, registration_fallback)!
		run_setup(account_command, []string{})!
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
	run_manager(greeter: greeter_command, desktop: desktop_command,
		greeter_fallback: greeter_fallback, desktop_fallback: desktop_fallback)
}
