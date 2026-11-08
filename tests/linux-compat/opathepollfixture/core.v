// SPDX-License-Identifier: GPL-2.0-or-later
module opathepollfixture

#include <alloca.h>
#include <errno.h>
#include <fcntl.h>
#include <sys/epoll.h>
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
struct Targets { mut: fds [10]i32 normal i32 epfd i32 }
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
fn C.epoll_create1(i32) i32
fn C.epoll_ctl(i32, i32, i32, voidptr) i32
fn C.epoll_wait(i32, voidptr, i32, i32) i32
fn C.epoll_pwait(i32, voidptr, i32, i32, voidptr) i32
fn C.pipe(&i32) i32
fn C.fork() i32
fn C.waitpid(i32, &i32, i32) i32
fn C._exit(i32)
fn C.setgid(u32) i32
fn C.setuid(u32) i32
fn C.getuid() u32
fn C.usleep(u32) i32

fn fatal(stage int) {
	C.printf(c'LINUX OPATHEPOLL FAIL: setup=%d errno=%d\n', stage, unsafe { *C.__errno_location() })
	C.fflush(unsafe { nil }); C._exit(90)
}
fn targets() Targets {
 unsafe {
  mut t := Targets{}
  mut path := [96]char{}
  mut link := [96]char{}
  mut dangling := [96]char{}
  pid := C.syscall(isize(C.SYS_getpid))
  if C.snprintf(&path[0], sizeof(path), c'/tmp/opathepoll-%ld', pid) <= 0 || C.snprintf(&link[0], sizeof(link), c'/tmp/opathepoll-link-%ld', pid) <= 0 || C.snprintf(&dangling[0], sizeof(dangling), c'/tmp/opathepoll-dangling-%ld', pid) <= 0 { fatal(1) }
  t.normal = C.open(&path[0], C.O_CREAT | C.O_EXCL | C.O_RDWR, 0o600)
  if t.normal < 0 { fatal(2) }
  t.fds[0] = C.open(&path[0], C.O_PATH)
  t.fds[1] = C.open(&path[0], C.O_PATH | C.O_CLOEXEC)
  t.fds[2] = C.dup(t.fds[0])
  t.fds[3] = C.fcntl(t.fds[0], C.F_DUPFD_CLOEXEC, 70)
  t.fds[4] = C.open(c'/tmp', C.O_PATH | C.O_DIRECTORY)
  t.fds[5] = C.open(c'/proc/version', C.O_PATH)
  if C.symlink(&path[0], &link[0]) != 0 || C.symlink(c'/missing-opathepoll', &dangling[0]) != 0 { fatal(3) }
  t.fds[6] = C.open(&link[0], C.O_PATH | C.O_NOFOLLOW)
  t.fds[7] = C.open(&dangling[0], C.O_PATH | C.O_NOFOLLOW)
  t.fds[8] = C.open(c'/proc/self/exe', C.O_PATH | C.O_NOFOLLOW)
  t.fds[9] = C.fcntl(t.fds[4], C.F_DUPFD_CLOEXEC, 90)
  t.epfd = C.epoll_create1(C.EPOLL_CLOEXEC)
  if t.epfd < 0 { fatal(20) }
  for fd in t.fds { if fd < 0 || C.fcntl(fd, C.F_GETFL) & C.O_PATH == 0 { fatal(4) } }
  if C.unlink(&link[0]) != 0 || C.unlink(&dangling[0]) != 0 || C.unlink(&path[0]) != 0 { fatal(5) }
  return t
 }
}
fn close_targets(t &Targets) { unsafe { for fd in t.fds { C.close(fd) }; C.close(t.normal); C.close(t.epfd) } }
fn wait_call(api int, fd i32, bytes voidptr) isize {
 unsafe {
  mut ts := C.timespec{}
  match api {
   0 { return C.syscall(isize(C.SYS_epoll_pwait), fd, bytes, 1, 0, nil, 8) }
   1 { return C.epoll_wait(fd, bytes, 1, 0) }
   2 { return C.epoll_pwait(fd, bytes, 1, 0, nil) }
   3 { return C.syscall(isize(C.SYS_epoll_pwait2), fd, bytes, 1, &ts, nil, 8) }
   else { $if amd64 { return C.syscall(isize(C.SYS_epoll_wait), fd, bytes, 1, 0) } $else { fatal(22); return -1 } }
  }
 }
}
fn cycle(t &Targets, apis int, report bool) Totals {
 unsafe {
  mut sum := Totals{}
  for index, fd in t.fds {
   flags := C.fcntl(fd, C.F_GETFL)
   position := C.lseek(t.normal, 0, C.SEEK_CUR)
   for api in 0 .. apis {
    mut failures := 0
    mut checks := 0
    if api < 2 {
     for op in [1, 3, 2]! { for mode in 0 .. 9 { for mask in [u32(0), 0x80000005]! {
      bytes := &u64(C.alloca(32))
      for i in 0 .. 4 { bytes[i] = 0x1122334455667788 }
      (&u32(bytes))[0] = mask
      a, b, c, d := bytes[0], bytes[1], bytes[2], bytes[3]
      epfd := if mode in [0, 6]! { t.epfd } else if mode in [3, 7, 8]! { t.normal } else if mode == 4 { -1 } else { fd }
      target := if mode == 1 { t.normal } else if mode in [5, 8]! { -1 } else if mode in [6, 7]! { t.epfd } else { fd }
      expected := if mode in [6, 7]! { C.EINVAL } else { C.EBADF }
      err := C.__errno_location(); *err = 0
      ret := if api == 0 { C.syscall(isize(C.SYS_epoll_ctl), epfd, op, target, bytes) } else { isize(C.epoll_ctl(epfd, op, target, voidptr(bytes))) }
      code := *err
      good := ret == -1 && code == expected && bytes[0] == a && bytes[1] == b && bytes[2] == c && bytes[3] == d && C.fcntl(fd, C.F_GETFL) == flags && C.lseek(t.normal, 0, C.SEEK_CUR) == position
      // Refused calls cannot leave a registration in the actual epoll set.
      mut out := [4]u64{}
      empty := C.epoll_wait(t.epfd, voidptr(&out[0]), 1, 0) == 0
      checks++
      if !good || !empty { failures++ }
      if (!good || !empty) && report { C.printf(c'LINUX OPATHEPOLL MISMATCH: uid=%u kind=%d api=%d op=%d mode=%d mask=%x actual=%ld/%d\n', C.getuid(), index, api, op, mode, mask, ret, code) }
      if op == 1 && ret == 0 && mode == 0 { C.epoll_ctl(t.epfd, 2, fd, nil) }
     } } }
    } else {
     mut waits := 4
     $if amd64 { waits = 5 }
     for method in 0 .. waits {
      bytes := &u64(C.alloca(32))
      for i in 0 .. 4 { bytes[i] = 0x1122334455667788 }
      err := C.__errno_location(); *err = 0
      ret := wait_call(method, fd, voidptr(bytes))
      code := *err
      mut good := ret == -1 && code == C.EBADF
      for i in 0 .. 4 { if bytes[i] != 0x1122334455667788 { good = false } }
      checks++
      if !good { failures++ }
      if !good && report { C.printf(c'LINUX OPATHEPOLL MISMATCH: uid=%u kind=%d wait=%d actual=%ld/%d\n', C.getuid(), index, method, ret, code) }
     }
    }
    sum.checks += checks; sum.failures += failures
    if report { C.printf(c'LINUX OPATHEPOLL CASE: uid=%u kind=%d api=%d checks=%d failures=%d\n', C.getuid(), index, api, checks, failures) }
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
fn cleanup_cycle(t &Targets) int {
	unsafe {
		mut failures := 0
		for mode in 0 .. 3 {
			alias := C.dup(if mode == 2 { t.fds[0] } else { t.epfd })
			if alias < 0 { fatal(23) }
			mut bytes := [4]u64{}
			(&u32(&bytes[0]))[0] = 1
			err := C.__errno_location(); *err = 0
			ret := C.epoll_ctl(if mode == 0 { alias } else if mode == 1 { t.normal } else { t.epfd }, 1, alias, voidptr(&bytes[0]))
			if ret != -1 || *err != if mode == 2 { C.EBADF } else { C.EINVAL } { failures++ }
			if mode == 2 {
				*err = 0
				if C.epoll_wait(alias, voidptr(&bytes[0]), 1, 0) != -1 || *err != C.EBADF { failures++ }
			}
			if C.close(alias) != 0 { fatal(24) }
		}
		return failures
	}
}
fn storage(t &Targets, apis int) bool {
	unsafe {
		fd := C.open(c'/proc/slabinfo', C.O_RDONLY)
		if fd < 0 { fatal(6) }
		defer { C.close(fd) }
		for _ in 0 .. 16 { if cycle(t, apis, false).failures != 0 || cleanup_cycle(t) != 0 { fatal(7) } }
		C.usleep(13_000_000)
		before := &Slabs(C.alloca(usize(sizeof(Slabs))))
		after := &Slabs(C.alloca(usize(sizeof(Slabs))))
		if !snapshot(fd, before) { fatal(8) }
		mut failures := 0
		for _ in 0 .. 200 { failures += cycle(t, apis, false).failures + cleanup_cycle(t) }
		C.usleep(13_000_000)
		if !snapshot(fd, after) { fatal(9) }
		mut good := failures == 0 && before.rows == after.rows && before.large == after.large && before.tainted == 0 && after.tainted == 0
		for row in 0 .. before.rows {
			if before.sizes[row] != after.sizes[row] || before.live[row] != after.live[row] { good = false }
			C.printf(c'LINUX OPATHEPOLL SLAB: uid=%u size=%lu live=%lu/%lu\n', C.getuid(), before.sizes[row], before.live[row], after.live[row])
		}
		C.printf(c'LINUX OPATHEPOLL STORAGE: uid=%u cycles=200 big_pages=%lu/%lu tainted=%lu/%lu %s\n', C.getuid(), before.large, after.large, before.tainted, after.tainted, if good { &char(c'PASS') } else { &char(c'FAIL') })
		return good
	}
}
@[export: 'main']
pub fn run(argc i32, argv &&char) i32 {
	unsafe {
		C.alarm(600)
		if C.chmod(c'/tmp', 0o1777) != 0 { fatal(10) }
		reference := argc == 2 && C.strcmp(argv[1], c'--reference') == 0
		apis := 3
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
				if reference { C.printf(c'LINUX OPATHEPOLL STORAGE: uid=%u SKIP reference\n', C.getuid()) }
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
		C.printf(c'LINUX OPATHEPOLL SUMMARY: checks=%d failures=%d\n', total.checks, total.failures)
		C.printf(c'LINUX OPATHEPOLL: %s\n', if total.failures == 0 { &char(c'PASS') } else { &char(c'FAIL') })
		C.fflush(nil); C.alarm(0)
		for { C.pause() }
	}
	return 0
}
