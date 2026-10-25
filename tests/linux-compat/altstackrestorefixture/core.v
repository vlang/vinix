// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module altstackrestorefixture

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
 stack_a usize
 stack_b usize
 initial bool
 active bool
 variation int
 case_number int
 calls i32
 expected_base usize
 expected_flags u32
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
fn C.alloca(usize) voidptr
fn C.sigaction(i32, &C.sigaction, &C.sigaction) i32
fn C.sigemptyset(&C.sigset_t) i32
fn C.raise(i32) i32

fn fatal(stage int) {
 C.printf(c'LINUX ALTSTACKRESTORE FAIL: setup=%d errno=%d\n', stage, unsafe { *C.__errno_location() })
 C.fflush(unsafe { nil }); C._exit(90)
}
fn check(good bool, stage int) {
 unsafe {
  totals.checks++
  if !good {
   totals.failures++
   if totals.failures <= 40 { C.printf(c'LINUX ALTSTACKRESTORE MISMATCH: stage=%d case=%d\n', stage, case_number) }
  }
 }
}
fn query(base usize, onstack bool, stage int) {
 unsafe {
  mut out := [48]u8{init: 0xa5}
  result := C.syscall(isize(C.SYS_sigaltstack), nil, &out[8])
  mut record := [3]u64{}
  C.memcpy(&record[0], &out[8], 24)
  mut guards := true
  for i in 0 .. 8 { if out[i] != 0xa5 { guards = false } }
  for i in 32 .. 48 { if out[i] != 0xa5 { guards = false } }
  check(result == 0 && record[0] == u64(base)
    && u32(record[1]) == if base == 0 { u32(2) } else if onstack { u32(1) } else { u32(0) }
    && record[2] == if base == 0 { u64(0) } else { u64(65536) } && guards, stage)
 }
}
fn saved(context voidptr, base usize, flags u32, stage int) {
 unsafe {
  mut raw := [3]u64{}
  C.memcpy(&raw[0], voidptr(usize(context) + 16), 24)
  check(raw[0] == u64(base) && u32(raw[1]) == flags
   && raw[2] == if base == 0 { u64(0) } else { u64(65536) }, stage)
 }
}
fn handler(signum i32, _info &C.siginfo_t, context voidptr) {
 unsafe {
  calls++
  base := if initial { stack_a } else { usize(0) }
  marker := usize(C.alloca(1))
  check(signum == C.SIGUSR1, 20)
  saved(context, base, if initial { u32(0) } else { u32(2) }, 21)
  check((marker > stack_a && marker < stack_a + 65536) == active, 22)
  query(base, active, 23)
  mut live_base := base
  if variation == 6 {
   // Change the live stack, leaving uc_stack untouched. Returning must undo
   // an accepted update; a handler currently on stack A receives EPERM.
   raw := [u64(stack_b), u64(0), u64(65536)]!
   error_slot := C.__errno_location()
   *error_slot = 0
   result := C.syscall(isize(C.SYS_sigaltstack), &raw[0], nil)
   check(if active { result == -1 && *C.__errno_location() == C.EPERM } else { result == 0 }, 24)
   if !active { live_base = stack_b }
  } else {
   mut raw := [u64(stack_b), u64(0), u64(65536)]!
   if variation == 0 { C.memcpy(&raw[0], voidptr(usize(context) + 16), 24) }
   if variation == 2 { raw = [u64(0x1234), u64(2), u64(1)]! }
   if variation == 3 { raw[1] = 4 }
   if variation == 4 { raw[2] = 1 }
   if variation == 5 { raw[1] = 1 }
   // Nonzero ABI padding must not be interpreted as additional flag bits.
   raw[1] |= u64(0x76543210) << 32
   C.memcpy(voidptr(usize(context) + 16), &raw[0], 24)
   check(true, 24)
  }
  query(live_base, active, 25)
 }
}
fn observer(signum i32, _info &C.siginfo_t, context voidptr) {
 unsafe {
  calls++
  marker := usize(C.alloca(1))
  check(signum == C.SIGUSR2, 30)
  saved(context, expected_base, expected_flags, 31)
  check(if expected_base == 0 {
   !(marker > stack_a && marker < stack_a + 65536) && !(marker > stack_b && marker < stack_b + 65536)
  } else { marker > expected_base && marker < expected_base + 65536 }, 32)
  query(expected_base, expected_base != 0, 33)
 }
}
fn suite(configuration int) {
 unsafe {
  page := usize(C.sysconf(C._SC_PAGESIZE))
  if page < 4096 || page > 65536 { fatal(1) }
  length := page * 3 + 131072
  allocation := usize(C.mmap(nil, length, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
  if allocation == usize(-1) { fatal(2) }
  stack_a = allocation + page; stack_b = stack_a + 65536 + page
  for guard in [allocation, stack_a + 65536, stack_b + 65536]! {
   if C.mprotect(voidptr(guard), page, C.PROT_NONE) != 0 { fatal(3) }
  }
  case_number = configuration
  variation = configuration % 7
  initial = configuration / 7 & 2 != 0
  onstack := configuration / 7 & 1 != 0
  active = initial && onstack
  calls = 0
  mut raw := [u64(0), u64(2), u64(0)]!
  if C.syscall(isize(C.SYS_sigaltstack), &raw[0], nil) != 0 { fatal(4) }
  if initial {
   raw = [u64(stack_a), u64(0), u64(65536)]!
   if C.syscall(isize(C.SYS_sigaltstack), &raw[0], nil) != 0 { fatal(5) }
  }
  mut action := C.sigaction{sa_sigaction: handler, sa_flags: C.SA_SIGINFO | if onstack { C.SA_ONSTACK } else { 0 }}
  mut observe := C.sigaction{sa_sigaction: observer, sa_flags: C.SA_SIGINFO | C.SA_ONSTACK}
  if C.sigemptyset(&action.sa_mask) != 0 || C.sigaction(C.SIGUSR1, &action, nil) != 0 { fatal(6) }
  if C.sigemptyset(&observe.sa_mask) != 0 || C.sigaction(C.SIGUSR2, &observe, nil) != 0 { fatal(7) }
  expected_base = if initial { stack_a } else { usize(0) }
  // Linux x86 restores uc_stack before interrupted registers; AArch64 restores
  // it afterwards. Our interrupted main stack is outside A and B.
  allowed := $if arm64 { true } $else { !active }
  if allowed {
   if variation in [1, 5] { expected_base = stack_b }
   if variation == 2 { expected_base = 0 }
  }
  expected_flags = if expected_base == 0 { u32(2) } else if allowed && variation == 5 { u32(1) } else { u32(0) }
  check(C.raise(C.SIGUSR1) == 0, 40)
  query(expected_base, false, 41)
  check(calls == 1, 42)
  check(C.raise(C.SIGUSR2) == 0, 43)
  query(expected_base, false, 44)
  check(calls == 2, 45)
  raw = [u64(0), u64(2), u64(0)]!
  if C.syscall(isize(C.SYS_sigaltstack), &raw[0], nil) != 0 { fatal(8) }
  if C.munmap(voidptr(allocation), length) != 0 { fatal(9) }
 }
}

@[export: 'main']
pub fn run() i32 {
 unsafe {
  C.alarm(180)
  for unprivileged in [false, true]! { for configuration in 0 .. 28 {
   case_number = configuration
   mut pipe := [2]i32{}
   if C.pipe(&pipe[0]) != 0 { fatal(10) }
   C.fflush(nil)
   pid := C.fork()
   if pid < 0 { fatal(11) }
   if pid == 0 {
    C.alarm(10); totals = Totals{}; C.close(pipe[0])
    if unprivileged && (C.setgid(2000) != 0 || C.setuid(1000) != 0) { fatal(12) }
    suite(configuration)
    if C.write(pipe[1], &totals, sizeof(Totals)) != sizeof(Totals) { fatal(13) }
    C.fflush(nil); C._exit(0)
   }
   C.close(pipe[1])
   mut t := Totals{}
   length := C.read(pipe[0], &t, sizeof(Totals))
   mut status := i32(0)
   if C.waitpid(pid, &status, 0) != pid { fatal(15) }
   check(length == sizeof(Totals) && status == 0 && t.checks == 16, 50)
   C.printf(c'LINUX ALTSTACKRESTORE CHILD: ordinary=%d case=%d status=%d bytes=%ld checks=%d failures=%d\n', int(unprivileged), configuration, status, length, t.checks, t.failures)
   C.close(pipe[0]); totals.checks += t.checks; totals.failures += t.failures
  } }
  C.printf(c'LINUX ALTSTACKRESTORE SUMMARY: checks=%d failures=%d\n', totals.checks, totals.failures)
  if totals.failures == 0 { C.printf(c'LINUX ALTSTACKRESTORE: PASS\n') } else { C.printf(c'LINUX ALTSTACKRESTORE: FAIL\n') }
  C.fflush(nil); C.alarm(0)
  for { C.pause() }
 }
 return 0
}
