// SPDX-License-Identifier: GPL-2.0-or-later
module altstackabifixture

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
fn C.memcmp(voidptr, voidptr, usize) i32

fn fatal(stage int) {
 C.printf(c'LINUX ALTSTACKABI FAIL: setup=%d errno=%d\n', stage, unsafe { *C.__errno_location() })
 C.fflush(unsafe { nil }); C._exit(90)
}
fn check(mut t Totals, good bool, stage int) {
 t.checks++
 if !good {
  t.failures++
  if t.failures <= 30 { C.printf(c'LINUX ALTSTACKABI MISMATCH: stage=%d\n', stage) }
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

fn bytes_are(pointer voidptr, size int, value u8) bool {
 unsafe {
  data := &u8(pointer)
  for i in 0 .. size { if data[i] != value { return false } }
 }
 return true
}

fn record_is(pointer voidptr, stack u64, flags u32, size u64) bool {
 unsafe {
  mut raw := [3]u64{}
  C.memcpy(&raw[0], pointer, 24)
  return raw[0] == stack && u32(raw[1]) == flags && raw[2] == size
 }
}

// No handlers run on these stacks. This checks the normal input modes and the
// native architecture's minimum, including error precedence and copy effects.
fn suite(mut t Totals) {
 unsafe {
  pages := usize(C.sysconf(C._SC_PAGESIZE))
  if pages < 4096 || pages > 65536 { fatal(2) }
  input_memory := C.mmap(nil, pages * 2, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0)
  output_memory := C.mmap(nil, pages * 2, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0)
  readonly := C.mmap(nil, pages, C.PROT_READ, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0)
  stack := C.mmap(nil, 262144, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0)
  if input_memory == voidptr(usize(-1)) || output_memory == voidptr(usize(-1)) || readonly == voidptr(usize(-1)) || stack == voidptr(usize(-1)) { fatal(3) }
  if C.mprotect(voidptr(usize(input_memory) + pages), pages, C.PROT_NONE) != 0 || C.mprotect(voidptr(usize(output_memory) + pages), pages, C.PROT_NONE) != 0 { fatal(4) }
  input_tail := &u8(usize(input_memory) + pages - 48)
  output_tail := &u8(usize(output_memory) + pages - 48)
  next_stack := u64(usize(stack) + 131072)
  minimum := $if arm64 { u64(5120) } $else { u64(2048) }
  for before in [false, true]! {
   old_sp := if before { u64(usize(stack)) } else { u64(0) }
   old_flags := if before { u32(0) } else { u32(2) }
   old_size := if before { u64(65536) } else { u64(0) }
   for flags in [u32(0), 1, 2, 3, 4, 7, 0x7fffffff, 0xfffffffe]! {
    for size in [u64(0), 1, 2047, 2048, 2049, 5119, 5120, 5121, 65536]! {
     for input_kind in 0 .. 3 {
      for output_kind in 0 .. 9 {
       establish(before, stack)
       mut input_buffer := [48]u8{init: 0xa5}
       mut output_buffer := [48]u8{init: 0xa5}
       for i in 0 .. 48 { input_tail[i] = 0xa5; output_tail[i] = 0xa5 }
       input_offset := if input_kind == 0 { 8 } else { 3 }
       input := if input_kind < 2 { voidptr(&input_buffer[input_offset]) } else { voidptr(&input_tail[24]) }
       mut request := [3]u64{}
       request[0] = next_stack; request[1] = (u64(0xa5a5a5a5) << 32) | u64(flags); request[2] = size
       C.memcpy(input, &request[0], 24)
       output_offset := if output_kind == 1 { 8 } else { 3 }
       output := if output_kind == 0 { nil }
        else if output_kind < 3 { voidptr(&output_buffer[output_offset]) }
        else if output_kind == 3 { voidptr(&output_tail[24]) }
        else if output_kind == 4 { voidptr(1) }
        else if output_kind == 5 { voidptr(usize(-1)) }
        else if output_kind == 6 { readonly }
        else if output_kind == 7 { voidptr(&output_tail[36]) }
        else { input }
       valid_mode := flags in [u32(0), 1, 2]!
       update := valid_mode && (flags == 2 || size >= minimum)
       bad_output := output_kind >= 4 && output_kind <= 7
       expected := if !valid_mode { C.EINVAL } else if flags != 2 && size < minimum { C.ENOMEM } else if bad_output { C.EFAULT } else { 0 }
       result := call(input, output)
       actual_errno := *C.__errno_location()
       check(mut t, result == (if expected == 0 { isize(0) } else { isize(-1) }), 20)
       check(mut t, actual_errno == expected, 21)
       mut current := [3]u64{}
       state_result := call(nil, &current[0])
       expected_sp := if update { if flags == 2 { u64(0) } else { next_stack } } else { old_sp }
       expected_flags := if update { if flags == 2 { u32(2) } else { u32(0) } } else { old_flags }
       expected_size := if update { if flags == 2 { u64(0) } else { size } } else { old_size }
       check(mut t, state_result == 0 && record_is(&current[0], expected_sp, expected_flags, expected_size), 22)
       mut output_good := true
       if output_kind != 0 && !bad_output {
        if update { output_good = record_is(output, old_sp, old_flags, old_size) }
        else if output_kind == 8 { output_good = C.memcmp(input, &request[0], 24) == 0 }
        else { output_good = bytes_are(output, 24, 0xa5) }
       }
       check(mut t, output_good, 23)
       mut guards := true
       for i in 0 .. 48 {
        if !(input_kind < 2 && i >= input_offset && i < input_offset + 24) && input_buffer[i] != 0xa5 { guards = false }
        if !(output_kind in [1, 2]! && i >= output_offset && i < output_offset + 24) && output_buffer[i] != 0xa5 { guards = false }
        if i < 24 && input_tail[i] != 0xa5 { guards = false }
        if i < (if output_kind == 7 { 36 } else { 24 }) && output_tail[i] != 0xa5 { guards = false }
       }
       if !(output_kind == 8 && update) && C.memcmp(input, &request[0], 24) != 0 { guards = false }
       check(mut t, guards, 24)
      }
     }
    }
   }
  }
  establish(false, stack)
  if C.munmap(input_memory, pages * 2) != 0 || C.munmap(output_memory, pages * 2) != 0 || C.munmap(readonly, pages) != 0 || C.munmap(stack, 262144) != 0 { fatal(5) }
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
  C.printf(c'LINUX ALTSTACKABI SUMMARY: checks=%d failures=%d\n', total.checks, total.failures)
  if total.failures == 0 { C.printf(c'LINUX ALTSTACKABI: PASS\n') } else { C.printf(c'LINUX ALTSTACKABI: FAIL\n') }
  C.fflush(nil); C.alarm(0)
  for { C.pause() }
 }
 return 0
}
