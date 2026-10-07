// SPDX-License-Identifier: GPL-2.0-or-later
// Independent securelevel, UTS-domain and concurrent process/thread fixture.
@[translated; has_globals]
module securefixture

#include <native-abi.h>

@[typedef] struct C.FILE {}
@[typedef] struct C.pthread_t {}
struct C.iovec { iov_base voidptr iov_len usize }
@[c_extern] __global C.stdout &C.FILE
@[c_extern] __global C.errno i32
__global failures i32

fn C.printf(&char, ...) i32
fn C.snprintf(&char, usize, &char, ...) i32
fn C.puts(&char) i32
fn C.setvbuf(&C.FILE, voidptr, i32, usize) i32
fn C.open(&char, i32, ...) i32
fn C.close(i32) i32
fn C.dup2(i32, i32) i32
fn C.write(i32, voidptr, usize) isize
fn C.read(i32, voidptr, usize) isize
fn C.pwrite(i32, voidptr, usize, i64) isize
fn C.writev(i32, &C.iovec, i32) isize
fn C.setdomainname(&char, usize) i32
fn C.mknod(&char, u32, u64) i32
fn C.fork() i32
fn C.waitpid(i32, &i32, i32) i32
fn C.WIFEXITED(i32) bool
fn C.WEXITSTATUS(i32) i32
fn C.unshare(i32) i32
fn C._exit(i32)
fn C.pthread_create(&C.pthread_t, voidptr, fn (voidptr) voidptr, voidptr) i32
fn C.pthread_join(C.pthread_t, &voidptr) i32
fn C.vsecure_raise_level(voidptr) voidptr
fn C.fsync(i32) i32
fn C.pause() i32

fn check(valid bool, name &char) {
 unsafe {
  label := if valid { &char(c'PASS') } else { &char(c'FAIL') }
  C.printf(c'SECURELEVEL %s: %s (errno=%d)\n', label, name, C.errno)
  failures += if valid { i32(0) } else { i32(1) }
 }
}

fn level(value i32) i32 {
 unsafe {
  mut text := [8]char{}
  length := C.snprintf(&text[0], sizeof(text), c'%d\n', value)
  fd := C.open(c'/proc/sys/kernel/securelevel', C.O_WRONLY)
  if fd < 0 { return -1 }
  error := if C.write(fd, &text[0], usize(length)) == isize(length) { i32(0) } else { i32(-1) }
  saved := i32(C.errno)
  C.close(fd); C.errno = saved
  return error
 }
}

fn read_level() i32 {
 unsafe {
  mut text := [16]char{}
  fd := C.open(c'/proc/sys/kernel/securelevel', C.O_RDONLY)
  if fd < 0 || C.read(fd, &text[0], sizeof(text) - 1) < 1 { return -99 }
  C.close(fd)
  return i32(text[0]) - i32(`0`)
 }
}

fn wait_ok(child i32) bool {
 unsafe {
  mut status := i32(0); mut ret := i32(0)
  for {
   ret = C.waitpid(child, &status, 0)
   if !(ret < 0 && C.errno == C.EINTR) { break }
  }
  return ret == child && C.WIFEXITED(status) && C.WEXITSTATUS(status) == 0
 }
}

@[export: 'vsecure_raise_level']
pub fn raise_level(value voidptr) voidptr {
 unsafe { level(i32(isize(value))) }
 return unsafe { nil }
}

@[export: 'main']
pub fn entry() i32 {
 unsafe {
  console := C.open(c'/dev/com1', C.O_WRONLY)
  if console >= 0 { C.dup2(console, 1); C.dup2(console, 2); C.close(console) }
  C.setvbuf(C.stdout, nil, C._IONBF, 0)
  check(level(0) == 0, c'init controls level')
  check(C.setdomainname(c'sealed.test', 11) == 0, c'configure domain')
  check(C.mknod(c'/policy-disk', u32(C.S_IFBLK) | 0o600, 0) == 0, c'create disk policy fixture')
  disk := C.open(c'/policy-disk', C.O_RDWR)
  check(disk >= 0, c'insecure disk description opens')
  check(level(1) == 0, c'raise to secure')
  C.errno = 0
  check(C.setdomainname(c'changed.test', 12) == -1 && C.errno == C.EPERM, c'established domain is sealed')
  C.errno = 0
  check(C.setdomainname(c'', 0) == -1 && C.errno == C.EPERM, c'sealed domain cannot be cleared')
  mut child := C.fork()
  if child == 0 {
   if level(0) != -1 || C.errno != C.EPERM { C._exit(1) }
   if C.unshare(C.CLONE_NEWUTS) != 0 || C.setdomainname(c'private.test', 12) != 0 { C._exit(2) }
   C._exit(0)
  }
  check(child > 0 && wait_ok(child), c'non-init cannot lower level; private UTS can set its domain')
  C.puts(c'SECURELEVEL PASS: sealed domain and level transitions')
  check(level(2) == 0, c'raise to highly secure')
  C.errno = 0
  check(C.open(c'/policy-disk', C.O_WRONLY) == -1 && C.errno == C.EPERM, c'new disk write opens are denied')
  readable := C.open(c'/policy-disk', C.O_RDONLY)
  check(readable >= 0, c'disk read open remains available')
  if readable >= 0 { C.close(readable) }
  path := C.open(c'/policy-disk', C.O_PATH)
  check(path >= 0, c'O_PATH remains available')
  if path >= 0 { C.close(path) }
  mut byte := char(`x`)
  C.errno = 0
  check(C.write(disk, &byte, 1) == -1 && C.errno == C.EPERM, c'retained description cannot write')
  C.errno = 0
  check(C.pwrite(disk, &byte, 1, 0) == -1 && C.errno == C.EPERM, c'retained description cannot pwrite')
  vector := C.iovec{iov_base: &byte, iov_len: 1}
  C.errno = 0
  check(C.writev(disk, &vector, 1) == -1 && C.errno == C.EPERM, c'retained description cannot writev')
  C.close(disk)
  C.puts(c'SECURELEVEL PASS: existing disk descriptions are protected')
  file := C.open(c'/root/securelevel-file', C.O_CREAT | C.O_WRONLY, i32(0o600))
  check(file >= 0 && C.write(file, &byte, 1) == 1 && C.fsync(file) == 0, c'filesystem writes and sync remain available')
  if file >= 0 { C.close(file) }
  C.puts(c'SECURELEVEL PASS: ordinary filesystem writes remain available')
  check(level(0) == 0 && C.setdomainname(c'changed.test', 12) == 0, c'init can restore single-user state')
  for i := i32(0); i < 50; i++ {
   if level(0) != 0 { check(false, c'reset concurrent raise'); break }
   child = C.fork()
   if child == 0 {
    mut a := C.pthread_t{}; mut b := C.pthread_t{}
    if C.pthread_create(&a, nil, C.vsecure_raise_level, voidptr(isize(1))) != 0 ||
       C.pthread_create(&b, nil, C.vsecure_raise_level, voidptr(isize(2))) != 0 { C._exit(3) }
    C.pthread_join(a, nil); C.pthread_join(b, nil)
    C._exit(if read_level() == 2 { i32(0) } else { i32(4) })
   }
   if child < 0 || !wait_ok(child) { check(false, c'concurrent raises never lower policy'); break }
  }
  C.puts(if failures != 0 { &char(c'SECURELEVEL GUEST: FAIL') } else { &char(c'SECURELEVEL GUEST: PASS') })
  for { C.pause() }
 }
 return 0
}
