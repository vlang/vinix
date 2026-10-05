// SPDX-License-Identifier: GPL-2.0-only
// Freestanding ARM init policies. Syscalls own no retained V allocations;
// argument/status/signal/time records are fixed globals or stack storage.
@[translated]
module initcore
#include "syscall_abi.h"
fn C.vinit_syscall(u64, u64, u64, u64, u64, u64) i64
fn C.vinit_power_callback() voidptr
fn C.vinit_child_callback() voidptr
fn C.vinit_restorer() voidptr
fn C.vinit_wifi_enabled() i32
fn C.vinit_echo_enabled() i32
@[export: 'vinit_power']
__global volatile requested_power i32
@[export: 'vinit_reload']
__global volatile requested_reload i32
__global vinit_environment [15]&char
struct SignalAction { mut: handler voidptr flags u64 restorer voidptr mask u64 }
struct Delay { mut: seconds i64 nanoseconds i64 }
struct LiveApp { path &char temporary &char version &char }
fn call(nr u64, a0 u64, a1 u64, a2 u64, a3 u64, a4 u64) i64 { return C.vinit_syscall(nr,a0,a1,a2,a3,a4) }
fn length(text &char) u64 { unsafe { mut n := u64(0); for text[n] != 0 { n++ }; return n } }
fn init_print(text &char) { unsafe { call(64,1,u64(text),length(text),0,0) } }
fn print_number(value u64) {
 unsafe { mut digits := [24]char{}; mut index := u64(24); mut number := value; for { index--; digits[index] = char(`0` + number % 10); number /= 10; if number == 0 { break } }; call(64,1,u64(&digits[index]),24-index,0,0) }
}
fn compare(a &char, b &char) i32 {
 unsafe { mut at := u64(0); for a[at] != 0 && a[at] == b[at] { at++ }; return i32(u8(a[at])) - i32(u8(b[at])) }
}
@[export: 'memcpy']
pub fn copy(destination voidptr, source voidptr, size usize) voidptr {
 unsafe { out := &u8(destination); input := &u8(source); for i := usize(0); i < size; i++ { out[i] = input[i] }; return destination }
}
@[export: 'memset']
pub fn zero(destination voidptr, byte i32, size usize) voidptr {
 unsafe { out := &u8(destination); for i := usize(0); i < size; i++ { out[i] = u8(byte) }; return destination }
}
@[export: 'memmove']
pub fn move(destination voidptr, source voidptr, size usize) voidptr {
 unsafe { out := &u8(destination); input := &u8(source); if usize(destination) < usize(source) { for i := usize(0); i < size; i++ { out[i] = input[i] } } else { for i := size; i > 0; { i--; out[i] = input[i] } }; return destination }
}
fn signal_name(signal i32) &char {
 return match signal { 1 { c'SIGHUP' } 2 { c'SIGINT' } 3 { c'SIGQUIT' } 4 { c'SIGILL' } 5 { c'SIGTRAP' } 6 { c'SIGABRT' } 7 { c'SIGBUS' } 8 { c'SIGFPE' } 9 { c'SIGKILL' } 10 { c'SIGUSR1' } 11 { c'SIGSEGV' } 12 { c'SIGUSR2' } 13 { c'SIGPIPE' } 14 { c'SIGALRM' } 15 { c'SIGTERM' } 24 { c'SIGXCPU' } 25 { c'SIGXFSZ' } 31 { c'SIGSYS' } else { c'unknown signal' } }
}
fn report_desktop_exit(child i64, status i32) {
 signal := status & 0x7f
 init_print(c'init: vinix-desktop (pid '); print_number(u64(child))
 if signal != 0 && signal != 0x7f { init_print(c') crashed with '); init_print(signal_name(signal)); init_print(c' (signal '); print_number(u64(signal)); init_print(c')') }
 else { code := (status >> 8) & 0xff; if code == 0 { init_print(c') exited cleanly') } else { init_print(c') exited with status '); print_number(u64(code)) } }
 init_print(c'; restarting in one second\n')
}
@[export: 'vinix_init_power_signal']
pub fn power_signal(signal i32) { unsafe { if signal == 1 { requested_reload = 1 } else { requested_power = signal } } }
@[export: 'vinix_init_child_signal']
pub fn child_signal(signal i32) { _ = signal }
fn install_power_signals() {
 unsafe { action := SignalAction{handler:C.vinit_power_callback(),restorer:C.vinit_restorer()}; for signal in [u64(1),u64(15),u64(10),u64(12)]! { call(134,signal,u64(&action),0,8,0) }; child := SignalAction{handler:C.vinit_child_callback(),restorer:C.vinit_restorer()}; call(134,17,u64(&child),0,8,0) }
}
fn apply_power_request() {
 unsafe { signal := requested_power; if signal == 0 { return }; command := if signal == 15 { u64(0x01234567) } else if signal == 10 { u64(0xcdef0123) } else { u64(0x4321fedc) }; call(81,0,0,0,0,0); call(142,0xfee1dead,0x28121969,command,0,0); init_print(c'init: the kernel refused the power request\n'); requested_power = 0 }
}
fn pause_for(original Delay) {
 unsafe { mut delay := original; for call(115,1,0,u64(&delay),u64(&delay),0) == -4 && requested_power == 0 && requested_reload == 0 { continue } }
}
fn wait_for_child(child i64, status &i32) {
 unsafe { mut forwarded := i32(0); for { mut signal := requested_power; if signal == 0 && requested_reload != 0 { signal = 1 }; if signal != 0 && signal != forwarded { call(129,u64(child),u64(signal),0,0,0); forwarded = signal }; mut any_status := i32(0); if call(260,u64(i64(-1)),u64(&any_status),0,0,0) == child { *status = any_status; return } } }
}
fn spawn_program(arguments &&char, fallback &&char, own_group bool, status &i32, environment &&char, trace bool) i64 {
 unsafe {
  child := call(220,17,0,0,0,0)
  if child == 0 {
   if own_group { call(154,0,0,0,0,0) }
   if trace { init_print(c'init: GPU desktop child process group ready; entering execve\n') }
   call(221,u64(arguments[0]),u64(arguments),u64(environment),0,0)
   if trace { init_print(c'init: GPU desktop execve returned; trying software fallback\n') }
   if usize(fallback) != 0 { call(221,u64(fallback[0]),u64(fallback),u64(environment),0,0) }
   if trace { init_print(c'init: GPU and software desktop execve both failed\n') }
   call(93,127,0,0,0,0)
  }
  if child > 0 { if own_group { call(154,u64(child),u64(child),0,0,0) }; wait_for_child(child,status) }
  return child
 }
}
fn executable_available(path &char) bool {
 unsafe { fd := call(56,u64(i64(-100)),u64(path),0,0,0); if fd < 0 { return false }; call(57,u64(fd),0,0,0,0); return true }
}
fn gpu_available() bool {
 unsafe { fd := call(56,u64(i64(-100)),u64(c'/dev/dri/renderD128'),2,0,0); if fd < 0 { return false }; call(57,u64(fd),0,0,0,0); return true }
}
fn start_helper(path &char, audit bool) {
 unsafe {
  arguments := [&char(path), &char(nil)]!
  if !executable_available(arguments[0]) { return }
  child := call(220,17,0,0,0,0)
  if child == 0 { call(154,0,0,0,0,0); call(221,u64(arguments[0]),u64(&arguments[0]),u64(&vinit_environment[0]),0,0); if audit { init_print(c'init: security audit supervisor could not start\n') }; call(93,127,0,0,0,0) }
  else if child < 0 && audit { init_print(c'init: security audit supervisor could not fork\n') }
 }
}
fn reap_exited_children() { unsafe { mut status := i32(0); for call(260,u64(i64(-1)),u64(&status),1,0,0) > 0 { continue } } }
fn wait_for_desktop_group(child i64, attempts i32) bool {
 mut left := attempts
 for left > 0 { left--; reap_exited_children(); if call(129,u64(-child),0,0,0,0) < 0 { return true }; pause_for(Delay{nanoseconds:10000000}) }
 return false
}
fn stop_desktop_group(child i64) {
 if child <= 0 { reap_exited_children(); return }
 call(129,u64(-child),15,0,0,0)
 if wait_for_desktop_group(child,100) { return }
 call(129,u64(-child),9,0,0,0)
 if !wait_for_desktop_group(child,500) { init_print(c'init: old desktop process group did not stop within five seconds\n') }
 reap_exited_children()
}
fn prepare_desktop_boot() {
 unsafe {
  at := u64(i64(-100))
  call(35,at,u64(c'/run/vinix-desktop-development'),0,0,0)
  call(35,at,u64(c'/run/vinix-desktop-ready'),0,0,0)
  call(35,at,u64(c'/run/vinix-latest-release'),0,0,0)
  live := [LiveApp{path:c'/usr/bin/vinix-files',temporary:c'/usr/bin/.vinix-files.system',version:c'/run/vinix-files-version'}, LiveApp{path:c'/usr/bin/vinix-activity',temporary:c'/usr/bin/.vinix-activity.system',version:c'/run/vinix-activity-version'}, LiveApp{path:c'/usr/bin/vinix-settings',temporary:c'/usr/bin/.vinix-settings.system',version:c'/run/vinix-settings-version'}]!
  for i := 0; i < 3; i++ { call(35,at,u64(live[i].version),0,0,0); call(35,at,u64(live[i].temporary),0,0,0); if call(36,u64(c'vinix-desktop'),at,u64(live[i].temporary),0,0) < 0 { continue }; if call(38,at,u64(live[i].temporary),at,u64(live[i].path),0) < 0 { call(35,at,u64(live[i].temporary),0,0,0) } }
  if !executable_available(c'/usr/libexec/vinix-desktop-system') { return }
  call(35,at,u64(c'/usr/bin/.vinix-desktop.system'),0,0,0)
  if call(37,at,u64(c'/usr/libexec/vinix-desktop-system'),at,u64(c'/usr/bin/.vinix-desktop.system'),0) < 0 || call(38,at,u64(c'/usr/bin/.vinix-desktop.system'),at,u64(c'/usr/bin/vinix-desktop'),0) < 0 { call(35,at,u64(c'/usr/bin/.vinix-desktop.system'),0,0,0); init_print(c'init: could not restore the packaged desktop; keeping the existing binary\n') }
 }
}
fn prepare_hosted_x11_storage() {
 unsafe { at := u64(i64(-100)); call(34,at,u64(c'/run/vinix-hosted-x11'),0o700,0,0); if call(40,u64(c'/dev/null'),u64(c'/run/vinix-hosted-x11'),u64(c'tmpfs'),0,0) < 0 { init_print(c'init: hosted X11 scratch mount unavailable; using /tmp\n'); return }; fd := call(56,at,u64(c'/run/vinix-hosted-x11/.tmpfs-ready'),0x41,0o600,0); if fd >= 0 { call(57,u64(fd),0,0,0,0) } }
}
fn prepare_environment() {
 unsafe { vinit_environment[0] = c'PATH=/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin'; vinit_environment[1] = c'HOME=/root'; vinit_environment[2] = c'TERM=linux'; vinit_environment[3] = c'PS1=vinix# '; vinit_environment[4] = c'USER=root'; vinit_environment[5] = c'LOGNAME=root'; vinit_environment[6] = c'SHELL=/bin/zsh'; vinit_environment[7] = c'LD_LIBRARY_PATH=/usr/lib:/usr/lib/xorg/modules'; vinit_environment[8] = c'LIBGL_DRIVERS_PATH=/usr/lib/xorg/modules/dri:/usr/lib/dri'; vinit_environment[9] = c'XDG_RUNTIME_DIR=/run/user/0'; vinit_environment[10] = c'XDG_CONFIG_HOME=/root/.config'; vinit_environment[11] = c'XDG_CACHE_HOME=/root/.cache'; vinit_environment[12] = c'SSL_CA_CERT_FILE=/etc/ssl/certs/ca-certificates.crt'; vinit_environment[13] = c'VINIX_SYSTEM_SESSION=1'; vinit_environment[14] = nil }
}
@[export: 'vinix_init_desktop']
pub fn desktop_start() {
 unsafe {
  desktop := [&char(c'/usr/bin/vinix-desktop'),&char(nil)]!
  gpu := [&char(c'/usr/bin/vinix-desktop-gpu'),&char(nil)]!
  hyprland := [&char(c'/usr/bin/start-hyprland-vinix'),&char(nil)]!
  shell := [&char(c'/bin/zsh'),&char(c'-l'),&char(nil)]!
  mut status := i32(0)
  prepare_environment(); prepare_desktop_boot(); prepare_hosted_x11_storage(); install_power_signals()
  start_helper(c'/usr/libexec/vinix-security-audit-supervise',true)
  start_helper(c'/usr/bin/vinix-files-sync',false)
  start_helper(c'/usr/libexec/vinix-version-check',false)
  if C.vinit_wifi_enabled() != 0 {
   wifi := [&char(c'/usr/bin/wifi-ctl'),&char(c'load'),&char(c'/usr/share/vinix/wifi'),&char(nil)]!
   init_print(c'\nVinix: loading the selected Wi-Fi firmware\n')
   child := spawn_program(&wifi[0],&&char(nil),false,&status,&vinit_environment[0],false)
   if requested_power != 0 { apply_power_request() }
   if child < 0 || status != 0 { init_print(c'init: Wi-Fi firmware load failed; continuing without wireless\n') }
  }
  if executable_available(c'/etc/vinix/boot-hyprland') && executable_available(hyprland[0]) {
   init_print(c'\nVinix: starting Hyprland\n'); spawn_program(&hyprland[0],&&char(nil),true,&status,&vinit_environment[0],false)
   if requested_power != 0 { apply_power_request() }; init_print(c'init: Hyprland exited; starting the native recovery desktop\n')
  }
  for {
   mut selected := &desktop[0]; mut fallback := &&char(nil)
   if requested_power != 0 { apply_power_request() }
   if gpu_available() && !executable_available(c'/run/vinix-desktop-development') { selected = &gpu[0]; fallback = &desktop[0]; init_print(c'\nVinix: starting the GPU-enabled desktop\n') }
   else { init_print(c'\nVinix: starting the desktop\n') }
   status = 0
   mut child := spawn_program(selected,fallback,true,&status,&vinit_environment[0],voidptr(selected) == voidptr(&gpu[0]))
   if requested_power != 0 { apply_power_request() }
   if requested_reload != 0 { requested_reload = 0; init_print(c'init: desktop reload requested; starting the new binary\n'); stop_desktop_group(child); requested_reload = 0; continue }
   if child < 0 || status == 127 << 8 {
    init_print(c'init: could not start vinix-desktop; opening a recovery shell\n'); status = 0
    child = spawn_program(&shell[0],&&char(nil),false,&status,&vinit_environment[0],false)
    if requested_power != 0 { apply_power_request() }; if child < 0 { init_print(c'init: no recovery shell either; retrying the desktop\n') }; continue
   }
   report_desktop_exit(child,status); stop_desktop_group(child); pause_for(Delay{seconds:1})
  }
 }
}
@[export: 'vinix_init_full']
pub fn full_start() {
 unsafe {
  normal := [&char(c'/bin/busybox'),&char(c'sh'),&char(c'/etc/vinix-boot-test.sh'),&char(nil)]!
  echo := [&char(c'/bin/busybox'),&char(c'echo'),&char(c'VINIX BUSYBOX EXEC TEST: PASS'),&char(nil)]!
  environment := [&char(c'PATH=/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin'),&char(c'HOME=/root'),&char(c'TERM=linux'),&char(c'PS1=vinix# '),&char(c'LD_LIBRARY_PATH=/usr/lib:/usr/lib/xorg/modules'),&char(c'LIBGL_DRIVERS_PATH=/usr/lib/xorg/modules/dri:/usr/lib/dri'),&char(nil)]!
  arguments := if C.vinit_echo_enabled() != 0 { &echo[0] } else { &normal[0] }
  init_print(c'\nVinix ARM64 test userland: starting boot tests\n')
  call(221,u64(arguments[0]),u64(arguments),u64(&environment[0]),0,0)
  init_print(c'init: execve /bin/sh failed\n'); call(93,1,0,0,0,0)
  for { continue }
 }
}
fn is_empty(text &char) bool {
 unsafe { mut at := u64(0); for text[at] == ` ` || text[at] == `\t` { at++ }; return text[at] == 0 }
}
fn shell_help() {
 init_print(c'Available commands:\n'); init_print(c'  help   - show this message\n'); init_print(c'  hello  - print greeting\n'); init_print(c'  uname  - show system info\n'); init_print(c'  echo   - echo arguments\n'); init_print(c'  exit   - exit shell\n')
}
fn shell_echo(line &char) { unsafe { mut p := line + 4; for *p == ` ` { p++ }; if *p != 0 { init_print(p) }; init_print(c'\n') } }
fn exit_shell(status i32) { call(93,u64(status),0,0,0,0); for { continue } }
@[export: 'vinix_init_shell']
pub fn shell_start() {
 unsafe {
  init_print(c'\n'); init_print(c'  _   _ _       _\n'); init_print(c' | | | (_)_ __ (_)_  __\n'); init_print(c' | | | | | \'_ \\| \\ \\/ /\n'); init_print(c' | |_| | | | | | |>  <\n'); init_print(c'  \\___/|_|_| |_|_/_/\\_\\\n'); init_print(c'\n'); init_print(c'Welcome to Vinix (aarch64)\n'); init_print(c'Type \'help\' for available commands.\n\n')
  mut buffer := [256]char{}
  for {
   init_print(c'vinix# ')
   n := call(63,0,u64(&buffer[0]),255,0,0)
   if n <= 0 { init_print(c'\nread error or EOF, exiting\n'); exit_shell(1) }
   buffer[n] = 0
   if n > 0 && buffer[n-1] == `\n` { buffer[n-1] = 0 }
   if n > 1 && buffer[n-2] == `\r` { buffer[n-2] = 0 }
   if is_empty(&buffer[0]) { continue }
   if compare(&buffer[0],c'help') == 0 { shell_help() }
   else if compare(&buffer[0],c'hello') == 0 { init_print(c'Hello from userland!\n') }
   else if compare(&buffer[0],c'uname') == 0 { init_print(c'Vinix 0.1.0 aarch64\n') }
   else if buffer[0] == `e` && buffer[1] == `c` && buffer[2] == `h` && buffer[3] == `o` && (buffer[4] == ` ` || buffer[4] == 0) { shell_echo(&buffer[0]) }
   else if compare(&buffer[0],c'exit') == 0 { init_print(c'Goodbye!\n'); exit_shell(0) }
   else { init_print(c'unknown command: '); init_print(&buffer[0]); init_print(c'\n') }
  }
 }
}
@[export: '_start']
pub fn entry() {
 $if init_desktop ? { desktop_start() }
 $else $if init_full ? { full_start() }
 $else { shell_start() }
}
