// SPDX-License-Identifier: GPL-2.0-or-later
module jitfixture

#include <errno.h>
#include <fcntl.h>
#include <grp.h>
#include <stdio.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/mount.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <unistd.h>

fn C.open(&char, i32, ...) i32
fn C.read(i32, voidptr, usize) isize
fn C.write(i32, voidptr, usize) isize
fn C.close(i32) i32
fn C.mkdir(&char, u32) i32
fn C.chmod(&char, u32) i32
fn C.mount(&char, &char, &char, usize, voidptr) i32
fn C.fork() i32
fn C.execve(&char, &&char, &&char) i32
fn C.waitpid(i32, &i32, i32) i32
fn C.WIFEXITED(i32) bool
fn C.WEXITSTATUS(i32) i32
fn C.setgroups(usize, voidptr) i32
fn C.setgid(u32) i32
fn C.setuid(u32) i32
fn C.getuid() u32
fn C.getgid() u32
fn C.geteuid() u32
fn C.getegid() u32
fn C.__errno_location() &i32
fn C._exit(i32)
fn C.strcmp(&char, &char) i32
fn C.mmap(voidptr, usize, i32, i32, i32, i64) voidptr
fn C.mprotect(voidptr, usize, i32) i32
fn C.munmap(voidptr, usize) i32
fn C.puts(&char) i32
fn C.printf(&char, ...) i32
fn C.fflush(voidptr) i32
fn C.pause() i32

fn copy_probe(target &char) bool {
	unsafe {
		input := C.open(c'/sbin/init', C.O_RDONLY)
		output := C.open(target, C.O_WRONLY | C.O_CREAT | C.O_EXCL, u32(0o755))
		if input < 0 || output < 0 { return false }
		defer { C.close(input); C.close(output) }
		mut buffer := [4096]u8{}
		for {
			n := C.read(input, &buffer[0], sizeof(buffer))
			if n < 0 { return false }
			if n == 0 { return true }
			mut written := isize(0)
			for written < n {
				amount := C.write(output, &buffer[written], usize(n - written))
				if amount <= 0 { return false }
				written += amount
			}
		}
	}
	return false
}

fn child_result(path &char, request bool) i32 {
	unsafe {
		child := C.fork()
		if child < 0 { return 255 }
		if child == 0 {
			if C.setgroups(0, nil) != 0 || C.setgid(1000) != 0 || C.setuid(1000) != 0 { C._exit(254) }
			mut arguments := [3]&char{}
			arguments[0] = path
			arguments[1] = if request { c'--wx' } else { c'--default' }
			mut environment := [2]&char{}
			if request { environment[0] = c'VINIX_ALLOW_WX=1' }
			C.execve(path, &arguments[0], &environment[0])
			C._exit(*C.__errno_location())
		}
		mut status := i32(0)
		if C.waitpid(child, &status, 0) != child || !C.WIFEXITED(status) { return 255 }
		return C.WEXITSTATUS(status)
	}
}

fn probe(allowed bool) i32 {
	unsafe {
		if C.getuid() != 1000 || C.getgid() != 1000 || C.geteuid() != 1000 || C.getegid() != 1000 { return 10 }
		if C.mount(c'none', c'/jit/runtime', nil, usize(C.MS_REMOUNT | C.MS_BIND), c'wxallowed') != -1
			|| *C.__errno_location() != C.EPERM { return 11 }
		file := C.open(c'/jit/runtime/writable', C.O_WRONLY)
		if file >= 0 { C.close(file); return 12 }
		if *C.__errno_location() != C.EROFS { return 13 }
		page := usize(16384)
		flags := C.MAP_PRIVATE | C.MAP_ANONYMOUS
		mapping := C.mmap(nil, page, C.PROT_READ | C.PROT_WRITE | C.PROT_EXEC, flags, -1, 0)
		if allowed {
			if mapping == voidptr(isize(-1)) { return 14 }
			*&u64(mapping) = u64(0x1122334455667788)
			if *&u64(mapping) != u64(0x1122334455667788) || C.munmap(mapping, page) != 0 { return 15 }
		} else if mapping != voidptr(isize(-1)) || *C.__errno_location() != C.EOPNOTSUPP { return 16 }
		writable := C.mmap(nil, page, C.PROT_READ | C.PROT_WRITE, flags, -1, 0)
		if writable == voidptr(isize(-1)) { return 17 }
		result := C.mprotect(writable, page, C.PROT_READ | C.PROT_WRITE | C.PROT_EXEC)
		valid := if allowed { result == 0 } else { result == -1 && *C.__errno_location() == C.EOPNOTSUPP }
		if C.munmap(writable, page) != 0 || !valid { return 18 }
		return 0
	}
}

@[export: 'main']
pub fn run(argc i32, argv &&char) i32 {
	unsafe {
		if argc == 2 { return probe(C.strcmp(argv[1], c'--wx') == 0) }
		if C.mkdir(c'/jit', u32(0o755)) != 0 || C.mkdir(c'/jit/runtime', u32(0o755)) != 0
			|| C.mkdir(c'/jit/plain', u32(0o755)) != 0
			|| !copy_probe(c'/jit/runtime/probe') || !copy_probe(c'/jit/plain/probe') { return 1 }
		file := C.open(c'/jit/runtime/writable', C.O_CREAT | C.O_EXCL | C.O_WRONLY, u32(0o666))
		if file < 0 || C.close(file) != 0 || C.chmod(c'/jit/runtime/writable', u32(0o666)) != 0
			|| C.chmod(c'/jit/runtime/probe', u32(0o6755)) != 0 { return 1 }
		if C.mount(c'/jit/runtime', c'/jit/runtime', nil, usize(C.MS_BIND), nil) != 0 { return 1 }
		flags := usize(C.MS_REMOUNT | C.MS_BIND | C.MS_RDONLY | C.MS_NOSUID | C.MS_NODEV)
		if C.mount(c'none', c'/jit/runtime', nil, flags, c'wxallowed') != 0 { return 1 }
		paths := [&char(c'/jit/plain/probe'), &char(c'/jit/runtime/probe'), &char(c'/jit/runtime/probe')]!
		requests := [true, false, true]!
		expected := [i32(C.EPERM), 0, 0]!
		for i in 0 .. paths.len {
			actual := child_result(paths[i], requests[i])
			if actual != expected[i] { C.printf(c'LINUX JIT FAIL: case=%d actual=%d expected=%d\n', i, actual, expected[i]); return 1 }
		}
		C.puts(c'LINUX JIT PASS: ordinary-user approval, read-only runtime and default W^X')
		if C.mount(c'none', c'/jit/runtime', nil, flags, nil) != 0
			|| child_result(c'/jit/runtime/probe', true) != C.EPERM
			|| child_result(c'/jit/runtime/probe', false) != 0 { return 1 }
		C.puts(c'LINUX JIT PASS: administrator revocation rejects future requests')
		C.puts(c'LINUX JIT: PASS')
		C.fflush(nil)
		for { C.pause() }
	}
	return 0
}
