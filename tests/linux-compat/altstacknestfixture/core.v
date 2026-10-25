// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module altstacknestfixture

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
 enabled bool
 outer_onstack bool
 inner_onstack bool
 outer_calls i32
 inner_calls i32
 case_number int
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
 C.printf(c'LINUX ALTSTACKNEST FAIL: setup=%d errno=%d\n', stage, unsafe { *C.__errno_location() })
 C.fflush(unsafe { nil }); C._exit(90)
}
fn check(good bool, stage int, nested bool) {
 unsafe {
  totals.checks++
  if !good {
   totals.failures++
   if totals.failures <= 40 { C.printf(c'LINUX ALTSTACKNEST MISMATCH: stage=%d case=%d nested=%d\n', stage, case_number, int(nested)) }
  }
 }
}
fn query(active bool, stage int, nested bool) {
 unsafe {
  mut out := [48]u8{init: 0xa5}
  result := C.syscall(isize(C.SYS_sigaltstack), nil, &out[8])
  mut record := [3]u64{}
  C.memcpy(&record[0], &out[8], 24)
  mut guards := true
  for i in 0 .. 8 { if out[i] != 0xa5 { guards = false } }
  for i in 32 .. 48 { if out[i] != 0xa5 { guards = false } }
  check(result == 0 && record[0] == if enabled { u64(stack_base) } else { u64(0) }
    && u32(record[1]) == if !enabled { u32(2) } else if active { u32(1) } else { u32(0) }
    && record[2] == if enabled { u64(65536) } else { u64(0) } && guards, stage, nested)
 }
}
fn inspect(signum i32, context voidptr, nested bool) {
 unsafe {
  mut saved := [3]u64{}
  C.memcpy(&saved[0], voidptr(usize(context) + 16), 24)
  active := enabled && (outer_onstack || (nested && inner_onstack))
  marker := usize(C.alloca(1))
  check(signum == if nested { C.SIGUSR2 } else { C.SIGUSR1 }, 20, nested)
  check(saved[0] == if enabled { u64(stack_base) } else { u64(0) }, 21, nested)
  // Linux saves the configured flags, even when interrupted on this stack.
  check(u32(saved[1]) == if enabled { u32(0) } else { u32(2) }, 22, nested)
  check(saved[2] == if enabled { u64(65536) } else { u64(0) }, 23, nested)
  check((marker > stack_base && marker < stack_base + 65536) == active, 24, nested)
  query(active, 25, nested)
 }
}
fn inner_handler(signum i32, _info &C.siginfo_t, context voidptr) {
 unsafe { inner_calls++ }
 inspect(signum, context, true)
}
fn outer_handler(signum i32, _info &C.siginfo_t, context voidptr) {
 unsafe {
  outer_calls++
  inspect(signum, context, false)
  guard := &u64(C.alloca(512))
  for index in 0 .. 64 { guard[index] = u64(0xabcddcba12340000) + u64(index) }
  for _ in 0 .. 3 {
   check(C.raise(C.SIGUSR2) == 0, 30, false)
   query(enabled && outer_onstack, 31, false)
   mut intact := true
   for index in 0 .. 64 { if guard[index] != u64(0xabcddcba12340000) + u64(index) { intact = false } }
   check(intact, 32, false)
  }
 }
}
fn suite(configuration int) {
 unsafe {
  page := usize(C.sysconf(C._SC_PAGESIZE))
  if page < 4096 || page > 65536 { fatal(1) }
  allocation := usize(C.mmap(nil, page * 2 + 65536, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
  if allocation == usize(-1) { fatal(2) }
  stack_base = allocation + page
  if C.mprotect(voidptr(allocation), page, C.PROT_NONE) != 0 || C.mprotect(voidptr(stack_base + 65536), page, C.PROT_NONE) != 0 { fatal(3) }
   case_number = configuration
   enabled = configuration & 4 != 0
   outer_onstack = configuration & 2 != 0
   inner_onstack = configuration & 1 != 0
   outer_calls = 0; inner_calls = 0
   mut raw := [u64(0), u64(2), u64(0)]!
   if C.syscall(isize(C.SYS_sigaltstack), &raw[0], nil) != 0 { fatal(4) }
   if enabled {
    raw = [u64(stack_base), u64(0), u64(65536)]!
    if C.syscall(isize(C.SYS_sigaltstack), &raw[0], nil) != 0 { fatal(5) }
   }
   mut outer := C.sigaction{sa_sigaction: outer_handler, sa_flags: C.SA_SIGINFO | if outer_onstack { C.SA_ONSTACK } else { 0 }}
   mut inner := C.sigaction{sa_sigaction: inner_handler, sa_flags: C.SA_SIGINFO | if inner_onstack { C.SA_ONSTACK } else { 0 }}
   if C.sigemptyset(&outer.sa_mask) != 0 || C.sigaction(C.SIGUSR1, &outer, nil) != 0 { fatal(6) }
   if C.sigemptyset(&inner.sa_mask) != 0 || C.sigaction(C.SIGUSR2, &inner, nil) != 0 { fatal(7) }
   check(C.raise(C.SIGUSR1) == 0, 40, false)
   check(outer_calls == 1 && inner_calls == 3, 41, false)
   query(false, 42, false)
  raw = [u64(0), u64(2), u64(0)]!
  if C.syscall(isize(C.SYS_sigaltstack), &raw[0], nil) != 0 { fatal(8) }
  if C.munmap(voidptr(allocation), page * 2 + 65536) != 0 { fatal(9) }
 }
}

@[export: 'main']
pub fn run() i32 {
 unsafe {
  C.alarm(120)
  for unprivileged in [false, true]! { for configuration in 0 .. 8 {
   case_number = configuration
   mut pipe := [2]i32{}
   if C.pipe(&pipe[0]) != 0 { fatal(10) }
   C.fflush(nil)
   pid := C.fork()
   if pid < 0 { fatal(11) }
   if pid == 0 {
    C.alarm(10)
    totals = Totals{}
    C.close(pipe[0])
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
   check(length == sizeof(Totals) && status == 0 && t.checks == 36, 50, false)
   C.printf(c'LINUX ALTSTACKNEST CHILD: ordinary=%d case=%d status=%d bytes=%ld checks=%d failures=%d\n', int(unprivileged), configuration, status, length, t.checks, t.failures)
   C.close(pipe[0]); totals.checks += t.checks; totals.failures += t.failures
  } }
  C.printf(c'LINUX ALTSTACKNEST SUMMARY: checks=%d failures=%d\n', totals.checks, totals.failures)
  if totals.failures == 0 { C.printf(c'LINUX ALTSTACKNEST: PASS\n') } else { C.printf(c'LINUX ALTSTACKNEST: FAIL\n') }
  C.fflush(nil); C.alarm(0)
  for { C.pause() }
 }
 return 0
}
