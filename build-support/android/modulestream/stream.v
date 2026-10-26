// SPDX-License-Identifier: GPL-2.0-or-later
module modulestream

import os

#include "@VMODROOT/spawn_abi.h"
#include <sys/wait.h>
#include <errno.h>
#include <signal.h>
#include <fcntl.h>

@[typedef]
struct C.posix_spawn_file_actions_t {}

fn C.posix_spawn_file_actions_init(voidptr) i32
fn C.posix_spawn_file_actions_destroy(voidptr) i32
fn C.posix_spawn_file_actions_adddup2(voidptr, i32, i32) i32
fn C.posix_spawn_file_actions_addclose(voidptr, i32) i32
fn C.posix_spawnp(&i32, &char, voidptr, voidptr, &&char, &&char) i32
fn C.waitpid(i32, &i32, i32) i32
fn C.WIFEXITED(i32) i32
fn C.WEXITSTATUS(i32) i32
fn C.WTERMSIG(i32) i32
fn C.kill(i32, i32) i32

pub struct Statuses {
pub:
	producer int
	consumer int
}

pub struct HashResult {
pub:
	sha256   string
	statuses Statuses
}

fn spawn_child(arguments []string, read_fd int, write_fd int, pipe_fds []int) !i32 {
	if arguments.len == 0 || arguments.any(it.contains('\x00')) {
		return error('invalid stream command')
	}
	mut actions := C.posix_spawn_file_actions_t{}
	initialized := C.posix_spawn_file_actions_init(&actions)
	if initialized != 0 { return error('stream spawn actions: ' + os.get_error_msg(initialized)) }
	defer { C.posix_spawn_file_actions_destroy(&actions) }
	for pair in [[read_fd, 0], [write_fd, 1]] {
		if pair[0] < 0 { continue }
		status := C.posix_spawn_file_actions_adddup2(&actions, i32(pair[0]), i32(pair[1]))
		if status != 0 { return error('stream redirect: ' + os.get_error_msg(status)) }
	}
	for descriptor in pipe_fds {
		status := C.posix_spawn_file_actions_addclose(&actions, i32(descriptor))
		if status != 0 { return error('stream close action: ' + os.get_error_msg(status)) }
	}
	mut argv := []&char{cap: arguments.len + 1}
	for argument in arguments { argv << &char(argument.str) }
	argv << &char(unsafe { nil })
	mut environment := []string{}
	for key, value in os.environ() { environment << key + '=' + value }
	mut envp := []&char{cap: environment.len + 1}
	for item in environment { envp << &char(item.str) }
	envp << &char(unsafe { nil })
	mut pid := i32(0)
	status := C.posix_spawnp(&pid, &char(arguments[0].str), &actions, unsafe { nil }, argv.data, envp.data)
	if status != 0 {
		return error('stream spawn ' + arguments[0] + ': ' + os.get_error_msg(status))
	}
	return pid
}

fn wait_child(pid i32) !int {
	mut status := i32(0)
	for C.waitpid(pid, &status, 0) < 0 {
		if C.errno != C.EINTR { return error('stream wait: ' + os.get_error_msg(C.errno)) }
	}
	return if C.WIFEXITED(status) != 0 {
		int(C.WEXITSTATUS(status))
	} else {
		128 + int(C.WTERMSIG(status))
	}
}

// Diagnostics inherit the parent's descriptors, so neither child can block on
// an undrained diagnostic pipe. Always reap both children, including spawn errors.
fn commands(producer []string, consumer []string) !Statuses {
	return commands_to(producer, consumer, -1)
}

fn commands_to(producer []string, consumer []string, output_fd int) !Statuses {
	mut pipe := os.pipe()!
	defer { pipe.close() }
	if pipe.read_fd < 3 || pipe.write_fd < 3 {
		return error('stream requires open standard descriptors')
	}
	mut descriptors := [pipe.read_fd, pipe.write_fd]
	if output_fd >= 0 {
		if output_fd < 3 { return error('stream requires a separate output descriptor') }
		descriptors << output_fd
	}
	producer_pid := spawn_child(producer, -1, pipe.write_fd, descriptors)!
	mut producer_reaped := false
	defer {
		if !producer_reaped {
			C.kill(producer_pid, C.SIGKILL)
			wait_child(producer_pid) or {}
		}
	}
	consumer_pid := spawn_child(consumer, pipe.read_fd, output_fd, descriptors)!
	mut consumer_reaped := false
	defer {
		if !consumer_reaped {
			C.kill(consumer_pid, C.SIGKILL)
			wait_child(consumer_pid) or {}
		}
	}
	pipe.close()
	producer_status := wait_child(producer_pid)!
	producer_reaped = true
	consumer_status := wait_child(consumer_pid)!
	consumer_reaped = true
	return Statuses{ producer: producer_status, consumer: consumer_status }
}

fn fat_member(member string) !string {
	if member.len == 0 || member.len > 255 || member in ['.', '..']
		|| !member.bytes().all((it >= `a` && it <= `z`) || (it >= `A` && it <= `Z`)
			|| (it >= `0` && it <= `9`) || it in [`_`, `-`, `.`]) {
		return error('stream requires a literal FAT member basename')
	}
	return '::/boot/' + member
}

// extract_member streams the exact binary FAT member into tar without a host
// archive. Diagnostics inherit the parent's descriptors. The destination may
// contain partial extraction on failure; callers must check BOTH child statuses.
pub fn extract_member(boot_image string, member string, destination string) !Statuses {
	return commands(['mcopy', '-i', boot_image, fat_member(member)!, '-'],
		['/usr/bin/tar', '-xf', '-', '-C', destination])
}

// hash_member streams the exact binary FAT member into shasum. Only its small
// stdout receipt is retained at a fresh output path; diagnostics remain inherited.
// Both child statuses are returned on command failure, with an empty sha256.
// Setup/spawn/invalid-success-output errors are returned after children are reaped.
pub fn hash_member(boot_image string, member string, output_path string) !HashResult {
	path := fat_member(member)!
	if output_path.contains('\x00') { return error('invalid stream output path') }
	output_fd := C.open(output_path.str, C.O_WRONLY | C.O_CREAT | C.O_EXCL | C.O_CLOEXEC, 0o600)
	if output_fd < 0 { return error('stream output: ' + os.get_error_msg(C.errno)) }
	defer { os.fd_close(output_fd) }
	statuses := commands_to(['mcopy', '-i', boot_image, path, '-'],
		['/usr/bin/shasum', '-a', '256'], output_fd)!
	if statuses.producer != 0 || statuses.consumer != 0 { return HashResult{ statuses: statuses } }
	output := os.read_file(output_path)!
	if output.len != 68 || output[64..] != '  -\n'
		|| !output[..64].bytes().all((it >= `0` && it <= `9`) || (it >= `a` && it <= `f`)) {
		return error('invalid stream SHA-256 receipt')
	}
	return HashResult{ sha256: output[..64], statuses: statuses }
}

// copy streams a ustar module into the FAT boot image without a temporary tar.
// A failed copy may leave a partial module: callers must not boot that image
// until another copy succeeds. Success requires both tar and mcopy to succeed.
pub fn copy(module_root string, boot_image string) ! {
	result := commands(['tar', '--format=ustar', '-b', '1', '-cf', '-', '-C', module_root, '.'],
		['mcopy', '-o', '-i', boot_image, '-', '::/boot/qemu-runtime.tar'])!
	println('MODULE-STREAM producer=' + result.producer.str() + ' consumer=' + result.consumer.str())
	if result.producer != 0 || result.consumer != 0 {
		return error('module stream failed: tar=' + result.producer.str() + ' mcopy=' + result.consumer.str())
	}
}
