// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module altstackclonefixture

#include <alloca.h>
#include <errno.h>
#include <pthread.h>
#include <sched.h>
#include <signal.h>
#include <stdio.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/syscall.h>
#include <sys/wait.h>
#include <unistd.h>

@[typedef]
struct C.pthread_t {}
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
 operation int
 number int
 pipe i32
mut:
 base usize
 flags u32
 calls int
 phase int
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
fn C.pthread_create(&C.pthread_t, voidptr, fn (voidptr) voidptr, voidptr) i32
fn C.pthread_join(C.pthread_t, voidptr) i32
fn C.clone(fn (voidptr) i32, voidptr, i32, voidptr, ...) i32

fn fatal(stage int) {
 C.printf(c'LINUX ALTSTACKCLONE FAIL: setup=%d errno=%d\n', stage, unsafe { *C.__errno_location() })
 C.fflush(unsafe { nil }); C._exit(90)
}
fn check(good bool, stage int) {
 unsafe {
  mut s := current_state
  s.totals.checks++
  if !good {
   s.totals.failures++
   C.printf(c'LINUX ALTSTACKCLONE MISMATCH: case=%d phase=%d stage=%d\n', s.number, s.phase, stage)
  }
 }
}
fn query(active bool, stage int) {
 unsafe {
  s := current_state
  mut out := [48]u8{init: 0xa5}
  result := C.syscall(isize(C.SYS_sigaltstack), nil, &out[8])
  mut record := [3]u64{}
  C.memcpy(&record[0], &out[8], 24)
  mut guards := true
  for i in 0 .. 8 { if out[i] != 0xa5 { guards = false } }
  for i in 32 .. 48 { if out[i] != 0xa5 { guards = false } }
  check(result == 0 && record[0] == u64(s.base)
   && u32(record[1]) == if s.base == 0 { u32(2) } else if active { u32(1) } else { u32(0) }
   && record[2] == if s.base == 0 { u64(0) } else { u64(65536) } && guards, stage)
 }
}
fn handler(signum i32, _info &C.siginfo_t, context voidptr) {
 unsafe {
  mut s := current_state
  s.calls++
  marker := usize(C.alloca(1))
  mut raw := [3]u64{}
  C.memcpy(&raw[0], voidptr(usize(context) + 16), 24)
  check(signum == C.SIGUSR1, 20)
  check(raw[0] == u64(s.base) && u32(raw[1]) == s.flags
   && raw[2] == if s.base == 0 { u64(0) } else { u64(65536) }, 21)
  check(if s.base == 0 {
   !(marker > s.a && marker < s.a + 65536) && !(marker > s.b && marker < s.b + 65536)
  } else { marker > s.base && marker < s.base + 65536 }, 22)
  query(s.base != 0, 23)
 }
}
fn send_signal() isize {
 // A CLONE_VM process without CLONE_SETTLS can share musl's thread descriptor;
 // use kernel identity rather than libc's cached pthread identity.
 return C.syscall(isize(C.SYS_tgkill), C.syscall(isize(C.SYS_getpid)),
  C.syscall(isize(C.SYS_gettid)), isize(C.SIGUSR1))
}
fn child(argument voidptr) i32 {
 unsafe {
  mut s := *(&State(argument))
  s.phase = 1; s.totals = Totals{}; s.calls = 0
  if s.operation in [2, 5] { s.base = 0; s.flags = 2 }
  current_state = &s
  query(false, 30)
  check(send_signal() == 0, 31)
  query(false, 32)
  check(s.calls == 1, 33)
  // A child's updates must remain private even when memory is shared.
  raw := [u64(s.b), u64(1), u64(65536)]!
  check(C.syscall(isize(C.SYS_sigaltstack), &raw[0], nil) == 0, 34)
  s.base = s.b; s.flags = 1
  query(false, 35)
  check(send_signal() == 0, 36)
  query(false, 37)
  check(s.calls == 2, 38)
  disabled := [u64(0), u64(2), u64(0)]!
  check(C.syscall(isize(C.SYS_sigaltstack), &disabled[0], nil) == 0, 39)
  s.base = 0; s.flags = 2
  query(false, 40)
  if C.write(s.pipe, &s.totals, sizeof(Totals)) != sizeof(Totals) { fatal(1) }
  C.fflush(nil)
  return 37
 }
}
fn thread(argument voidptr) voidptr {
 return unsafe { voidptr(usize(child(argument))) }
}
fn suite(configuration int, operation int) Totals {
 unsafe {
  C.alarm(20)
  page := usize(C.sysconf(C._SC_PAGESIZE))
  if page < 4096 || page > 65536 { fatal(2) }
  length := page * 4 + 393216
  allocation := usize(C.mmap(nil, length, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
  if allocation == usize(-1) { fatal(3) }
  a := allocation + page; b := a + 65536 + page; clone_stack := b + 65536 + page
  for guard in [allocation, a + 65536, b + 65536, clone_stack + 262144]! {
   if C.mprotect(voidptr(guard), page, C.PROT_NONE) != 0 { fatal(4) }
  }
  mut pipe := [2]i32{}
  if C.pipe(&pipe[0]) != 0 { fatal(5) }
  mut s := State{a: a, b: b, configuration: configuration, operation: operation,
   number: configuration * 8 + operation, pipe: pipe[1],
   base: if configuration == 0 { usize(0) } else { a },
   flags: if configuration == 0 { u32(2) } else { u32(configuration - 1) }}
  current_state = &s
  raw := [u64(s.base), u64(s.flags), u64(if s.base == 0 { 0 } else { 65536 })]!
  if C.syscall(isize(C.SYS_sigaltstack), &raw[0], nil) != 0 { fatal(6) }
  mut action := C.sigaction{sa_sigaction: handler, sa_flags: C.SA_SIGINFO | C.SA_ONSTACK}
  if C.sigemptyset(&action.sa_mask) != 0 || C.sigaction(C.SIGUSR1, &action, nil) != 0 { fatal(7) }
  mut status := i32(0)
  if operation == 5 {
   mut id := C.pthread_t{}
   if C.pthread_create(&id, nil, thread, &s) != 0 { fatal(8) }
   mut result := voidptr(nil)
   joined := C.pthread_join(id, &result)
   current_state = &s
   check(joined == 0 && usize(result) == 37, 50)
  } else {
   mut pid := i32(-1)
   if operation == 0 {
    pid = C.fork()
    if pid == 0 { C._exit(child(&s)) }
   } else if operation in [6, 7] {
    mut args := [11]u64{}
    args[0] = if operation == 7 { u64(C.CLONE_VFORK) } else { u64(0) }
    args[4] = u64(C.SIGCHLD)
    pid = i32(C.syscall(isize(C.SYS_clone3), &args[0], usize(88)))
    if pid == 0 { C._exit(child(&s)) }
   } else {
    flags := C.SIGCHLD | if operation in [2, 4] { C.CLONE_VM } else { 0 }
     | if operation in [3, 4] { C.CLONE_VFORK } else { 0 }
    pid = C.clone(child, voidptr(clone_stack + 262144), flags, &s)
   }
   if pid < 0 { fatal(9) }
   waited := C.waitpid(pid, &status, 0)
   current_state = &s
   check(waited == pid && status == 37 << 8, 50)
  }
  mut reply := Totals{}
  received := C.read(pipe[0], &reply, sizeof(Totals))
  check(received == sizeof(Totals) && reply.checks == 19, 51)
  C.printf(c'LINUX ALTSTACKCLONE DESCENDANT: case=%d status=%d bytes=%ld checks=%d failures=%d\n',
   s.number, status, received, reply.checks, reply.failures)
  query(false, 52)
  check(send_signal() == 0, 53)
  query(false, 54)
  check(s.calls == 1, 55)
  s.totals.checks += reply.checks; s.totals.failures += reply.failures
  disabled := [u64(0), u64(2), u64(0)]!
  if C.syscall(isize(C.SYS_sigaltstack), &disabled[0], nil) != 0 { fatal(10) }
  if C.close(pipe[0]) != 0 || C.close(pipe[1]) != 0 || C.munmap(voidptr(allocation), length) != 0 { fatal(11) }
  return s.totals
 }
}

@[export: 'main']
pub fn run() i32 {
 unsafe {
  C.alarm(180)
  mut all := Totals{}
  for ordinary in [false, true]! { for configuration in 0 .. 3 { for operation in 0 .. 8 {
   mut pipe := [2]i32{}
   if C.pipe(&pipe[0]) != 0 { fatal(12) }
   C.fflush(nil)
   pid := C.fork()
   if pid < 0 { fatal(13) }
   if pid == 0 {
    C.close(pipe[0])
    if ordinary && (C.setgid(2000) != 0 || C.setuid(1000) != 0) { fatal(14) }
    result := suite(configuration, operation)
    if C.write(pipe[1], &result, sizeof(Totals)) != sizeof(Totals) { fatal(15) }
    C.fflush(nil); C._exit(0)
   }
   C.close(pipe[1])
   mut result := Totals{}
   received := C.read(pipe[0], &result, sizeof(Totals))
   mut status := i32(0)
   if C.waitpid(pid, &status, 0) != pid { fatal(16) }
   all.checks++
   if received != sizeof(Totals) || status != 0 || result.checks != 29 { all.failures++ }
   C.printf(c'LINUX ALTSTACKCLONE CHILD: ordinary=%d case=%d status=%d bytes=%ld checks=%d failures=%d\n',
    int(ordinary), configuration * 8 + operation, status, received, result.checks, result.failures)
   C.close(pipe[0]); all.checks += result.checks; all.failures += result.failures
  } } }
  C.printf(c'LINUX ALTSTACKCLONE SUMMARY: checks=%d failures=%d\n', all.checks, all.failures)
  if all.failures == 0 { C.printf(c'LINUX ALTSTACKCLONE: PASS\n') } else { C.printf(c'LINUX ALTSTACKCLONE: FAIL\n') }
  C.fflush(nil); C.alarm(0)
  for { C.pause() }
 }
 return 0
}
