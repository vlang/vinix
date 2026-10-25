// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module autodisarmfixture

#include <alloca.h>
#include <errno.h>
#include <signal.h>
#include <stdio.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/syscall.h>
#include <sys/wait.h>
#include <unistd.h>

const autodisarm = u32(0x80000000)
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
struct State {
 a usize
 b usize
 configuration int
 onstack bool
 operation int
 number int
mut:
 calls int
 totals Totals
}
__global ( current_state &State )
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
 C.printf(c'LINUX AUTODISARM FAIL: setup=%d errno=%d\n', stage, unsafe { *C.__errno_location() })
 C.fflush(unsafe { nil }); C._exit(90)
}
fn check(good bool, stage int) {
 unsafe {
  mut s := current_state
  s.totals.checks++
  if !good {
   s.totals.failures++
   C.printf(c'LINUX AUTODISARM MISMATCH: case=%d stage=%d\n', s.number, stage)
  }
 }
}
fn query(base usize, flags u32, stage int) {
 unsafe {
  mut out := [48]u8{init: 0xa5}
  result := C.syscall(isize(C.SYS_sigaltstack), nil, &out[8])
  mut raw := [3]u64{}
  C.memcpy(&raw[0], &out[8], 24)
  mut guards := true
  for i in 0 .. 8 { if out[i] != 0xa5 { guards = false } }
  for i in 32 .. 48 { if out[i] != 0xa5 { guards = false } }
  check(result == 0 && raw[0] == u64(base) && u32(raw[1]) == flags
   && raw[2] == if base == 0 { u64(0) } else { u64(65536) } && guards, stage)
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
fn placed(marker usize, base usize, stage int) {
 unsafe {
  s := current_state
  check(if base != 0 { marker > base && marker < base + 65536 }
   else { !(marker > s.a && marker < s.a + 65536) && !(marker > s.b && marker < s.b + 65536) }, stage)
 }
}
fn nested(_signal i32, _info &C.siginfo_t, context voidptr) {
 unsafe {
  mut s := current_state; s.calls++
  base := if s.operation in [1, 2] { s.b } else { usize(0) }
  flags := if s.operation == 1 { u32(0) } else if s.operation == 2 { autodisarm }
   else if s.operation == 3 { autodisarm | 2 } else { u32(2) }
  check(_signal == C.SIGUSR2, 30)
  saved(context, base, flags, 31)
  placed(usize(C.alloca(1)), if base != 0 { base }
   else if s.configuration != 2 && s.onstack { s.a } else { usize(0) }, 32)
  query(if s.operation == 1 { s.b } else { usize(0) }, if s.operation == 1 { u32(1) } else { u32(2) }, 33)
 }
}
fn handler(signum i32, _info &C.siginfo_t, context voidptr) {
 unsafe {
  mut s := current_state; s.calls++
  base := if s.configuration == 2 { usize(0) } else { s.a }
  check(signum == C.SIGUSR1, 20)
  saved(context, base, autodisarm | u32(s.configuration), 21)
  placed(usize(C.alloca(1)), if s.onstack { base } else { usize(0) }, 22)
  query(0, 2, 23)
  live_base := if s.operation in [1, 2] { s.b } else { usize(0) }
  live_flags := if s.operation == 1 { u32(0) } else if s.operation == 2 { autodisarm }
   else if s.operation == 3 { autodisarm | 2 } else { u32(2) }
  raw := [u64(live_base), u64(live_flags), u64(if live_base == 0 { 0 } else { 65536 })]!
  check(C.syscall(isize(C.SYS_sigaltstack), &raw[0], nil) == 0, 24)
  query(live_base, live_flags, 25)
  if s.operation == 4 {
   replacement := [u64(s.b), u64(autodisarm | 1), u64(65536)]!
   C.memcpy(voidptr(usize(context) + 16), &replacement[0], 24)
  }
  check(C.raise(C.SIGUSR2) == 0, 26)
  query(live_base, live_flags, 27)
  placed(usize(C.alloca(1)), if s.onstack { base } else { usize(0) }, 28)
 }
}
fn verify_handler(signum i32, _info &C.siginfo_t, context voidptr) {
 unsafe {
  mut s := current_state; s.calls++
  base := if s.operation == 4 { s.b } else if s.configuration == 2 { usize(0) } else { s.a }
  flags := autodisarm | if s.operation == 4 { u32(1) } else { u32(s.configuration) }
  check(signum == C.SIGUSR1, 40)
  saved(context, base, flags, 41)
  placed(usize(C.alloca(1)), base, 42)
  query(0, 2, 43)
 }
}
fn suite(configuration int, onstack bool, operation int) Totals {
 unsafe {
  C.alarm(20)
  page := usize(C.sysconf(C._SC_PAGESIZE))
  if page < 4096 || page > 65536 { fatal(1) }
  length := page * 3 + 131072
  allocation := usize(C.mmap(nil, length, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
  if allocation == usize(-1) { fatal(2) }
  a := allocation + page; b := a + 65536 + page
  for guard in [allocation, a + 65536, b + 65536]! {
   if C.mprotect(voidptr(guard), page, C.PROT_NONE) != 0 { fatal(3) }
  }
  mut s := State{a: a, b: b, configuration: configuration, onstack: onstack,
   operation: operation, number: configuration * 10 + int(onstack) * 5 + operation}
  current_state = &s
  base := if configuration == 2 { usize(0) } else { a }
  mut raw := [u64(base), u64(autodisarm | u32(configuration)), u64(if base == 0 { 0 } else { 65536 })]!
  installed := C.syscall(isize(C.SYS_sigaltstack), &raw[0], nil)
  check(installed == 0, 10)
  if installed != 0 {
   // Keep testing the original kernel after recording its refusal.
   raw[1] = u64(configuration)
   if C.syscall(isize(C.SYS_sigaltstack), &raw[0], nil) != 0 { fatal(4) }
  }
  query(base, if base == 0 { autodisarm | 2 } else { autodisarm }, 11)
  mut action := C.sigaction{sa_sigaction: nested, sa_flags: C.SA_SIGINFO | C.SA_ONSTACK}
  if C.sigemptyset(&action.sa_mask) != 0 || C.sigaction(C.SIGUSR2, &action, nil) != 0 { fatal(5) }
  action.sa_sigaction = handler
  action.sa_flags = C.SA_SIGINFO | if onstack { C.SA_ONSTACK } else { 0 }
  if C.sigaction(C.SIGUSR1, &action, nil) != 0 { fatal(6) }
  check(C.raise(C.SIGUSR1) == 0, 12)
  restored_base := if operation == 4 { b } else { base }
  restored_flags := if restored_base == 0 { autodisarm | 2 } else { autodisarm }
  query(restored_base, restored_flags, 50)
  check(s.calls == 2, 51)
  action.sa_sigaction = verify_handler; action.sa_flags = C.SA_SIGINFO | C.SA_ONSTACK
  if C.sigaction(C.SIGUSR1, &action, nil) != 0 { fatal(7) }
  check(C.raise(C.SIGUSR1) == 0, 52)
  query(restored_base, restored_flags, 53)
  check(s.calls == 3, 54)
  raw = [u64(0), u64(2), u64(0)]!
  if C.syscall(isize(C.SYS_sigaltstack), &raw[0], nil) != 0 { fatal(8) }
  if C.munmap(voidptr(allocation), length) != 0 { fatal(9) }
  return s.totals
 }
}

@[export: 'main']
pub fn run() i32 {
 unsafe {
  C.alarm(240)
  mut total := Totals{}
  for ordinary in [false, true]! { for number in 0 .. 30 {
   mut pipe := [2]i32{}
   if C.pipe(&pipe[0]) != 0 { fatal(10) }
   C.fflush(nil)
   pid := C.fork()
   if pid < 0 { fatal(11) }
   if pid == 0 {
    C.close(pipe[0])
    if ordinary && (C.setgid(2000) != 0 || C.setuid(1000) != 0) { fatal(12) }
    result := suite(number / 10, number % 10 >= 5, number % 5)
    if C.write(pipe[1], &result, sizeof(Totals)) != sizeof(Totals) { fatal(13) }
    C.fflush(nil); C._exit(0)
   }
   C.close(pipe[1])
   mut result := Totals{}
   length := C.read(pipe[0], &result, sizeof(Totals))
   mut status := i32(0)
   if C.waitpid(pid, &status, 0) != pid { fatal(14) }
   total.checks++
   if length != sizeof(Totals) || status != 0 || result.checks != 25 { total.failures++ }
   C.printf(c'LINUX AUTODISARM CHILD: ordinary=%d case=%d status=%d bytes=%ld checks=%d failures=%d\n', int(ordinary), number, status, length, result.checks, result.failures)
   total.checks += result.checks; total.failures += result.failures
   C.close(pipe[0])
  } }
  C.printf(c'LINUX AUTODISARM SUMMARY: checks=%d failures=%d\n', total.checks, total.failures)
  if total.failures == 0 { C.printf(c'LINUX AUTODISARM: PASS\n') } else { C.printf(c'LINUX AUTODISARM: FAIL\n') }
  C.fflush(nil); C.alarm(0)
  for { C.pause() }
 }
 return 0
}
