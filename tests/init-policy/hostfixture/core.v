// SPDX-License-Identifier: GPL-2.0-only
// Independent raw-syscall fixture: the production policy calls no host syscall.
@[translated; has_globals]
module hostfixture

#include <host-native-abi.h>

@[typedef] struct C.vinix_init_escape {}
struct C.delay { mut: seconds i64 nanoseconds i64 }
struct C.action {
 handler fn (i32)
 flags u64
 restorer fn ()
 mask u64
}
@[c_extern] __global volatile C.vinit_power i32
@[c_extern] __global volatile C.vinit_reload i32

fn C.assert(bool)
fn C.strlen(&char) usize
fn C.strcpy(&char, &char) &char
fn C.strstr(&char, &char) &char
fn C.strcmp(&char, &char) i32
fn C.memcpy(voidptr, voidptr, usize) voidptr
fn C.setjmp(C.vinix_init_escape) i32
fn C.longjmp(C.vinix_init_escape, i32)
fn C.puts(&char) i32
fn C.vinix_init_shell()
fn C.vinix_init_full()
fn C.vinix_init_power_signal(i32)
fn C.vinix_init_child_signal(i32)
fn C.initcore__prepare_desktop_boot()
fn C.initcore__prepare_hosted_x11_storage()
fn C.initcore__install_power_signals()
fn C.initcore__apply_power_request()
fn C.initcore__pause_for(C.delay)
fn C.initcore__wait_for_child(i64, &i32)
fn C.initcore__stop_desktop_group(i64)
fn C.initcore__spawn_program(&&char, &&char, bool, &i32, &&char, bool) i64

struct Record { mut: nr u64 a [5]u64 path [160]char other [160]char }
__global calls [4096]Record
__global used usize
__global output_used usize
__global read_at usize
__global waits usize
__global sleeps usize
__global probes usize
__global output [32768]char
__global lines &&char
__global finished C.vinix_init_escape
__global mode i32
__global exit_status i32
__global symlink_failure i32
__global link_failure i32
__global mount_failure i32
__global cloned i64
__global stop_sleep bool
__global full_echo bool
const basic = i32(0)
const shell = i32(1)
const full = i32(2)
const wait = i32(3)
const reload = i32(4)
const sleep = i32(5)
const spawn_mode = i32(6)
const group = i32(7)
const shell_input = [&char(c' \t\r\n'), &char(c'help\n'), &char(c'hello\r\n'), &char(c'uname\n'), &char(c'echo   hello world\n'), &char(c'echo\n'), &char(c'echoes\n'), &char(c'missing\n'), &char(c'exit\n'), &char(nil)]!
const shell_eof = [&char(nil)]!
const signals = [u64(1), u64(15), u64(10), u64(12), u64(17)]!
const power = [u64(15), u64(10), u64(12)]!
const commands = [u64(0x01234567), u64(0xcdef0123), u64(0x4321fedc)]!

fn reset(next i32) {
 unsafe {
  used = 0; output_used = 0; read_at = 0; waits = 0; sleeps = 0; probes = 0
  output[0] = 0; mode = next; exit_status = -1
  symlink_failure = 0; link_failure = 0; mount_failure = 0
  cloned = 77; stop_sleep = false; C.vinit_reload = 0; C.vinit_power = 0
 }
}
fn text_copy(out &char, ptr u64) {
 unsafe { C.assert(ptr != 0); source := &char(usize(ptr)); C.assert(C.strlen(source) < 160); C.strcpy(out, source) }
}

@[export: 'vinit_syscall']
pub fn syscall(nr u64, a0 u64, a1 u64, a2 u64, a3 u64, a4 u64) i64 {
 unsafe {
  C.assert(used < 4096); mut r := &calls[used]; used++
  *r = Record{nr: nr, a: [a0, a1, a2, a3, a4]!}
  if nr == 64 {
   C.assert(a0 == 1 && output_used + a2 < sizeof(output))
   C.memcpy(&output[output_used], voidptr(usize(a1)), usize(a2))
   output_used += usize(a2); output[output_used] = 0; return i64(a2)
  }
  if nr == 63 {
   C.assert(mode == shell && a0 == 0 && a2 == 255)
   line := lines[read_at]; read_at++; if line == nil { return 0 }
   C.assert(C.strlen(line) <= a2); C.memcpy(voidptr(usize(a1)), line, C.strlen(line)); return i64(C.strlen(line))
  }
  if nr == 93 { exit_status = i32(a0); C.longjmp(finished, 1) }
  if nr == 56 {
   C.assert(a0 == u64(i64(-100))); text_copy(&r.path[0], a1)
   if a2 == 0x41 { C.assert(a3 == 0o600); return 9 }; return 8
  }
  if nr == 57 { C.assert(a0 == 8 || a0 == 9); return 0 }
  if nr == 35 || nr == 34 {
   C.assert(a0 == u64(i64(-100))); text_copy(&r.path[0], a1)
   if nr == 34 { C.assert(a2 == 0o700) }; return 0
  }
  if nr == 36 {
   text_copy(&r.path[0], a0); text_copy(&r.other[0], a2); C.assert(a1 == u64(i64(-100)))
   return if C.strstr(&r.other[0], c'activity') != nil && symlink_failure != 0 { i64(-5) } else { i64(0) }
  }
  if nr == 37 || nr == 38 {
   C.assert(a0 == u64(i64(-100)) && a2 == u64(i64(-100)))
   text_copy(&r.path[0], a1); text_copy(&r.other[0], a3)
   return if nr == 37 && link_failure != 0 { i64(-5) } else { i64(0) }
  }
  if nr == 40 {
   text_copy(&r.path[0], a0); text_copy(&r.other[0], a1)
   C.assert(C.strcmp(&char(usize(a2)), c'tmpfs') == 0); C.assert(a3 == 0 && a4 == 0)
   return if mount_failure != 0 { i64(-5) } else { i64(0) }
  }
  if nr == 134 {
   C.assert(a2 == 0 && a3 == 8); action := &C.action(usize(a1))
   C.assert(action.flags == 0 && action.mask == 0 && voidptr(action.restorer) != nil)
   expected := if a0 == 17 { voidptr(C.vinix_init_child_signal) } else { voidptr(C.vinix_init_power_signal) }
   C.assert(usize(voidptr(action.handler)) == usize(expected)); return 0
  }
  if nr == 81 { C.assert(a0 == 0); return 0 }
  if nr == 142 { C.assert(a0 == 0xfee1dead && a1 == 0x28121969 && a3 == 0); return -1 }
  if nr == 115 {
   C.assert(a0 == 1 && a1 == 0 && a2 == a3); mut d := &C.delay(usize(a2)); sleeps++
   if mode == sleep && sleeps < 3 { d.seconds = 0; d.nanoseconds = 1000 / i64(sleeps); if stop_sleep { C.vinit_reload = 1 }; return -4 }
   if mode == sleep { C.assert(d.seconds == 0 && d.nanoseconds == 500) }
   else { C.assert(d.seconds == 0 && d.nanoseconds == 10000000) }; return 0
  }
  if nr == 220 { C.assert(a0 == 17 && a1 == 0 && a2 == 0 && a3 == 0 && a4 == 0); return cloned }
  if nr == 154 { C.assert((a0 == 0 && a1 == 0) || (a0 == 77 && a1 == 77)); return 0 }
  if nr == 221 {
   text_copy(&r.path[0], a0); arguments := &&char(usize(a1)); environment := &&char(usize(a2))
   C.assert(C.strcmp(arguments[0], &r.path[0]) == 0)
   C.assert(environment != nil && C.strcmp(environment[0], c'PATH=/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin') == 0)
   if mode == full {
    C.assert(C.strcmp(&r.path[0], c'/bin/busybox') == 0)
    C.assert(C.strcmp(arguments[1], if full_echo { c'echo' } else { c'sh' }) == 0)
    C.assert(C.strcmp(arguments[2], if full_echo { c'VINIX BUSYBOX EXEC TEST: PASS' } else { c'/etc/vinix-boot-test.sh' }) == 0 && arguments[3] == nil)
    C.assert(C.strcmp(environment[1], c'HOME=/root') == 0 && C.strcmp(environment[2], c'TERM=linux') == 0 && C.strcmp(environment[3], c'PS1=vinix# ') == 0)
    C.assert(C.strcmp(environment[4], c'LD_LIBRARY_PATH=/usr/lib:/usr/lib/xorg/modules') == 0)
    C.assert(C.strcmp(environment[5], c'LIBGL_DRIVERS_PATH=/usr/lib/xorg/modules/dri:/usr/lib/dri') == 0 && environment[6] == nil)
   } else { C.assert(mode == spawn_mode && arguments[1] == nil && environment[1] == nil) }; return -2
  }
  if nr == 260 {
   C.assert(a0 == u64(i64(-1)) && a3 == 0); waits++
   if a2 == 1 { return 0 }
   C.assert(a2 == 0 && (mode == wait || mode == reload || mode == spawn_mode))
   mut status := &i32(usize(a1))
   if mode == spawn_mode { *status = (i32(4) << 8); return 77 }
   if waits == 1 { *status = 0; return 101 }
   if waits == 2 { if mode == wait { C.vinit_power = 12 }; return -4 }
   C.assert(waits == 3); *status = 11; return 77
  }
  if nr == 129 {
   if mode == group && a1 == 0 { probes++; return if probes > 100 { i64(-3) } else { i64(0) } }
   C.assert((mode == group && i64(a0) == -77) || (a0 == 77 && (mode == wait || mode == reload))); return 0
  }
  C.assert(false); return -1
 }
}

fn count(nr u64) usize {
 unsafe { mut n := usize(0); for i := usize(0); i < used; i++ { if calls[i].nr == nr { n++ } }; return n }
}
fn number(nr u64, at usize) &Record {
 unsafe {
  mut remaining := at
  for i := usize(0); i < used; i++ { if calls[i].nr == nr { if remaining == 0 { return &calls[i] }; remaining-- } }
  C.assert(false); return nil
 }
}
fn shell_test() {
 unsafe {
  reset(shell); lines = &&char(&shell_input[0]); if C.setjmp(finished) == 0 { C.vinix_init_shell() }
  C.assert(exit_status == 0 && read_at == 9)
  C.assert(C.strstr(&output[0], c' | | | | | \'_ \\| \\ \\/ /\n') != nil)
  C.assert(C.strstr(&output[0], c'Type \'help\' for available commands.\n\nvinix# vinix# Available commands:\n') != nil)
  C.assert(C.strstr(&output[0], c'  exit   - exit shell\nvinix# Hello from userland!\nvinix# Vinix 0.1.0 aarch64\nvinix# hello world\nvinix# \nvinix# unknown command: echoes\nvinix# unknown command: missing\nvinix# Goodbye!\n') != nil)
  reset(shell); lines = &&char(&shell_eof[0]); if C.setjmp(finished) == 0 { C.vinix_init_shell() }
  C.assert(exit_status == 1 && C.strstr(&output[0], c'read error or EOF, exiting\n') != nil)
 }
}
fn full_test() {
 unsafe {
  reset(full); if C.setjmp(finished) == 0 { C.vinix_init_full() }
  C.assert(exit_status == 1 && count(221) == 1)
  C.assert(C.strcmp(&output[0], c'\nVinix ARM64 test userland: starting boot tests\ninit: execve /bin/sh failed\n') == 0)
 }
}
fn boot_test() {
 unsafe {
  reset(basic); C.initcore__prepare_desktop_boot()
  C.assert(used == 20 && count(35) == 10 && count(36) == 3 && count(38) == 4 && count(37) == 1)
  C.assert(C.strcmp(&calls[0].path[0], c'/run/vinix-desktop-development') == 0 && C.strcmp(&calls[2].path[0], c'/run/vinix-latest-release') == 0)
  C.assert(C.strcmp(&number(36, 0).path[0], c'vinix-desktop') == 0 && C.strcmp(&number(36, 2).other[0], c'/usr/bin/.vinix-settings.system') == 0)
  C.assert(C.strcmp(&number(38, 3).other[0], c'/usr/bin/vinix-desktop') == 0)
  reset(basic); symlink_failure = 1; link_failure = 1; C.initcore__prepare_desktop_boot()
  C.assert(count(38) == 2 && count(37) == 1 && count(35) == 11 && C.strstr(&output[0], c'could not restore the packaged desktop') != nil)
  reset(basic); C.initcore__prepare_hosted_x11_storage()
  C.assert(used == 4 && calls[0].nr == 34 && calls[1].nr == 40 && calls[2].nr == 56 && calls[3].nr == 57)
  reset(basic); mount_failure = 1; C.initcore__prepare_hosted_x11_storage()
  C.assert(count(56) == 0 && C.strstr(&output[0], c'scratch mount unavailable; using /tmp') != nil)
 }
}
fn signal_test() {
 unsafe {
  reset(basic); C.initcore__install_power_signals(); C.assert(used == 5)
  for i := usize(0); i < 5; i++ { C.assert(calls[i].nr == 134 && calls[i].a[0] == signals[i]) }
  C.vinix_init_power_signal(1); C.assert(C.vinit_reload == 1 && C.vinit_power == 0)
  C.vinix_init_power_signal(15); C.assert(C.vinit_reload == 1 && C.vinit_power == 15)
  C.vinix_init_child_signal(17); C.assert(C.vinit_reload == 1 && C.vinit_power == 15)
  for i := usize(0); i < 3; i++ {
   reset(basic); C.vinix_init_power_signal(i32(power[i])); C.initcore__apply_power_request()
   C.assert(calls[0].nr == 81 && calls[1].nr == 142 && calls[1].a[2] == commands[i] && C.vinit_power == 0)
  }
  reset(wait); C.vinit_power = 15; mut status := i32(-1); C.initcore__wait_for_child(77, &status)
  C.assert(status == 11 && waits == 3 && count(129) == 2 && number(129, 0).a[1] == 15 && number(129, 1).a[1] == 12)
  reset(reload); C.vinit_reload = 1; C.initcore__wait_for_child(77, &status)
  C.assert(status == 11 && waits == 3 && count(129) == 1 && number(129, 0).a[1] == 1)
  reset(sleep); C.initcore__pause_for(C.delay{seconds: 1}); C.assert(sleeps == 3)
  reset(sleep); stop_sleep = true; C.initcore__pause_for(C.delay{seconds: 1}); C.assert(sleeps == 1 && C.vinit_reload == 1)
 }
}
fn process_test() {
 unsafe {
  mut arguments := [&char(c'/usr/bin/vinix-desktop-gpu'), &char(nil)]!
  mut fallback := [&char(c'/usr/bin/vinix-desktop'), &char(nil)]!
  mut environment := [&char(c'PATH=/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin'), &char(nil)]!
  mut status := i32(0)
  reset(spawn_mode); C.assert(C.initcore__spawn_program(&arguments[0], &fallback[0], true, &status, &environment[0], true) == 77)
  C.assert(status == (i32(4) << 8) && count(154) == 1 && count(260) == 1 && output_used == 0)
  reset(spawn_mode); cloned = 0
  if C.setjmp(finished) == 0 { C.initcore__spawn_program(&arguments[0], &fallback[0], true, &status, &environment[0], true) }
  C.assert(exit_status == 127 && count(221) == 2 && count(154) == 1)
  C.assert(C.strcmp(&number(221, 0).path[0], arguments[0]) == 0 && C.strcmp(&number(221, 1).path[0], fallback[0]) == 0)
  C.assert(C.strcmp(&output[0], c'init: GPU desktop child process group ready; entering execve\ninit: GPU desktop execve returned; trying software fallback\ninit: GPU and software desktop execve both failed\n') == 0)
  reset(spawn_mode); cloned = -12
  C.assert(C.initcore__spawn_program(&arguments[0], nil, false, &status, &environment[0], false) == -12 && used == 1)
  reset(group); C.initcore__stop_desktop_group(77)
  C.assert(probes == 101 && sleeps == 100 && count(260) == 102 && count(129) == 103)
  C.assert(number(129, 0).a[1] == 15 && number(129, 101).a[1] == 9 && output_used == 0)
 }
}

@[export: 'main']
pub fn entry(argc i32, argv &&char) i32 {
 unsafe { full_echo = argc > 1 && C.strcmp(argv[1], c'echo') == 0 }
 shell_test(); full_test(); boot_test(); signal_test(); process_test()
 C.puts(c'INIT POLICY TEST: PASS'); return 0
}
