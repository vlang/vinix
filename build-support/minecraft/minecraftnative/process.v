// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module minecraftnative

import os
import time

#include <signal.h>
#include <stdlib.h>
#include <unistd.h>
#include <fcntl.h>
#include <sys/wait.h>
#include <errno.h>
#flag -I @DIR
#include "spawn_abi.h"

fn C.signal(i32, voidptr) voidptr
fn C.__atomic_store_n(&i32, i32, i32)
fn C.__atomic_load_n(&i32, i32) i32
fn C.mkdtemp(&char) &char
fn C.posix_spawnp(&i32, &char, voidptr, voidptr, &&char, &&char) i32
fn C.posix_spawn_file_actions_init(voidptr) i32
fn C.posix_spawn_file_actions_destroy(voidptr) i32
fn C.posix_spawn_file_actions_adddup2(voidptr, i32, i32) i32
fn C.posix_spawn_file_actions_addclose(voidptr, i32) i32
fn C.posix_spawn_file_actions_addopen(&C.posix_spawn_file_actions_t, i32, &char, i32, u32) i32
fn C.posix_spawnattr_init(&C.posix_spawnattr_t) i32
fn C.posix_spawnattr_destroy(&C.posix_spawnattr_t) i32
fn C.posix_spawnattr_setpgroup(&C.posix_spawnattr_t, i32) i32
fn C.posix_spawnattr_setsigdefault(&C.posix_spawnattr_t, voidptr) i32
fn C.posix_spawnattr_setflags(&C.posix_spawnattr_t, i16) i32
fn C.waitpid(i32, &i32, i32) i32
fn C.WIFEXITED(i32) i32
fn C.WEXITSTATUS(i32) i32
fn C.killpg(i32, i32) i32

@[typedef]
struct C.posix_spawn_file_actions_t {}

@[typedef]
struct C.posix_spawnattr_t {}

@[typedef]
struct C.sigset_t {}

__global minecraft_signal i32

fn interrupted(signal i32) {
	unsafe { C.__atomic_store_n(&minecraft_signal, signal, C.__ATOMIC_RELAXED) }
}

struct SignalGuard {
	interrupt voidptr
	terminate voidptr
	pipe      voidptr
}

fn own_commands() SignalGuard {
	unsafe { C.__atomic_store_n(&minecraft_signal, 0, C.__ATOMIC_RELAXED) }
	return SignalGuard{unsafe { C.signal(C.SIGINT, voidptr(interrupted)) }, unsafe { C.signal(C.SIGTERM, voidptr(interrupted)) }, unsafe { C.signal(C.SIGPIPE, C.SIG_IGN) }}
}

fn (guard SignalGuard) close() {
	unsafe {
		C.signal(C.SIGINT, guard.interrupt)
		C.signal(C.SIGTERM, guard.terminate)
		C.signal(C.SIGPIPE, guard.pipe)
	}
}

fn interrupt_status() int {
	signal := unsafe { C.__atomic_load_n(&minecraft_signal, C.__ATOMIC_RELAXED) }
	return if signal == 0 { 0 } else { 128 + int(signal) }
}

fn command_checkpoint() ! {
	if interrupt_status() != 0 {
		return error_with_code('Minecraft fetch interrupted', interrupt_status())
	}
}

fn ensure_directory(path string) ! {
	if os.is_dir(path) { return }
	parent := os.dir(path)
	if parent != path { ensure_directory(parent)! }
	// Each ancestor is complete before creating its child. A simultaneous
	// worker may win mkdir; only an existing directory is a successful race.
	os.mkdir(path) or { if !os.is_dir(path) { return err } }
}

fn temporary(parent string, prefix string) !string {
	ensure_directory(parent)!
	mut template := (os.join_path(parent, prefix + 'XXXXXX') + '\x00').bytes()
	defer { unsafe { template.free() } }
	if isnil(C.mkdtemp(&char(template.data))) {
		return error('Cannot create private Minecraft directory: ' + os.get_error_msg(int(C.errno)))
	}
	return template[..template.len - 1].bytestr().clone()
}

fn retire(path string) { os.rmdir_all(path) or {} }

fn checked_spawn(status i32) ! {
	if status != 0 { return error(os.get_error_msg(int(status))) }
}

// Every curl owns a process group and a private log. There are no inherited
// worker pipes, no glibc-only spawn extensions and no fork in a threaded V
// process. Cancellation kills the group and reaps its child before cleanup.
fn command(argv []string, log string) ! {
	command_checkpoint()!
	if argv.len == 0 || argv.any(it.contains('\x00')) { return error('Invalid curl arguments') }
	mut fd := C.open(log.str, C.O_WRONLY | C.O_CREAT | C.O_EXCL | C.O_CLOEXEC, 0o600)
	if fd < 0 { return error('Cannot create curl log') }
	if fd < 3 {
		moved := C.fcntl(fd, C.F_DUPFD_CLOEXEC, 3)
		C.close(fd)
		if moved < 0 { return error('Cannot move curl log descriptor') }
		fd = moved
	}
	defer { C.close(fd) }
	mut actions := C.posix_spawn_file_actions_t{}
	checked_spawn(C.posix_spawn_file_actions_init(&actions))!
	defer { C.posix_spawn_file_actions_destroy(&actions) }
	checked_spawn(C.posix_spawn_file_actions_addopen(&actions, 0, c'/dev/null', C.O_RDONLY, 0))!
	checked_spawn(C.posix_spawn_file_actions_adddup2(&actions, fd, 1))!
	checked_spawn(C.posix_spawn_file_actions_adddup2(&actions, fd, 2))!
	if fd > 2 { checked_spawn(C.posix_spawn_file_actions_addclose(&actions, fd))! }
	mut attributes := C.posix_spawnattr_t{}
	checked_spawn(C.posix_spawnattr_init(&attributes))!
	defer { C.posix_spawnattr_destroy(&attributes) }
	checked_spawn(C.posix_spawnattr_setpgroup(&attributes, 0))!
	$if darwin {
		mut defaults := u32(0)
		C.sigemptyset(&defaults)
		C.sigaddset(&defaults, C.SIGPIPE)
		checked_spawn(C.posix_spawnattr_setsigdefault(&attributes, &defaults))!
	} $else {
		mut defaults := C.sigset_t{}
		C.sigemptyset(&defaults)
		C.sigaddset(&defaults, C.SIGPIPE)
		checked_spawn(C.posix_spawnattr_setsigdefault(&attributes, &defaults))!
	}
	mut flags := C.POSIX_SPAWN_SETPGROUP | C.POSIX_SPAWN_SETSIGDEF
	$if darwin {
		flags |= C.POSIX_SPAWN_CLOEXEC_DEFAULT
	}
	checked_spawn(C.posix_spawnattr_setflags(&attributes, i16(flags)))!
	mut arguments := []&char{cap: argv.len + 1}
	defer { unsafe { arguments.free() } }
	for value in argv { arguments << &char(value.str) }
	arguments << &char(unsafe { nil })
	mut pid := i32(0)
	checked_spawn(C.posix_spawnp(&pid, argv[0].str, &actions, &attributes, arguments.data, unsafe { &&char(C.environ) }))!
	mut reaped := false
	defer {
		if !reaped {
			C.killpg(pid, C.SIGKILL)
			C.kill(pid, C.SIGKILL)
			mut status := i32(0)
			for {
				result := C.waitpid(pid, &status, 0)
				if result == pid || (result < 0 && C.errno != C.EINTR) { break }
			}
		}
	}
	mut status := i32(0)
	for {
		command_checkpoint()!
		result := C.waitpid(pid, &status, C.WNOHANG)
		if result == pid {
			reaped = true
			break
		}
		if result < 0 && C.errno != C.EINTR { return error('Cannot reap curl') }
		time.sleep(10 * time.millisecond)
	}
	command_checkpoint()!
	if C.WIFEXITED(status) == 0 || C.WEXITSTATUS(status) != 0 {
		mut stream := os.open(log)!
		detail := stream.read_bytes(16384).bytestr()
		stream.close()
		return error(detail.trim_space())
	}
}
