// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module resethandfixture

#include <errno.h>
#include <pthread.h>
#include <signal.h>
#include <stdio.h>
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
 signal int
 mode int
 request int
 response int
mut:
 installed [4]u64
 replacement [4]u64
 calls int
 replacements int
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
fn C.getuid() u32
fn C.getgid() u32
fn C._exit(i32)
fn C.sigaction(i32, &C.sigaction, &C.sigaction) i32
fn C.sigemptyset(&C.sigset_t) i32
fn C.sigaddset(&C.sigset_t, i32) i32
fn C.pthread_create(&C.pthread_t, voidptr, fn (voidptr) voidptr, voidptr) i32
fn C.pthread_join(C.pthread_t, voidptr) i32

fn fatal(stage int) {
 C.printf(c'LINUX RESETHAND FAIL: setup=%d errno=%d\n', stage, unsafe { *C.__errno_location() })
 C.fflush(unsafe { nil }); C._exit(90)
}
fn check(good bool, stage int) {
 unsafe {
  mut s := current_state
  s.totals.checks++
  if !good {
   s.totals.failures++
   C.printf(c'LINUX RESETHAND MISMATCH: signal=%d mode=%d stage=%d\n', s.signal, s.mode, stage)
  }
 }
}
fn query() [4]u64 {
 mut raw := [4]u64{}
 if C.syscall(isize(C.SYS_rt_sigaction), unsafe { current_state.signal }, unsafe { nil }, &raw[0], usize(8)) != 0 { fatal(1) }
 return raw
}
fn send_signal() isize {
 return C.syscall(isize(C.SYS_tgkill), C.syscall(isize(C.SYS_getpid)),
  C.syscall(isize(C.SYS_gettid)), unsafe { current_state.signal })
}
fn exchange(command i32) [4]u64 {
 unsafe {
  s := current_state
  mut raw := [4]u64{}
  if C.write(s.request, &command, sizeof(i32)) != sizeof(i32)
   || C.read(s.response, &raw[0], sizeof(raw)) != sizeof(raw) { fatal(2) }
  return raw
 }
}
fn replacement_handler(signum i32, _info &C.siginfo_t, _context voidptr) {
 unsafe {
  mut s := current_state
  s.replacements++
  check(signum == s.signal, 40)
  check(query() == s.replacement, 41)
 }
}
fn handler(signum i32, _info &C.siginfo_t, _context voidptr) {
 unsafe {
  mut s := current_state
  s.calls++
  mut expected := s.installed
  if s.mode != 0 { expected[0] = 0 }
  check(signum == s.signal, 10)
  check(query() == expected, 11)
  mut mask := u64(0)
  check(C.syscall(isize(C.SYS_rt_sigprocmask), 2, nil, &mask, usize(8)) == 0, 12)
  check((mask & (u64(1) << u64(s.signal - 1)) != 0) == (s.mode != 2), 13)
  check(mask & (u64(1) << 14) != 0, 14)
  if s.calls == 1 {
   // The sibling existed before installation and queries while this handler
   // is still active. No timer, scheduler delay or userspace race is needed.
   check(exchange(1) == expected, 15)
   if s.mode == 3 {
    s.replacement = exchange(2)
    check(s.replacement[0] == u64(voidptr(replacement_handler))
     && s.replacement[1] & u64(0x80000000) == 0, 16)
    check(query() == s.replacement, 17)
   }
  }
 }
}
fn worker(argument voidptr) voidptr {
 unsafe {
  fds := &i32(argument)
  for {
   mut command := i32(0)
   if C.read(fds[0], &command, sizeof(command)) != sizeof(command) { fatal(3) }
   if command == 0 { return nil }
   if command == 2 {
    mut action := C.sigaction{sa_sigaction: replacement_handler, sa_flags: C.SA_SIGINFO}
    if C.sigemptyset(&action.sa_mask) != 0 || C.sigaction(current_state.signal, &action, nil) != 0 { fatal(4) }
   } else if command != 1 { fatal(5) }
   raw := query()
   if C.write(fds[1], &raw[0], sizeof(raw)) != sizeof(raw) { fatal(6) }
  }
 }
 return unsafe { nil }
}
fn stop_worker(id C.pthread_t) {
 unsafe {
  command := i32(0)
  if C.write(current_state.request, &command, sizeof(command)) != sizeof(command)
   || C.pthread_join(id, nil) != 0 { fatal(7) }
 }
}
fn suite(signal int, mode int) Totals {
 unsafe {
  C.alarm(20)
  mut request := [2]i32{}
  mut response := [2]i32{}
  if C.pipe(&request[0]) != 0 || C.pipe(&response[0]) != 0 { fatal(8) }
  mut s := State{signal: signal, mode: mode, request: request[1], response: response[0]}
  current_state = &s
  fds := [request[0], response[1]]!
  mut id := C.pthread_t{}
  if C.pthread_create(&id, nil, worker, &fds[0]) != 0 { fatal(9) }
  mut action := C.sigaction{sa_sigaction: handler, sa_flags: C.SA_SIGINFO
   | if mode == 0 { 0 } else { i32(u32(0x80000000)) }
   | if mode == 2 { C.SA_NODEFER | C.SA_RESTART } else { 0 }}
  if C.sigemptyset(&action.sa_mask) != 0 || C.sigaddset(&action.sa_mask, C.SIGTERM) != 0
   || C.sigaction(signal, &action, nil) != 0 { fatal(10) }
  s.installed = query()
  check(exchange(1) == s.installed, 20)
  check(send_signal() == 0, 21)
  check(s.calls == 1 && s.replacements == 0, 22)
  mut expected := s.installed
  if mode != 0 { expected[0] = 0 }
  if mode == 3 { expected = s.replacement }
  check(query() == expected, 23)
  check(exchange(1) == expected, 24)
  stop_worker(id)
  if C.pthread_create(&id, nil, worker, &fds[0]) != 0 { fatal(11) }
  check(exchange(1) == expected, 25)
  stop_worker(id)

  // A fork child inherits the consumed action. Fatal defaults must terminate
  // with the actual signal; the ignored SIGWINCH default must return normally.
  C.fflush(nil)
  pid := C.fork()
  if pid < 0 { fatal(12) }
  if pid == 0 {
   if query() != expected { C._exit(91) }
   failures := s.totals.failures
   // Persistent handlers no longer need the sibling exchange after call one.
   if send_signal() != 0 { C._exit(92) }
   if mode == 0 && s.calls != 2 { C._exit(93) }
   if mode == 3 && s.replacements != 1 { C._exit(94) }
   if s.totals.failures != failures { C._exit(95) }
   C.fflush(nil); C._exit(37)
  }
  mut status := i32(0)
  check(C.waitpid(pid, &status, 0) == pid, 26)
  check(if mode in [1, 2] && signal != C.SIGWINCH {
   status & 127 == signal
  } else { status == 37 << 8 }, 27)

  // SIG_IGN is not a handler: SA_RESETHAND must leave the entire record alone.
  ignored := [u64(1), u64(0x80000004), u64(0x12340000), u64(1) << 14]!
  check(C.syscall(isize(C.SYS_rt_sigaction), signal, &ignored[0], nil, usize(8)) == 0, 28)
  check(send_signal() == 0, 29)
  check(query() == ignored, 30)
  for fd in [request[0], request[1], response[0], response[1]]! { C.close(fd) }
  return s.totals
 }
}

@[export: 'main']
pub fn run() i32 {
 unsafe {
  C.alarm(180)
  mut total := Totals{}
  for ordinary in [false, true]! { for signal in [10, 12, 28]! { for mode in 0 .. 4 {
   mut pipe := [2]i32{}
   if C.pipe(&pipe[0]) != 0 { fatal(13) }
   C.fflush(nil)
   pid := C.fork()
   if pid < 0 { fatal(14) }
   if pid == 0 {
    C.close(pipe[0])
    if ordinary && (C.setgid(2000) != 0 || C.setuid(1000) != 0) { fatal(15) }
    t := suite(signal, mode)
    C.printf(c'LINUX RESETHAND CASE: uid=%u gid=%u signal=%d mode=%d checks=%d failures=%d\n',
     C.getuid(), C.getgid(), signal, mode, t.checks, t.failures)
    if C.write(pipe[1], &t, sizeof(Totals)) != sizeof(Totals) { fatal(16) }
    C.fflush(nil); C._exit(0)
   }
   C.close(pipe[1])
   mut t := Totals{}
   if C.read(pipe[0], &t, sizeof(Totals)) != sizeof(Totals) { fatal(17) }
   mut status := i32(0)
   if C.waitpid(pid, &status, 0) != pid || status != 0 { fatal(18) }
   C.close(pipe[0])
   total.checks += t.checks; total.failures += t.failures
  } } }
  C.printf(c'LINUX RESETHAND SUMMARY: checks=%d failures=%d\n', total.checks, total.failures)
  if total.failures == 0 { C.printf(c'LINUX RESETHAND: PASS\n') } else { C.printf(c'LINUX RESETHAND: FAIL\n') }
  C.fflush(nil); C.alarm(0)
  for { C.pause() }
 }
 return 0
}
