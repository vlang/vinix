// SPDX-License-Identifier: GPL-2.0-or-later
module sigactioncopyfixture

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
 C.printf(c'LINUX SIGACTIONCOPY FAIL: setup=%d errno=%d\n', stage, unsafe { *C.__errno_location() })
 C.fflush(unsafe { nil }); C._exit(90)
}
fn check(mut t Totals, good bool, stage int) {
 t.checks++
 if !good {
  t.failures++
  if t.failures <= 30 { C.printf(c'LINUX SIGACTIONCOPY MISMATCH: stage=%d\n', stage) }
 }
}
fn call(signal int, input voidptr, output voidptr, size usize) isize {
 unsafe { location := C.__errno_location(); *location = 0 }
 return C.syscall(isize(C.SYS_rt_sigaction), i32(signal), input, output, size)
}
fn action(signal int) [4]u64 {
 mut output := [4]u64{}
 if call(signal, unsafe { nil }, unsafe { &output[0] }, 8) != 0 { fatal(1) }
 return output
}
fn establish(signal int, value [4]u64) {
 if call(signal, unsafe { &value[0] }, unsafe { nil }, 8) != 0 { fatal(2) }
}
fn normalized(value [4]u64) [4]u64 {
 mut output := value
 output[3] &= ~((u64(1) << 8) | (u64(1) << 18))
 return output
}
fn pattern(kind int) [4]u64 {
 return [u64(kind & 1), if kind < 2 { u64(0) } else { u64(0x10000004) }, u64(0),
  if kind == 0 { u64(0) } else if kind == 1 { u64(-1) } else if kind == 2 { u64(1) << 63 } else { u64(1) << 9 | u64(1) << 34 }]!
}

// No signals are delivered: this isolates disposition mutation and usercopy.
// A valid update survives output EFAULT; import/size errors preserve state.
fn suite(mut t Totals) {
 unsafe {
  pages := usize(C.sysconf(C._SC_PAGESIZE))
  if pages < 4096 || pages > 65536 { fatal(3) }
  memory := C.mmap(nil, pages * 2, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0)
  readonly := C.mmap(nil, pages, C.PROT_READ, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0)
  gone := C.mmap(nil, pages, C.PROT_READ, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0)
  if memory == voidptr(usize(-1)) || readonly == voidptr(usize(-1)) || gone == voidptr(usize(-1)) { fatal(4) }
  if C.mprotect(voidptr(usize(memory) + pages), pages, C.PROT_NONE) != 0 || C.munmap(gone, pages) != 0 { fatal(5) }
  bad := [voidptr(1), voidptr(usize(-1)), gone, voidptr(usize(memory) + pages), readonly, voidptr(usize(memory) + pages - 16)]!
  for signal in [10, 12, 35]! {
   original := action(signal)
   for before_kind in 0 .. 4 {
    before := pattern(before_kind)
    for incoming_kind in 0 .. 4 {
     value := pattern(incoming_kind)
     for pointer in bad {
      establish(signal, before)
      result := call(signal, &value[0], pointer, 8)
      check(mut t, result == -1 && *C.__errno_location() == C.EFAULT, 10)
      check(mut t, action(signal) == normalized(value), 11)
     }
     for kind in 0 .. 5 {
      establish(signal, before)
      mut input := value
      mut buffer := [48]u8{init: 0xa5}
      pointer := if kind == 0 { voidptr(&buffer[8]) } else if kind == 1 { voidptr(&buffer[3]) } else if kind == 2 { voidptr(usize(memory) + pages - 32) } else if kind == 3 { nil } else { voidptr(&input[0]) }
      check(mut t, call(signal, &input[0], pointer, 8) == 0, 12)
      check(mut t, action(signal) == normalized(value), 13)
      if kind != 3 {
       mut old := [4]u64{}
       C.memcpy(&old[0], pointer, 32)
       check(mut t, old == normalized(before), 14)
      }
      if kind < 2 {
       offset := if kind == 0 { 8 } else { 3 }
       mut good := true
       for i in 0 .. 48 { if (i < offset || i >= offset + 32) && buffer[i] != 0xa5 { good = false } }
       check(mut t, good, 15)
      }
     }
    }
    for pointer in [voidptr(1), voidptr(usize(-1)), gone, voidptr(usize(memory) + pages), voidptr(usize(memory) + pages - 1), voidptr(usize(memory) + pages - 31)]! {
     for bad_output in [false, true]! {
      establish(signal, before)
      mut output := [4]u64{init: 0xa5a5a5a5a5a5a5a5}
      result := call(signal, pointer, if bad_output { voidptr(1) } else { voidptr(&output[0]) }, 8)
      check(mut t, result == -1 && *C.__errno_location() == C.EFAULT, 20)
      check(mut t, action(signal) == normalized(before), 21)
      check(mut t, output == [u64(0xa5a5a5a5a5a5a5a5), u64(0xa5a5a5a5a5a5a5a5), u64(0xa5a5a5a5a5a5a5a5), u64(0xa5a5a5a5a5a5a5a5)]!, 22)
     }
    }
    for size in [usize(0), usize(1), usize(7), usize(9), usize(16), usize(-1)]! {
     for pointers in [false, true]! {
      establish(signal, before)
      value := pattern(1)
      mut output := [4]u64{init: 0xa5a5a5a5a5a5a5a5}
      result := call(signal, if pointers { voidptr(1) } else { voidptr(&value[0]) }, if pointers { voidptr(1) } else { voidptr(&output[0]) }, size)
      check(mut t, result == -1 && *C.__errno_location() == C.EINVAL, 23)
      check(mut t, action(signal) == normalized(before) && output[0] == 0xa5a5a5a5a5a5a5a5 && output[1] == output[0] && output[2] == output[0] && output[3] == output[0], 24)
     }
    }
    establish(signal, before)
    check(mut t, call(signal, nil, nil, 8) == 0 && action(signal) == normalized(before), 25)
    for pointer in bad {
     result := call(signal, nil, pointer, 8)
     check(mut t, result == -1 && *C.__errno_location() == C.EFAULT, 26)
     check(mut t, action(signal) == normalized(before), 27)
    }
   }
   establish(signal, original)
  }
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
  C.printf(c'LINUX SIGACTIONCOPY SUMMARY: checks=%d failures=%d\n', total.checks, total.failures)
  if total.failures == 0 { C.printf(c'LINUX SIGACTIONCOPY: PASS\n') } else { C.printf(c'LINUX SIGACTIONCOPY: FAIL\n') }
  C.fflush(nil); C.alarm(0)
  for { C.pause() }
 }
 return 0
}
