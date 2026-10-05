// SPDX-License-Identifier: GPL-2.0-or-later
// Native libc layouts remain owned by the target's headers.
module auditcore

#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <signal.h>
#include <stdio.h>
#include <sys/file.h>
#include <sys/stat.h>
#include <time.h>
#include <unistd.h>

struct C.stat {
mut:
 st_mode u32
 st_uid u32
 st_nlink u64
 st_dev u64
 st_ino u64
}
struct C.sigset_t {}
struct C.sigaction {
mut:
 sa_handler fn (i32)
 sa_mask C.sigset_t
 sa_flags i32
}
struct C.timespec {
mut:
 tv_sec i64
 tv_nsec i64
}
@[c_extern] __global C.errno i32
@[c_extern] __global C.stderr voidptr
@[export: 'stopping'] __global volatile audit_stopping = i32(0)
@[export: 'reopening'] __global volatile audit_reopening = i32(0)
fn C.fstat(i32, &C.stat) i32
fn C.S_ISREG(u32) i32
fn C.S_ISDIR(u32) i32
fn C.strtok_r(&char, &char, &&char) &char
fn C.open(&char, i32, ...voidptr) i32
fn C.openat(i32, &char, i32, ...voidptr) i32
fn C.fcntl(i32, i32, ...voidptr) i32
fn C.flock(i32, i32) i32
fn C.mkdirat(i32, &char, u32) i32
fn C.read(i32, voidptr, usize) i64
fn C.write(i32, voidptr, usize) i64
fn C.close(i32) i32
fn C.fsync(i32) i32
fn C.getuid() u32
fn C.geteuid() u32
fn C.getpid() i32
fn C.umask(u32) u32
fn C.sigemptyset(&C.sigset_t) i32
fn C.sigaction(i32, &C.sigaction, &C.sigaction) i32
fn C.vka_signal_handler(i32)
fn C.clock_gettime(i32, &C.timespec) i32
fn C.nanosleep(&C.timespec, &C.timespec) i32
fn C.fputs(&char, voidptr) i32
fn C.fprintf(voidptr, &char, ...voidptr) i32
fn C.perror(&char)
fn C.strerror(i32) &char

fn signal_stopping() i32 { unsafe { return audit_stopping } }
fn signal_reopening() i32 { unsafe { return audit_reopening } }
fn signal_clear_reopening() { unsafe { audit_reopening = 0 } }

@[export: 'vka_signal_handler']
pub fn signal_handler(signal i32) {
 unsafe {
  if signal == C.SIGHUP { audit_reopening = 1 }
  else { audit_stopping = 1 }
 }
}
@[export: 'vka_stat']
pub fn stat_fd(fd i32, out &C.vka_stat) i32 {
 unsafe {
  mut st := C.stat{}
  if C.fstat(fd, &st) != 0 { return -1 }
  *out = C.vka_stat{mode: u64(st.st_mode), owner: u64(st.st_uid), links: st.st_nlink,
   device: st.st_dev, inode: st.st_ino, regular: C.S_ISREG(st.st_mode), directory: C.S_ISDIR(st.st_mode)}
  return 0
 }
}
@[export: 'vka_path_max']
pub fn path_max() usize { return usize(C.PATH_MAX) }
@[export: 'vka_token']
pub fn tokenize(text &char, delimiters &char, save &&char) &char { return C.strtok_r(text, delimiters, save) }
fn error_code(selector i32) i32 {
 codes := [i32(C.EINTR), i32(C.EEXIST), i32(C.ENOENT), i32(C.EOVERFLOW), i32(C.EPROTO), i32(C.EACCES), i32(C.EINVAL), i32(C.EIO)]!
 return unsafe { codes[selector] }
}
@[export: 'vka_errno']
pub fn error_number() i32 { unsafe { return C.errno } }
@[export: 'vka_is_error']
pub fn is_error(selector i32) i32 { return if error_number() == error_code(selector) { 1 } else { 0 } }
@[export: 'vka_set_errno']
pub fn set_error(selector i32) { unsafe { C.errno = error_code(selector) } }
@[export: 'vka_restore_errno']
pub fn restore_error(error i32) { unsafe { C.errno = error } }
@[export: 'vka_open_read']
pub fn open_read(path &char) i32 { return C.open(path, C.O_RDONLY | C.O_NOFOLLOW | C.O_CLOEXEC) }
@[export: 'vka_open_root']
pub fn open_root() i32 { return C.open(c'/', C.O_RDONLY | C.O_DIRECTORY | C.O_NOFOLLOW | C.O_CLOEXEC) }
@[export: 'vka_open_dir']
pub fn open_dir(parent i32, name &char) i32 { return C.openat(parent, name, C.O_RDONLY | C.O_DIRECTORY | C.O_NOFOLLOW | C.O_CLOEXEC) }
@[export: 'vka_open_log_file']
pub fn open_log_file(parent i32, name &char, create i32) i32 {
 flags := C.O_WRONLY | C.O_APPEND | C.O_NONBLOCK | C.O_NOFOLLOW | C.O_CLOEXEC | if create != 0 { C.O_CREAT | C.O_EXCL } else { 0 }
 return C.openat(parent, name, i32(flags), u32(0o600))
}
@[export: 'vka_dup']
pub fn duplicate(fd i32) i32 { return C.fcntl(fd, C.F_DUPFD_CLOEXEC, i32(3)) }
@[export: 'vka_lock']
pub fn lock_file(fd i32) i32 { return C.flock(fd, C.LOCK_EX | C.LOCK_NB) }
@[export: 'vka_mkdir']
pub fn make_dir(parent i32, name &char) i32 { return C.mkdirat(parent, name, 0o700) }
@[export: 'vka_read']
pub fn read_fd(fd i32, buffer voidptr, size usize) i64 { return C.read(fd, buffer, size) }
@[export: 'vka_write']
pub fn write_fd(fd i32, buffer voidptr, size usize) i64 { return C.write(fd, buffer, size) }
@[export: 'vka_close']
pub fn close_fd(fd i32) i32 { return C.close(fd) }
@[export: 'vka_fsync']
pub fn sync_fd(fd i32) i32 { return C.fsync(fd) }
@[export: 'vka_uid']
pub fn uid() u32 { return C.getuid() }
@[export: 'vka_euid']
pub fn euid() u32 { return C.geteuid() }
@[export: 'vka_pid']
pub fn pid() i64 { return i64(C.getpid()) }
@[export: 'vka_umask']
pub fn mask() { C.umask(0o77) }
@[export: 'vka_signals']
pub fn signals() i32 {
 unsafe {
  mut action := C.sigaction{}
  action.sa_handler = C.vka_signal_handler
  C.sigemptyset(&action.sa_mask)
  return if C.sigaction(C.SIGTERM, &action, nil) != 0 || C.sigaction(C.SIGINT, &action, nil) != 0
   || C.sigaction(C.SIGHUP, &action, nil) != 0 { -1 } else { 0 }
 }
}
@[export: 'vka_wall_ns']
pub fn wall_ns() u64 {
 mut now := C.timespec{}
 if C.clock_gettime(C.CLOCK_REALTIME, unsafe { &now }) != 0 { return 0 }
 return u64(now.tv_sec) * 1000000000 + u64(now.tv_nsec)
}
@[export: 'vka_sleep']
pub fn sleep(seconds &u64, nanoseconds &u64) i32 {
 unsafe {
  mut delay := C.timespec{tv_sec: i64(*seconds), tv_nsec: i64(*nanoseconds)}
  result := C.nanosleep(&delay, &delay)
  *seconds = u64(delay.tv_sec); *nanoseconds = u64(delay.tv_nsec)
  return result
 }
}
@[export: 'vka_usage']
pub fn print_usage() { C.fputs(c'usage: vinix-security-audit [--log /var/log/vinix-audit/seccomp.log] [--source /proc/security_audit] [--interval-ms 250] [--once]\n', C.stderr) }
@[export: 'vka_root_required']
pub fn root_required() { C.fputs(c'vinix-security-audit: initial-namespace root required\n', C.stderr) }
@[export: 'vka_perror']
pub fn print_error(operation &char) { C.perror(operation) }
@[export: 'vka_collection_error']
pub fn collection_error(error i32) { C.fprintf(C.stderr, c'vinix-security-audit: collection stopped: %s\n', C.strerror(error)) }
// The independent fixture appends two literal rows through this bounded path.
$if security_no_main ? {
 @[export: 'vka_add']
 pub fn fixture_add(out &C.output, text &char) i32 { return put(out, text) }
}
$if !security_no_main ? {
 @[export: 'main']
 pub fn entry(argc i32, argv &&char) i32 { return audit_main(argc, argv) }
}
