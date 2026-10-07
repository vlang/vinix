// SPDX-License-Identifier: GPL-2.0-only
// Native applications exercise the installed init's process and exec policy.
@[translated; has_globals]
module guestfixture

#include <guest-native-abi.h>

@[typedef] struct C.FILE {}
struct C.vinix_init_guest_signal_word { mut: value i32 }
@[c_extern] __global C.stdout &C.FILE
@[c_extern] __global C.errno i32
__global reloaded C.vinix_init_guest_signal_word
const shell_lines = [&char(c'hello\n'), &char(c'uname\n'), &char(c'echo SHELL INIT GUEST: PASS\n')]!

fn C.printf(&char, ...) i32
fn C.fflush(&C.FILE) i32
fn C.puts(&char) i32
fn C.pause() i32
fn C.pipe(&i32) i32
fn C.fork() i32
fn C.close(i32) i32
fn C.usleep(u32) i32
fn C.write(i32, voidptr, usize) isize
fn C.read(i32, voidptr, usize) isize
fn C.strlen(&char) usize
fn C.strcmp(&char, &char) i32
fn C.execv(&char, &&char) i32
fn C.dup2(i32, i32) i32
fn C.getpid() i32
fn C.getppid() i32
fn C.getpgrp() i32
fn C.getenv(&char) &char
fn C.fcntl(i32, i32, ...) i32
fn C.setvbuf(&C.FILE, voidptr, i32, usize) i32
fn C.signal(i32, fn (i32)) fn (i32)
fn C.kill(i32, i32) i32
fn C.open(&char, i32, ...) i32
fn C._exit(i32)

fn fail(message &char) {
	unsafe { C.printf(c'INIT GUEST FAIL: %s errno=%d\n', message, C.errno); C.fflush(C.stdout) }
	for { C.pause() }
}

fn require(ok bool, message &char) {
	if !ok { fail(message) }
}

fn shell_entry() i32 {
	unsafe {
		mut input := [2]i32{}
		require(C.pipe(&input[0]) == 0, c'shell pipe')
		writer := C.fork()
		require(writer >= 0, c'shell writer')
		if writer == 0 {
			C.close(input[0]); C.usleep(100000)
			for i := usize(0); i < sizeof(shell_lines) / sizeof(shell_lines[0]); i++ {
				line := &char(shell_lines[i])
				require(C.write(input[1], line, C.strlen(line)) == isize(C.strlen(line)), c'shell input')
				C.usleep(100000)
			}
			for { C.pause() }
		}
		C.close(input[1])
		require(C.dup2(input[0], 0) == 0, c'shell stdin')
		if input[0] != 0 { C.close(input[0]) }
		mut args := [&char(c'/shell-init'), &char(nil)]!
		C.execv(args[0], &args[0])
		fail(c'shell exec')
		return 1
	}
}

fn full_entry(argc i32, argv &&char) i32 {
	unsafe {
		require(C.getpid() == 1 && argc == 3, c'full PID1 argv')
		require(C.strcmp(argv[0], c'/bin/busybox') == 0 && C.strcmp(argv[1], c'sh') == 0 && C.strcmp(argv[2], c'/etc/vinix-boot-test.sh') == 0, c'full command')
		require(C.strcmp(C.getenv(c'PATH'), c'/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin') == 0 && C.strcmp(C.getenv(c'HOME'), c'/root') == 0 && C.strcmp(C.getenv(c'TERM'), c'linux') == 0, c'full environment')
		require(C.fcntl(0, C.F_GETFD) >= 0 && C.fcntl(1, C.F_GETFD) >= 0 && C.fcntl(2, C.F_GETFD) >= 0, c'full console descriptors')
		C.puts(c'FULL INIT GUEST: PASS'); C.fflush(C.stdout)
		for { C.pause() }
	}
}

fn reload(signo i32) { unsafe { reloaded.value = signo } }

fn closing(signo i32) {
	unsafe {
		fd := C.open(c'/run/child-closed', C.O_WRONLY | C.O_CREAT | C.O_TRUNC, i32(0o600))
		if fd >= 0 {
			byte := char(`1`); C.write(fd, &byte, 1); C.close(fd)
		}
		C._exit(0)
	}
}

fn phase_write(phase i32) {
	unsafe {
		fd := C.open(c'/run/init-phase', C.O_WRONLY | C.O_CREAT | C.O_TRUNC, i32(0o600))
		require(fd >= 0, c'phase open')
		byte := char(i32(`0`) + phase)
		require(C.write(fd, &byte, 1) == 1, c'phase write')
		C.close(fd)
	}
}

fn desktop_entry(argc i32, argv &&char) i32 {
	unsafe {
		C.setvbuf(C.stdout, nil, C._IONBF, 0)
		require(argc == 1 && C.strcmp(argv[0], c'/usr/bin/vinix-desktop') == 0, c'desktop args')
		require(C.getppid() == 1 && C.getpgrp() == C.getpid(), c'desktop owner/group')
		require(C.getenv(c'VINIX_SYSTEM_SESSION') != nil && C.strcmp(C.getenv(c'VINIX_SYSTEM_SESSION'), c'1') == 0, c'desktop environment')
		require(C.fcntl(0, C.F_GETFD) >= 0 && C.fcntl(1, C.F_GETFD) >= 0 && C.fcntl(2, C.F_GETFD) >= 0, c'desktop console descriptors')
		mut fd := C.open(c'/run/init-phase', C.O_RDONLY)
		mut byte := char(`0`)
		if fd >= 0 { require(C.read(fd, &byte, 1) == 1, c'phase read'); C.close(fd) }
		if byte == `0` {
			require(voidptr(C.signal(C.SIGHUP, reload)) != voidptr(C.SIG_ERR), c'reload handler')
			phase_write(1)
			require(C.kill(1, C.SIGHUP) == 0, c'reload request')
			for reloaded.value == 0 { C.pause() }
			require(reloaded.value == C.SIGHUP, c'reload forwarded')
			C.puts(c'DESKTOP RELOAD FORWARDED: PASS')
			return 0
		}
		if byte == `1` {
			C.puts(c'DESKTOP RESTART: PASS'); phase_write(2)
			mut ready := [2]i32{}
			require(C.pipe(&ready[0]) == 0, c'orphan gate')
			mut child := C.fork()
			require(child >= 0, c'desktop child')
			if child == 0 {
				C.close(ready[0])
				require(voidptr(C.signal(C.SIGTERM, closing)) != voidptr(C.SIG_ERR), c'child signal')
				mark := char(`1`); C.write(ready[1], &mark, 1); C.close(ready[1])
				for { C.pause() }
			}
			C.close(ready[1])
			require(C.read(ready[0], &byte, 1) == 1, c'child ready'); C.close(ready[0])
			fd = C.open(c'/run/child-pid', C.O_WRONLY | C.O_CREAT | C.O_TRUNC, i32(0o600))
			require(fd >= 0, c'child pid open')
			require(C.write(fd, &child, sizeof(child)) == isize(sizeof(child)), c'child pid write'); C.close(fd)
			require(C.kill(C.getpid(), C.SIGTERM) == 0, c'desktop signal exit')
			for { C.pause() }
		}
		require(byte == `2`, c'desktop restart phase')
		fd = C.open(c'/run/child-closed', C.O_RDONLY); require(fd >= 0, c'orphan group terminated'); C.close(fd)
		fd = C.open(c'/run/child-pid', C.O_RDONLY); require(fd >= 0, c'orphan pid open')
		mut child := i32(0)
		require(C.read(fd, &child, sizeof(child)) == isize(sizeof(child)), c'orphan pid read'); C.close(fd)
		C.errno = 0
		require(C.kill(child, 0) < 0 && C.errno == C.ESRCH, c'orphan reaped before restart')
		C.puts(c'DESKTOP INIT GUEST: PASS')
		for { C.pause() }
	}
}

@[export: 'main']
pub fn entry(argc i32, argv &&char) i32 {
	$if init_shell_driver ? { return shell_entry() }
	$else $if init_full_program ? { return full_entry(argc, argv) }
	$else { return desktop_entry(argc, argv) }
}
