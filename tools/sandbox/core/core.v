// SPDX-License-Identifier: GPL-2.0-or-later
// Parse first, then fail closed at every ordered privilege transition.
@[translated]
module sandboxcore

#include "sandbox_v.h"
struct C.sb_cap_data {
mut:
 effective u32
 permitted u32
 inheritable u32
}
fn C.strlen(&char) usize
fn C.strcmp(&char, &char) i32
fn C.strncmp(&char, &char, usize) i32
fn C.strchr(&char, i32) &char
fn C.strspn(&char, &char) usize
fn C.memset(voidptr, i32, usize) voidptr
fn C.__builtin_alloca(usize) voidptr
fn C.vksb_prctl(i32, u64) i32
fn C.vksb_capget(voidptr) i32
fn C.vksb_capset(voidptr) i32
fn C.vksb_verify_ambient() i32
fn C.vksb_ambient_cap(u64) i32
fn C.vksb_getids(&u32, &u32) i32
fn C.vksb_setids(u32, u32) i32
fn C.vksb_groups(i32) i32
fn C.vksb_close_fds() i32
fn C.vksb_unveil(&char, &char) i32
fn C.vksb_pledge(&char, &char) i32
fn C.vksb_exec(&char, &&char, &&char) i32
fn C.vksb_errno() i32
fn C.vksb_error(&char)
fn C.vksb_bad(&char)
fn C.vksb_help(&char)

struct Config {
mut:
 promises &char
 paths [127]&char
 perms [127]&char
 env [66]&char
 paths_count usize
 env_count usize
 uid u32
 gid u32
 has_uid bool
 has_gid bool
 command i32
}
fn sb_error(operation &char) i32 { C.vksb_error(operation); return 125 }
fn bad(message &char) i32 { C.vksb_bad(message); return 125 }
fn id(text &char, value &u32) i32 {
 unsafe {
  if text[0] == 0 { return -1 }
  mut number := u32(0)
  for p := text; p[0] != 0; p++ {
   byte := u8(p[0])
   if byte < 48 || byte > 57 { return -1 }
   digit := u32(byte - 48)
   if number > (u32(-1) - 1 - digit) / 10 { return -1 }
   number = number * 10 + digit
  }
  if number == 0 { return -1 }
  *value = number
  return 0
 }
}
fn absolute(path &char) bool { unsafe { return path[0] == 47 && C.strlen(path) < 4096 } }
fn environment(entry &char) bool {
 unsafe {
  equals := C.strchr(entry, 61)
  if usize(equals) == 0 || equals == entry { return false }
  for p := entry; p != equals; p++ {
   byte := u8(p[0])
   if (byte >= 97 && byte <= 122) || (byte >= 65 && byte <= 90) || byte == 95 { continue }
   if p != entry && byte >= 48 && byte <= 57 { continue }
   return false
  }
  return true
 }
}
fn parse(argc i32, argv &&char, config &Config) i32 {
 unsafe {
  for i := i32(1); i < argc; i++ {
   option := argv[i]
   if C.strcmp(option, c'--') == 0 { config.command = i + 1; break }
   if C.strcmp(option, c'--promises') == 0 {
    i++
    if i == argc || usize(config.promises) != 0 || C.strlen(argv[i]) >= 1024 { return bad(c'--promises needs one string shorter than 1024 bytes') }
    config.promises = argv[i]
   } else if C.strcmp(option, c'--uid') == 0 || C.strcmp(option, c'--gid') == 0 {
    is_uid := C.strcmp(option, c'--uid') == 0
    i++
    if i == argc { return bad(c'UID and GID must be numeric nonzero IDs below 4294967295') }
    if is_uid {
     if config.has_uid || id(argv[i], &config.uid) != 0 { return bad(c'UID and GID must be numeric nonzero IDs below 4294967295') }
     config.has_uid = true
    } else {
     if config.has_gid || id(argv[i], &config.gid) != 0 { return bad(c'UID and GID must be numeric nonzero IDs below 4294967295') }
     config.has_gid = true
    }
   } else if C.strcmp(option, c'--unveil') == 0 {
    if i + 2 >= argc || config.paths_count == 127 { return bad(c'--unveil needs an absolute path and permissions (at most 127 paths)') }
    i++
    path := argv[i]
    i++
    perms := argv[i]
    if !absolute(path) || C.strlen(perms) > 4 || C.strspn(perms, c'rwxc') != C.strlen(perms) { return bad(c'unveil paths must be absolute; permissions contain only rwxc') }
    for j := usize(0); j < config.paths_count; j++ { if C.strcmp(path, config.paths[j]) == 0 { return bad(c'duplicate unveil path') } }
    config.paths[config.paths_count] = path
    config.perms[config.paths_count] = perms
    config.paths_count++
   } else if C.strcmp(option, c'--env') == 0 {
    i++
    if i == argc || config.env_count == 64 || !environment(argv[i]) { return bad(c'--env needs NAME=VALUE (at most 64 entries)') }
    equals := C.strchr(argv[i], 61)
    for j := usize(0); j < config.env_count; j++ {
     previous := C.strchr(config.env[j], 61)
     length := usize(equals) - usize(argv[i])
     if length == usize(previous) - usize(config.env[j]) && C.strncmp(argv[i], config.env[j], length) == 0 { return bad(c'duplicate environment variable') }
    }
    config.env[config.env_count] = argv[i]
    config.env_count++
   } else { return bad(c'unknown option; use --help for usage') }
  }
  if usize(config.promises) == 0 || config.command <= 0 || config.command >= argc || !absolute(argv[config.command]) { return bad(c'--promises and -- /absolute/program are required') }
  if config.has_uid != config.has_gid { return bad(c'--uid and --gid must be supplied together') }
  return 0
 }
}

fn harden(config &Config) i32 {
 unsafe {
  mut uid := [3]u32{}
  mut gid := [3]u32{}
  mut caps := [2]C.sb_cap_data{}
  if C.vksb_getids(&uid[0], &gid[0]) != 0 { return sb_error(c'read credentials') }
  if !config.has_uid {
   if uid[0] == 0 || uid[1] == 0 || uid[2] == 0 || gid[0] == 0 || gid[1] == 0 || gid[2] == 0 { return bad(c'root credentials require explicit --uid and --gid') }
   config.uid = uid[1]
   config.gid = gid[1]
  }
  if C.vksb_prctl(38, 1) != 0 { return sb_error(c'set no_new_privs') }
  if C.vksb_prctl(39, 0) != 1 { return bad(c'no_new_privs was not enforced') }
  if C.vksb_capget(&caps[0]) != 0 { return sb_error(c'read capabilities') }
  if C.vksb_prctl(47, 4) != 0 { return sb_error(c'clear ambient capabilities') }
  if (caps[0].effective & 256) != 0 {
   mut cap := i32(0)
   for cap < 64 {
    present := C.vksb_prctl(23, u64(cap))
    if present == -1 && C.vksb_errno() == C.EINVAL { break }
    if present < 0 { return sb_error(c'read capability bounding set') }
    if present != 0 && C.vksb_prctl(24, u64(cap)) != 0 { return sb_error(c'drop bounding capability') }
    cap++
   }
   if cap == 64 { return bad(c'unsupported capability bounding set width') }
  }
  groups := C.vksb_groups(0)
  if groups < 0 { return sb_error(c'read supplementary groups') }
  if groups != 0 && C.vksb_groups(1) != 0 { return sb_error(c'clear supplementary groups') }
  if C.vksb_groups(0) != 0 { return bad(c'supplementary groups were not cleared') }
  if C.vksb_prctl(8, 0) != 0 { return sb_error(c'disable keepcaps') }
  if C.vksb_setids(config.uid, config.gid) != 0 { return sb_error(c'drop credentials') }
  if C.vksb_getids(&uid[0], &gid[0]) != 0 { return sb_error(c'verify credentials') }
  for i := 0; i < 3; i++ { if uid[i] != config.uid || gid[i] != config.gid { return bad(c'credential drop was not enforced') } }
  C.memset(&caps[0], 0, sizeof(C.sb_cap_data) * 2)
  if C.vksb_capset(&caps[0]) != 0 { return sb_error(c'clear capabilities') }
  if C.vksb_capget(&caps[0]) != 0 { return sb_error(c'verify capabilities') }
  for i := 0; i < 2; i++ { if caps[i].effective != 0 || caps[i].permitted != 0 || caps[i].inheritable != 0 { return bad(c'capability drop was not enforced') } }
  if C.vksb_verify_ambient() != 0 { return bad(c'ambient capability drop was not enforced') }
  if C.vksb_close_fds() != 0 { return sb_error(c'close inherited descriptors') }
  return 0
 }
}

@[export: 'vksb_verify_ambient_core']
pub fn verify_ambient() i32 {
 for cap := u64(0); cap <= 40; cap++ { if C.vksb_ambient_cap(cap) != 0 { return -1 } }
 return 0
}

@[export: 'vksb_main']
pub fn run(argc i32, argv &&char) i32 {
 unsafe {
  if argc == 2 && C.strcmp(argv[1], c'--help') == 0 {
   C.vksb_help(c'Usage: vinix-sandbox --promises \'stdio ...\' [--uid UID --gid GID]\n       [--unveil /path rwxc]... [--env NAME=VALUE]... -- /program [args...]\nDrops capabilities, supplementary groups and inherited FDs >=3; sets\nno_new_privs, locks unveil and keeps the target promises across exec.\nRoot must choose nonzero UID/GID. Environment is empty unless --env\nis supplied. The program is automatically unveiled rx; shared library\nand data paths must be explicitly unveiled. Setup failure exits 125.')
   return 0
  }
  // Both helpers finish synchronously and retain no configuration pointer.
  // Keep this call-local value on the stack in the allocation-free core.
  config := &Config(C.__builtin_alloca(sizeof(Config)))
  C.memset(config, 0, sizeof(Config))
  mut result := parse(argc, argv, config)
  if result != 0 { return result }
  result = harden(config)
  if result != 0 { return result }
  program := argv[config.command]
  if C.vksb_unveil(program, c'rx') != 0 { return sb_error(c'unveil program') }
  for i := usize(0); i < config.paths_count; i++ { if C.vksb_unveil(config.paths[i], config.perms[i]) != 0 { return sb_error(c'unveil path') } }
  if C.vksb_unveil(nil, nil) != 0 { return sb_error(c'lock unveil') }
  if C.vksb_pledge(c'stdio rpath exec', config.promises) != 0 { return sb_error(c'pledge') }
  C.vksb_exec(program, argv + config.command, &config.env[0])
  return sb_error(c'exec program')
 }
}
