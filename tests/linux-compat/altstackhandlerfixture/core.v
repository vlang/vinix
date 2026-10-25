// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module altstackhandlerfixture

#include <errno.h>
#include <signal.h>
#include <stdio.h>
#include <sys/mman.h>
#include <sys/syscall.h>
#include <sys/wait.h>
#include <unistd.h>
#include <alloca.h>

@[typedef]
struct C.sigset_t {}
@[typedef]
struct C.siginfo_t {}
struct C.sigaction {
mut:
 sa_sigaction fn (i32, &C.siginfo_t, voidptr)
 sa_mask C.sigset_t
 sa_flags i32
}
struct Totals { mut: checks i32 failures i32 }
__global (
 totals Totals
 page usize
 input_memory usize
 output_memory usize
 readonly usize
 stack_base usize
 handler_calls i32
)
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
fn C.memcmp(voidptr, voidptr, usize) i32
fn C.alloca(usize) voidptr
fn C.sigaction(i32, &C.sigaction, &C.sigaction) i32
fn C.sigemptyset(&C.sigset_t) i32
fn C.raise(i32) i32

fn fatal(stage int) {
 C.printf(c'LINUX ALTSTACKHANDLER FAIL: setup=%d errno=%d\n', stage, unsafe { *C.__errno_location() })
 C.fflush(unsafe { nil }); C._exit(90)
}
fn check(good bool, stage int) {
 unsafe {
  totals.checks++
  if !good {
   totals.failures++
   if totals.failures <= 30 { C.printf(c'LINUX ALTSTACKHANDLER MISMATCH: stage=%d\n', stage) }
  }
 }
}
fn call(input voidptr, output voidptr) isize {
 unsafe { location := C.__errno_location(); *location = 0 }
 return C.syscall(isize(C.SYS_sigaltstack), input, output)
}
fn bytes_are(pointer voidptr, size int, value u8) bool {
 unsafe {
  data := &u8(pointer)
  for i in 0 .. size { if data[i] != value { return false } }
 }
 return true
}
fn record_is(pointer voidptr, flags u32) bool {
 unsafe {
  mut raw := [3]u64{}
  C.memcpy(&raw[0], pointer, 24)
  return raw[0] == u64(stack_base) && u32(raw[1]) == flags && raw[2] == 65536
 }
}

// Every request runs inside a real SA_ONSTACK handler. Readable updates must
// fail EPERM, even with an invalid mode/size; unreadable inputs fail EFAULT
// first. Queries still work and report SS_ONSTACK without changing the stack.
fn handler(signum i32, _info &C.siginfo_t, _context voidptr) {
 unsafe {
  handler_calls++
  marker := usize(C.alloca(1))
  check(signum == C.SIGUSR1 && marker >= stack_base && marker < stack_base + 65536, 10)
  input_tail := &u8(input_memory + page - 48)
  output_tail := &u8(output_memory + page - 48)
  for flags in [u32(0), 1, 2, 3, 4, 7, 0x7fffffff, 0xfffffffe]! {
   for size in [u64(0), 2048, 65536]! {
    for input_kind in 0 .. 9 {
     for output_kind in 0 .. 9 {
      mut input_buffer := [48]u8{init: 0xa5}
      mut output_buffer := [48]u8{init: 0xa5}
      for i in 0 .. 48 { input_tail[i] = 0xa5; output_tail[i] = 0xa5 }
      mut request := [3]u64{}
      request[0] = u64(stack_base); request[1] = (u64(0xa5a5a5a5) << 32) | u64(flags); request[2] = size
      input_offset := if input_kind == 1 { 8 } else { 3 }
      input := if input_kind == 0 { nil }
       else if input_kind < 3 { voidptr(&input_buffer[input_offset]) }
       else if input_kind == 3 { voidptr(&input_tail[24]) }
       else if input_kind == 4 { voidptr(1) }
       else if input_kind == 5 { voidptr(usize(-1)) }
       else if input_kind == 6 { voidptr(input_memory + page) }
       else if input_kind == 7 { voidptr(&input_tail[36]) }
       else { voidptr(&input_tail[28]) }
      if input_kind >= 1 && input_kind <= 3 { C.memcpy(input, &request[0], 24) }
      if input_kind >= 7 { C.memcpy(input, &request[0], if input_kind == 7 { 12 } else { 20 }) }
      output_offset := if output_kind == 1 { 8 } else { 3 }
      output := if output_kind == 0 { nil }
       else if output_kind < 3 { voidptr(&output_buffer[output_offset]) }
       else if output_kind == 3 { voidptr(&output_tail[24]) }
       else if output_kind == 4 { voidptr(1) }
       else if output_kind == 5 { voidptr(usize(-1)) }
       else if output_kind == 6 { voidptr(readonly) }
       else if output_kind == 7 { voidptr(&output_tail[36]) }
       else { input }
      bad_output := output_kind >= 4 && output_kind <= 7
      expected := if input_kind >= 4 { C.EFAULT }
       else if input_kind != 0 { C.EPERM }
       else if bad_output { C.EFAULT } else { 0 }
      result := call(input, output)
      code := *C.__errno_location()
      check(result == if expected == 0 { isize(0) } else { isize(-1) }, 20)
      check(code == expected, 21)
      mut current := [3]u64{}
      query := call(nil, &current[0])
      check(query == 0 && record_is(&current[0], 1), 22)
      writes_record := input_kind == 0 && output_kind in [1, 2, 3]!
      mut good_output := true
      if output_kind in [1, 2, 3]! {
       good_output = if writes_record { record_is(output, 1) } else { bytes_are(output, 24, 0xa5) }
      }
      check(good_output, 23)
      mut guards := true
      for i in 0 .. 48 {
       if !(input_kind in [1, 2]! && i >= input_offset && i < input_offset + 24) && input_buffer[i] != 0xa5 { guards = false }
       if !(writes_record && output_kind in [1, 2]! && i >= output_offset && i < output_offset + 24) && output_buffer[i] != 0xa5 { guards = false }
       if i < (if input_kind == 7 { 36 } else if input_kind == 8 { 28 } else { 24 }) && input_tail[i] != 0xa5 { guards = false }
       if i < (if input_kind == 0 && output_kind == 7 { 36 } else if writes_record && output_kind == 3 { 24 } else { 48 }) && output_tail[i] != 0xa5 { guards = false }
      }
      if input_kind >= 1 && input_kind <= 3 && C.memcmp(input, &request[0], 24) != 0 { guards = false }
      if input_kind >= 7 && C.memcmp(input, &request[0], if input_kind == 7 { 12 } else { 20 }) != 0 { guards = false }
      check(guards, 24)
     }
    }
   }
  }
 }
}

fn suite() {
 unsafe {
  page = usize(C.sysconf(C._SC_PAGESIZE))
  if page < 4096 || page > 65536 { fatal(1) }
  input_memory = usize(C.mmap(nil, page * 2, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
  output_memory = usize(C.mmap(nil, page * 2, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
  readonly = usize(C.mmap(nil, page, C.PROT_READ, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
  allocation := usize(C.mmap(nil, page * 2 + 65536, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
  if input_memory == usize(-1) || output_memory == usize(-1) || readonly == usize(-1) || allocation == usize(-1) { fatal(2) }
  stack_base = allocation + page
  if C.mprotect(voidptr(input_memory + page), page, C.PROT_NONE) != 0 || C.mprotect(voidptr(output_memory + page), page, C.PROT_NONE) != 0 || C.mprotect(voidptr(allocation), page, C.PROT_NONE) != 0 || C.mprotect(voidptr(stack_base + 65536), page, C.PROT_NONE) != 0 { fatal(3) }
  mut raw := [u64(stack_base), u64(0), u64(65536)]!
  if call(&raw[0], nil) != 0 { fatal(4) }
  mut action := C.sigaction{sa_sigaction: handler, sa_flags: C.SA_SIGINFO | C.SA_ONSTACK}
  if C.sigemptyset(&action.sa_mask) != 0 || C.sigaction(C.SIGUSR1, &action, nil) != 0 { fatal(5) }
  if C.raise(C.SIGUSR1) != 0 { fatal(6) }
  mut after := [3]u64{}
  result := call(nil, &after[0])
  check(handler_calls == 1 && result == 0 && record_is(&after[0], 0), 30)
  raw[1] = 2
  if call(&raw[0], nil) != 0 { fatal(7) }
  if C.munmap(voidptr(input_memory), page * 2) != 0 || C.munmap(voidptr(output_memory), page * 2) != 0 || C.munmap(voidptr(readonly), page) != 0 || C.munmap(voidptr(allocation), page * 2 + 65536) != 0 { fatal(8) }
 }
}

@[export: 'main']
pub fn run() i32 {
 unsafe {
  C.alarm(120)
  mut total := Totals{}
  for unprivileged in [false, true]! {
   mut pipe := [2]i32{}
   if C.pipe(&pipe[0]) != 0 { fatal(9) }
   C.fflush(nil)
   pid := C.fork()
   if pid < 0 { fatal(10) }
   if pid == 0 {
    C.close(pipe[0])
    if unprivileged && (C.setgid(2000) != 0 || C.setuid(1000) != 0) { fatal(11) }
    suite()
    if C.write(pipe[1], &totals, sizeof(Totals)) != sizeof(Totals) { fatal(12) }
    C.fflush(nil); C._exit(0)
   }
   C.close(pipe[1])
   mut t := Totals{}
   if C.read(pipe[0], &t, sizeof(Totals)) != sizeof(Totals) { fatal(13) }
   mut status := i32(0)
   if C.waitpid(pid, &status, 0) != pid || status != 0 { fatal(14) }
   C.close(pipe[0]); total.checks += t.checks; total.failures += t.failures
  }
  C.printf(c'LINUX ALTSTACKHANDLER SUMMARY: checks=%d failures=%d\n', total.checks, total.failures)
  if total.failures == 0 { C.printf(c'LINUX ALTSTACKHANDLER: PASS\n') } else { C.printf(c'LINUX ALTSTACKHANDLER: FAIL\n') }
  C.fflush(nil); C.alarm(0)
  for { C.pause() }
 }
 return 0
}
