// SPDX-License-Identifier: GPL-2.0-or-later
@[translated]
module maccli

#include "mac_v.h"
fn C.strlen(&char) usize
fn C.strcmp(&char, &char) i32
fn C.strchr(&char, i32) &char
fn C.memcmp(voidptr, voidptr, usize) i32
fn C.vm_prctl(u64, u64, u64, u64) i64
fn C.vm_lsetxattr(&char, &char, voidptr, usize, i32) i32
fn C.vm_execvp(&char, &&char) i32
fn C.vm_error(&char)
fn C.vm_usage(&char)
fn C.vm_status(i64, i64)

@[export: 'vm_number']
pub fn number(text &char, limit u32, value &u32) i32 {
 unsafe {
  if text[0] == 0 || (text[0] == 48 && text[1] != 0) { return -1 }
  mut result := u32(0)
  for p := text; p[0] != 0; p++ {
   digit := u8(p[0])
   if digit < 48 || digit > 57 || result > limit / 10 { return -1 }
   result = result * 10 + u32(digit - 48)
   if result >= limit { return -1 }
  }
  *value = result
  return 0
 }
}

fn name(index int) &char {
 return match index {
  0 { c'inspect' }
  1 { c'read' }
  2 { c'write' }
  3 { c'execute' }
  4 { c'create' }
  5 { c'remove' }
  6 { c'metadata' }
  7 { c'ioctl' }
  else { c'search' }
 }
}

@[export: 'vm_permissions']
pub fn permissions(text &char, mask &u32) i32 {
 unsafe {
  if C.strcmp(text, c'none') == 0 { *mask = 0; return 0 }
  mut result := u32(0)
  mut p := text
  for p[0] != 0 {
   end := C.strchr(p, 44)
   length := if usize(end) != 0 { usize(end) - usize(p) } else { C.strlen(p) }
   mut found := false
   for i := 0; i < 9; i++ {
    candidate := name(i)
    bit := u32(1) << u32(i)
    if C.strlen(candidate) == length && C.memcmp(p, candidate, length) == 0 {
     if (result & bit) != 0 { return -1 }
     result |= bit
     found = true
     break
    }
   }
   if !found { return -1 }
   if usize(end) == 0 { *mask = result; return 0 }
   p = end + 1
  }
  return -1
 }
}

fn failed(operation &char) i32 { C.vm_error(operation); return 1 }
fn usage() i32 {
 C.vm_usage(c'usage: vinix-mac status\n       vinix-mac rule DOMAIN TYPE inspect,read,write,execute,search,create,remove,metadata,ioctl|none\n       vinix-mac label TYPE PATH...\n       vinix-mac seal\n       vinix-mac run DOMAIN PROGRAM [ARG...]\n')
 return 2
}

@[export: 'vm_main']
pub fn run(argc i32, argv &&char) i32 {
 unsafe {
  if argc == 2 && C.strcmp(argv[1], c'status') == 0 {
   domain := C.vm_prctl(0, 0, 0, 0)
   if domain < 0 { return failed(c'read domain') }
   sealed := C.vm_prctl(4, 0, 0, 0)
   if sealed < 0 { return failed(c'read policy state') }
   C.vm_status(domain, sealed)
   return 0
  }
  if argc == 2 && C.strcmp(argv[1], c'seal') == 0 {
   if C.vm_prctl(2, 0, 0, 0) < 0 { return failed(c'seal policy') }
   return 0
  }
  mut domain := u32(0)
  mut kind := u32(0)
  mut mask := u32(0)
  if argc == 5 && C.strcmp(argv[1], c'rule') == 0 {
   if number(argv[2], 16, &domain) != 0 || domain == 0 || number(argv[3], 32, &kind) != 0 || permissions(argv[4], &mask) != 0 { return usage() }
   if C.vm_prctl(1, domain, kind, mask) < 0 { return failed(c'install rule') }
   return 0
  }
  if argc >= 4 && C.strcmp(argv[1], c'label') == 0 {
   if number(argv[2], 29, &kind) != 0 { return usage() }
   for i := i32(3); i < argc; i++ {
    if C.vm_lsetxattr(argv[i], c'security.vinix', argv[2], C.strlen(argv[2]), 0) != 0 { return failed(argv[i]) }
   }
   return 0
  }
  if argc >= 4 && C.strcmp(argv[1], c'run') == 0 {
   if number(argv[2], 16, &domain) != 0 || domain == 0 { return usage() }
   if C.vm_prctl(3, domain, 0, 0) < 0 { return failed(c'stage domain') }
   C.vm_execvp(argv[3], argv + 3)
   return failed(argv[3])
  }
  return usage()
 }
}
