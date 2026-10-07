// Copyright (c) 2026 Alexander Medvednikov. All rights reserved.
// Use of this source code is governed by a GPL v2 license
// that can be found in the LICENSE file.
// SPDX-License-Identifier: GPL-2.0-or-later
// The original PID 1 writes a closed file, then the same machine resets itself.
@[translated; has_globals]
module persistfixture

#include <persistence-native-abi.h>

@[typedef]
struct C.FILE {}

@[c_extern] __global C.stdout &C.FILE
@[c_extern] __global C.errno i32

fn C.fputs(&char, &C.FILE) i32
fn C.fflush(&C.FILE) i32
fn C.setbuf(&C.FILE, voidptr)
fn C.open(&char, i32, ...) i32
fn C.dup2(i32, i32) i32
fn C.close(i32) i32
fn C.read(i32, voidptr, usize) isize
fn C.write(i32, voidptr, usize) isize
fn C.memcmp(voidptr, voidptr, usize) i32
fn C.unlink(&char) i32
fn C.sync()
fn C.reboot(i32) i32
fn C.printf(&char, ...) i32

fn say(text &char) {
	unsafe { C.fputs(text, C.stdout); C.fflush(C.stdout) }
}

@[export: 'main']
pub fn entry() i32 {
	unsafe {
		marker := &char(c'/root/hello.txt')
		payload := &char(c'vinix-reboot-persistence-v1')
		C.setbuf(C.stdout, nil)
		// ARM's console is serial; x86 exposes its serial port as com1.
		mut console := i32(-1)
		$if amd64 {
			console = C.open(c'/dev/com1', C.O_WRONLY)
		} $else {
			console = C.open(c'/dev/console', C.O_WRONLY)
		}
		if console >= 0 {
			C.dup2(console, C.STDOUT_FILENO)
			C.dup2(console, C.STDERR_FILENO)
			if console > C.STDERR_FILENO { C.close(console) }
		}
		say(c'VINIX REBOOT PERSISTENCE: START\n')
		mut fd := C.open(marker, C.O_RDONLY)
		if fd >= 0 {
			mut observed := [28]char{}
			got := C.read(fd, &observed[0], sizeof(observed))
			C.close(fd)
			if got != 27 || C.memcmp(&observed[0], payload, 27) != 0 {
				say(c'VINIX REBOOT PERSISTENCE: FAIL corrupt marker\n')
				return 1
			}
			C.unlink(marker)
			say(c'VINIX REBOOT PERSISTENCE: SYNCING\n')
			C.sync()
			say(c'VINIX REBOOT PERSISTENCE: PASS\n')
			C.reboot(C.RB_POWER_OFF)
			say(c'VINIX REBOOT PERSISTENCE: FAIL power off refused\n')
			return 1
		}
		if C.errno != C.ENOENT {
			C.printf(c'VINIX REBOOT PERSISTENCE: FAIL open errno=%d\n', C.errno)
			return 1
		}
		fd = C.open(marker, C.O_CREAT | C.O_EXCL | C.O_WRONLY, i32(0o600))
		if fd < 0 {
			C.printf(c'VINIX REBOOT PERSISTENCE: FAIL create errno=%d\n', C.errno)
			return 1
		}
		if C.write(fd, payload, 27) != 27 {
			C.printf(c'VINIX REBOOT PERSISTENCE: FAIL write errno=%d\n', C.errno)
			return 1
		}
		if C.close(fd) != 0 {
			C.printf(c'VINIX REBOOT PERSISTENCE: FAIL close errno=%d\n', C.errno)
			return 1
		}
		// No fsync/O_SYNC: preserve the buffered close, sync brackets and reboot.
		say(c'VINIX REBOOT PERSISTENCE: SYNCING\n')
		C.sync()
		say(c'VINIX REBOOT PERSISTENCE: WROTE MARKER, REBOOTING\n')
		C.reboot(C.RB_AUTOBOOT)
		C.printf(c'VINIX REBOOT PERSISTENCE: FAIL reboot returned errno=%d\n', C.errno)
		return 1
	}
}
