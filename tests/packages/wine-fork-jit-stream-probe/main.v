// SPDX-License-Identifier: GPL-2.0-or-later
// Supplemental one-fork logging probe. The canonical 32-fork probe is unchanged.
module main

import os

#include <unistd.h>
#include <fcntl.h>
#include <sys/wait.h>

fn C.fork() int
fn C.getpid() int
fn C.dup2(int, int) int
fn C.waitpid(int, &int, int) int
fn C._exit(int)
fn C.write(int, voidptr, usize) isize

fn emit(text string) {
	mut offset := 0
	for offset < text.len {
		count := C.write(2, unsafe { text.str + offset }, usize(text.len - offset))
		if count <= 0 { C._exit(90) }
		offset += int(count)
	}
}

@[noinline]
fn redirect(fd int) {
	if C.dup2(fd, 2) != 2 { C._exit(92) }
}

@[noinline]
fn child_loop() u64 {
	mut value := u64(0x9e3779b97f4a7c15) ^ 1
	for i := u64(0); i < 20001; i++ {
		value ^= value << 13
		value ^= value >> 7
		value ^= value << 17
		value += i
	}
	return value
}

@[noinline]
fn parent_loop() u64 {
	mut value := u64(0xd1b54a32d192ed03) ^ 1
	for i := u64(0); i < 30001; i++ {
		value ^= value >> 12
		value ^= value << 25
		value ^= value >> 27
		value = value * u64(0x2545f4914f6cdd1d) + i
	}
	return value
}

fn main() {
	if os.args.len != 3 { C._exit(93) }
	mut descriptors := [2]int{}
	for index, path in [os.args[2], os.args[1]] {
		descriptors[index] = C.open(path.str, C.O_WRONLY | C.O_CREAT | C.O_EXCL | C.O_NOFOLLOW, 0o600)
		if descriptors[index] < 0 { C._exit(94) }
	}
	// Compile the common helper before fork without changing stderr's destination.
	redirect(2)
	pid := C.fork()
	if pid < 0 { C._exit(95) }
	// Common straight-line redirection precedes any role-specific arithmetic.
	bits := u32(pid)
	role_index := (bits | (u32(0) - bits)) >> 31
	redirect(descriptors[role_index])
	for fd in descriptors { C.close(fd) }
	role := if pid == 0 { 'child' } else { 'parent' }
	identity := C.getpid().str()
	emit('JITSTREAM READY ' + role + ' pid=' + identity + '\n')
	if pid == 0 {
		if child_loop() != u64(0xb466aaeae3780b1c) { C._exit(96) }
		emit('JITSTREAM ARITHMETIC child PASS pid=' + identity + '\n')
		C._exit(0)
	}
	if parent_loop() != u64(0x708db3450649c883) { C._exit(97) }
	mut status := int(0)
	for {
		waited := C.waitpid(pid, &status, 0)
		if waited == pid { break }
		if waited >= 0 || C.errno != C.EINTR { C._exit(98) }
	}
	if status != 0 { C._exit(99) }
	emit('JITSTREAM ARITHMETIC parent PASS pid=' + identity + '\n')
}
