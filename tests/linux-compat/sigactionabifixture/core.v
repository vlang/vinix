// SPDX-License-Identifier: GPL-2.0-or-later
module sigactionabifixture

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
 C.printf(c'LINUX SIGACTIONABI FAIL: setup=%d errno=%d\n', stage, unsafe { *C.__errno_location() })
 C.fflush(unsafe { nil }); C._exit(90)
}
fn check(mut t Totals, good bool, stage int) {
 t.checks++
 if !good {
  t.failures++
  if t.failures <= 30 { C.printf(c'LINUX SIGACTIONABI MISMATCH: stage=%d\n', stage) }
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

// No signals are delivered; query/validation/copy ordering only.
// Inserted into the V fixture by prepare-probe.v.
fn suite(mut t Totals) {
 unsafe {
  pages := usize(C.sysconf(C._SC_PAGESIZE))
  if pages < 4096 || pages > 65536 { fatal(3) }
  memory := C.mmap(nil, pages * 2, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0)
  readonly := C.mmap(nil, pages, C.PROT_READ, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0)
  gone := C.mmap(nil, pages, C.PROT_READ, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0)
  if memory == voidptr(usize(-1)) || readonly == voidptr(usize(-1)) || gone == voidptr(usize(-1)) { fatal(4) }
  if C.mprotect(voidptr(usize(memory) + pages), pages, C.PROT_NONE) != 0 || C.munmap(gone, pages) != 0 { fatal(5) }
  before := [u64(0), u64(0), u64(0), u64(0)]!
  incoming := [u64(1), u64(0x10000004), u64(0), u64(-1)]!
  original10 := action(10)
  original12 := action(12)
  original35 := action(35)
  for signal in [10, 12, 35]! { establish(signal, before) }
  for signal in [int(-2147483647 - 1), -1, 0, 9, 10, 12, 19, 35, 65, 2147483647]! {
   ordinary := signal in [10, 12, 35]!
   valid := ordinary || signal in [9, 19]!
   for size in [usize(0), usize(1), usize(7), usize(8), usize(9), usize(16), usize(-1)]! {
    for input_kind, input in [voidptr(nil), voidptr(&incoming[0]), voidptr(1), voidptr(usize(-1)), gone,
      voidptr(usize(memory) + pages), voidptr(usize(memory) + pages - 1), voidptr(usize(memory) + pages - 31)]! {
     for output_kind in 0 .. 10 {
      if ordinary { establish(signal, before) }
      mut buffer := [48]u8{init: 0xa5}
      boundary := voidptr(usize(memory) + pages - 32)
      for i in 0 .. 32 { (&u8(boundary))[i] = 0xa5 }
      output := match output_kind {
       0 { voidptr(nil) }
       1 { voidptr(&buffer[8]) }
       2 { voidptr(&buffer[3]) }
       3 { boundary }
       4 { voidptr(1) }
       5 { voidptr(usize(-1)) }
       6 { gone }
       7 { voidptr(usize(memory) + pages) }
       8 { readonly }
       else { voidptr(usize(memory) + pages - 16) }
      }
      expected := if size != 8 { C.EINVAL } else if input_kind >= 2 { C.EFAULT }
       else if !valid || (!ordinary && input_kind != 0) { C.EINVAL }
       else if output_kind >= 4 { C.EFAULT } else { 0 }
      result := call(signal, input, output, size)
      saved_errno := *C.__errno_location()
      check(mut t, result == if expected == 0 { 0 } else { -1 }, 10)
      check(mut t, saved_errno == expected, 11)
      observed := action(if ordinary { signal } else { 10 })
      changed := ordinary && size == 8 && input_kind == 1
      check(mut t, observed == if changed { normalized(incoming) } else { before }, 12)
      mut output_ok := true
      if output_kind in [1, 2, 3]! {
       mut raw := [4]u64{}
       C.memcpy(&raw[0], output, 32)
       output_ok = raw == if expected == 0 { before } else {
        [u64(0xa5a5a5a5a5a5a5a5), u64(0xa5a5a5a5a5a5a5a5), u64(0xa5a5a5a5a5a5a5a5), u64(0xa5a5a5a5a5a5a5a5)]!
       }
      }
      check(mut t, output_ok, 13)
      offset := if output_kind == 2 { 3 } else { 8 }
      mut guards := true
      for i in 0 .. 48 {
       if (output_kind !in [1, 2]! || i < offset || i >= offset + 32) && buffer[i] != 0xa5 { guards = false }
      }
      check(mut t, guards, 14)
      if ordinary { establish(signal, before) }
     }
    }
   }
  }
  establish(10, original10)
  establish(12, original12)
  establish(35, original35)
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
  C.printf(c'LINUX SIGACTIONABI SUMMARY: checks=%d failures=%d\n', total.checks, total.failures)
  if total.failures == 0 { C.printf(c'LINUX SIGACTIONABI: PASS\n') } else { C.printf(c'LINUX SIGACTIONABI: FAIL\n') }
  C.fflush(nil); C.alarm(0)
  for { C.pause() }
 }
 return 0
}
