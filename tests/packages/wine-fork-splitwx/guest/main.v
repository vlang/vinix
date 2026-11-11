// SPDX-License-Identifier: GPL-2.0-or-later
module main

#include <unistd.h>
#include <sys/wait.h>
#include <grp.h>
#include <stdlib.h>
#include <signal.h>
fn C.fork() i32
fn C.waitpid(i32, &i32, i32) i32
fn C._exit(i32)
fn C.write(i32, voidptr, u64) i64
fn C.execve(&char, &&char, &&char) i32
fn C.setgroups(u64, voidptr) i32
fn C.setresgid(u32, u32, u32) i32
fn C.setresuid(u32, u32, u32) i32
fn C.usleep(u32) i32
fn C.kill(i32, i32) i32
fn C.setpgid(i32, i32) i32

fn emit(text string) {
	mut offset := 0
	for offset < text.len {
		written := C.write(1, unsafe { text.str + offset }, u64(text.len - offset))
		if written <= 0 { C._exit(90) }
		offset += int(written)
	}
}

// Runs one translator variant to completion (or a 60 s bound) and reports
// the wait status. ordinary drops to uid/gid 1000 before exec.
fn variant(name string, translator string, ordinary bool, allow_wx bool) {
	emit('FORKWX BEGIN ' + name + '\n')
	pid := C.fork()
	if pid == 0 {
		if C.setpgid(0, 0) != 0 { C._exit(121) }
		if ordinary {
			if C.setgroups(0, unsafe { nil }) != 0 || C.setresgid(1000, 1000, 1000) != 0
				|| C.setresuid(1000, 1000, 1000) != 0 { C._exit(124) }
		}
		args := [translator, '-B', '0x100000000', '/fork-probe']!
		mut argv := unsafe { [5]&char{} }
		for index, argument in args { argv[index] = &char(argument.str) }
		env := if allow_wx { 'VINIX_ALLOW_WX=1' } else { 'VINIX_FORKWX=0' }
		mut envp := unsafe { [2]&char{} }
		envp[0] = &char(env.str)
		C.execve(argv[0], &argv[0], &envp[0])
		C._exit(122)
	}
	mut status := i32(0)
	mut waited := false
	for _ in 0 .. 6000 {
		if C.waitpid(pid, unsafe { &status }, C.WNOHANG) == pid { waited = true; break }
		C.usleep(10000)
	}
	C.kill(-pid, 9)
	if !waited { C.waitpid(pid, unsafe { &status }, 0) }
	for _ in 0 .. 100 {
		mut other := i32(0)
		if C.waitpid(-1, unsafe { &other }, C.WNOHANG) <= 0 { break }
	}
	emit('FORKWX RESULT ' + name + ' waited=' + waited.str() + ' status=' + status.str() + '\n')
}

fn main() {
	emit('HWTEST START forkwx\n')
	// Stock translator, W+X allowed (root with CAP_SYS_ADMIN may request it).
	variant('root-stock-allowwx', '/qemu-stock', false, true)
	// Forced split RW/RX translator, same root identity, no W+X exception.
	variant('root-splitwx', '/qemu-x86_64', false, false)
	// The original failing configuration: ordinary account, split RW/RX.
	variant('user-splitwx', '/qemu-x86_64', true, false)
	emit('FORKWX DONE\n')
	for { C.usleep(1000000) }
}
