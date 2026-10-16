// SPDX-License-Identifier: GPL-2.0-or-later
// Independent native xattr, metadata, concurrent copy-up and reboot fixture.
@[translated; has_globals]
module xattrfixture

#include <xattr-native-abi.h>

@[typedef] struct C.FILE {}
@[typedef] struct C.pthread_t {}
@[typedef] struct C.vxattr_atomic_int {}
struct C.vxattr_copy_race {
 mut:
 fds [64]i32
 stop C.vxattr_atomic_int
 failed C.vxattr_atomic_int
 changes C.vxattr_atomic_int
}
struct C.timespec { tv_sec isize tv_nsec isize }
struct C.stat { st_uid u32 st_gid u32 st_mode u32 st_atim C.timespec st_mtim C.timespec st_blocks i64 }
struct C.statfs { f_type isize f_bfree u64 f_ffree u64 }
@[c_extern] __global C.stdout &C.FILE
@[c_extern] __global C.errno i32

fn C.printf(&char, ...) i32
fn C.sscanf(&char, &char, ...) i32
fn C.snprintf(&char, usize, &char, ...) i32
fn C.fopen(&char, &char) &C.FILE
fn C.fgets(&char, i32, &C.FILE) &char
fn C.fclose(&C.FILE) i32
fn C.setbuf(&C.FILE, voidptr)
fn C.memset(voidptr, i32, usize) voidptr
fn C.memcpy(voidptr, voidptr, usize) voidptr
fn C.memcmp(voidptr, voidptr, usize) i32
fn C.strlen(&char) usize
fn C.strcmp(&char, &char) i32
fn C.strncmp(&char, &char, usize) i32
fn C.open(&char, i32, ...) i32
fn C.close(i32) i32
fn C.fsetxattr(i32, &char, voidptr, usize, i32) i32
fn C.fgetxattr(i32, &char, voidptr, usize) isize
fn C.flistxattr(i32, &char, usize) isize
fn C.fremovexattr(i32, &char) i32
fn C.setxattr(&char, &char, voidptr, usize, i32) i32
fn C.getxattr(&char, &char, voidptr, usize) isize
fn C.lsetxattr(&char, &char, voidptr, usize, i32) i32
fn C.lgetxattr(&char, &char, voidptr, usize) isize
fn C.fchmod(i32, u32) i32
fn C.fchown(i32, u32, u32) i32
fn C.futimens(i32, &C.timespec) i32
fn C.stat(&char, &C.stat) i32
fn C.fstat(i32, &C.stat) i32
fn C.statfs(&char, &C.statfs) i32
fn C.fork() i32
fn C.setgid(u32) i32
fn C.setuid(u32) i32
fn C._exit(i32)
fn C.waitpid(i32, &i32, i32) i32
fn C.WIFEXITED(i32) bool
fn C.WEXITSTATUS(i32) i32
fn C.fsync(i32) i32
fn C.unlink(&char) i32
fn C.mkdir(&char, u32) i32
fn C.mount(&char, &char, &char, usize, voidptr) i32
fn C.umount(&char) i32
fn C.pthread_create(&C.pthread_t, voidptr, fn (voidptr) voidptr, voidptr) i32
fn C.pthread_join(C.pthread_t, &voidptr) i32
fn C.vxattr_change_source_attributes(voidptr) voidptr
fn C.atomic_load(&C.vxattr_atomic_int) i32
fn C.atomic_store(&C.vxattr_atomic_int, i32)
fn C.atomic_fetch_add(&C.vxattr_atomic_int, i32) i32
fn C.sched_yield() i32
fn C.readlink(&char, &char, usize) isize
fn C.symlink(&char, &char) i32
fn C.puts(&char) i32
fn C.reboot(i32) i32
fn C.pause() i32
fn C.sync()

const payload = [u8(0), 1, 0xff, 0, 0x42]!
const copies = [&char(c'/root/xattr-tmpfs-ext2-upper/file-00'), &char(c'/root/xattr-ext2-ext2-upper/file-00')]!
const copy_files = i32(64)
const copy_attributes = i32(12)
struct Heap { mut: size [32]isize objects [32]isize count i32 large isize }

@[inline]
fn check(ok bool, line i32) bool {
 if !ok { unsafe { C.printf(c'FAIL: xattr line %d errno=%d\n', line, C.errno) } }
 return ok
}

fn heap_snapshot(heap &Heap) i32 {
 unsafe {
  file := C.fopen(c'/proc/slabinfo', c'r')
  if !check(file != nil, 30) { return 1 }
  mut line := [256]char{}
  mut saw_large := i32(0)
  C.memset(heap, 0, sizeof(Heap))
  for C.fgets(&line[0], i32(sizeof(line)), file) != nil {
   mut label := isize(0); mut size := isize(0); mut objects := isize(0); mut pages := isize(0)
   if C.sscanf(&line[0], c'size-%ld %ld %ld %ld', &label, &size, &objects, &pages) == 4 && label == size && heap.count < 32 {
    heap.size[heap.count] = size; heap.objects[heap.count] = objects; heap.count++
   } else if C.sscanf(&line[0], c'large - - %ld', &pages) == 1 { heap.large = pages; saw_large = 1 }
  }
  C.fclose(file)
  $if arm64 { if !check(heap.count == 18 && saw_large != 0, 46) { return 1 } }
  $else { if !check(heap.count == 14 && saw_large != 0, 48) { return 1 } }
  return 0
 }
}

fn operations(fd i32, repeats i32) i32 {
 unsafe {
  for i := i32(0); i < repeats; i++ {
   mut got := [32]u8{}; mut names := [256]char{}
   if !check(C.fsetxattr(fd, c'user.repeat', &payload[0], sizeof(payload), C.XATTR_CREATE) == 0, 58) { return 1 }
   if !check(C.fgetxattr(fd, c'user.repeat', nil, 0) == isize(sizeof(payload)), 59) { return 1 }
   if !check(C.fgetxattr(fd, c'user.repeat', &got[0], sizeof(got)) == isize(sizeof(payload)), 60) { return 1 }
   if !check(C.memcmp(&got[0], &payload[0], sizeof(payload)) == 0, 61) { return 1 }
   if !check(C.flistxattr(fd, &names[0], sizeof(names)) > 0, 62) { return 1 }
   if !check(C.fsetxattr(fd, c'user.repeat', c'replacement', 11, C.XATTR_REPLACE) == 0, 63) { return 1 }
   if !check(C.fremovexattr(fd, c'user.repeat') == 0, 64) { return 1 }
  }
  return 0
 }
}

fn metadata_operations(fd i32, repeats i32) i32 {
 unsafe {
  times := [C.timespec{tv_sec: 1700000000}, C.timespec{tv_sec: 1700000001}]!
  for i := i32(0); i < repeats; i++ {
   if !check(C.fchmod(fd, 0o600) == 0 && C.fchown(fd, 0, 0) == 0 && C.futimens(fd, &times[0]) == 0, 73) { return 1 }
  }
  return 0
 }
}

fn metadata_measure(path &char, backend &char) i32 {
 unsafe {
  fd := C.open(path, C.O_RDWR)
  if !check(fd >= 0 && metadata_operations(fd, 100) == 0, 81) { return 1 }
  mut before := Heap{}; mut after := Heap{}
  if !check(heap_snapshot(&before) == 0 && metadata_operations(fd, 200) == 0 && heap_snapshot(&after) == 0, 83) { return 1 }
  if !check(before.count == after.count, 84) { return 1 }
  for i := i32(0); i < before.count; i++ {
   kept := after.objects[i] - before.objects[i]
   C.printf(c'PERF-METADATA %s class=%ld objects=%ld kept-bytes=%ld\n', backend, before.size[i], kept, kept * before.size[i])
   if !check(kept <= 0, 88) { return 1 }
  }
  C.printf(c'PERF-METADATA %s large-pages=%ld\n', backend, after.large - before.large)
  if !check(after.large <= before.large, 91) { return 1 }
  if !check(C.close(fd) == 0, 92) { return 1 }; return 0
 }
}

fn copied_identity(path &char) i32 {
 unsafe {
  mut file := C.stat{}
  if !check(C.stat(path, &file) == 0, 99) { return 1 }
  if !check(file.st_uid == 321 && file.st_gid == 654 && (file.st_mode & 0o7777) == 0o600, 100) { return 1 }
  if !check(file.st_atim.tv_sec == 1700000000 && file.st_mtim.tv_sec == 1700000001, 101) { return 1 }; return 0
 }
}

fn exercise(path &char, persistent i32) i32 {
 unsafe {
  fd := C.open(path, C.O_CREAT | C.O_EXCL | C.O_RDWR, i32(0o600))
  if !check(fd >= 0, 108) { return 1 }
  mut got := [32]u8{}
  if !check(C.fsetxattr(fd, c'user.binary', &payload[0], sizeof(payload), C.XATTR_CREATE) == 0, 110) { return 1 }
  C.errno = 0; if !check(C.fsetxattr(fd, c'user.binary', &payload[0], sizeof(payload), C.XATTR_CREATE) == -1 && C.errno == C.EEXIST, 111) { return 1 }
  C.errno = 0; if !check(C.fsetxattr(fd, c'user.missing', &payload[0], sizeof(payload), C.XATTR_REPLACE) == -1 && C.errno == C.ENODATA, 112) { return 1 }
  if !check(C.fgetxattr(fd, c'user.binary', &got[0], sizeof(got)) == isize(sizeof(payload)), 113) { return 1 }
  if !check(C.memcmp(&got[0], &payload[0], sizeof(payload)) == 0, 114) { return 1 }
  C.errno = 0; if !check(C.fsetxattr(fd, c'user.binary', voidptr(usize(1)), 1, 0) == -1 && C.errno == C.EFAULT, 115) { return 1 }
  C.errno = 0; if !check(C.fgetxattr(fd, c'user.binary', voidptr(usize(1)), sizeof(got)) == -1 && C.errno == C.EFAULT, 116) { return 1 }
  C.errno = 0; if !check(C.fsetxattr(fd, c'user.binary', &payload[0], 65537, 0) == -1 && C.errno == C.E2BIG, 117) { return 1 }
  C.errno = 0; if !check(C.fgetxattr(fd, c'user.binary', &got[0], 1) == -1 && C.errno == C.ERANGE, 118) { return 1 }
  if !check(C.fsetxattr(fd, c'user.empty', nil, 0, 0) == 0, 119) { return 1 }
  if !check(C.fgetxattr(fd, c'user.empty', nil, 0) == 0, 120) { return 1 }
  if !check(C.fremovexattr(fd, c'user.empty') == 0, 121) { return 1 }
  C.errno = 0; if !check(C.fremovexattr(fd, c'user.empty') == -1 && C.errno == C.ENODATA, 122) { return 1 }
  C.errno = 0; if !check(C.fsetxattr(fd, c'user.', &payload[0], sizeof(payload), 0) == -1 && C.errno == C.EINVAL, 123) { return 1 }
  C.errno = 0; if !check(C.fsetxattr(fd, c'unsupported.name', &payload[0], sizeof(payload), 0) == -1 && C.errno == C.EOPNOTSUPP, 124) { return 1 }
  C.errno = 0; if !check(C.fsetxattr(fd, c'system.unsupported', &payload[0], sizeof(payload), 0) == -1 && C.errno == C.EOPNOTSUPP, 125) { return 1 }
  C.errno = 0; if !check(C.fsetxattr(fd, c'user.binary', &payload[0], sizeof(payload), 4) == -1 && C.errno == C.EINVAL, 126) { return 1 }
  if !check(C.fsetxattr(fd, c'trusted.secret', c'admin', 5, 0) == 0, 127) { return 1 }
  if !check(C.fsetxattr(fd, c'security.test', c'policy', 6, 0) == 0, 128) { return 1 }
  if !check(C.fsetxattr(fd, c'user.\xc3\xa9', c'utf8', 4, 0) == 0, 129) { return 1 }
  mut names := [1024]char{}; mut long_name := [256]char{}
  C.memset(&long_name[0], i32(`x`), sizeof(long_name)); C.memcpy(&long_name[0], c'user.', 5); long_name[255] = 0
  if !check(C.fsetxattr(fd, &long_name[0], &payload[0], sizeof(payload), 0) == 0, 134) { return 1 }
  if !check(C.fgetxattr(fd, &long_name[0], &got[0], sizeof(got)) == isize(sizeof(payload)), 135) { return 1 }
  if !check(C.fremovexattr(fd, &long_name[0]) == 0, 136) { return 1 }
  if !check(C.flistxattr(fd, nil, 0) > 0, 137) { return 1 }
  C.errno = 0; if !check(C.flistxattr(fd, &names[0], 1) == -1 && C.errno == C.ERANGE, 138) { return 1 }
  if !check(C.flistxattr(fd, &names[0], sizeof(names)) > 0, 139) { return 1 }
  C.errno = 0; if !check(C.flistxattr(fd, &char(usize(1)), sizeof(names)) == -1 && C.errno == C.EFAULT, 140) { return 1 }
  if persistent != 0 {
   mut large := [4096]char{}
   C.errno = 0; if !check(C.fsetxattr(fd, c'user.binary', &large[0], sizeof(large), 0) == -1 && C.errno == C.ENOSPC, 143) { return 1 }
   if !check(C.fgetxattr(fd, c'user.binary', &got[0], sizeof(got)) == isize(sizeof(payload)), 144) { return 1 }
   if !check(C.memcmp(&got[0], &payload[0], sizeof(payload)) == 0, 145) { return 1 }
  }
  child := C.fork()
  if !check(child >= 0, 148) { return 1 }
  if child == 0 {
   if !check(C.setgid(1000) == 0 && C.setuid(1000) == 0, 150) { return 1 }
   C.errno = 0; if !check(C.fgetxattr(fd, c'user.binary', &got[0], sizeof(got)) == -1 && C.errno == C.EACCES, 151) { return 1 }
   C.errno = 0; if !check(C.fgetxattr(fd, c'trusted.secret', &got[0], sizeof(got)) == -1 && C.errno == C.ENODATA, 152) { return 1 }
   C.errno = 0; if !check(C.fsetxattr(fd, c'trusted.secret', c'x', 1, 0) == -1 && C.errno == C.EPERM, 153) { return 1 }
   C.errno = 0; if !check(C.fsetxattr(fd, c'security.test', c'x', 1, 0) == -1 && C.errno == C.EPERM, 154) { return 1 }
   length := C.flistxattr(fd, &names[0], sizeof(names))
   if !check(length > 0, 156) { return 1 }
   for i := isize(0); i < length; i += isize(C.strlen(&names[i])) + 1 {
    if !check(C.strcmp(&names[i], c'trusted.secret') != 0, 158) { return 1 }
   }
   C._exit(0)
  }
  mut status := i32(0)
  if !check(C.waitpid(child, &status, 0) == child && C.WIFEXITED(status) && C.WEXITSTATUS(status) == 0, 162) { return 1 }
  if !check(operations(fd, 200) == 0, 163) { return 1 }
  mut before := Heap{}; mut after := Heap{}
  if !check(heap_snapshot(&before) == 0, 165) { return 1 }
  if !check(operations(fd, 200) == 0, 166) { return 1 }
  if !check(heap_snapshot(&after) == 0, 167) { return 1 }
  if !check(before.count == after.count, 168) { return 1 }
  for i := i32(0); i < before.count; i++ {
   kept := after.objects[i] - before.objects[i]
   C.printf(c'PERF-XATTR %s class=%ld objects=%ld kept-bytes=%ld\n', if persistent != 0 { &char(c'ext2') } else { &char(c'tmpfs') }, before.size[i], kept, kept * before.size[i])
   if !check(kept <= 0, 172) { return 1 }
  }
  C.printf(c'PERF-XATTR %s large-pages=%ld\n', if persistent != 0 { &char(c'ext2') } else { &char(c'tmpfs') }, after.large - before.large)
  if !check(after.large <= before.large, 175) { return 1 }
  if !check(C.fsync(fd) == 0 && C.close(fd) == 0, 176) { return 1 }; return 0
 }
}

fn block_release() i32 {
 unsafe {
  mut before := C.statfs{}; mut after := C.statfs{}; mut inode := C.stat{}
  if !check(C.statfs(c'/root', &before) == 0, 184) { return 1 }
  fd := C.open(c'/root/xattr-disposable', C.O_CREAT | C.O_EXCL | C.O_RDWR, i32(0o600))
  if !check(fd >= 0, 186) { return 1 }
  if !check(C.fsetxattr(fd, c'user.only', &payload[0], sizeof(payload), 0) == 0, 187) { return 1 }
  if !check(C.fstat(fd, &inode) == 0 && inode.st_blocks == 8, 188) { return 1 }
  if !check(C.fremovexattr(fd, c'user.only') == 0, 189) { return 1 }
  if !check(C.fstat(fd, &inode) == 0 && inode.st_blocks == 0, 190) { return 1 }
  if !check(C.fsetxattr(fd, c'user.only', &payload[0], sizeof(payload), 0) == 0, 191) { return 1 }
  if !check(C.unlink(c'/root/xattr-disposable') == 0, 192) { return 1 }
  if !check(C.fgetxattr(fd, c'user.only', nil, 0) == isize(sizeof(payload)), 193) { return 1 }
  if !check(C.close(fd) == 0, 194) { return 1 }
  if !check(C.statfs(c'/root', &after) == 0, 195) { return 1 }
  if !check(before.f_bfree == after.f_bfree, 196) { return 1 }; return 0
 }
}

@[export: 'vxattr_change_source_attributes']
pub fn change_source_attributes(argument voidptr) voidptr {
 unsafe {
  race := &C.vxattr_copy_race(argument)
  for C.atomic_load(&race.stop) == 0 {
   for i := i32(0); i < copy_files && C.atomic_load(&race.stop) == 0; i++ {
    for j := i32(0); j < copy_attributes; j++ {
     mut name := [96]char{}
     C.snprintf(&name[0], sizeof(name), c'user.concurrent-%02d-long-name-for-copy-ownership', j)
     if (C.fremovexattr(race.fds[i], &name[0]) != 0 && C.errno != C.ENODATA) || C.fsetxattr(race.fds[i], &name[0], &payload[0], sizeof(payload), 0) != 0 {
      C.atomic_store(&race.failed, 1); return nil
     }
     C.atomic_fetch_add(&race.changes, 1)
    }
   }
  }
  return nil
 }
}

fn concurrent_copy_up(lower_base &char, upper_base &char, label &char) i32 {
 unsafe {
  mut lower := [192]char{}; mut upper := [192]char{}; mut work := [192]char{}; mut merged := [192]char{}; mut options := [768]char{}
  C.snprintf(&lower[0], sizeof(lower), c'%s/xattr-%s-lower', lower_base, label)
  C.snprintf(&upper[0], sizeof(upper), c'%s/xattr-%s-upper', upper_base, label)
  C.snprintf(&work[0], sizeof(work), c'%s/xattr-%s-work', upper_base, label)
  C.snprintf(&merged[0], sizeof(merged), c'/tmp/xattr-tmpfs/xattr-%s-merged', label)
  if !check(C.mkdir(&lower[0], 0o700) == 0 && C.mkdir(&upper[0], 0o700) == 0, 234) { return 1 }
  if !check(C.mkdir(&work[0], 0o700) == 0 && C.mkdir(&merged[0], 0o700) == 0, 235) { return 1 }
  mut race := C.vxattr_copy_race{}
  for i := i32(0); i < copy_files; i++ {
   mut path := [256]char{}; mut name := [96]char{}
   C.snprintf(&path[0], sizeof(path), c'%s/file-%02d', &lower[0], i)
   race.fds[i] = C.open(&path[0], C.O_CREAT | C.O_EXCL | C.O_RDWR, i32(0o600))
   if !check(race.fds[i] >= 0, 241) { return 1 }
   if !check(C.fsetxattr(race.fds[i], c'user.stable', &payload[0], sizeof(payload), 0) == 0, 242) { return 1 }
   if !check(C.fsetxattr(race.fds[i], c'trusted.copy', &payload[0], sizeof(payload), 0) == 0, 243) { return 1 }
   if !check(C.fsetxattr(race.fds[i], c'security.copy', &payload[0], sizeof(payload), 0) == 0, 244) { return 1 }
   if !check(C.fsetxattr(race.fds[i], c'trusted.overlay.hidden', c'y', 1, 0) == 0, 245) { return 1 }
   for j := i32(0); j < copy_attributes; j++ {
    C.snprintf(&name[0], sizeof(name), c'user.concurrent-%02d-long-name-for-copy-ownership', j)
    if !check(C.fsetxattr(race.fds[i], &name[0], &payload[0], sizeof(payload), 0) == 0, 248) { return 1 }
   }
   times := [C.timespec{tv_sec: 1700000000}, C.timespec{tv_sec: 1700000001}]!
   if !check(C.fchown(race.fds[i], 321, 654) == 0 && C.futimens(race.fds[i], &times[0]) == 0, 251) { return 1 }
  }
  mut capacity_fd := i32(-1); mut identity_fd := i32(-1)
  mut capacity_lower := [256]char{}; mut capacity_upper := [256]char{}; mut capacity_merged := [256]char{}
  mut identity_lower := [256]char{}; mut identity_upper := [256]char{}; mut identity_merged := [256]char{}
  if C.strcmp(label, c'tmpfs-ext2') == 0 {
   mut large := [4096]char{}
   C.snprintf(&capacity_lower[0], sizeof(capacity_lower), c'%s/too-large', &lower[0])
   C.snprintf(&capacity_upper[0], sizeof(capacity_upper), c'%s/too-large', &upper[0])
   C.snprintf(&capacity_merged[0], sizeof(capacity_merged), c'%s/too-large', &merged[0])
   capacity_fd = C.open(&capacity_lower[0], C.O_CREAT | C.O_EXCL | C.O_RDWR, i32(0o600))
   if !check(capacity_fd >= 0, 263) { return 1 }
   if !check(C.fsetxattr(capacity_fd, c'user.first', &payload[0], sizeof(payload), 0) == 0, 264) { return 1 }
   if !check(C.fsetxattr(capacity_fd, c'user.large', &large[0], sizeof(large), 0) == 0, 265) { return 1 }
   C.snprintf(&identity_lower[0], sizeof(identity_lower), c'%s/large-uid', &lower[0])
   C.snprintf(&identity_upper[0], sizeof(identity_upper), c'%s/large-uid', &upper[0])
   C.snprintf(&identity_merged[0], sizeof(identity_merged), c'%s/large-uid', &merged[0])
   identity_fd = C.open(&identity_lower[0], C.O_CREAT | C.O_EXCL | C.O_RDWR, i32(0o600))
   if !check(identity_fd >= 0 && C.fchown(identity_fd, 70000, 654) == 0, 270) { return 1 }
   if !check(C.fsetxattr(identity_fd, c'user.first', &payload[0], sizeof(payload), 0) == 0, 271) { return 1 }
  }
  C.snprintf(&options[0], sizeof(options), c'lowerdir=%s,upperdir=%s,workdir=%s', &lower[0], &upper[0], &work[0])
  if !check(C.mount(c'overlay', &merged[0], c'overlay', 0, &options[0]) == 0, 274) { return 1 }
  if capacity_fd >= 0 {
   mut ignored := C.stat{}; mut before_failure := C.statfs{}; mut after_failure := C.statfs{}
   if !check(C.statfs(&upper[0], &before_failure) == 0, 278) { return 1 }
   C.errno = 0; if !check(C.setxattr(&capacity_merged[0], c'user.trigger', &payload[0], sizeof(payload), 0) == -1 && C.errno == C.ENOSPC, 279) { return 1 }
   C.errno = 0; if !check(C.stat(&capacity_upper[0], &ignored) == -1 && C.errno == C.ENOENT, 280) { return 1 }
   if !check(C.statfs(&upper[0], &after_failure) == 0, 281) { return 1 }
   if !check(before_failure.f_bfree == after_failure.f_bfree && before_failure.f_ffree == after_failure.f_ffree, 282) { return 1 }
   if !check(C.fgetxattr(capacity_fd, c'user.large', nil, 0) == 4096, 283) { return 1 }
   if !check(C.fremovexattr(capacity_fd, c'user.large') == 0, 284) { return 1 }
   if !check(C.setxattr(&capacity_merged[0], c'user.trigger', &payload[0], sizeof(payload), 0) == 0, 285) { return 1 }
   if !check(C.getxattr(&capacity_upper[0], c'user.first', nil, 0) == isize(sizeof(payload)), 286) { return 1 }
   if !check(C.close(capacity_fd) == 0, 287) { return 1 }
  }
  if identity_fd >= 0 {
   mut ignored := C.stat{}; mut before_failure := C.statfs{}; mut after_failure := C.statfs{}
   if !check(C.statfs(&upper[0], &before_failure) == 0, 292) { return 1 }
   C.errno = 0; if !check(C.setxattr(&identity_merged[0], c'user.trigger', &payload[0], sizeof(payload), 0) == -1 && C.errno == C.EOVERFLOW, 293) { return 1 }
   C.errno = 0; if !check(C.stat(&identity_upper[0], &ignored) == -1 && C.errno == C.ENOENT, 294) { return 1 }
   if !check(C.statfs(&upper[0], &after_failure) == 0, 295) { return 1 }
   if !check(before_failure.f_bfree == after_failure.f_bfree && before_failure.f_ffree == after_failure.f_ffree, 296) { return 1 }
   times := [C.timespec{tv_sec: 1700000000}, C.timespec{tv_sec: 1700000001}]!
   if !check(C.fchown(identity_fd, 321, 654) == 0 && C.futimens(identity_fd, &times[0]) == 0, 298) { return 1 }
   if !check(C.setxattr(&identity_merged[0], c'user.trigger', &payload[0], sizeof(payload), 0) == 0, 299) { return 1 }
   if !check(copied_identity(&identity_upper[0]) == 0 && C.close(identity_fd) == 0, 300) { return 1 }
  }
  mut writer := C.pthread_t{}
  // The native callback borrows this stack record until the original join.
  if !check(C.pthread_create(&writer, nil, C.vxattr_change_source_attributes, &race) == 0, 303) { return 1 }
  for C.atomic_load(&race.changes) == 0 && C.atomic_load(&race.failed) == 0 { C.sched_yield() }
  if !check(C.atomic_load(&race.failed) == 0, 305) { return 1 }
  for i := i32(0); i < copy_files; i++ {
   mut path := [256]char{}
   C.snprintf(&path[0], sizeof(path), c'%s/file-%02d', &merged[0], i)
   if !check(C.setxattr(&path[0], c'user.stable', &payload[0], sizeof(payload), C.XATTR_REPLACE) == 0, 309) { return 1 }
   C.sched_yield()
  }
  C.atomic_store(&race.stop, 1)
  if !check(C.pthread_join(writer, nil) == 0 && C.atomic_load(&race.failed) == 0 && C.atomic_load(&race.changes) > 0, 313) { return 1 }
  for i := i32(0); i < copy_files; i++ {
   mut path := [256]char{}; mut names := [2048]char{}; mut got := [32]u8{}
   C.snprintf(&path[0], sizeof(path), c'%s/file-%02d', &upper[0], i)
   fd := C.open(&path[0], C.O_RDONLY)
   if !check(fd >= 0, 319) { return 1 }
   if !check(copied_identity(&path[0]) == 0, 320) { return 1 }
   if !check(C.fgetxattr(fd, c'user.stable', &got[0], sizeof(got)) == isize(sizeof(payload)), 321) { return 1 }
   if !check(C.memcmp(&got[0], &payload[0], sizeof(payload)) == 0, 322) { return 1 }
   C.errno = 0; if !check(C.fgetxattr(fd, c'trusted.overlay.hidden', &got[0], sizeof(got)) == -1 && C.errno == C.ENODATA, 323) { return 1 }
   length := C.flistxattr(fd, &names[0], sizeof(names))
   if !check(length > 0, 325) { return 1 }
   for offset := isize(0); offset < length; offset += isize(C.strlen(&names[offset])) + 1 {
    native_line := $if arm64 { i32(330) } $else { i32(327) }
    if !check(C.strcmp(&names[offset], c'user.stable') == 0 || C.strcmp(&names[offset], c'trusted.copy') == 0 || C.strcmp(&names[offset], c'security.copy') == 0 || C.strncmp(&names[offset], c'user.concurrent-', 16) == 0, native_line) { return 1 }
    if !check(C.fgetxattr(fd, &names[offset], &got[0], sizeof(got)) == isize(sizeof(payload)), 331) { return 1 }
    if !check(C.memcmp(&got[0], &payload[0], sizeof(payload)) == 0, 332) { return 1 }
   }
   if !check(C.close(fd) == 0 && C.close(race.fds[i]) == 0, 334) { return 1 }
  }
  if !check(C.umount(&merged[0]) == 0, 336) { return 1 }
  C.printf(c'XATTR: CONCURRENT COPY-UP %s PASS\n', label); return 0
 }
}

@[export: 'main']
pub fn entry() i32 {
 unsafe {
  C.setbuf(C.stdout, nil); C.puts(c'XATTR: START')
  mut filesystem := C.statfs{}
  if !check(C.statfs(c'/root', &filesystem) == 0 && filesystem.f_type == 0xef53, 346) { return 1 }
  // A persistent x86 root keeps /tmp on ext2; mount the same intended tmpfs.
  if !check(C.mount(c'tmpfs', c'/tmp', c'tmpfs', 0, c'') == 0, 349) { return 1 }
  fd := C.open(c'/root/xattr-marker', C.O_RDONLY)
  if fd >= 0 {
   mut got := [32]u8{}
   if !check(C.fgetxattr(fd, c'user.binary', &got[0], sizeof(got)) == isize(sizeof(payload)), 353) { return 1 }
   if !check(C.memcmp(&got[0], &payload[0], sizeof(payload)) == 0, 354) { return 1 }
   if !check(C.fgetxattr(fd, c'trusted.secret', &got[0], sizeof(got)) == 5, 355) { return 1 }
   if !check(C.memcmp(&got[0], c'admin', 5) == 0, 356) { return 1 }
   if !check(C.fgetxattr(fd, c'security.test', &got[0], sizeof(got)) == 6, 357) { return 1 }
   mut target := [32]char{}
   if !check(C.readlink(c'/root/xattr-link', &target[0], sizeof(target)) == 12, 359) { return 1 }
   if !check(C.memcmp(&target[0], c'xattr-marker', 12) == 0, 360) { return 1 }
   if !check(C.lgetxattr(c'/root/xattr-link', c'security.test', &got[0], sizeof(got)) == 4, 361) { return 1 }
   if !check(C.close(fd) == 0, 362) { return 1 }
   for i := usize(0); i < sizeof(copies) / sizeof(copies[0]); i++ {
    if !check(copied_identity(&char(copies[i])) == 0, 365) { return 1 }
    if !check(C.getxattr(copies[i], c'user.stable', &got[0], sizeof(got)) == isize(sizeof(payload)), 366) { return 1 }
    if !check(C.memcmp(&got[0], &payload[0], sizeof(payload)) == 0, 367) { return 1 }
    if !check(C.getxattr(copies[i], c'trusted.copy', &got[0], sizeof(got)) == isize(sizeof(payload)), 368) { return 1 }
    if !check(C.getxattr(copies[i], c'security.copy', &got[0], sizeof(got)) == isize(sizeof(payload)), 369) { return 1 }
   }
   C.puts(c'XATTR: PASS'); C.reboot(C.RB_POWER_OFF)
   for { C.pause() }
  }
  if !check(C.errno == C.ENOENT, 375) { return 1 }
  if !check(C.mkdir(c'/tmp/xattr-tmpfs', 0o700) == 0, 376) { return 1 }
  if !check(C.mount(c'tmpfs', c'/tmp/xattr-tmpfs', c'tmpfs', 0, nil) == 0, 377) { return 1 }
  if !check(C.statfs(c'/tmp/xattr-tmpfs', &filesystem) == 0 && filesystem.f_type == 0x01021994, 378) { return 1 }
  if !check(exercise(c'/tmp/xattr-tmpfs/xattr-file', 0) == 0, 379) { return 1 }
  if !check(exercise(c'/root/xattr-marker', 1) == 0, 380) { return 1 }
  if !check(metadata_measure(c'/tmp/xattr-tmpfs/xattr-file', c'tmpfs') == 0, 381) { return 1 }
  if !check(metadata_measure(c'/root/xattr-marker', c'ext2') == 0, 382) { return 1 }
  if !check(concurrent_copy_up(c'/tmp/xattr-tmpfs', c'/tmp/xattr-tmpfs', c'tmpfs-tmpfs') == 0, 383) { return 1 }
  if !check(concurrent_copy_up(c'/tmp/xattr-tmpfs', c'/root', c'tmpfs-ext2') == 0, 384) { return 1 }
  if !check(concurrent_copy_up(c'/root', c'/tmp/xattr-tmpfs', c'ext2-tmpfs') == 0, 385) { return 1 }
  if !check(concurrent_copy_up(c'/root', c'/root', c'ext2-ext2') == 0, 386) { return 1 }
  if !check(block_release() == 0, 387) { return 1 }
  if !check(C.symlink(c'xattr-marker', c'/root/xattr-link') == 0, 388) { return 1 }
  if !check(C.lsetxattr(c'/root/xattr-link', c'security.test', c'link', 4, 0) == 0, 389) { return 1 }
  C.puts(c'XATTR: SYNC'); C.sync(); C.puts(c'XATTR: REBOOT'); C.reboot(C.RB_AUTOBOOT)
  if !check(false, 394) { return 1 }; return 0
 }
}
