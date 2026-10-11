// SPDX-License-Identifier: GPL-2.0-or-later
module mountfixture

#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <sys/mount.h>
#include <sys/stat.h>
#include <unistd.h>

fn C.mount(&char, &char, &char, usize, voidptr) int
fn C.umount(&char) int
fn C.mkdir(&char, u32) int
fn C.symlink(&char, &char) int
fn C.open(&char, int, ...) int
fn C.read(int, voidptr, usize) isize
fn C.write(int, voidptr, usize) isize
fn C.close(int) int
fn C.puts(&char) int
fn C.printf(&char, ...) int
fn C.fflush(voidptr) int
fn C.sync()
fn C.pause() int
fn C.__errno_location() &int

fn check(ok bool, label &char) bool {
 if ok { return true }
 unsafe { C.printf(c'LINUX MOUNT FAIL: %s errno=%d\n', label, *C.__errno_location()) }
 C.fflush(unsafe { nil })
 return false
}

@[export: 'main']
pub fn run() int {
 unsafe {
  C.mkdir(c'/mnt', 0o755)
  C.mkdir(c'/mnt/store', 0o755)
  C.mkdir(c'/mnt/alias', 0o755)
  device := $if arm64 { &char(c'/dev/vda') } $else { &char(c'/dev/sd0') }
  if !check(C.mount(c'/no-such-device', c'/mnt/store', c'ext2', 0, nil) == -1 && *C.__errno_location() == C.ENOENT, c'missing source') { return 1 }
  if !check(C.mount(c'/dev/null', c'/mnt/store', c'ext2', 0, nil) == -1 && *C.__errno_location() == C.ENOTBLK, c'non-block source') { return 1 }
  if !check(C.mount(device, c'/mnt/store', c'ext42', 0, nil) == -1 && *C.__errno_location() == C.ENODEV, c'unknown filesystem') { return 1 }
  if !check(C.mount(device, c'/mnt/store', c'ext2', 0, nil) == 0, c'ordinary ext2 mount') { return 1 }
  fd := C.open(c'/mnt/store/persistent-marker', C.O_CREAT | C.O_RDWR | C.O_TRUNC, 0o600)
  if !check(fd >= 0 && C.write(fd, c'vinix-ext2-42', 13) == 13 && C.close(fd) == 0, c'write mounted volume') { return 1 }
  if !check(C.symlink(device, c'/dev/compat-mount-alias') == 0, c'source alias') { return 1 }
  if !check(C.mount(c'/dev/compat-mount-alias', c'/mnt/alias', c'ext2', usize(C.MS_RDONLY), nil) == 0, c'readonly alias mount') { return 1 }
  reopened := C.open(c'/mnt/alias/persistent-marker', C.O_RDONLY)
  mut bytes := [13]u8{}
  if !check(reopened >= 0 && C.read(reopened, &bytes[0], bytes.len) == 13 && C.close(reopened) == 0,
    c'alias reads same backing volume') { return 1 }
  expected := [u8(`v`), `i`, `n`, `i`, `x`, `-`, `e`, `x`, `t`, `2`, `-`, `4`, `2`]!
  if !check(bytes == expected, c'alias data content') { return 1 }
  denied := C.open(c'/mnt/alias/denied', C.O_CREAT | C.O_WRONLY, 0o600)
  if !check(denied == -1 && *C.__errno_location() == C.EROFS, c'readonly alias creation') { return 1 }
  if !check(C.open(c'/mnt/store/denied', C.O_RDONLY) == -1 && *C.__errno_location() == C.ENOENT, c'denied creation left no file') { return 1 }
  C.sync()
  if !check(C.umount(c'/mnt/alias') == 0 && C.umount(c'/mnt/store') == 0, c'unmount volumes') { return 1 }
  if !check(C.mount(device, c'/mnt/store', c'ext2', 0, nil) == 0, c'remount detected volume') { return 1 }
  again := C.open(c'/mnt/store/persistent-marker', C.O_RDONLY)
  if !check(again >= 0 && C.read(again, &bytes[0], bytes.len) == 13 && C.close(again) == 0
    && bytes == expected, c'remount saved content') { return 1 }
  C.sync()
  if !check(C.umount(c'/mnt/store') == 0, c'final unmount') { return 1 }
  C.puts(c'LINUX MOUNT: PASS')
  C.fflush(nil)
  for { C.pause() }
 }
 return 0
}
