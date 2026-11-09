// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module execownfixture

#include <alloca.h>
#include <errno.h>
#include <fcntl.h>
#include <grp.h>
#include <stdio.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <unistd.h>

struct Totals { mut: checks int failures int }
__global ( reference_mode bool )

fn C.alloca(usize) voidptr
fn C.open(&char, i32, ...) i32
fn C.close(i32) i32
fn C.read(i32, voidptr, usize) isize
fn C.pread(i32, voidptr, usize, i64) isize
fn C.write(i32, voidptr, usize) isize
fn C.mkdir(&char, u32) i32
fn C.chmod(&char, u32) i32
fn C.fork() i32
fn C.waitpid(i32, &i32, i32) i32
fn C.execve(&char, &&char, &&char) i32
fn C.setgroups(usize, voidptr) i32
fn C.setgid(u32) i32
fn C.setuid(u32) i32
fn C.getuid() u32
fn C.getgid() u32
fn C.__errno_location() &i32
fn C._exit(i32)
fn C.strlen(&char) usize
fn C.strcmp(&char, &char) i32
fn C.memcmp(voidptr, voidptr, usize) i32
fn C.getenv(&char) &char
fn C.sscanf(&char, &char, ...) i32
fn C.snprintf(&char, usize, &char, ...) i32
fn C.printf(&char, ...) i32
fn C.puts(&char) i32
fn C.fflush(voidptr) i32
fn C.alarm(u32) u32
fn C.usleep(u32) i32
fn C.pause() i32
fn C.pipe(&i32) i32

fn record(mut totals Totals, good bool, stage int) {
	totals.checks++
	if !good {
		totals.failures++
		C.printf(c'LINUX EXECOWN MISMATCH: uid=%u stage=%d errno=%d\n', C.getuid(), stage, unsafe { *C.__errno_location() })
	}
}
fn write_file(path &char, text &char) bool {
	unsafe {
		fd := C.open(path, C.O_WRONLY | C.O_CREAT | C.O_EXCL, u32(0o755))
		if fd < 0 { return false }
		length := C.strlen(text)
		good := C.write(fd, text, length) == isize(length)
		return C.close(fd) == 0 && good
	}
}
fn copy_image() bool {
	unsafe {
		source := C.open(if reference_mode { c'/sbin/probe' } else { c'/sbin/init' }, C.O_RDONLY)
		if source < 0 { return false }
		defer { C.close(source) }
		output := C.open(c'/tmp/linux-execown/interpreter', C.O_WRONLY | C.O_CREAT | C.O_EXCL, u32(0o755))
		if output < 0 { return false }
		defer { C.close(output) }
		mut data := [4096]u8{}
		for {
			length := C.read(source, &data[0], 4096)
			if length < 0 { return false }
			if length == 0 { return true }
			mut copied := isize(0)
			for copied < length {
				n := C.write(output, &data[0] + copied, usize(length - copied))
				if n <= 0 { return false }
				copied += n
			}
		}
	}
}
fn prepare() bool {
	unsafe {
		return C.mkdir(c'/tmp/linux-execown', u32(0o777)) == 0
			&& C.chmod(c'/tmp/linux-execown', u32(0o777)) == 0 && copy_image()
			&& write_file(c'/tmp/linux-execown/one', c'#!/tmp/linux-execown/interpreter --script-option with spaces\n')
			&& write_file(c'/tmp/linux-execown/chain', c'#!/tmp/linux-execown/one nested-option\n')
			&& write_file(c'/tmp/linux-execown/nooption', c'#!/tmp/linux-execown/interpreter\n')
			&& write_file(c'/tmp/linux-execown/badscript', c'#!/tmp/linux-execown/missing interpreter-option\n')
			&& write_file(c'/tmp/linux-execown/badelf', c'this is not an ELF image\n')
	}
}
fn patterned(data &char, length int) {
	unsafe {
		for i in 0 .. length { data[i] = char(`a` + i % 23) }
		data[length] = 0
	}
}
fn pattern_matches(data &char, length int) bool {
	unsafe {
		if C.strlen(data) != usize(length) { return false }
		for i in 0 .. length { if data[i] != char(`a` + i % 23) { return false } }
		return true
	}
}
fn verify_payload(argc i32, argv &&char, envp &&char) i32 {
	unsafe {
		if envp == nil || envp[0] == nil || envp[1] == nil || envp[2] == nil
			|| envp[3] == nil || envp[4] == nil || envp[5] != nil { return 31 }
		mut mode := i32(-1)
		if C.sscanf(envp[0], c'EXECOWN_MODE=%d', &mode) != 1 || mode < 0 || mode > 4 { return 32 }
		mut uid := u32(0)
		if C.sscanf(envp[1], c'EXECOWN_UID=%u', &uid) != 1 || uid != C.getuid() || uid != C.getgid() { return 33 }
		if C.strcmp(envp[2], c'EXECOWN_EMPTY=') != 0
			|| C.strcmp(envp[3], c'EXECOWN_TEXT=value with spaces=and punctuation') != 0
			|| C.memcmp(envp[4], c'EXECOWN_LONG=', 13) != 0
			|| !pattern_matches(envp[4] + 13, 6144) { return 34 }
		if mode == 4 {
			return if argc == 3 && argv[3] == nil
				&& C.strcmp(argv[0], c'/tmp/linux-execown/interpreter') == 0
				&& C.strcmp(argv[1], c'--script-option with spaces') == 0
				&& C.strcmp(argv[2], c'/tmp/linux-execown/one') == 0 { 0 } else { 41 }
		}
		offset := if mode == 0 { 1 } else if mode == 1 { 3 } else if mode == 2 { 5 } else { 2 }
		if argc != offset + 4 || argv[argc] != nil { return 35 }
		if mode == 0 {
			if C.strcmp(argv[0], c'chosen argv zero') != 0 { return 36 }
		} else if mode == 3 {
			if C.strcmp(argv[0], c'/tmp/linux-execown/interpreter') != 0
				|| C.strcmp(argv[1], c'/tmp/linux-execown/nooption') != 0 { return 42 }
		} else {
			if C.strcmp(argv[0], c'/tmp/linux-execown/interpreter') != 0
				|| C.strcmp(argv[1], c'--script-option with spaces') != 0
				|| C.strcmp(argv[2], c'/tmp/linux-execown/one') != 0 { return 37 }
			if mode == 2 && (C.strcmp(argv[3], c'nested-option') != 0
				|| C.strcmp(argv[4], c'/tmp/linux-execown/chain') != 0) { return 38 }
		}
		if C.strcmp(argv[offset], c'--payload') != 0 || !pattern_matches(argv[offset + 1], 4096)
			|| C.strcmp(argv[offset + 2], c'argument with spaces') != 0
			|| C.strcmp(argv[offset + 3], c'') != 0 { return 39 }
		return 0
	}
}
fn successful_exec(mode int) bool {
	unsafe {
		child := C.fork()
		if child < 0 { return false }
		if child == 0 {
			mut argument := [4097]char{}
			mut environment := [6158]char{}
			patterned(&argument[0], 4096)
			C.snprintf(&environment[0], 14, c'EXECOWN_LONG=')
			patterned(&environment[13], 6144)
			mut mode_text := [32]char{}
			mut uid_text := [32]char{}
			C.snprintf(&mode_text[0], 32, c'EXECOWN_MODE=%d', mode)
			C.snprintf(&uid_text[0], 32, c'EXECOWN_UID=%u', C.getuid())
			mut args := [6]&char{}
			args[0] = c'chosen argv zero'; args[1] = c'--payload'; args[2] = &argument[0]
			args[3] = c'argument with spaces'; args[4] = c''
			if mode == 4 { args[0] = nil }
			mut env := [6]&char{}
			env[0] = &mode_text[0]; env[1] = &uid_text[0]; env[2] = c'EXECOWN_EMPTY='
			env[3] = c'EXECOWN_TEXT=value with spaces=and punctuation'; env[4] = &environment[0]
			path := if mode == 0 { &char(c'/tmp/linux-execown/interpreter') }
				else if mode == 1 || mode == 4 { &char(c'/tmp/linux-execown/one') }
				else if mode == 2 { &char(c'/tmp/linux-execown/chain') } else { &char(c'/tmp/linux-execown/nooption') }
			C.execve(path, &args[0], &env[0]); C._exit(40)
		}
		mut status := i32(-1)
		completed := C.waitpid(child, &status, 0) == child && status == 0
		if !completed { C.printf(c'LINUX EXECOWN CHILD: uid=%u mode=%d status=%d\n', C.getuid(), mode, status) }
		return completed
	}
}
fn failed_exec(path &char, argv &&char, envp &&char, expected i32) bool {
	unsafe {
		error_slot := C.__errno_location()
		*error_slot = 0
		result := C.execve(path, argv, envp)
		return result == -1 && *C.__errno_location() == expected
	}
}
fn failure_cycle() bool {
	unsafe {
		mut argument := [4097]char{}
		patterned(&argument[0], 4096)
		mut args := [6]&char{}
		args[0] = c'original argv zero'; args[1] = c'first'; args[2] = &argument[0]
		args[3] = c'last with spaces'; args[4] = c''
		mut env := [5]&char{}
		env[0] = c'FIRST=one'; env[1] = c'SECOND=two'; env[2] = c'EMPTY='; env[3] = c'FINAL=last'
		for kind in 0 .. 3 {
			path := if kind == 0 { &char(c'/tmp/linux-execown/missing') }
				else if kind == 1 { &char(c'/tmp/linux-execown/badelf') } else { &char(c'/tmp/linux-execown/badscript') }
			if !failed_exec(path, &args[0], &env[0], if kind == 1 { i32(C.ENOEXEC) } else { i32(C.ENOENT) }) { return false }
		}
		return successful_exec(1) && C.strcmp(args[0], c'original argv zero') == 0 && C.strcmp(args[4], c'') == 0
			&& C.strcmp(env[0], c'FIRST=one') == 0 && pattern_matches(&argument[0], 4096)
	}
}
fn qualify(ordinary bool, reference bool) Totals {
	unsafe {
		reference_mode = reference
		C.alarm(240)
		mut totals := Totals{}
		if ordinary && (C.setgroups(0, nil) != 0 || C.setgid(1000) != 0 || C.setuid(1000) != 0) {
			record(mut totals, false, 1); return totals
		}
		for mode in 0 .. 5 { record(mut totals, successful_exec(mode), 10 + mode) }
		record(mut totals, failure_cycle(), 20)
		if reference { C.printf(c'LINUX EXECOWN STORAGE: uid=%u SKIP Linux reference\n', C.getuid()) }
		else { record(mut totals, storage(), 30) }
		C.printf(c'LINUX EXECOWN COHORT: uid=%u checks=%d failures=%d\n', C.getuid(), totals.checks, totals.failures)
		C.fflush(nil)
		return totals
	}
}
@[export: 'main']
pub fn run(argc i32, argv &&char, envp &&char) i32 {
	unsafe {
		if C.getenv(c'EXECOWN_MODE') != nil { return verify_payload(argc, argv, envp) }
		reference_mode = argc == 2 && C.strcmp(argv[1], c'--reference') == 0
		if !prepare() { C.puts(c'LINUX EXECOWN FAIL: setup'); C.fflush(nil); return 1 }
		mut final := Totals{}
		for ordinary in [false, true]! {
			mut channel := [2]i32{}
			if C.pipe(&channel[0]) != 0 { return 1 }
			child := C.fork()
			if child < 0 { return 1 }
			if child == 0 {
				C.close(channel[0]); totals := qualify(ordinary, reference_mode)
				sent := C.write(channel[1], &totals, sizeof(totals)) == isize(sizeof(totals))
				C.close(channel[1]); C._exit(if sent && totals.failures == 0 { 0 } else { 1 })
			}
			C.close(channel[1]); mut totals := Totals{}
			received := C.read(channel[0], &totals, sizeof(totals)) == isize(sizeof(totals))
			C.close(channel[0]); mut status := i32(-1)
			completed := C.waitpid(child, &status, 0) == child && status == 0
			if !received || !completed { final.failures++ }
			if received { final.checks += totals.checks; final.failures += totals.failures }
		}
		C.printf(c'LINUX EXECOWN SUMMARY: checks=%d failures=%d\n', final.checks, final.failures)
		C.fflush(nil)
		if final.failures != 0 { C.puts(c'LINUX EXECOWN FAIL: arguments, environment, errors or cleanup'); C.fflush(nil); return 1 }
		C.puts(if reference_mode { c'LINUX EXECOWN REFERENCE: PASS' } else { c'LINUX EXECOWN: PASS' })
		C.fflush(nil); for { C.pause() }
	}
	return 0
}
