// SPDX-License-Identifier: GPL-2.0-or-later
module sysrqfixture

#include <errno.h>
#include <fcntl.h>
#include <grp.h>
#include <stdio.h>
#include <sys/wait.h>
#include <unistd.h>

fn C.open(&char, i32, ...) i32
fn C.write(i32, voidptr, usize) isize
fn C.close(i32) i32
fn C.fork() i32
fn C.waitpid(i32, &i32, i32) i32
fn C.WIFEXITED(i32) bool
fn C.WEXITSTATUS(i32) i32
fn C.setgroups(usize, voidptr) i32
fn C.setgid(u32) i32
fn C.setuid(u32) i32
fn C.__errno_location() &i32
fn C._exit(i32)
fn C.puts(&char) i32
fn C.fflush(voidptr) i32
fn C.pause() i32

@[export: 'main']
pub fn run() i32 {
 unsafe {
  C.puts(c'LINUX SYSRQ: production task diagnostic')
  C.fflush(nil)
  child := C.fork()
  if child < 0 { return 1 }
  if child == 0 {
   if C.setgroups(0, nil) != 0 || C.setgid(1000) != 0 || C.setuid(1000) != 0 { C._exit(2) }
   fd := C.open(c'/proc/sysrq-trigger', C.O_WRONLY)
   if fd >= 0 { C.close(fd); C._exit(3) }
   if *C.__errno_location() != C.EACCES { C._exit(4) }
   C._exit(0)
  }
  mut status := i32(0)
  if C.waitpid(child, &status, 0) != child || !C.WIFEXITED(status) || C.WEXITSTATUS(status) != 0 { return 1 }
  fd := C.open(c'/proc/sysrq-trigger', C.O_WRONLY)
  if fd < 0 { return 1 }
  // A repeated explicit request must complete and print in production. The
  // controller requires the actual serial task row as well as this verdict.
  for _ in 0 .. 2 {
   mut trigger := [1]u8{init: `t`}
   if C.write(fd, &trigger[0], 1) != 1 { C.close(fd); return 1 }
  }
  C.close(fd)
  C.puts(c'LINUX SYSRQ: PASS')
  C.fflush(nil)
  for { C.pause() }
 }
 return 0
}
