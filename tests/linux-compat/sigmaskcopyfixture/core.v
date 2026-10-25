// SPDX-License-Identifier: GPL-2.0-or-later
module sigmaskcopyfixture

#include <errno.h>
#include <signal.h>
#include <stdio.h>
#include <sys/mman.h>
#include <sys/syscall.h>
#include <sys/wait.h>
#include <unistd.h>

struct Totals { mut: checks i32 failures i32 }
fn C.syscall(isize, ...) isize
fn C.__errno_location() &i32
fn C.printf(&char, ...) i32
fn C.fflush(voidptr) i32
fn C.alarm(u32) u32
fn C.pause() i32
fn C.fork() i32
fn C.waitpid(i32, &i32, i32) i32
fn C.pipe(&i32) i32
fn C.read(i32, voidptr, usize) isize
fn C.write(i32, voidptr, usize) isize
fn C.close(i32) i32
fn C.setgid(u32) i32
fn C.setuid(u32) i32
fn C.sysconf(i32) isize
fn C._exit(i32)
fn C.mmap(voidptr, usize, i32, i32, i32, isize) voidptr
fn C.mprotect(voidptr, usize, i32) i32
fn C.munmap(voidptr, usize) i32
fn C.memcpy(voidptr, voidptr, usize) voidptr

fn fatal(stage int) {
 C.printf(c'LINUX SIGMASKCOPY FAIL: setup=%d errno=%d\n', stage, unsafe { *C.__errno_location() })
 C.fflush(unsafe { nil }); C._exit(90)
}
fn check(mut t Totals, good bool, stage int) {
 t.checks++
 if !good {
  t.failures++
  if t.failures <= 30 { C.printf(c'LINUX SIGMASKCOPY MISMATCH: stage=%d\n', stage) }
 }
}
fn call(how i32, input voidptr, output voidptr, size usize) isize {
 unsafe { location := C.__errno_location(); *location = 0 }
 return C.syscall(isize(C.SYS_rt_sigprocmask), how, input, output, size)
}
fn blocked() u64 {
 unsafe {
  mut mask := u64(0)
  if call(-1, nil, &mask, 8) != 0 { fatal(1) }
  return mask
 }
}
fn establish(value u64) {
 mask := value
 if call(2, unsafe { &mask }, unsafe { nil }, 8) != 0 { fatal(2) }
}
fn allowed(mask u64) u64 { return mask & ~((u64(1) << 8) | (u64(1) << 18)) }
fn changed(before u64, input u64, how int) u64 {
 return allowed(if how == 0 { before | input } else if how == 1 { before & ~input } else { input })
}

// The update precedes copying the old mask to userspace, even on EFAULT.
// Size, input-import and how errors precede both the update and old output.
fn suite(mut t Totals) {
 unsafe {
  original := blocked()
  pages := usize(C.sysconf(C._SC_PAGESIZE))
  if pages < 4096 || pages > 65536 { fatal(3) }
  memory := C.mmap(nil, pages * 2, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0)
  readonly := C.mmap(nil, pages, C.PROT_READ, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0)
  gone := C.mmap(nil, pages, C.PROT_READ, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0)
  if memory == voidptr(usize(-1)) || readonly == voidptr(usize(-1)) || gone == voidptr(usize(-1)) { fatal(4) }
  if C.mprotect(voidptr(usize(memory) + pages), pages, C.PROT_NONE) != 0 || C.munmap(gone, pages) != 0 { fatal(5) }
  for before in [u64(0), u64(1) << 9 | u64(1) << 62, allowed(u64(-1)), u64(1) << 63]! {
   for value in [u64(0), u64(1) << 11 | u64(1) << 34, u64(-1), u64(1) << 63]! {
    for how in 0 .. 3 {
     for pointer in [voidptr(1), voidptr(usize(-1)), gone, voidptr(usize(memory) + pages), readonly, voidptr(usize(memory) + pages - 4)]! {
      establish(before)
      input := value
      result := call(i32(how), &input, pointer, 8)
      check(mut t, result == -1 && *C.__errno_location() == C.EFAULT, 10)
      check(mut t, blocked() == changed(before, value, how), 11)
     }
     for kind in 0 .. 5 {
      establish(before)
      mut input := value
      mut buffer := [32]u8{init: 0xa5}
      pointer := if kind == 0 { voidptr(&buffer[8]) } else if kind == 1 { voidptr(&buffer[3]) } else if kind == 2 { voidptr(usize(memory) + pages - 8) } else if kind == 3 { nil } else { voidptr(&input) }
      check(mut t, call(i32(how), &input, pointer, 8) == 0, 12)
      check(mut t, blocked() == changed(before, value, how), 13)
      if kind != 3 {
       mut old := u64(0)
       C.memcpy(&old, pointer, 8)
       check(mut t, old == before, 14)
      }
      if kind < 2 {
       offset := if kind == 0 { 8 } else { 3 }
       mut good := true
       for i in 0 .. 32 { if (i < offset || i >= offset + 8) && buffer[i] != 0xa5 { good = false } }
       check(mut t, good, 15)
      }
     }
    }
   }
   for invalid in 0 .. 9 {
    for bad_output in [false, true]! {
     establish(before)
     input := u64(-1)
     pointer := if invalid < 3 { voidptr(&input) } else if invalid == 3 { voidptr(1) } else if invalid == 4 { voidptr(usize(-1)) } else if invalid == 5 { gone } else if invalid == 6 { voidptr(usize(memory) + pages) } else if invalid == 7 { voidptr(usize(memory) + pages - 1) } else { voidptr(usize(memory) + pages - 7) }
     how := if invalid == 0 { i32(3) } else if invalid == 1 { i32(-1) } else { i32(-2147483648) }
     mut output := u64(0xa5a5a5a5a5a5a5a5)
     result := call(how, pointer, if bad_output { voidptr(1) } else { voidptr(&output) }, 8)
     check(mut t, result == -1 && *C.__errno_location() == (if invalid < 3 { C.EINVAL } else { C.EFAULT }), 20)
     check(mut t, blocked() == before, 21)
     check(mut t, output == 0xa5a5a5a5a5a5a5a5, 22)
    }
   }
   for size in [usize(0), usize(1), usize(7), usize(9), usize(16), usize(-1)]! {
    for pointers in [false, true]! {
     establish(before)
     input := u64(-1)
     mut output := u64(0xa5a5a5a5a5a5a5a5)
     result := call(-1, if pointers { voidptr(1) } else { voidptr(&input) }, if pointers { voidptr(1) } else { voidptr(&output) }, size)
     check(mut t, result == -1 && *C.__errno_location() == C.EINVAL, 23)
     check(mut t, blocked() == before && output == 0xa5a5a5a5a5a5a5a5, 24)
    }
   }
   for how in [i32(0), i32(1), i32(2), i32(3), i32(-1), i32(-2147483648)]! {
    establish(before)
    mut old := u64(-1)
    check(mut t, call(how, nil, &old, 8) == 0 && old == before && blocked() == before, 25)
    check(mut t, call(how, nil, nil, 8) == 0 && blocked() == before, 26)
    for pointer in [voidptr(1), voidptr(usize(-1)), gone, voidptr(usize(memory) + pages), readonly, voidptr(usize(memory) + pages - 4)]! {
     result := call(how, nil, pointer, 8)
     check(mut t, result == -1 && *C.__errno_location() == C.EFAULT, 27)
     check(mut t, blocked() == before, 28)
    }
   }
  }
  establish(original)
  if C.munmap(memory, pages * 2) != 0 || C.munmap(readonly, pages) != 0 { fatal(6) }
 }
}

@[export: 'main']
pub fn run() i32 {
 unsafe {
  C.alarm(120)
  mut total := Totals{}
  for unprivileged in [false, true]! {
   mut pipe := [2]i32{}
   if C.pipe(&pipe[0]) != 0 { fatal(7) }
   C.fflush(nil)
   pid := C.fork()
   if pid < 0 { fatal(8) }
   if pid == 0 {
    C.close(pipe[0])
    if unprivileged && (C.setgid(2000) != 0 || C.setuid(1000) != 0) { fatal(9) }
    mut t := Totals{}
    suite(mut t)
    if C.write(pipe[1], &t, sizeof(Totals)) != sizeof(Totals) { fatal(10) }
    C.fflush(nil); C._exit(0)
   }
   C.close(pipe[1])
   mut t := Totals{}
   if C.read(pipe[0], &t, sizeof(Totals)) != sizeof(Totals) { fatal(11) }
   mut status := i32(0)
   if C.waitpid(pid, &status, 0) != pid || status != 0 { fatal(12) }
   C.close(pipe[0])
   total.checks += t.checks; total.failures += t.failures
  }
  C.printf(c'LINUX SIGMASKCOPY SUMMARY: checks=%d failures=%d\n', total.checks, total.failures)
  if total.failures == 0 { C.printf(c'LINUX SIGMASKCOPY: PASS\n') } else { C.printf(c'LINUX SIGMASKCOPY: FAIL\n') }
  C.fflush(nil); C.alarm(0)
  for { C.pause() }
 }
 return 0
}
