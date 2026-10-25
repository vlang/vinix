// SPDX-License-Identifier: GPL-2.0-or-later
module sigactionflagsfixture

#include <errno.h>
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
fn C.getuid() u32
fn C.getgid() u32
fn C.sysconf(i32) isize
fn C._exit(i32)
fn C.mmap(voidptr, usize, i32, i32, i32, isize) voidptr
fn C.munmap(voidptr, usize) i32

// Linux v6.12 UAPI_SA_FLAGS on native x86-64 and AArch64. Retaining a
// flag here tests the raw ABI; delivery semantics are qualified separately.
const accepted = u64(0xdc000807)

fn fatal(stage int) {
 C.printf(c'LINUX SIGACTIONFLAGS FAIL: setup=%d errno=%d\n', stage, unsafe { *C.__errno_location() })
 C.fflush(unsafe { nil }); C._exit(90)
}
fn check(mut t Totals, good bool, stage int, index int, signal int) {
 t.checks++
 if !good {
  t.failures++
  if t.failures <= 30 { C.printf(c'LINUX SIGACTIONFLAGS MISMATCH: stage=%d index=%d signal=%d\n', stage, index, signal) }
 }
}
fn call(signal int, input voidptr, output voidptr) isize {
 unsafe { location := C.__errno_location(); *location = 0 }
 return C.syscall(isize(C.SYS_rt_sigaction), i32(signal), input, output, usize(8))
}
fn action(signal int) [4]u64 {
 mut output := [4]u64{}
 if call(signal, unsafe { nil }, unsafe { &output[0] }) != 0 { fatal(1) }
 return output
}
fn establish(signal int, value [4]u64) {
 if call(signal, unsafe { &value[0] }, unsafe { nil }) != 0 { fatal(2) }
}
fn normalized(value [4]u64) [4]u64 {
 mut output := value
 output[1] &= accepted
 output[3] &= ~((u64(1) << 8) | (u64(1) << 18))
 return output
}
fn flags(index int) u64 {
 if index < 64 { return u64(1) << u64(index) }
 return match index {
  64 { u64(0) }
  65 { accepted }
  66 { ~accepted }
  67 { u64(-1) }
  68 { accepted | 0x400 }
  69 { u64(0x800) | 0x400 }
  70 { u64(0x00800000) | 0x400 }
  else { u64(0xffffffff00000000) | accepted | 0x400 }
 }
}

// No signal is sent: individual bits, capability probing and copy ordering.
fn suite(mut t Totals) {
 unsafe {
  pages := usize(C.sysconf(C._SC_PAGESIZE))
  if pages < 4096 || pages > 65536 { fatal(3) }
  readonly := C.mmap(nil, pages, C.PROT_READ, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0)
  if readonly == voidptr(usize(-1)) { fatal(4) }
  before := [u64(0), u64(0), u64(0), u64(0)]!
  for signal in [10, 12, 35]! {
   original := action(signal)
   start_checks := t.checks
   start_failures := t.failures
   for index in 0 .. 72 {
    establish(signal, before)
    incoming := [u64(1), flags(index), u64(0x123456780000), u64(-1)]!
    mut old := [4]u64{init: 0xa5a5a5a5a5a5a5a5}
    result := call(signal, &incoming[0], &old[0])
    saved_errno := *C.__errno_location()
    check(mut t, result == 0, 10, index, signal)
    check(mut t, saved_errno == 0, 11, index, signal)
    check(mut t, old == before, 12, index, signal)
    observed := action(signal)
    check(mut t, observed == normalized(incoming), 13, index, signal)

    replacement := [u64(0), flags(index) ^ accepted, u64(0x876543210000), u64(1) << 34]!
    mut alias := replacement
    alias_result := call(signal, &alias[0], &alias[0])
    alias_errno := *C.__errno_location()
    check(mut t, alias_result == 0, 14, index, signal)
    check(mut t, alias_errno == 0, 15, index, signal)
    check(mut t, alias == normalized(incoming), 16, index, signal)
    check(mut t, action(signal) == normalized(replacement), 17, index, signal)

    fault_result := call(signal, &incoming[0], readonly)
    fault_errno := *C.__errno_location()
    check(mut t, fault_result == -1, 18, index, signal)
    check(mut t, fault_errno == C.EFAULT, 19, index, signal)
    check(mut t, action(signal) == normalized(incoming), 20, index, signal)

    sentinel := [u64(0xa5a5a5a5a5a5a5a5), u64(0xa5a5a5a5a5a5a5a5),
     u64(0xa5a5a5a5a5a5a5a5), u64(0xa5a5a5a5a5a5a5a5)]!
    mut untouched := sentinel
    input_result := call(signal, voidptr(1), &untouched[0])
    input_errno := *C.__errno_location()
    check(mut t, input_result == -1, 21, index, signal)
    check(mut t, input_errno == C.EFAULT, 22, index, signal)
    check(mut t, untouched == sentinel, 23, index, signal)
    check(mut t, action(signal) == normalized(incoming), 24, index, signal)
   }
   establish(signal, original)
   C.printf(c'LINUX SIGACTIONFLAGS CASE: uid=%u gid=%u signal=%d checks=%d failures=%d\n',
    C.getuid(), C.getgid(), signal, t.checks - start_checks, t.failures - start_failures)
  }
  if C.munmap(readonly, pages) != 0 { fatal(5) }
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
  C.printf(c'LINUX SIGACTIONFLAGS SUMMARY: checks=%d failures=%d\n', total.checks, total.failures)
  if total.failures == 0 { C.printf(c'LINUX SIGACTIONFLAGS: PASS\n') } else { C.printf(c'LINUX SIGACTIONFLAGS: FAIL\n') }
  C.fflush(nil); C.alarm(0)
  for { C.pause() }
 }
 return 0
}
