// SPDX-License-Identifier: GPL-2.0-or-later
module namespacefixture

#include <errno.h>
#include <fcntl.h>
#include <sched.h>
#include <signal.h>
#include <stdio.h>
#include <sys/syscall.h>
#include <unistd.h>

struct CloneArgs {
 flags u64
 pidfd u64
 child_tid u64
 parent_tid u64
 exit_signal u64
 stack u64
 stack_size u64
 tls u64
 set_tid u64
 set_tid_size u64
 cgroup u64
}
fn C.syscall(isize, ...) isize
fn C.open(&char, int, ...) int
fn C.read(int, voidptr, usize) isize
fn C.write(int, voidptr, usize) isize
fn C.close(int) int
fn C.readlink(&char, &char, usize) isize
fn C.memcmp(voidptr, voidptr, usize) int
fn C.printf(&char, ...) int
fn C.puts(&char) int
fn C.fflush(voidptr) int
fn C.pause() int
fn C.__errno_location() &int

fn check(ok bool, label &char) bool {
 if ok { return true }
 unsafe { C.printf(c'LINUX NAMESPACE FAIL: %s errno=%d\n', label, *C.__errno_location()) }
 C.fflush(unsafe { nil })
 return false
}

fn rejects_write(path &char, value &char, count usize) bool {
 unsafe {
  fd := C.open(path, C.O_RDWR)
  if !check(fd >= 0, c'open namespace policy') { return false }
  mut before := [64]u8{}
  size := C.read(fd, &before[0], before.len)
  C.close(fd)
  writefd := C.open(path, C.O_WRONLY)
  if !check(writefd >= 0, c'open namespace policy for write') { return false }
  result := C.write(writefd, value, count)
  error_code := *C.__errno_location()
  C.close(writefd)
  afterfd := C.open(path, C.O_RDONLY)
  mut after := [64]u8{}
  aftersize := C.read(afterfd, &after[0], after.len)
  C.close(afterfd)
  return check(result == -1 && error_code == C.EPERM && size > 0
   && aftersize == size && before == after, c'policy write rejects and retains state')
 }
}

@[export: 'main']
pub fn run() int {
 unsafe {
  if !rejects_write(c'/proc/self/uid_map', c'0 1000 1\n', 9)
   || !rejects_write(c'/proc/self/gid_map', c'0 1000 1\n', 9)
   || !rejects_write(c'/proc/self/setgroups', c'deny\n', 5) { return 1 }
  names := [&char(c'/proc/self/ns/user'), &char(c'/proc/self/ns/net'), &char(c'/proc/self/ns/time'), &char(c'/proc/self/ns/uts')]!
  mut original := [4][64]u8{}
  mut sizes := [4]isize{}
  for index in 0 .. names.len {
   sizes[index] = C.readlink(names[index], &char(&original[index][0]), 64)
   if !check(sizes[index] > 0, c'read original namespace') { return 1 }
  }
  for flag in [u64(0x10000000), 0x40000000, 0x80]! {
   for request in [flag, flag | u64(0x04000000)]! {
    if !check(C.syscall(isize(C.SYS_unshare), request) == -1
     && *C.__errno_location() == C.EINVAL, c'unsupported unshare') { return 1 }
   }
   args := CloneArgs{flags: flag | u64(0x04000000), exit_signal: u64(C.SIGCHLD)}
   if !check(C.syscall(isize(C.SYS_clone3), &args, usize(sizeof(CloneArgs))) == -1
    && *C.__errno_location() == C.EINVAL, c'unsupported clone3') { return 1 }
   if flag != u64(0x80) {
    if !check(C.syscall(isize(C.SYS_clone), flag | u64(C.SIGCHLD), voidptr(nil), voidptr(nil), voidptr(nil), voidptr(nil)) == -1
     && *C.__errno_location() == C.EINVAL, c'unsupported clone') { return 1 }
   }
   for index in 0 .. names.len {
    mut current := [64]u8{}
    size := C.readlink(names[index], &char(&current[0]), 64)
    if !check(size == sizes[index] && C.memcmp(&current[0], &original[index][0], usize(size)) == 0,
     c'rejected mixed flags retain all namespace identities') { return 1 }
   }
  }
  fd := C.open(c'/proc/self/ns/user', C.O_RDONLY)
  if !check(fd >= 0 && C.syscall(isize(C.SYS_setns), isize(fd), isize(0)) == -1
   && *C.__errno_location() == C.EINVAL, c'unavailable setns') { return 1 }
  C.close(fd)
  C.puts(c'LINUX NAMESPACE: PASS')
  C.fflush(nil)
  for { C.pause() }
 }
 return 0
}
