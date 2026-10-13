// SPDX-License-Identifier: GPL-2.0-or-later
module execnamesfixture

#include <alloca.h>
#include <errno.h>
#include <fcntl.h>
#include <grp.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sched.h>
#include <signal.h>
#include <sys/mount.h>
#include <sys/prctl.h>
#include <sys/wait.h>
#include <unistd.h>

struct Counts { mut: reads [4]u64 bad [4]u64 cycles u64 }
struct Slabs { mut: sizes [32]u64 live [32]u64 rows i32 large u64 }
fn C.alloca(usize) voidptr
fn C.__errno_location() &i32
fn C.open(&char, i32, ...) i32
fn C.openat(i32, &char, i32, ...) i32
fn C.close(i32) i32
fn C.read(i32, voidptr, usize) isize
fn C.pread(i32, voidptr, usize, i64) isize
fn C.write(i32, voidptr, usize) isize
fn C.pipe(&i32) i32
fn C.fcntl(i32, i32, ...) i32
fn C.readlinkat(i32, &char, &char, usize) isize
fn C.mkdir(&char, u32) i32
fn C.mount(&char, &char, &char, usize, voidptr) i32
fn C.fork() i32
fn C.execv(&char, &&char) i32
fn C.waitpid(i32, &i32, i32) i32
fn C.kill(i32, i32) i32
fn C.setgroups(usize, voidptr) i32
fn C.setgid(u32) i32
fn C.setuid(u32) i32
fn C.getpid() i32
fn C.alarm(u32) u32
fn C.usleep(u32) i32
fn C.sched_yield() i32
fn C.pause() i32
fn C._exit(i32)
fn C.prctl(i32, ...) i32
fn C.atoi(&char) i32
fn C.strlen(&char) usize
fn C.memcmp(voidptr, voidptr, usize) i32
fn C.strcmp(&char, &char) i32
fn C.strchr(&char, i32) &char
fn C.strrchr(&char, i32) &char
fn C.strstr(&char, &char) &char
fn C.sscanf(&char, &char, ...) i32
fn C.snprintf(&char, usize, &char, ...) i32
fn C.printf(&char, ...) i32
fn C.puts(&char) i32
fn C.fflush(voidptr) i32

fn image(index i32) &char {
	unsafe { return if index == 0 { &char(c'/tmp/linux-execnames/exec-one') } else { &char(c'/tmp/linux-execnames/exec-two') } }
}
fn label(kind i32) &char {
	unsafe { return if kind == 0 { &char(c'comm') } else if kind == 1 { &char(c'stat') } else if kind == 2 { &char(c'status') } else { &char(c'exe') } }
}
fn allowed(data &char, length usize, executable bool) bool {
	unsafe {
		for index in 0 .. 3 {
			wanted := if executable { if index == 0 { &char(c'/sbin/init') } else { image(i32(index - 1)) } }
			else { if index == 0 { &char(c'before-exec') } else if index == 1 { &char(c'exec-one') } else { &char(c'exec-two') } }
			if length == C.strlen(wanted) && C.memcmp(data, wanted, length) == 0 { return true }
		}
		return false
	}
}
fn record(dirfd i32, pid i32, kind i32, counts &Counts, ordinary bool, verbose bool) bool {
	unsafe {
		mut tally := &Counts(counts); mut path := [96]char{}; C.snprintf(&path[0], 96, c'%d/%s', pid, label(kind))
		error_slot := C.__errno_location(); *error_slot = 0
		mut data := [4096]char{}; mut length := isize(-1); mut good := false; mut saved := i32(0)
		if kind == 3 {
			length = C.readlinkat(dirfd, &path[0], &data[0], 4095); saved = *C.__errno_location()
			good = length > 0 && length < 4096 && allowed(&data[0], usize(length), true)
		} else {
			fd := C.openat(dirfd, &path[0], C.O_RDONLY); saved = *C.__errno_location()
			if fd >= 0 {
				length = C.read(fd, &data[0], 4095); saved = *C.__errno_location(); C.close(fd)
				if length > 0 && length < 4096 {
					data[int(length)] = 0
					if kind == 0 { good = data[int(length) - 1] == char(`\n`) && allowed(&data[0], usize(length - 1), false) }
					else if kind == 1 {
						start := C.strchr(&data[0], i32(`(`)); end := C.strrchr(&data[0], i32(`)`))
						good = start != nil && end != nil && usize(end) > usize(start) && allowed(start + 1, usize(end) - usize(start) - 1, false)
					} else {
						end := C.strchr(&data[0], i32(`\n`))
						good = length >= 7 && C.memcmp(&data[0], c'Name:\t', 6) == 0 && end != nil && usize(end) >= usize(&data[0]) + 6 && allowed(&data[6], usize(end) - usize(&data[6]), false)
					}
				}
			}
		}
		tally.reads[kind]++
		if !good {
			tally.bad[kind]++
			if verbose && tally.bad[kind] <= 4 { C.printf(c'LINUX EXECNAMES DETAIL: ordinary=%d kind=%s length=%ld errno=%d failure=%lu\n', i32(ordinary), label(kind), length, saved, tally.bad[kind]); C.fflush(nil) }
		}
		return good
	}
}
fn cycle(dirs &i32, pid i32, counts &Counts, ordinary bool, verbose bool) bool {
	unsafe {
		mut good := true; mut tally := &Counts(counts)
		for view in 0 .. 3 { for kind in 0 .. 4 { if !record(dirs[view], pid, i32(kind), counts, ordinary, verbose) { good = false } } }
		tally.cycles++; return good
	}
}
fn replace_image(remaining i32, report i32, gate i32) i32 {
	unsafe {
		if remaining < 0 || remaining > 200 || report < 0 || gate < 0 { return 1 }
		if remaining == 0 { mut token := char(`d`); if C.write(report, &token, 1) != 1 || C.read(gate, &token, 1) != 1 { return 1 }; return 0 }
		// The arguments survive until exec consumes them; none escape a return.
		arguments := &char(C.alloca(48)); C.snprintf(arguments, 16, c'%d', remaining - 1); C.snprintf(arguments + 16, 16, c'%d', report); C.snprintf(arguments + 32, 16, c'%d', gate)
		mut argv := &&char(C.alloca(usize(6 * sizeof(voidptr))))
		argv[0] = &char(c'exec-loop'); argv[1] = &char(c'--replace'); argv[2] = arguments; argv[3] = arguments + 16; argv[4] = arguments + 32; argv[5] = nil
		C.execv(image(remaining & 1), argv); return 1
	}
}
fn copy_image(destination &char) bool {
	unsafe {
		input := C.open(c'/sbin/init', C.O_RDONLY); if input < 0 { return false }; defer { C.close(input) }
		output := C.open(destination, C.O_WRONLY | C.O_CREAT | C.O_EXCL, i32(0o755)); if output < 0 { return false }; defer { C.close(output) }
		mut data := [4096]u8{}
		for { length := C.read(input, &data[0], 4096); if length < 0 { return false }; if length == 0 { return true }; mut copied := isize(0)
			for copied < length { n := C.write(output, &data[0] + copied, usize(length - copied)); if n <= 0 { return false }; copied += n }
		}
	}
}
fn snapshot(fd i32, destination &Slabs) bool {
	unsafe {
		mut counts := &Slabs(destination); *counts = Slabs{}; mut data := [4096]char{}
		length := C.pread(fd, &data[0], 4095, 0); if length <= 0 || length >= 4096 { return false }; data[int(length)] = 0
		mut position := 0; mut large := false
		for position < int(length) {
			mut size := u64(0); mut duplicate := u64(0); mut live := u64(0); mut pages := u64(0)
			if C.sscanf(&data[position], c'size-%lu %lu %lu %lu', &size, &duplicate, &live, &pages) == 4 {
				if counts.rows >= 32 || size != duplicate { return false }; counts.sizes[counts.rows] = size; counts.live[counts.rows] = live; counts.rows++
			} else if C.sscanf(&data[position], c'large - - %lu', &counts.large) == 1 { large = true }
			for position < int(length) && data[position] != char(10) { position++ }; position++
		}
		return counts.rows > 0 && large
	}
}
fn storage(dirs &i32, pid i32, counts &Counts, ordinary bool) bool {
	unsafe {
		observer := C.open(c'/proc/slabinfo', C.O_RDONLY); if observer < 0 { return false }; defer { C.close(observer) }
		for _ in 0 .. 32 { if !cycle(dirs, pid, counts, ordinary, false) { return false } }; C.usleep(13000000)
		mut before := &Slabs(C.alloca(usize(sizeof(Slabs)))); mut after := &Slabs(C.alloca(usize(sizeof(Slabs))))
		if !snapshot(observer, before) { return false }
		for _ in 0 .. 200 { if !cycle(dirs, pid, counts, ordinary, false) { return false } }; C.usleep(13000000)
		if !snapshot(observer, after) { return false }
		mut good := before.rows == after.rows && before.large == after.large
		for i in 0 .. int(before.rows) {
			if before.sizes[i] != after.sizes[i] || before.live[i] != after.live[i] { good = false }
			C.printf(c'LINUX EXECNAMES SLAB: ordinary=%d size=%lu live=%lu/%lu cycles=200\n', i32(ordinary), before.sizes[i], before.live[i], after.live[i])
		}
		C.printf(c'LINUX EXECNAMES STORAGE: ordinary=%d cycles=200 big_pages=%lu/%lu %s\n', i32(ordinary), before.large, after.large, if good { &char(c'PASS') } else { &char(c'FAIL') }); C.fflush(nil)
		return good
	}
}
fn qualify(dirs &i32, ordinary bool) bool {
	unsafe {
		if ordinary && (C.setgroups(0, nil) != 0 || C.setgid(1000) != 0 || C.setuid(1000) != 0) { return false }
		// setuid disables dumpability until exec. Establish same-UID procfs
		// access before the child starts, including the initial name snapshot.
		if C.prctl(C.PR_SET_DUMPABLE, isize(1), isize(0), isize(0), isize(0)) != 0 { return false }
		C.alarm(300); mut gate := [2]i32{}; mut report := [2]i32{}
		if C.pipe(&gate[0]) != 0 { return false }; if C.pipe(&report[0]) != 0 { C.close(gate[0]); C.close(gate[1]); return false }
		child := C.fork(); if child < 0 { for fd in gate { C.close(fd) }; for fd in report { C.close(fd) }; return false }
		if child == 0 {
			C.close(gate[1]); C.close(report[0]); mut token := char(`r`)
			if C.prctl(C.PR_SET_NAME, c'before-exec', isize(0), isize(0), isize(0)) != 0 || C.write(report[1], &token, 1) != 1 || C.read(gate[0], &token, 1) != 1 { C._exit(1) }
			C._exit(replace_image(200, report[1], gate[0]))
		}
		C.close(gate[0]); C.close(report[1]); mut reaped := false; mut outcome := i32(-1)
		defer { if !reaped { C.kill(child, C.SIGKILL); if C.waitpid(child, &outcome, 0) != child { C._exit(1) } }; C.close(gate[1]); C.close(report[0]) }
		mut token := char(0); if C.read(report[0], &token, 1) != 1 || token != char(`r`) || C.fcntl(report[0], C.F_SETFL, C.O_NONBLOCK) != 0 || C.write(gate[1], &token, 1) != 1 { return false }
		mut counts := &Counts(C.alloca(usize(sizeof(Counts)))); *counts = Counts{}; mut good := true
		error_slot := C.__errno_location()
		for {
			*error_slot = 0; n := C.read(report[0], &token, 1); error_code := *error_slot
			if n == 1 { if token != char(`d`) { return false }; break }
			if n != -1 || (error_code != C.EAGAIN && error_code != C.EINTR) { return false }
			if !cycle(dirs, child, counts, ordinary, true) { good = false }; C.sched_yield()
		}
		for kind in 0 .. 4 { C.printf(c'LINUX EXECNAMES OBSERVE: ordinary=%d kind=%s reads=%lu failures=%lu execs=200\n', i32(ordinary), label(i32(kind)), counts.reads[kind], counts.bad[kind]) }; C.fflush(nil)
		if counts.cycles < 1 || !storage(dirs, child, counts, ordinary) { good = false }
		if C.write(gate[1], &token, 1) != 1 || C.waitpid(child, &outcome, 0) != child { return false }; reaped = true
		C.alarm(0); return good && outcome == 0
	}
}
@[export: 'main']
pub fn run(argc i32, argv &&char) i32 {
	unsafe {
		if argc == 5 && C.strcmp(argv[1], c'--replace') == 0 { return replace_image(C.atoi(argv[2]), C.atoi(argv[3]), C.atoi(argv[4])) }
		if C.mkdir(c'/tmp/linux-execnames', u32(0o755)) != 0 || C.mkdir(c'/tmp/linux-execnames/first', u32(0o755)) != 0 || C.mkdir(c'/tmp/linux-execnames/second', u32(0o755)) != 0
			|| C.mount(c'proc', c'/tmp/linux-execnames/first', c'proc', 0, nil) != 0 || C.mount(c'proc', c'/tmp/linux-execnames/second', c'proc', 0, nil) != 0 || !copy_image(image(0)) || !copy_image(image(1)) { return 1 }
		mut dirs := [i32(-1), -1, -1]!
		for i in 0 .. 3 { path := if i == 0 { &char(c'/proc') } else if i == 1 { &char(c'/tmp/linux-execnames/first') } else { &char(c'/tmp/linux-execnames/second') }; dirs[i] = C.open(path, C.O_PATH | C.O_DIRECTORY); if dirs[i] < 0 { for fd in dirs { if fd >= 0 { C.close(fd) } }; return 1 } }
		mut good := true
		for ordinary in [true, false]! {
			C.fflush(nil); child := C.fork(); if child < 0 { good = false; break }; if child == 0 { C._exit(if qualify(&dirs[0], ordinary) { 0 } else { 1 }) }
			mut status := i32(-1); if C.waitpid(child, &status, 0) != child || status != 0 { good = false }
		}
		for fd in dirs { C.close(fd) }
		if !good { C.puts(c'LINUX EXECNAMES FAIL: exec metadata, child status or observer storage'); C.fflush(nil); return 1 }
		C.puts(c'LINUX EXECNAMES: PASS'); C.fflush(nil); for { C.pause() }
	}
	return 0
}
