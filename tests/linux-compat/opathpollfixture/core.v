// SPDX-License-Identifier: GPL-2.0-or-later
module opathpollfixture

#include <alloca.h>
#include <errno.h>
#include <fcntl.h>
#include <poll.h>
#include <stdio.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <sys/syscall.h>
#include <sys/wait.h>
#include <unistd.h>

struct C.timespec { mut: tv_sec i64 tv_nsec i64 }
struct Poll { mut: fd i32 events i16 revents i16 }
struct Guard { mut: before u64 polls [4]Poll after u64 }
struct Totals { mut: checks int failures int }
struct Targets { mut: fds [10]i32 normal i32 }
struct Slabs { mut: sizes [32]u64 live [32]u64 rows int large u64 tainted u64 }

fn C.alloca(usize) voidptr
fn C.syscall(isize, ...) isize
fn C.__errno_location() &i32
fn C.printf(&char, ...) i32
fn C.snprintf(&char, usize, &char, ...) i32
fn C.sscanf(&char, &char, ...) i32
fn C.strcmp(&char, &char) i32
fn C.fflush(voidptr) i32
fn C.alarm(u32) u32
fn C.pause() i32
fn C.open(&char, i32, ...) i32
fn C.close(i32) i32
fn C.dup(i32) i32
fn C.symlink(&char, &char) i32
fn C.unlink(&char) i32
fn C.chmod(&char, u32) i32
fn C.fcntl(i32, i32, ...) i32
fn C.memfd_create(&char, u32) i32
fn C.lseek(i32, i64, i32) i64
fn C.write(i32, voidptr, usize) isize
fn C.read(i32, voidptr, usize) isize
fn C.pread(i32, voidptr, usize, i64) isize
fn C.poll(voidptr, usize, i32) i32
fn C.ppoll(voidptr, usize, &C.timespec, voidptr) i32
fn C.pipe(&i32) i32
fn C.fork() i32
fn C.waitpid(i32, &i32, i32) i32
fn C._exit(i32)
fn C.setgid(u32) i32
fn C.setuid(u32) i32
fn C.getuid() u32
fn C.usleep(u32) i32

fn fatal(stage int) {
	C.printf(c'LINUX OPATHPOLL FAIL: setup=%d errno=%d\n', stage, unsafe { *C.__errno_location() })
	C.fflush(unsafe { nil }); C._exit(90)
}
fn targets() Targets {
 unsafe {
  mut t := Targets{}
  mut path := [96]char{}
  mut link := [96]char{}
  mut dangling := [96]char{}
  pid := C.syscall(isize(C.SYS_getpid))
  if C.snprintf(&path[0], sizeof(path), c'/tmp/opathpoll-%ld', pid) <= 0 || C.snprintf(&link[0], sizeof(link), c'/tmp/opathpoll-link-%ld', pid) <= 0 || C.snprintf(&dangling[0], sizeof(dangling), c'/tmp/opathpoll-dangling-%ld', pid) <= 0 { fatal(1) }
  t.normal = C.open(&path[0], C.O_CREAT | C.O_EXCL | C.O_RDWR, 0o600)
  if t.normal < 0 { fatal(2) }
  t.fds[0] = C.open(&path[0], C.O_PATH)
  t.fds[1] = C.open(&path[0], C.O_PATH | C.O_CLOEXEC)
  t.fds[2] = C.dup(t.fds[0])
  t.fds[3] = C.fcntl(t.fds[0], C.F_DUPFD_CLOEXEC, 70)
  t.fds[4] = C.open(c'/tmp', C.O_PATH | C.O_DIRECTORY)
  t.fds[5] = C.open(c'/proc/version', C.O_PATH)
  if C.symlink(&path[0], &link[0]) != 0 || C.symlink(c'/missing-opathpoll', &dangling[0]) != 0 { fatal(3) }
  t.fds[6] = C.open(&link[0], C.O_PATH | C.O_NOFOLLOW)
  t.fds[7] = C.open(&dangling[0], C.O_PATH | C.O_NOFOLLOW)
  t.fds[8] = C.open(c'/proc/self/exe', C.O_PATH | C.O_NOFOLLOW)
  t.fds[9] = C.fcntl(t.fds[4], C.F_DUPFD_CLOEXEC, 90)
  for fd in t.fds { if fd < 0 || C.fcntl(fd, C.F_GETFL) & C.O_PATH == 0 { fatal(4) } }
  if C.unlink(&link[0]) != 0 || C.unlink(&dangling[0]) != 0 || C.unlink(&path[0]) != 0 { fatal(5) }
  return t
 }
}
fn close_targets(t &Targets) { unsafe { for fd in t.fds { C.close(fd) }; C.close(t.normal) } }
fn call(api int, p &Poll, count uint, timed bool) isize {
	unsafe {
		mut timeout := C.timespec{tv_nsec: if timed { 1_000_000 } else { 0 }}
		match api {
			0 { return C.syscall(isize(C.SYS_ppoll), p, count, &timeout, nil, usize(8)) }
			1 { return C.ppoll(voidptr(p), count, &timeout, nil) }
			2 { return C.poll(voidptr(p), count, if timed { 1 } else { 0 }) }
			else {
				$if amd64 { return C.syscall(isize(C.SYS_poll), p, count, if timed { 1 } else { 0 }) }
				$else { fatal(5); return -1 }
			}
		}
	}
}
fn cycle(t &Targets, apis int, report bool) Totals {
 unsafe {
  mut sum := Totals{}
  for index, fd in t.fds {
   flags := C.fcntl(fd, C.F_GETFL)
   normal_flags := C.fcntl(t.normal, C.F_GETFL)
   position := C.lseek(t.normal, 0, C.SEEK_CUR)
   mut original := u8(0)
   size := C.pread(t.normal, &original, 1, 0)
   if size < 0 || position < 0 { fatal(21) }
   for api in 0 .. apis {
    mut failures := 0
    for mask in [0, 1, 4, 5, 0x40, 0x100, 0x140, 0x145, 2, 8, 16, 32, 0x80, 0x200, 0x2000, 0x7fff]! {
     for mixed in [false, true]! {
      g := &Guard(C.alloca(usize(sizeof(Guard))))
      *g = Guard{before: 0x123456789abcdef0, after: 0xfedcba9876543210}
      g.polls[0] = Poll{fd: fd, events: i16(mask), revents: -1}
      g.polls[1] = Poll{fd: t.normal, events: i16(mask), revents: -1}
      g.polls[2] = g.polls[0]
      g.polls[3] = Poll{fd: -1, events: i16(mask), revents: -1}
      count := uint(if mixed { 4 } else { 1 })
      err := C.__errno_location(); *err = 0
      ret := call(api, &g.polls[0], count, mask & 1 != 0)
      normal_bits := mask & 0x145
      expected := if mixed { 2 + (if normal_bits != 0 { 1 } else { 0 }) } else { 1 }
      mut good := ret == expected && *err == 0 && g.before == 0x123456789abcdef0 && g.after == 0xfedcba9876543210
      for i in 0 .. 4 {
       wanted := if i >= int(count) { -1 } else if i in [0, 2]! { 32 } else if i == 1 { normal_bits } else { 0 }
       wanted_fd := if i in [0, 2]! { fd } else if i == 1 { t.normal } else { -1 }
       if g.polls[i].fd != wanted_fd || g.polls[i].events != mask || g.polls[i].revents != wanted { good = false }
      }
      mut current := u8(0)
      good = good && C.fcntl(fd, C.F_GETFL) == flags && C.fcntl(t.normal, C.F_GETFL) == normal_flags && C.lseek(t.normal, 0, C.SEEK_CUR) == position && C.pread(t.normal, &current, 1, 0) == size && current == original
      sum.checks++
      if !good { failures++; sum.failures++ }
      if !good && report { C.printf(c'LINUX OPATHPOLL MISMATCH: uid=%u kind=%d api=%d mask=%x mixed=%d actual=%ld/%d/%x expected=%d/0/20\n', C.getuid(), index, api, mask, int(mixed), ret, *err, g.polls[0].revents, expected) }
     }
    }
    if report { C.printf(c'LINUX OPATHPOLL CASE: uid=%u kind=%d api=%d checks=32 failures=%d\n', C.getuid(), index, api, failures) }
   }
  }
  return sum
 }
}
fn snapshot(fd i32, destination &Slabs) bool {
	unsafe {
		mut counts := &Slabs(destination)
		*counts = Slabs{}
		mut data := [4096]char{}
		length := C.pread(fd, &data[0], 4095, 0)
		if length <= 0 || length >= 4096 { return false }
		data[int(length)] = 0
		mut position := 0; mut large := false; mut guarded := false
		for position < int(length) {
			mut size := u64(0); mut duplicate := u64(0); mut live := u64(0); mut pages := u64(0)
			if C.sscanf(&data[position], c'size-%lu %lu %lu %lu', &size, &duplicate, &live, &pages) == 4 {
				if counts.rows >= 32 || size != duplicate { return false }
				counts.sizes[counts.rows] = size; counts.live[counts.rows] = live; counts.rows++
			} else if C.sscanf(&data[position], c'large - - %lu', &counts.large) == 1 { large = true }
			else if C.sscanf(&data[position], c'# written after free %lu', &counts.tainted) == 1 { guarded = true }
			for position < int(length) && data[position] != char(10) { position++ }; position++
		}
		return counts.rows > 0 && large && guarded
	}
}
fn storage(t &Targets, apis int) bool {
	unsafe {
		fd := C.open(c'/proc/slabinfo', C.O_RDONLY)
		if fd < 0 { fatal(6) }
		defer { C.close(fd) }
		for _ in 0 .. 16 { if cycle(t, apis, false).failures != 0 { fatal(7) } }
		C.usleep(13_000_000)
		before := &Slabs(C.alloca(usize(sizeof(Slabs))))
		after := &Slabs(C.alloca(usize(sizeof(Slabs))))
		if !snapshot(fd, before) { fatal(8) }
		mut failures := 0
		for _ in 0 .. 200 { failures += cycle(t, apis, false).failures }
		C.usleep(13_000_000)
		if !snapshot(fd, after) { fatal(9) }
		mut good := failures == 0 && before.rows == after.rows && before.large == after.large && before.tainted == 0 && after.tainted == 0
		for row in 0 .. before.rows {
			if before.sizes[row] != after.sizes[row] || before.live[row] != after.live[row] { good = false }
			C.printf(c'LINUX OPATHPOLL SLAB: uid=%u size=%lu live=%lu/%lu\n', C.getuid(), before.sizes[row], before.live[row], after.live[row])
		}
		C.printf(c'LINUX OPATHPOLL STORAGE: uid=%u cycles=200 big_pages=%lu/%lu tainted=%lu/%lu %s\n', C.getuid(), before.large, after.large, before.tainted, after.tainted, if good { &char(c'PASS') } else { &char(c'FAIL') })
		return good
	}
}
@[export: 'main']
pub fn run(argc i32, argv &&char) i32 {
	unsafe {
		C.alarm(600)
		if C.chmod(c'/tmp', 0o1777) != 0 { fatal(10) }
		reference := argc == 2 && C.strcmp(argv[1], c'--reference') == 0
		mut apis := 3
		$if amd64 { apis = 4 }
		mut total := Totals{}
		for ordinary in [false, true]! {
			mut pipes := [2]i32{}
			if C.pipe(&pipes[0]) != 0 { fatal(11) }
			C.fflush(nil)
			pid := C.fork()
			if pid < 0 { fatal(12) }
			if pid == 0 {
				C.close(pipes[0])
				if ordinary && (C.setgid(2000) != 0 || C.setuid(1000) != 0) { fatal(13) }
				t := &Targets(C.alloca(usize(sizeof(Targets))))
				*t = targets()
				mut sum := Totals{}
				for phase in 0 .. 4 {
					if phase == 1 {
						byte := u8(0x51)
						if C.write(t.normal, &byte, 1) != 1 { fatal(14) }
					}
					if C.lseek(t.normal, if phase < 2 { 0 } else if phase == 2 { 1 } else { 4096 }, C.SEEK_SET) < 0 { fatal(15) }
					result := cycle(t, apis, true)
					sum.checks += result.checks; sum.failures += result.failures
				}
				if !reference && sum.failures == 0 && !storage(t, apis) { sum.failures++ }
				if reference { C.printf(c'LINUX OPATHPOLL STORAGE: uid=%u SKIP reference\n', C.getuid()) }
				close_targets(t)
				if C.write(pipes[1], &sum, sizeof(sum)) != sizeof(sum) { fatal(16) }
				C.fflush(nil); C._exit(0)
			}
			C.close(pipes[1])
			mut sum := Totals{}
			if C.read(pipes[0], &sum, sizeof(sum)) != sizeof(sum) { fatal(17) }
			C.close(pipes[0])
			mut status := i32(0)
			if C.waitpid(pid, &status, 0) != pid || status != 0 { fatal(18) }
			total.checks += sum.checks; total.failures += sum.failures
		}
		C.printf(c'LINUX OPATHPOLL SUMMARY: checks=%d failures=%d\n', total.checks, total.failures)
		C.printf(c'LINUX OPATHPOLL: %s\n', if total.failures == 0 { &char(c'PASS') } else { &char(c'FAIL') })
		C.fflush(nil); C.alarm(0)
		for { C.pause() }
	}
	return 0
}
