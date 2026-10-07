// SPDX-License-Identifier: GPL-2.0-or-later
// Independent mounted-device capabilities, transfers and retained-denial fixture.
@[translated; has_globals]
module diskfixture

#include <disk-native-abi.h>

@[typedef] struct C.FILE {}
@[typedef] struct C.DIR {}
@[typedef] struct C.vdisk_ull {}
@[typedef] struct C.vdisk_ll {}
struct C.dirent { d_name [256]char }
struct C.stat { st_mode u32 st_rdev u64 st_size i64 }
struct C.statfs { f_type isize }
struct C.iovec { iov_base voidptr iov_len usize }
@[c_extern] __global C.stdout &C.FILE
@[c_extern] __global C.errno i32
__global data [512]u8
__global observed [512]u8

fn C.printf(&char, ...) i32
fn C.snprintf(&char, usize, &char, ...) i32
fn C.sscanf(&char, &char, ...) i32
fn C.fopen(&char, &char) &C.FILE
fn C.fgets(&char, i32, &C.FILE) &char
fn C.fclose(&C.FILE) i32
fn C.setbuf(&C.FILE, voidptr)
fn C.puts(&char) i32
fn C.open(&char, i32, ...) i32
fn C.close(i32) i32
fn C.dup2(i32, i32) i32
fn C.write(i32, voidptr, usize) isize
fn C.read(i32, voidptr, usize) isize
fn C.pwrite(i32, voidptr, usize, i64) isize
fn C.pread(i32, voidptr, usize, i64) isize
fn C.writev(i32, &C.iovec, i32) isize
fn C.pipe2(&i32, i32) i32
fn C.splice(i32, &i64, i32, &i64, usize, u32) isize
fn C.copy_file_range(i32, &i64, i32, &i64, usize, u32) isize
fn C.lseek(i32, i64, i32) i64
fn C.memcmp(voidptr, voidptr, usize) i32
fn C.memcpy(voidptr, voidptr, usize) voidptr
fn C.memset(voidptr, i32, usize) voidptr
fn C.strcmp(&char, &char) i32
fn C.strrchr(&char, i32) &char
fn C.opendir(&char) &C.DIR
fn C.readdir(&C.DIR) &C.dirent
fn C.closedir(&C.DIR) i32
fn C.stat(&char, &C.stat) i32
fn C.statfs(&char, &C.statfs) i32
fn C.S_ISBLK(u32) bool
fn C.mknod(&char, u32, u64) i32
fn C.symlink(&char, &char) i32
fn C.mkdir(&char, u32) i32
fn C.mount(&char, &char, &char, usize, voidptr) i32
fn C.umount(&char) i32
fn C.fsync(i32) i32
fn C.pause() i32
fn C.sync()

fn ull(value u64) C.vdisk_ull { unsafe { result := C.vdisk_ull{}; C.memcpy(&result, &value, 8); return result } }
fn ll(value i64) C.vdisk_ll { unsafe { result := C.vdisk_ll{}; C.memcpy(&result, &value, 8); return result } }

@[inline]
fn check(ok bool, line i32, expression &char) {
 if !ok {
  unsafe { C.printf(c'SECUREDISK FAIL line=%d errno=%d: %s FAIL END\n', line, C.errno, expression) }
  for { C.pause() }
 }
}

fn level(value i32) {
 unsafe {
  mut text := [8]char{}
  length := C.snprintf(&text[0], sizeof(text), c'%d\n', value)
  fd := C.open(c'/proc/sys/kernel/securelevel', C.O_WRONLY)
  check(fd >= 0, 20, c'fd >= 0')
  check(C.write(fd, &text[0], usize(length)) == isize(length) && C.close(fd) == 0, 21, c'write(fd, text, (size_t)length) == length && close(fd) == 0')
 }
}

fn slab() isize {
 unsafe {
  file := C.fopen(c'/proc/meminfo', c'r')
  check(file != nil, 26, c'file != NULL')
  mut line := [256]char{}; mut key := [64]char{}; mut value := isize(0); mut found := isize(-1)
  for C.fgets(&line[0], i32(sizeof(line)), file) != nil {
   if C.sscanf(&line[0], c'%63s %ld', &key[0], &value) == 2 && C.strcmp(&key[0], c'Slab:') == 0 { found = value }
  }
  check(C.fclose(file) == 0 && found >= 0, 30, c'fclose(file) == 0 && found >= 0')
  return found
 }
}

fn denied_open(path &char) {
 unsafe {
  C.errno = 0; check(C.open(path, C.O_WRONLY) == -1 && C.errno == C.EPERM, 35, c'open(path, O_WRONLY) == -1 && errno == EPERM')
  mut fd := C.open(path, C.O_RDONLY); check(fd >= 0 && C.close(fd) == 0, 36, c'fd >= 0 && close(fd) == 0')
  fd = C.open(path, C.O_PATH); check(fd >= 0 && C.close(fd) == 0, 37, c'fd >= 0 && close(fd) == 0')
 }
}

fn denied_write(fd i32) {
 unsafe {
  C.errno = 0; check(C.write(fd, &data[0], sizeof(data)) == -1 && C.errno == C.EPERM, 42, c'write(fd, data, sizeof data) == -1 && errno == EPERM')
  C.errno = 0; check(C.pwrite(fd, &data[0], sizeof(data), 0) == -1 && C.errno == C.EPERM, 43, c'pwrite(fd, data, sizeof data, 0) == -1 && errno == EPERM')
  vector := C.iovec{iov_base: &data[0], iov_len: sizeof(data)}
  C.errno = 0; check(C.writev(fd, &vector, 1) == -1 && C.errno == C.EPERM, 45, c'writev(fd, &vector, 1) == -1 && errno == EPERM')
 }
}

fn denied_transfer(fd i32, input i32) {
 unsafe {
  mut pipes := [2]i32{}; check(C.pipe2(&pipes[0], C.O_NONBLOCK | C.O_CLOEXEC) == 0, 50, c'pipe2(pipes, O_NONBLOCK | O_CLOEXEC) == 0')
  check(C.write(pipes[1], &data[0], sizeof(data)) == isize(sizeof(data)), 51, c'write(pipes[1], data, sizeof data) == sizeof data')
  mut destination := i64(0)
  C.errno = 0; check(C.splice(pipes[0], nil, fd, &destination, sizeof(data), 0) == -1 && C.errno == C.EPERM, 53, c'splice(pipes[0], NULL, fd, &destination, sizeof data, 0) == -1 && errno == EPERM')
  check(destination == 0, 54, c'destination == 0')
  check(C.read(pipes[0], &observed[0], sizeof(observed)) == isize(sizeof(observed)) && C.memcmp(&data[0], &observed[0], sizeof(data)) == 0, 55, c'read(pipes[0], observed, sizeof observed) == sizeof observed && !memcmp(data, observed, sizeof data)')
  check(C.close(pipes[0]) == 0 && C.close(pipes[1]) == 0, 56, c'close(pipes[0]) == 0 && close(pipes[1]) == 0')
  check(C.lseek(input, 0, C.SEEK_SET) == 0, 57, c'lseek(input, 0, SEEK_SET) == 0')
  mut source := i64(0)
  C.errno = 0; check(C.copy_file_range(input, &source, fd, &destination, sizeof(data), 0) == -1 && C.errno == C.EPERM, 59, c'copy_file_range(input, &source, fd, &destination, sizeof data, 0) == -1 && errno == EPERM')
  check(source == 0 && destination == 0 && C.lseek(input, 0, C.SEEK_CUR) == 0, 60, c'source == 0 && destination == 0 && lseek(input, 0, SEEK_CUR) == 0')
 }
}

@[export: 'main']
pub fn entry() i32 {
 unsafe {
  $if amd64 {
   serial := C.open(c'/dev/com1', C.O_WRONLY | C.O_NOCTTY)
   if serial >= 0 { C.dup2(serial, 1); C.dup2(serial, 2); C.close(serial) }
  }
  mounted := $if amd64 { &char(c'/dev/sd0') } $else { &char(c'/dev/vda') }
  spare := $if amd64 { &char(c'/dev/sd1') } $else { &char(c'/dev/vdb') }
  C.setbuf(C.stdout, nil); C.puts(c'SECUREDISK START'); level(0)
  devices := C.opendir(c'/dev'); check(devices != nil, 73, c'devices != NULL')
  for {
   directory_entry := C.readdir(devices)
   if directory_entry == nil { break }
   mut path := [256]char{}; C.snprintf(&path[0], sizeof(path), c'/dev/%.240s', &directory_entry.d_name[0])
   mut device := C.stat{}
   if C.stat(&path[0], &device) == 0 && C.S_ISBLK(device.st_mode) {
    C.printf(c'SECUREDISK DEVICE: %s rdev=%llu bytes=%lld\n', &path[0], ull(device.st_rdev), ll(device.st_size))
   }
  }
  check(C.closedir(devices) == 0, 81, c'closedir(devices) == 0')
  mut original := C.stat{}; mut extra := C.stat{}
  check(C.stat(mounted, &original) == 0 && C.S_ISBLK(original.st_mode), 83, c'stat(mounted, &original) == 0 && S_ISBLK(original.st_mode)')
  check(C.stat(spare, &extra) == 0 && C.S_ISBLK(extra.st_mode), 84, c'stat(spare, &extra) == 0 && S_ISBLK(extra.st_mode)')
  mut filesystem := C.statfs{}
  check(C.statfs(c'/root', &filesystem) == 0 && filesystem.f_type == 0xef53, 86, c'statfs("/root", &filesystem) == 0 && filesystem.f_type == 0xef53')
  check(C.mknod(c'/policy-mounted', u32(C.S_IFBLK) | 0o600, original.st_rdev) == 0, 87, c'mknod("/policy-mounted", S_IFBLK | 0600, original.st_rdev) == 0')
  check(C.mknod(c'/policy-spare', u32(C.S_IFBLK) | 0o600, extra.st_rdev) == 0, 88, c'mknod("/policy-spare", S_IFBLK | 0600, extra.st_rdev) == 0')
  check(C.mknod(c'/policy-unknown', u32(C.S_IFBLK) | 0o600, ~u64(0)) == 0, 89, c'mknod("/policy-unknown", S_IFBLK | 0600, (dev_t)-1) == 0')
  check(C.symlink(mounted, c'/policy-symlink') == 0, 90, c'symlink(mounted, "/policy-symlink") == 0')
  check(C.mkdir(c'/policy-aliases', 0o700) == 0, 91, c'mkdir("/policy-aliases", 0700) == 0')
  mut misleading := [64]char{}; C.snprintf(&misleading[0], sizeof(misleading), c'/policy-aliases/%s', C.strrchr(mounted, i32(`/`)) + 1)
  check(C.mknod(&misleading[0], u32(C.S_IFCHR) | 0o600, 0) == 0, 93, c'mknod(misleading, S_IFCHR | 0600, 0) == 0')
  held := C.open(mounted, C.O_RDWR); alias := C.open(c'/policy-mounted', C.O_RDWR)
  disguised := C.open(&misleading[0], C.O_RDWR | C.O_NOCTTY); unmounted := C.open(spare, C.O_RDWR)
  check(held >= 0 && alias >= 0 && disguised >= 0 && unmounted >= 0, 96, c'held >= 0 && alias >= 0 && disguised >= 0 && unmounted >= 0')
  check(C.pread(held, &observed[0], sizeof(observed), 0) == isize(sizeof(observed)), 97, c'pread(held, observed, sizeof observed, 0) == sizeof observed')
  mut before := [512]u8{}; C.memcpy(&before[0], &observed[0], sizeof(before))
  C.memset(&data[0], 0xa7, sizeof(data))
  input := C.open(c'/root/policy-input', C.O_CREAT | C.O_RDWR, i32(0o600)); check(input >= 0, 100, c'input >= 0')
  check(C.write(input, &data[0], sizeof(data)) == isize(sizeof(data)) && C.lseek(input, 0, C.SEEK_SET) == 0, 101, c'write(input, data, sizeof data) == sizeof data && lseek(input, 0, SEEK_SET) == 0')
  check(C.pwrite(unmounted, &data[0], sizeof(data), 4096) == isize(sizeof(data)), 102, c'pwrite(unmounted, data, sizeof data, 4096) == sizeof data')
  check(C.pread(unmounted, &observed[0], sizeof(observed), 4096) == isize(sizeof(observed)) && C.memcmp(&data[0], &observed[0], sizeof(data)) == 0, 103, c'pread(unmounted, observed, sizeof observed, 4096) == sizeof observed && !memcmp(data, observed, sizeof data)')
  level(1)
  denied_open(mounted); denied_open(c'/policy-mounted'); denied_open(c'/policy-symlink'); denied_open(&misleading[0]); denied_open(c'/policy-unknown')
  denied_write(held); denied_write(alias)
  denied_transfer(held, input); denied_transfer(alias, input); denied_transfer(disguised, input)
  C.errno = 0; check(C.write(disguised, &data[0], sizeof(data)) == -1 && C.errno == C.EPERM, 110, c'write(disguised, data, sizeof data) == -1 && errno == EPERM')
  check(C.pread(held, &observed[0], sizeof(observed), 0) == isize(sizeof(observed)) && C.memcmp(&before[0], &observed[0], sizeof(before)) == 0, 111, c'pread(held, observed, sizeof observed, 0) == sizeof observed && !memcmp(before, observed, sizeof before)')
  C.puts(c'SECUREDISK PASS: mounted capability and aliases cannot write at level 1')
  spare_alias := C.open(c'/policy-spare', C.O_RDWR); check(spare_alias >= 0, 114, c'spare_alias >= 0')
  C.memset(&data[0], 0x59, sizeof(data))
  check(C.pwrite(unmounted, &data[0], sizeof(data), 4096) == isize(sizeof(data)), 116, c'pwrite(unmounted, data, sizeof data, 4096) == sizeof data')
  check(C.pwrite(spare_alias, &data[0], sizeof(data), 8192) == isize(sizeof(data)), 117, c'pwrite(spare_alias, data, sizeof data, 8192) == sizeof data')
  check(C.pread(unmounted, &observed[0], sizeof(observed), 8192) == isize(sizeof(observed)) && C.memcmp(&data[0], &observed[0], sizeof(data)) == 0, 118, c'pread(unmounted, observed, sizeof observed, 8192) == sizeof observed && !memcmp(data, observed, sizeof data)')
  $if amd64 {
   denied_open(c'/dev/sd0-0')
   partition := C.open(c'/dev/sd1-0', C.O_RDWR); check(partition >= 0, 123, c'partition >= 0')
   check(C.pwrite(partition, &data[0], sizeof(data), 4096) == isize(sizeof(data)) && C.close(partition) == 0, 124, c'pwrite(partition, data, sizeof data, 4096) == sizeof data && close(partition) == 0')
  } $else {
   check(C.mkdir(c'/policy-second', 0o700) == 0, 128, c'mkdir("/policy-second", 0700) == 0')
   mut file := C.open(c'/root/policy-template', C.O_CREAT | C.O_WRONLY, i32(0o600)); check(file >= 0, 129, c'file >= 0')
   check(C.write(file, &data[0], sizeof(data)) == isize(sizeof(data)) && C.fsync(file) == 0 && C.close(file) == 0, 130, c'write(file, data, sizeof data) == sizeof data && fsync(file) == 0 && close(file) == 0')
   check(C.mount(spare, c'/policy-second', c'qemu-persist', 0, c'') == 0, 131, c'mount(spare, "/policy-second", "qemu-persist", 0, "") == 0')
   file = C.open(c'/policy-second/policy-template', C.O_RDONLY); check(file >= 0, 132, c'file >= 0')
   check(C.read(file, &observed[0], sizeof(observed)) == isize(sizeof(observed)) && C.memcmp(&data[0], &observed[0], sizeof(data)) == 0 && C.close(file) == 0, 133, c'read(file, observed, sizeof observed) == sizeof observed && !memcmp(data, observed, sizeof data) && close(file) == 0')
   check(C.umount(c'/policy-second') == 0, 134, c'umount("/policy-second") == 0')
   denied_open(mounted)
   check(C.pwrite(unmounted, &data[0], sizeof(data), 4096) == isize(sizeof(data)), 136, c'pwrite(unmounted, data, sizeof data, 4096) == sizeof data')
  }
  C.puts(c'SECUREDISK PASS: unrelated raw disk remains writable and actual backing wins')
  output := C.open(c'/root/policy-writeback', C.O_CREAT | C.O_TRUNC | C.O_WRONLY, i32(0o600)); check(output >= 0, 140, c'output >= 0')
  for i := i32(0); i < 128; i++ { check(C.write(output, &data[0], sizeof(data)) == isize(sizeof(data)), 141, c'write(output, data, sizeof data) == sizeof data') }
  check(C.fsync(output) == 0 && C.close(output) == 0, 142, c'fsync(output) == 0 && close(output) == 0')
  C.puts(c'SECUREDISK PASS: mounted filesystem writeback remains available')
  vector := C.iovec{iov_base: &data[0], iov_len: sizeof(data)}
  mut transfers := [2]i32{}; check(C.pipe2(&transfers[0], C.O_NONBLOCK | C.O_CLOEXEC) == 0, 146, c'pipe2(transfers, O_NONBLOCK | O_CLOEXEC) == 0')
  check(C.write(transfers[1], &data[0], sizeof(data)) == isize(sizeof(data)), 147, c'write(transfers[1], data, sizeof data) == sizeof data')
  for i := i32(0); i < 50; i++ {
   C.errno = 0; check(C.open(c'/policy-mounted', C.O_WRONLY) == -1 && C.errno == C.EPERM, 149, c'open("/policy-mounted", O_WRONLY) == -1 && errno == EPERM')
   denied_write(held)
   mut source := i64(0); mut destination := i64(0)
   C.errno = 0; check(C.splice(transfers[0], nil, held, &destination, sizeof(data), 0) == -1 && C.errno == C.EPERM, 152, c'splice(transfers[0], NULL, held, &destination, sizeof data, 0) == -1 && errno == EPERM')
   C.errno = 0; check(C.copy_file_range(input, &source, held, &destination, sizeof(data), 0) == -1 && C.errno == C.EPERM, 153, c'copy_file_range(input, &source, held, &destination, sizeof data, 0) == -1 && errno == EPERM')
  }
  old := slab()
  for i := i32(0); i < 1000; i++ {
   C.errno = 0; check(C.open(c'/policy-mounted', C.O_WRONLY) == -1 && C.errno == C.EPERM, 157, c'open("/policy-mounted", O_WRONLY) == -1 && errno == EPERM')
   C.errno = 0; check(C.pwrite(held, &data[0], sizeof(data), 0) == -1 && C.errno == C.EPERM, 158, c'pwrite(held, data, sizeof data, 0) == -1 && errno == EPERM')
   C.errno = 0; check(C.write(held, &data[0], sizeof(data)) == -1 && C.errno == C.EPERM, 159, c'write(held, data, sizeof data) == -1 && errno == EPERM')
   C.errno = 0; check(C.writev(alias, &vector, 1) == -1 && C.errno == C.EPERM, 160, c'writev(alias, &vector, 1) == -1 && errno == EPERM')
   mut source := i64(0); mut destination := i64(0)
   C.errno = 0; check(C.splice(transfers[0], nil, held, &destination, sizeof(data), 0) == -1 && C.errno == C.EPERM, 162, c'splice(transfers[0], NULL, held, &destination, sizeof data, 0) == -1 && errno == EPERM')
   C.errno = 0; check(C.copy_file_range(input, &source, held, &destination, sizeof(data), 0) == -1 && C.errno == C.EPERM, 163, c'copy_file_range(input, &source, held, &destination, sizeof data, 0) == -1 && errno == EPERM')
   check(source == 0 && destination == 0, 164, c'source == 0 && destination == 0')
  }
  after := slab()
  C.printf(c'SECUREDISK RETAINED: 6000 denials slab_kb=%ld -> %ld\n', old, after); check(after <= old + 16, 167, c'after <= old + 16')
  check(C.read(transfers[0], &observed[0], sizeof(observed)) == isize(sizeof(observed)) && C.memcmp(&data[0], &observed[0], sizeof(data)) == 0, 168, c'read(transfers[0], observed, sizeof observed) == sizeof observed && !memcmp(data, observed, sizeof data)')
  check(C.close(transfers[0]) == 0 && C.close(transfers[1]) == 0, 169, c'close(transfers[0]) == 0 && close(transfers[1]) == 0')
  level(2); denied_open(spare); denied_open(c'/policy-spare'); denied_write(unmounted); denied_write(spare_alias)
  denied_transfer(unmounted, input); denied_transfer(spare_alias, input)
  C.errno = 0; check(C.write(disguised, &data[0], sizeof(data)) == -1 && C.errno == C.EPERM, 172, c'write(disguised, data, sizeof data) == -1 && errno == EPERM')
  check(C.close(held) == 0 && C.close(alias) == 0 && C.close(disguised) == 0 && C.close(unmounted) == 0 && C.close(spare_alias) == 0 && C.close(input) == 0, 173, c'close(held) == 0 && close(alias) == 0 && close(disguised) == 0 && close(unmounted) == 0 && close(spare_alias) == 0 && close(input) == 0')
  level(0); C.sync(); C.puts(c'SECUREDISK DONE pass ino=0')
  for { C.pause() }
 }
 return 0
}
