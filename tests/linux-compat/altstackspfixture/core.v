// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module altstackspfixture

#include <alloca.h>
#include <errno.h>
#include <signal.h>
#include <stdio.h>
#include <sys/mman.h>
#include <sys/syscall.h>
#include <sys/wait.h>
#include <unistd.h>

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
 C.printf(c'LINUX ALTSTACKSP FAIL: setup=%d errno=%d\n', stage, unsafe { *C.__errno_location() })
 C.fflush(unsafe { nil }); C._exit(90)
}
fn check(good bool, stage int, phase int, position int, mode int) {
 unsafe {
  totals.checks++
  if !good {
   totals.failures++
   if totals.failures <= 30 { C.printf(c'LINUX ALTSTACKSP MISMATCH: stage=%d phase=%d position=%d mode=%d\n', stage, phase, position, mode) }
  }
 }
}
fn bytes_are(pointer voidptr, size int) bool {
 unsafe {
  data := &u8(pointer)
  for i in 0 .. size { if data[i] != 0xa5 { return false } }
 }
 return true
}

// No stack access or function call occurs between moving SP and restoring it.
// The saved SP register survives the Linux syscall ABI on both architectures.
// Signals other than the synchronous test handler remain absent during this
// single-threaded probe; the alarm is only a watchdog for a broken guest.
fn pivot(target usize, input voidptr, output voidptr) isize {
 number := isize(C.SYS_sigaltstack)
 mut returned := isize(0)
 $if arm64 {
  asm arm64 raw {
   "mov x9, sp\n\tmov sp, %[target]\n\tmov x8, %[number]\n\tmov x0, %[input]\n\tmov x1, %[output]\n\tsvc #0\n\tmov %[returned], x0\n\tmov sp, x9"
   ; [returned] "=r" (returned)
   ; [target] "r" (target)
     [number] "r" (number)
     [input] "r" (input)
     [output] "r" (output)
   ; x0
     x1
     x8
     x9
     memory
     cc
  }
 } $else {
  asm amd64 raw {
   "mov %%rsp, %%r12\n\tmov %[target], %%rsp\n\tmov %[number], %%rax\n\tmov %[input], %%rdi\n\tmov %[output], %%rsi\n\tsyscall\n\tmov %%rax, %[returned]\n\tmov %%r12, %%rsp"
   ; [returned] "=r" (returned)
   ; [target] "r" (target)
     [number] "r" (number)
     [input] "r" (input)
     [output] "r" (output)
   ; rax
     rdi
     rsi
     rcx
     r11
     r12
     memory
     cc
  }
 }
 return returned
}

fn positions(phase int) {
 unsafe {
  for position, offset in [-16, 0, 16, 65520, 65536, 65552]! {
   target := usize(isize(stack_base) + offset)
   active := offset > 0 && offset <= 65536
   for mode in 0 .. 4 {
    mut request := [u64(stack_base), u64(if mode == 2 { 4 } else { 0 }), u64(if mode == 3 { 0 } else { 65536 })]!
    mut out := [48]u8{init: 0xa5}
    result := pivot(target, if mode == 0 { nil } else { voidptr(&request[0]) }, &out[8])
    expected := if mode == 0 { isize(0) } else if active { -isize(C.EPERM) }
      else if mode == 2 { -isize(C.EINVAL) } else if mode == 3 { -isize(C.ENOMEM) } else { isize(0) }
    check(result == expected, 20, phase, position, mode)
    mut old := [3]u64{}
    C.memcpy(&old[0], &out[8], 24)
    good_output := if expected == 0 {
      old[0] == stack_base && u32(old[1]) == if active { u32(1) } else { u32(0) } && old[2] == 65536
     } else { bytes_are(&out[8], 24) }
    check(good_output, 21, phase, position, mode)
    mut current := [3]u64{}
    query := C.syscall(isize(C.SYS_sigaltstack), nil, &current[0])
    check(query == 0 && current[0] == stack_base && u32(current[1]) == if phase == 1 { u32(1) } else { u32(0) } && current[2] == 65536, 22, phase, position, mode)
    check(bytes_are(&out[0], 8) && bytes_are(&out[32], 16) && request[0] == stack_base && request[1] == u64(if mode == 2 { 4 } else { 0 }) && request[2] == u64(if mode == 3 { 0 } else { 65536 }), 23, phase, position, mode)
   }
  }
 }
}
fn handler(signum i32, _info &C.siginfo_t, _context voidptr) {
 unsafe {
  handler_calls++
  marker := usize(C.alloca(1))
  check(signum == C.SIGUSR1 && marker > stack_base && marker < stack_base + 65536, 10, 1, -1, -1)
  positions(1)
 }
}
fn suite() {
 unsafe {
  page := usize(C.sysconf(C._SC_PAGESIZE))
  if page < 4096 || page > 65536 { fatal(1) }
  allocation := usize(C.mmap(nil, page * 2 + 65536, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
  if allocation == usize(-1) { fatal(2) }
  stack_base = allocation + page
  if C.mprotect(voidptr(allocation), page, C.PROT_NONE) != 0 || C.mprotect(voidptr(stack_base + 65536), page, C.PROT_NONE) != 0 { fatal(3) }
  mut raw := [u64(stack_base), u64(0), u64(65536)]!
  if C.syscall(isize(C.SYS_sigaltstack), &raw[0], nil) != 0 { fatal(4) }
  positions(0)
  mut action := C.sigaction{sa_sigaction: handler, sa_flags: C.SA_SIGINFO | C.SA_ONSTACK}
  if C.sigemptyset(&action.sa_mask) != 0 || C.sigaction(C.SIGUSR1, &action, nil) != 0 { fatal(5) }
  if C.raise(C.SIGUSR1) != 0 { fatal(6) }
  mut current := [3]u64{}
  query := C.syscall(isize(C.SYS_sigaltstack), nil, &current[0])
  check(handler_calls == 1 && query == 0 && current[0] == stack_base && u32(current[1]) == 0 && current[2] == 65536, 30, 2, -1, -1)
  raw[1] = 2
  if C.syscall(isize(C.SYS_sigaltstack), &raw[0], nil) != 0 { fatal(7) }
  if C.munmap(voidptr(allocation), page * 2 + 65536) != 0 { fatal(8) }
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
  C.printf(c'LINUX ALTSTACKSP SUMMARY: checks=%d failures=%d\n', total.checks, total.failures)
  if total.failures == 0 { C.printf(c'LINUX ALTSTACKSP: PASS\n') } else { C.printf(c'LINUX ALTSTACKSP: FAIL\n') }
  C.fflush(nil); C.alarm(0)
  for { C.pause() }
 }
 return 0
}
