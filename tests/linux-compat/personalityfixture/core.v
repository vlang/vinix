// SPDX-License-Identifier: GPL-2.0-or-later
// personality(2): query/set words and results, the 32-bit domain, UNAME26,
// per-thread values, fork and exec inheritance (READ_IMPLIES_EXEC cleared),
// ADDR_NO_RANDOMIZE layouts after exec and READ_IMPLIES_EXEC protections.
// The same ELF runs as Vinix's init and, given --reference, under Linux.
module personalityfixture

#include <alloca.h>
#include <errno.h>
#include <fcntl.h>
#include <pthread.h>
#include <sched.h>
#include <stdio.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/mount.h>
#include <sys/syscall.h>
#include <sys/utsname.h>
#include <sys/wait.h>
#include <unistd.h>

struct C.pthread_t {}

struct C.utsname {
	release [65]char
	machine [65]char
}

fn C.syscall(isize, ...) isize
fn C.__errno_location() &i32
fn C.printf(&char, ...) i32
fn C.puts(&char) i32
fn C.fflush(voidptr) i32
fn C.pause() i32
fn C.fork() i32
fn C.waitpid(i32, &i32, i32) i32
fn C._exit(i32)
fn C.pipe(&i32) i32
fn C.read(i32, voidptr, usize) isize
fn C.write(i32, voidptr, usize) isize
fn C.close(i32) i32
fn C.dup2(i32, i32) i32
fn C.open(&char, i32, ...) i32
fn C.execv(&char, &&char) i32
fn C.strcmp(&char, &char) i32
fn C.strncmp(&char, &char, usize) i32
fn C.strlen(&char) usize
fn C.strchr(&char, i32) &char
fn C.strtoul(&char, &&char, i32) u64
fn C.alloca(usize) voidptr
fn C.uname(&C.utsname) i32
fn C.mmap(voidptr, usize, i32, i32, i32, i64) voidptr
fn C.munmap(voidptr, usize) i32
fn C.mprotect(voidptr, usize, i32) i32
fn C.mount(&char, &char, &char, u64, voidptr) i32
fn C.sbrk(isize) voidptr
fn C.pthread_create(&C.pthread_t, voidptr, fn (voidptr) voidptr, voidptr) i32
fn C.pthread_join(C.pthread_t, voidptr) i32

const query = u64(0xffffffff)
const per_linux32 = u64(0x0008)
const uname26 = u64(0x0020000)
const no_randomize = u64(0x0040000)
const read_exec = u64(0x0400000)
// The descriptor an exec'd copy reports through.
const report_fd = 9

struct State {
mut:
	checks   int
	failures int
}

struct Result {
	value isize
	err   int
}

fn persona(value u64) Result {
	unsafe {
		errno_ptr := C.__errno_location()
		*errno_ptr = 0
		result := C.syscall(isize(C.SYS_personality), value)
		return Result{result, if result < 0 { *errno_ptr } else { 0 }}
	}
}

fn check(mut s State, label &char, ok bool, got Result) {
	s.checks++
	if !ok {
		s.failures++
		C.printf(c'LINUX PERSONALITY FAIL: %s value=0x%lx errno=%d\n', label, got.value, got.err)
	}
}

fn expect(mut s State, label &char, got Result, want u64) {
	check(mut s, label, got.err == 0 && u64(got.value) == want, got)
}

fn values(mut s State) {
	expect(mut s, c'initial', persona(query), 0)
	expect(mut s, c'set returns old', persona(no_randomize), 0)
	expect(mut s, c'query after set', persona(query), no_randomize)
	expect(mut s, c'set zero', persona(0), no_randomize)
	expect(mut s, c'arbitrary', persona(0x12345678), 0)
	expect(mut s, c'arbitrary kept', persona(query), 0x12345678)
	// An unsigned int: the register's upper half is ignored.
	expect(mut s, c'upper word', persona((u64(1) << 32) | no_randomize), 0x12345678)
	expect(mut s, c'upper word kept', persona(query), no_randomize)
	expect(mut s, c'high value', persona(0xfffffffe), no_randomize)
	expect(mut s, c'high value kept', persona(query), 0xfffffffe)
	expect(mut s, c'sign bit', persona(0x80000000), 0xfffffffe)
	expect(mut s, c'sign bit kept', persona(query), 0x80000000)
	expect(mut s, c'query word', persona((u64(5) << 32) | query), 0x80000000)
	expect(mut s, c'reset', persona(0), 0x80000000)
}

fn uname_fields(release &u8, machine &u8) {
	unsafe {
		u := &C.utsname(C.alloca(usize(sizeof(C.utsname))))
		C.uname(u)
		for i in 0 .. 65 {
			release[i] = u8(u.release[i])
			machine[i] = u8(u.machine[i])
		}
	}
}

// The release UNAME26 makes of `release`, computed independently.
fn expected_uname26(release &u8, out &u8) {
	unsafe {
		mut i := 0
		mut dots := 0
		mut minor := 0
		for release[i] != 0 {
			c := release[i]
			if c == `.` {
				dots++
				if dots >= 3 { break }
			} else if c >= `0` && c <= `9` {
				if dots == 1 { minor = minor * 10 + int(c - `0`) }
			} else {
				break
			}
			i++
		}
		C.snprintf(&char(out), 65, c'2.6.%d%s', minor + 60, &char(&release[i]))
	}
}

fn C.snprintf(&char, usize, &char, ...) i32

fn domains(mut s State) {
	unsafe {
		release := &u8(C.alloca(65))
		machine := &u8(C.alloca(65))
		changed := &u8(C.alloca(65))
		changed_machine := &u8(C.alloca(65))
		wanted := &u8(C.alloca(65))
		uname_fields(release, machine)
		$if arm64 {
			// No AArch32 at EL0: the 32-bit domain is refused, flags or not.
			r := persona(per_linux32)
			check(mut s, c'linux32 refused', r.value == -1 && r.err == C.EINVAL, r)
			r2 := persona(uname26 | per_linux32)
			check(mut s, c'linux32 with flags refused', r2.value == -1 && r2.err == C.EINVAL, r2)
			expect(mut s, c'linux32 unchanged', persona(query), 0)
		} $else {
			expect(mut s, c'linux32', persona(per_linux32), 0)
			uname_fields(changed, changed_machine)
			check(mut s, c'linux32 machine', C.strcmp(&char(changed_machine), c'i686') == 0,
				Result{0, 0})
			check(mut s, c'linux32 release', C.strcmp(&char(changed), &char(release)) == 0, Result{0, 0})
			expect(mut s, c'linux32 reset', persona(0), per_linux32)
		}
		expect(mut s, c'uname26', persona(uname26), 0)
		uname_fields(changed, changed_machine)
		expected_uname26(release, wanted)
		check(mut s, c'uname26 release', C.strcmp(&char(changed), &char(wanted)) == 0, Result{0, 0})
		check(mut s, c'uname26 machine', C.strcmp(&char(changed_machine), &char(machine)) == 0,
			Result{0, 0})
		expect(mut s, c'uname26 reset', persona(0), uname26)
		uname_fields(changed, changed_machine)
		check(mut s, c'release restored', C.strcmp(&char(changed), &char(release)) == 0, Result{0, 0})
		C.printf(c'LINUX PERSONALITY UNAME: %s -> %s\n', &char(release), &char(wanted))
	}
}

struct ThreadShare {
mut:
	seen    u64
	changed u64
}

fn thread_main(arg voidptr) voidptr {
	unsafe {
		mut share := &ThreadShare(arg)
		share.seen = u64(persona(query).value)
		persona(uname26)
		share.changed = u64(persona(query).value)
	}
	return unsafe { nil }
}

fn threads(mut s State) {
	unsafe {
		persona(no_randomize)
		mut share := &ThreadShare(C.alloca(usize(sizeof(ThreadShare))))
		*share = ThreadShare{}
		handle := &C.pthread_t(C.alloca(usize(sizeof(C.pthread_t))))
		C.pthread_create(handle, nil, thread_main, share)
		C.pthread_join(*handle, nil)
		check(mut s, c'thread inherits', share.seen == no_randomize, Result{isize(share.seen), 0})
		check(mut s, c'thread own', share.changed == uname26, Result{isize(share.changed), 0})
		// The value is the task's: the thread's change stays with it.
		expect(mut s, c'creator unchanged', persona(query), no_randomize)
		child := C.fork()
		if child == 0 {
			C._exit(if u64(persona(query).value) == no_randomize { 0 } else { 1 })
		}
		mut status := i32(0)
		C.waitpid(child, &status, 0)
		check(mut s, c'fork inherits', status == 0, Result{isize(status), 0})
		persona(0)
	}
}

// Run this program again with `value` set, collecting what the new image
// reports: its personality and, for layouts, four addresses.
fn exec_report(value u64, mode &char, words &u64, count int) bool {
	unsafe {
		mut channel := [2]i32{}
		C.pipe(&channel[0])
		child := C.fork()
		if child == 0 {
			C.close(channel[0])
			C.dup2(channel[1], report_fd)
			C.syscall(isize(C.SYS_personality), value)
			mut argv := &&char(C.alloca(usize(3 * sizeof(voidptr))))
			argv[0] = &char(c'personality-exec')
			argv[1] = &char(mode)
			argv[2] = nil
			C.execv(c'/proc/self/exe', argv)
			C._exit(3)
		}
		C.close(channel[1])
		mut total := 0
		for total < count * 8 {
			n := C.read(channel[0], voidptr(u64(words) + u64(total)), usize(count * 8 - total))
			if n <= 0 { break }
			total += int(n)
		}
		C.close(channel[0])
		mut status := i32(0)
		C.waitpid(child, &status, 0)
		return total == count * 8 && status == 0
	}
}

fn execs(mut s State) {
	unsafe {
		word := &u64(C.alloca(8))
		sets := [no_randomize, read_exec, uname26, u64(0x12345678), read_exec | no_randomize,
			u64(0x0100000), u64(0x4000000)]!
		kept := [no_randomize, u64(0), uname26, u64(0x12345678), no_randomize, u64(0x0100000),
			u64(0x4000000)]!
		for index in 0 .. sets.len {
			ok := exec_report(sets[index], c'--report-persona', word, 1)
			check(mut s, c'exec keeps all but read-implies-exec', ok && *word == kept[index],
				Result{isize(*word), 0})
		}
	}
}

// Without randomization two execs place everything alike; with it, they
// differ.
fn layouts(mut s State) {
	unsafe {
		first := &u64(C.alloca(32))
		second := &u64(C.alloca(32))
		ok := exec_report(no_randomize, c'--report-layout', first, 4)
			&& exec_report(no_randomize, c'--report-layout', second, 4)
		mut same := ok
		for i in 0 .. 4 { same = same && first[i] == second[i] }
		check(mut s, c'fixed layout repeats', same, Result{isize(first[1]), 0})
		C.printf(c'LINUX PERSONALITY LAYOUT: stack=0x%lx mmap=0x%lx brk=0x%lx\n', first[0], first[1],
			first[2])
		random_ok := exec_report(0, c'--report-layout', first, 4)
			&& exec_report(0, c'--report-layout', second, 4)
		// The stack, the mmap area and the break are all randomized.
		check(mut s, c'randomized layout differs', random_ok && first[0] != second[0]
			&& first[1] != second[1] && first[2] != second[2], Result{isize(first[1]), 0})
	}
}

// The permissions /proc/self/maps shows for the mapping at `address`.
fn permissions(address u64, out &u8) bool {
	unsafe {
		buf := &u8(C.alloca(65536))
		fd := C.open(c'/proc/self/maps', C.O_RDONLY)
		if fd < 0 { return false }
		mut total := isize(0)
		for total < 65535 {
			n := C.read(fd, voidptr(u64(buf) + u64(total)), usize(65535 - total))
			if n <= 0 { break }
			total += n
		}
		C.close(fd)
		buf[total] = 0
		mut line := &char(buf)
		for *line != 0 {
			if C.strtoul(line, nil, 16) == address {
				field := C.strchr(line, ` `)
				if field == nil { return false }
				for i in 0 .. 4 { out[i] = u8(*&char(u64(field) + 1 + u64(i))) }
				out[4] = 0
				return true
			}
			next := C.strchr(line, `\n`)
			if next == nil { break }
			line = &char(u64(next) + 1)
		}
		return false
	}
}

fn protections(mut s State) {
	unsafe {
		perms := &u8(C.alloca(8))
		persona(read_exec)
		readable := C.mmap(nil, 4096, C.PROT_READ, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0)
		check(mut s, c'read implies exec mmap', permissions(u64(readable), perms)
			&& C.strcmp(&char(perms), c'r-xp') == 0, Result{0, 0})
		later := C.mmap(nil, 4096, C.PROT_NONE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0)
		C.mprotect(later, 4096, C.PROT_READ)
		check(mut s, c'read implies exec mprotect', permissions(u64(later), perms)
			&& C.strcmp(&char(perms), c'r-xp') == 0, Result{0, 0})
		hidden := C.mmap(nil, 4096, C.PROT_NONE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0)
		check(mut s, c'unreadable stays', permissions(u64(hidden), perms)
			&& C.strcmp(&char(perms), c'---p') == 0, Result{0, 0})
		persona(0)
		plain := C.mmap(nil, 4096, C.PROT_READ, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0)
		check(mut s, c'plain read', permissions(u64(plain), perms)
			&& C.strcmp(&char(perms), c'r--p') == 0, Result{0, 0})
		for mapping in [readable, later, hidden, plain]! { C.munmap(mapping, 4096) }
	}
}

fn report(argv &&char) {
	unsafe {
		if C.strcmp(argv[1], c'--report-persona') == 0 {
			mut value := u64(persona(query).value)
			C.write(report_fd, &value, 8)
		} else {
			stack := C.alloca(16)
			mapping := C.mmap(nil, 4096, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0)
			words := &u64(C.alloca(32))
			words[0] = u64(stack) & ~u64(0xfff)
			words[1] = u64(mapping)
			words[2] = u64(C.sbrk(0))
			words[3] = u64(voidptr(report))
			C.write(report_fd, words, 32)
		}
		C._exit(0)
	}
}

@[export: 'main']
pub fn run(argc i32, argv &&char) i32 {
	unsafe {
		if argc > 1 && C.strncmp(argv[1], c'--report-', 9) == 0 { report(argv) }
		reference := argc > 1 && C.strcmp(argv[1], c'--reference') == 0
		// The Linux wrapper has mounted /proc already.
		C.mount(c'proc', c'/proc', c'proc', 0, nil)
		mut s := State{}
		values(mut s)
		domains(mut s)
		threads(mut s)
		execs(mut s)
		layouts(mut s)
		protections(mut s)
		C.printf(c'LINUX PERSONALITY SUMMARY: checks=%d failures=%d\n', s.checks, s.failures)
		if s.failures == 0 {
			C.puts(if reference { c'LINUX PERSONALITY REFERENCE: PASS' } else { c'LINUX PERSONALITY: PASS' })
		}
		C.fflush(nil)
		for { C.pause() }
	}
	return 0
}
