// SPDX-License-Identifier: GPL-2.0-or-later
module altstackcopyfixture

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
 C.printf(c'LINUX ALTSTACKCOPY FAIL: setup=%d errno=%d\n', stage, unsafe { *C.__errno_location() })
 C.fflush(unsafe { nil }); C._exit(90)
}
fn check(mut t Totals, good bool, stage int) {
 t.checks++
 if !good {
  t.failures++
  if t.failures <= 30 { C.printf(c'LINUX ALTSTACKCOPY MISMATCH: stage=%d\n', stage) }
 }
}
fn call(input voidptr, output voidptr) isize {
 unsafe { location := C.__errno_location(); *location = 0 }
 return C.syscall(isize(C.SYS_sigaltstack), input, output)
}
fn establish(enabled bool, stack voidptr) {
 unsafe {
  mut raw := [3]u64{}
  raw[0] = u64(usize(stack)); raw[1] = if enabled { u64(0) } else { u64(2) }; raw[2] = 65536
  if call(&raw[0], nil) != 0 { fatal(1) }
 }
}
fn state_is(mut t Totals, enabled bool, stack voidptr) {
 unsafe {
  mut raw := [3]u64{init: u64(-1)}
  check(mut t, call(nil, &raw[0]) == 0, 10)
  check(mut t, raw[0] == (if enabled { u64(usize(stack)) } else { u64(0) }) &&
   raw[1] == (if enabled { u64(0) } else { u64(2) }) &&
   raw[2] == (if enabled { u64(131072) } else { u64(0) }), 11)
 }
}
fn old_is(pointer voidptr, enabled bool, stack voidptr) bool {
 unsafe {
  mut raw := [3]u64{}
  C.memcpy(&raw[0], pointer, 24)
  return raw[0] == (if enabled { u64(usize(stack)) } else { u64(0) }) &&
   raw[1] == (if enabled { u64(0) } else { u64(2) }) &&
   raw[2] == (if enabled { u64(65536) } else { u64(0) })
 }
}

// A valid update is committed before the old-stack output is copied. Input
// faults and validation errors preserve state and do not copy the old record.
fn suite(mut t Totals) {
 unsafe {
  pages := usize(C.sysconf(C._SC_PAGESIZE))
  if pages < 4096 || pages > 65536 { fatal(2) }
  memory := C.mmap(nil, pages * 2, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0)
  readonly := C.mmap(nil, pages, C.PROT_READ, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0)
  gone := C.mmap(nil, pages, C.PROT_READ, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0)
  stack := C.mmap(nil, 262144, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0)
  if memory == voidptr(usize(-1)) || readonly == voidptr(usize(-1)) || gone == voidptr(usize(-1)) || stack == voidptr(usize(-1)) { fatal(3) }
  if C.mprotect(voidptr(usize(memory) + pages), pages, C.PROT_NONE) != 0 || C.munmap(gone, pages) != 0 { fatal(4) }
  next_stack := voidptr(usize(stack) + 131072)
  for before in [false, true]! {
   for after in [false, true]! {
    for pointer in [voidptr(1), voidptr(usize(-1)), gone, voidptr(usize(memory) + pages), readonly, voidptr(usize(memory) + pages - 12)]! {
     establish(before, stack)
     mut request := [3]u64{}
     request[0] = u64(usize(next_stack)); request[1] = (u64(0xa5a5a5a5) << 32) | if after { u64(0) } else { u64(2) }; request[2] = 131072
     result := call(&request[0], pointer)
     check(mut t, result == -1 && *C.__errno_location() == C.EFAULT, 20)
     state_is(mut t, after, next_stack)
    }
    for kind in 0 .. 5 {
     establish(before, stack)
     mut request := [3]u64{}
     request[0] = u64(usize(next_stack)); request[1] = if after { u64(0) } else { u64(2) }; request[2] = 131072
     mut buffer := [48]u8{init: 0xa5}
     pointer := if kind == 0 { voidptr(&buffer[8]) } else if kind == 1 { voidptr(&buffer[3]) } else if kind == 2 { voidptr(usize(memory) + pages - 24) } else if kind == 3 { nil } else { voidptr(&request[0]) }
     check(mut t, call(&request[0], pointer) == 0, 21)
     state_is(mut t, after, next_stack)
     if kind != 3 { check(mut t, old_is(pointer, before, stack), 22) }
     if kind < 2 {
      offset := if kind == 0 { 8 } else { 3 }
      mut good := true
      for i in 0 .. 48 { if (i < offset || i >= offset + 24) && buffer[i] != 0xa5 { good = false } }
      check(mut t, good, 23)
     }
    }
   }
   // Validation must win over an inaccessible output. A valid output must
   // remain untouched when input import or validation fails.
   for invalid in 0 .. 8 {
    for bad_output in [false, true]! {
     establish(before, stack)
     mut request := [3]u64{}
     request[0] = u64(usize(next_stack)); request[1] = if invalid == 0 { u64(4) } else { u64(0) }; request[2] = if invalid == 1 { u64(1) } else { u64(131072) }
     pointer := if invalid < 2 { voidptr(&request[0]) } else if invalid == 2 { voidptr(1) } else if invalid == 3 { voidptr(usize(-1)) } else if invalid == 4 { gone } else if invalid == 5 { voidptr(usize(memory) + pages) } else if invalid == 6 { voidptr(usize(memory) + pages - 23) } else { voidptr(usize(memory) + pages - 8) }
     mut buffer := [3]u64{init: u64(0xa5a5a5a5a5a5a5a5)}
     output := if bad_output { voidptr(1) } else { voidptr(&buffer[0]) }
     result := call(pointer, output)
     expected := if invalid == 0 { C.EINVAL } else if invalid == 1 { C.ENOMEM } else { C.EFAULT }
     check(mut t, result == -1 && *C.__errno_location() == expected, 30)
     check(mut t, old_is_current(before, stack), 31)
     check(mut t, buffer[0] == 0xa5a5a5a5a5a5a5a5 && buffer[1] == 0xa5a5a5a5a5a5a5a5 && buffer[2] == 0xa5a5a5a5a5a5a5a5, 32)
    }
   }
   establish(before, stack)
   check(mut t, call(nil, nil) == 0, 33)
   check(mut t, old_is_current(before, stack), 34)
   for pointer in [voidptr(1), voidptr(usize(-1)), gone, voidptr(usize(memory) + pages), readonly, voidptr(usize(memory) + pages - 12)]! {
    result := call(nil, pointer)
    check(mut t, result == -1 && *C.__errno_location() == C.EFAULT, 35)
    check(mut t, old_is_current(before, stack), 36)
   }
  }
  establish(false, stack)
  if C.munmap(memory, pages * 2) != 0 || C.munmap(readonly, pages) != 0 || C.munmap(stack, 262144) != 0 { fatal(5) }
 }
}
fn old_is_current(enabled bool, stack voidptr) bool {
 unsafe {
  mut raw := [3]u64{}
  if call(nil, &raw[0]) != 0 { fatal(6) }
  return old_is(&raw[0], enabled, stack)
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
  C.printf(c'LINUX ALTSTACKCOPY SUMMARY: checks=%d failures=%d\n', total.checks, total.failures)
  if total.failures == 0 { C.printf(c'LINUX ALTSTACKCOPY: PASS\n') } else { C.printf(c'LINUX ALTSTACKCOPY: FAIL\n') }
  C.fflush(nil); C.alarm(0)
  for { C.pause() }
 }
 return 0
}
