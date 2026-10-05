// SPDX-License-Identifier: GPL-2.0-or-later
module sandboxcore

#include <stdio.h>
#include <unistd.h>
$if !security_fixture ? {
 #include <sys/syscall.h>
}
@[c_extern] __global C.errno i32
@[c_extern] __global C.stderr voidptr
fn C.fprintf(voidptr, &char, ...voidptr) i32
fn C.puts(&char) i32
fn C.strerror(i32) &char
fn C.execve(&char, &&char, &&char) i32
fn C.syscall(i64, ...voidptr) i64
$if security_fixture ? {
 fn C.sb_prctl(i32, u64) i32
 fn C.sb_capget(&C.sb_cap_data) i32
 fn C.sb_capset(&C.sb_cap_data) i32
 fn C.sb_verify_ambient() i32
 fn C.sb_getids(&u32, &u32) i32
 fn C.sb_setids(u32, u32) i32
 fn C.sb_groups(i32) i32
 fn C.sb_close_fds() i32
 fn C.sb_unveil(&char, &char) i32
 fn C.sb_pledge(&char, &char) i32
 fn C.sb_exec(&char, &&char, &&char) i32
}
struct CapHeader { version u32 pid i32 }
@[export: 'vksb_prctl']
pub fn prctl(option i32, arg u64) i32 {
 $if security_fixture ? { return C.sb_prctl(option, arg) }
 $else { return i32(C.syscall(i64(C.SYS_prctl), option, arg, u64(0), u64(0), u64(0))) }
}
@[export: 'vksb_capget']
pub fn capget(data voidptr) i32 {
 $if security_fixture ? { return C.sb_capget(data) }
 $else {
  header := CapHeader{version: 0x20080522, pid: 0}
  return i32(C.syscall(i64(C.SYS_capget), unsafe { voidptr(usize(&header)) }, data))
 }
}
@[export: 'vksb_capset']
pub fn capset(data voidptr) i32 {
 $if security_fixture ? { return C.sb_capset(data) }
 $else {
  header := CapHeader{version: 0x20080522, pid: 0}
  return i32(C.syscall(i64(C.SYS_capset), unsafe { voidptr(usize(&header)) }, data))
 }
}
@[export: 'vksb_verify_ambient']
pub fn verify_ambient_native() i32 {
 $if security_fixture ? { return C.sb_verify_ambient() }
 $else { return verify_ambient() }
}
@[export: 'vksb_ambient_cap']
pub fn ambient_cap(cap u64) i32 {
 $if security_fixture ? { _ = cap; return 0 }
 $else { return i32(C.syscall(i64(C.SYS_prctl), i32(47), u64(3), cap, u64(0), u64(0))) }
}
@[export: 'vksb_getids']
pub fn get_ids(uid &u32, gid &u32) i32 {
 $if security_fixture ? { return C.sb_getids(uid, gid) }
 $else {
  unsafe {
   if C.syscall(i64(C.SYS_getresuid), &uid[0], &uid[1], &uid[2]) != 0 { return -1 }
   return i32(C.syscall(i64(C.SYS_getresgid), &gid[0], &gid[1], &gid[2]))
  }
 }
}
@[export: 'vksb_setids']
pub fn set_ids(uid u32, gid u32) i32 {
 $if security_fixture ? { return C.sb_setids(uid, gid) }
 $else {
  if C.syscall(i64(C.SYS_setresgid), gid, gid, gid) != 0 { return -1 }
  return i32(C.syscall(i64(C.SYS_setresuid), uid, uid, uid))
 }
}
@[export: 'vksb_groups']
pub fn supplementary_groups(clear i32) i32 {
 $if security_fixture ? { return C.sb_groups(clear) }
 $else { return i32(C.syscall(i64(if clear != 0 { C.SYS_setgroups } else { C.SYS_getgroups }), i32(0), voidptr(0))) }
}
@[export: 'vksb_close_fds']
pub fn close_fds() i32 {
 $if security_fixture ? { return C.sb_close_fds() }
 $else { return i32(C.syscall(i64(C.SYS_close_range), u32(3), u32(-1), u32(0))) }
}
@[export: 'vksb_unveil']
pub fn unveil(path &char, perms &char) i32 {
 $if security_fixture ? { return C.sb_unveil(path, perms) }
 $else {
  $if arm64 { return i32(C.syscall(i64(249), path, perms)) }
  $else { return i32(C.syscall(i64(502), path, perms)) }
 }
}
@[export: 'vksb_pledge']
pub fn pledge(promises &char, execpromises &char) i32 {
 $if security_fixture ? { return C.sb_pledge(promises, execpromises) }
 $else {
  $if arm64 { return i32(C.syscall(i64(248), promises, execpromises)) }
  $else { return i32(C.syscall(i64(501), promises, execpromises)) }
 }
}
@[export: 'vksb_exec']
pub fn execute(path &char, argv &&char, env &&char) i32 {
 $if security_fixture ? { return C.sb_exec(path, argv, env) }
 $else { return C.execve(path, argv, env) }
}
@[export: 'vksb_errno']
pub fn error_number() i32 { unsafe { return C.errno } }
@[export: 'vksb_error']
pub fn error(operation &char) { unsafe { C.fprintf(C.stderr, c'vinix-sandbox: %s: %s\n', operation, C.strerror(C.errno)) } }
@[export: 'vksb_bad']
pub fn print_bad(message &char) { C.fprintf(C.stderr, c'vinix-sandbox: %s\n', message) }
@[export: 'vksb_help']
pub fn print_help(text &char) { C.puts(text) }
@[export: 'vinix_sandbox_main']
pub fn sandbox_main(argc i32, argv &&char) i32 { return run(argc, argv) }
$if !security_no_main ? {
 @[export: 'main']
 pub fn entry(argc i32, argv &&char) i32 { return run(argc, argv) }
}
