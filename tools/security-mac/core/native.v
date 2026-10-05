// SPDX-License-Identifier: GPL-2.0-or-later
module maccli

#include "mac.h"
#include <errno.h>
#include <stdio.h>
#include <unistd.h>
$if !security_fixture ? {
 #include <sys/prctl.h>
 #include <sys/xattr.h>
}
@[c_extern] __global C.errno i32
@[c_extern] __global C.stderr voidptr
fn C.prctl(i32, ...voidptr) i32
fn C.lsetxattr(&char, &char, voidptr, usize, i32) i32
fn C.execvp(&char, &&char) i32
fn C.fprintf(voidptr, &char, ...voidptr) i32
fn C.fputs(&char, voidptr) i32
fn C.printf(&char, ...voidptr) i32
fn C.strerror(i32) &char

@[export: 'vm_prctl']
pub fn policy(command u64, domain u64, kind u64, mask u64) i64 {
 return i64(C.prctl(i32(C.VINIX_MAC_PRCTL), command, domain, kind, mask))
}
@[export: 'vm_lsetxattr']
pub fn set_label(path &char, name &char, value voidptr, length usize, flags i32) i32 { return C.lsetxattr(path, name, value, length, flags) }
@[export: 'vm_execvp']
pub fn execute(path &char, argv &&char) i32 { return C.execvp(path, argv) }
@[export: 'vm_error']
pub fn error(operation &char) { unsafe { C.fprintf(C.stderr, c'vinix-mac: %s: %s\n', operation, C.strerror(C.errno)) } }
@[export: 'vm_usage']
pub fn print_usage(text &char) { C.fputs(text, C.stderr) }
@[export: 'vm_status']
pub fn status(domain i64, sealed i64) { C.printf(c'domain=%ld sealed=%ld\n', isize(domain), isize(sealed)) }
$if !security_no_main ? {
 @[export: 'main']
 pub fn entry(argc i32, argv &&char) i32 { return run(argc, argv) }
}
