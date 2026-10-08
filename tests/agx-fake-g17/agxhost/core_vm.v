// SPDX-License-Identifier: GPL-2.0-or-later
module agxhost

import os
import json2
import encoding.hex
import math

fn C.execvp(&char, &&char) i32

const core_pass_marker = 'VINIX QEMU CORE: PASS'
const core_persist_marker = 'VINIX QEMU CORE PERSIST: PASS'
const core_fail_markers = [
	'VINIX QEMU CORE: FAIL'
	'QEMU CORE FAIL line'
	'FATAL EXCEPTION'
	'KERNEL PANIC'
]
const core_feature_markers = [
	'QEMU CORE PASS: secure getrandom'
	'QEMU CORE PASS: sparse tmpfs shared mappings allocate on touch'
	'QEMU CORE PASS: copy-on-write fork'
	'QEMU CORE PASS: anonymous first touch, zero pages, fork and explicit population'
	'QEMU CORE PASS: syscalls page in untouched buffers'
	'QEMU CORE PASS: partial unmap reclaims pages and retains forked shares'
	'QEMU CORE PASS: a range split while a sharer unmaps it keeps its pages'
	'QEMU CORE PASS: madvise returns anonymous pages to the allocator'
	'QEMU CORE PASS: exit and exec reclaim process mappings'
	'QEMU CORE PASS: forked copy-on-write pages are reclaimed'
	'QEMU CORE PASS: default signal dispositions'
	'QEMU CORE PASS: signals reach a thread that makes no syscalls'
	'QEMU CORE PASS: SA_RESTART restarts an interrupted read'
	'QEMU CORE PASS: exit and exec take down threads blocked in the kernel'
	'QEMU CORE PASS: interrupted nanosleep returns a relative remainder'
	'QEMU CORE PASS: anonymous IPC buffers are reclaimed'
	'QEMU CORE PASS: socket interface boxes are reclaimed'
	'QEMU CORE PASS: full UNIX stream clears write readiness'
	'QEMU CORE PASS: futex wake-op updates and compares user words'
	'QEMU CORE PASS: alarm and ITIMER_REAL fire on time'
	'QEMU CORE PASS: mprotect and munmap refuse an address inside a page'
	'QEMU CORE PASS: more waiters than an event holds'
	'QEMU CORE PASS: fork keeps the program, auxv and directory'
	'QEMU CORE PASS: /proc/cpuinfo describes the machine'
	'QEMU CORE PASS: joined threads return their memory'
	'QEMU CORE PASS: the console controls a session'
	'QEMU CORE PASS: page table changes reach every CPU'
	'QEMU CORE PASS: a FIFO thread keeps its CPU'
	'QEMU CORE PASS: a frozen cgroup stops its threads'
	'QEMU CORE PASS: a wait ends for a signal already pending'
	'QEMU CORE PASS: ext2 cache, mmap, sync, namespace, timestamps'
	'QEMU CORE PASS: a shared mapping is visible to every reader'
	'QEMU CORE PASS: a released pid stays out of use while its group lives'
	'QEMU CORE PASS: fcntl and flock exclusion'
	'QEMU CORE PASS: permissions, umask, and resource limits'
	'QEMU CORE PASS: inotify events'
	'QEMU CORE PASS: priority, affinity, and accounting'
	'QEMU CORE PASS: concurrent wakeups enqueue one thread once'
	'QEMU CORE PASS: POSIX SIGEV_THREAD timer notification'
	'QEMU CORE PASS: anonymous descriptors are open both ways'
	'QEMU CORE PASS: Linux pollfd ABI'
	'QEMU CORE PASS: large blocking pipe transfer makes progress'
	'QEMU CORE PASS: empty pipes defer buffers and reclaim first-write storage'
	'QEMU CORE PASS: Linux epoll ABI and event count'
	'QEMU CORE PASS: syscall C-int truncation'
	'QEMU CORE PASS: abstract socket names are released'
	'QEMU CORE PASS: persistence markers synchronized'
]
const core_amd64_feature_markers = [
	'QEMU CORE PASS: x86-64 utime, utimes, futimesat and getdents'
	'QEMU CORE PASS: x86-64 TLS descriptors, LDT and 32-bit code'
]

struct CoreState {
mut:
 transcript []u8
 has_status bool
 status int
 shutdown_deadline f64
 has_shutdown_deadline bool
 finished_at f64
 has_finished_at bool
}

fn core_timeout(text string, kind string) !f64 {
 if kind != 'number' { return NativeFailure{'TypeError', "unsupported operand type(s) for +: 'float' and '" + kind + "'"} }
 value := unsafe { C.strtod(text.str, nil) }
 if math.is_inf(value, 0) && text !in ['inf', '-inf', 'Infinity', '-Infinity'] { return NativeFailure{'OverflowError', 'int too large to convert to float'} }
 return value
}

fn core_spawn(command []string, environment map[string]string, root string, python string, binding string, architecture string, search bool) !(i32, i32) {
 encoded := json2.encode(json2.Any(command.map(json2.Any(it))))
 mut argv := [python, binding, if search { '--vinix-pty-child-path' } else { '--vinix-pty-child' }, hex.encode(root.bytes()), encoded]
 $if darwin {
  if architecture in ['arm64', 'aarch64', 'x86_64', 'amd64'] { argv = ['/usr/bin/arch', if architecture in ['arm64', 'aarch64'] { '-arm64' } else { '-x86_64' }, ...argv] }
 }
 mut argument_pointers := []&char{}
 for item in argv { argument_pointers << &char(item.str) }
 argument_pointers << &char(unsafe { nil })
 mut entries := []string{}
 for key, value in environment { entries << key + '=' + value }
 mut envp := []&char{}
 for item in entries { envp << &char(item.str) }
 envp << &char(unsafe { nil })
 mut master := i32(-1)
 pid := C.forkpty(&master, unsafe { nil }, unsafe { nil }, unsafe { nil })
 if pid < 0 { return vm_os_error() }
 if pid == 0 {
  if search { unsafe { C.execvp(argv[0].str, argument_pointers.data) } } else { unsafe { C.execve(argv[0].str, argument_pointers.data, envp.data) } }
  C._exit(127)
 }
 return pid, master
}

fn (mut out Transcript) core_drive(pid i32, master i32, timeout_text string, timeout_kind string, verification bool, amd64 bool, mut state CoreState) ! {
 deadline := vm_now() + core_timeout(timeout_text, timeout_kind)!
 mut buffer := []u8{len: 65536}
 for vm_now() < deadline {
  vm_interrupt_check()!
  waited, status := vm_wait(pid, C.WNOHANG)!
  if waited { state.has_status = true; state.status = status; break }
  if vm_socket_ready(master, false, vm_now() + 0.25)! {
   count := C.read(master, buffer.data, usize(buffer.len))
   if count < 0 { if C.errno in [C.EIO, C.EINTR] { continue }; return vm_os_error() }
   if count > 0 {
    state.transcript << buffer[..count]
    out.vm_bytes(buffer[..count])!
   }
  }
  recent := state.transcript[if state.transcript.len > 131072 { state.transcript.len - 131072 } else { 0 }..].bytestr()
  expected := if verification { core_persist_marker } else { core_pass_marker }
  finished := recent.contains(expected) || core_fail_markers.any(recent.contains(it))
  if amd64 {
   if !state.has_finished_at && finished { state.has_finished_at = true; state.finished_at = vm_now() }
   if state.has_finished_at && vm_now() - state.finished_at > 2 { break }
  } else {
   if finished && !state.has_shutdown_deadline {
    if C.write(master, c'\x01x', 2) < 0 && C.errno != C.EIO { return vm_os_error() }
    state.shutdown_deadline = vm_now() + 10
    state.has_shutdown_deadline = true
   }
   if state.has_shutdown_deadline && vm_now() >= state.shutdown_deadline { break }
  }
 }
}

pub fn core_results(output string, verification bool, amd64 bool, has_status bool, status int, forced bool, finished bool) ([]string, []string) {
 expected := if verification { [core_persist_marker] } else if amd64 { [...core_feature_markers, ...core_amd64_feature_markers, core_pass_marker] } else { [...core_feature_markers, core_pass_marker] }
 mut missing := []string{}
 for marker in expected { if output.count(marker) != 1 { missing << marker } }
 mut failures := []string{}
 for marker in core_fail_markers { if output.contains(marker) { failures << marker } }
 if amd64 { if !finished { failures << 'the test did not finish before the timeout' } } else {
  if has_status && vm_child_exit_code(status) != 0 { failures << 'VM runner exit status ' + vm_child_exit_code(status).str() }
  if forced { failures << 'VM did not exit after the test' }
 }
 return missing, failures
}

fn (mut out Transcript) core_text(text string) {
 if out.inherit && !out.python_stdout_buffered { out.streams(text, '') } else { out.stdout += text }
}

fn (mut out Transcript) core_finish(state CoreState, verification bool, amd64 bool, forced bool, phase string) int {
 missing, failures := core_results(state.transcript.bytestr(), verification, amd64, state.has_status, state.status, forced, state.has_finished_at)
 for item in missing { out.streams('', 'ERROR: missing expected QEMU result: ' + item + '\n') }
 for item in failures { out.streams('', 'ERROR: observed QEMU failure: ' + item + '\n') }
 if missing.len > 0 || failures.len > 0 { return 1 }
 out.core_text(if amd64 { '==> amd64 QEMU core regression passed\n' } else { '==> AArch64 QEMU ' + phase + ' boot passed\n' })
 return 0
}

pub fn (mut out Transcript) core_phase(root string, guest_init string, initramfs string, state_dir string, timeout_text string, timeout_kind string, verification bool, python string, binding string, system string) !int {
 mut environment := os.environ()
 environment['VINIX_INITRAMFS'] = initramfs
 environment['VINIX_BOOT_DISK'] = state_dir + '/boot.img'
 environment['VINIX_EFIVARS'] = state_dir + '/efivars.fd'
 environment['VINIX_QEMU_PACKAGE_STORE'] = state_dir + '/packages.tar'
 environment['VINIX_QEMU_PERSIST_DISK'] = state_dir + '/root.ext2'
 environment['VINIX_QEMU_PERSIST_SIZE_MB'] = '64'
 environment.delete('VINIX_QEMU_PERSIST')
 environment['VINIX_KEEP_TEMP_BOOT_DISK'] = '1'
 port := vm_available_port()!
 if 'VINIX_QEMU_PACKAGE_STORE_PORT' !in environment { environment['VINIX_QEMU_PACKAGE_STORE_PORT'] = port }
 if system != 'Darwin' && 'USE_TCG' !in environment { environment['USE_TCG'] = '1' }
 mut command := [root + '/scripts/run-aarch64.sh', '--serial', '--mem=2048', '--guest-init=' + guest_init]
 if verification || (os.getenv_opt('VINIX_QEMU_CORE_NO_BUILD') or { '' }) == '1' { command.insert(1, '--no-build') }
 phase := if verification { 'persistence verification' } else { 'core feature' }
 out.core_text('==> Starting AArch64 QEMU ' + phase + ' boot\n')
 unsafe { C.__atomic_store_n(&i32(C.VINIX_AGX_VM_INTERRUPTED), i32(0), C.__ATOMIC_RELAXED) }
 previous := unsafe { C.signal(C.SIGINT, voidptr(vm_signal)) }
 defer { unsafe { C.signal(C.SIGINT, previous) } }
 previous_pipe := unsafe { C.signal(C.SIGPIPE, C.SIG_IGN) }
 defer { unsafe { C.signal(C.SIGPIPE, previous_pipe) } }
 pid, master := core_spawn(command, environment, root, python, binding, out.host_arch, false)!
 mut state := CoreState{}
 mut failed := false
 mut failure := IError(none)
 out.core_drive(pid, master, timeout_text, timeout_kind, verification, false, mut state) or { failed = true; failure = err }
 unsafe { C.__atomic_store_n(&i32(C.VINIX_AGX_VM_INTERRUPTED), i32(0), C.__ATOMIC_RELAXED); C.signal(C.SIGINT, C.SIG_IGN) }
 forced := !state.has_status
 if forced { vm_stop_child(pid, master, false) or { C.close(master); return err } }
 if C.close(master) < 0 { return vm_os_error() }
 if failed { return failure }
 return out.core_finish(state, verification, false, forced, phase)
}

pub fn (mut out Transcript) core_vm(root string, guest_init string, initramfs string, state_dir string, timeout_text string, timeout_kind string, python string, binding string, system string) !int {
 // pathlib.mkdir(parents=True, exist_ok=True) owns only the caller's state tree.
 native_mkdir(state_dir, true, true)!
 first := out.core_phase(root, guest_init, initramfs, state_dir, timeout_text, timeout_kind, false, python, binding, system)!
 if first != 0 { return first }
 second := out.core_phase(root, guest_init, initramfs, state_dir, timeout_text, timeout_kind, true, python, binding, system)!
 if second == 0 { out.core_text('==> AArch64 QEMU core regression passed across reboot\n') }
 return second
}

pub fn (mut out Transcript) core_amd64(iso string, qemu string, firmware string, timeout_text string, timeout_kind string, cpus_text string, python string, binding string) !int {
 command := [qemu, '-machine', 'q35,smm=off', '-accel', os.getenv_opt('VINIX_QEMU_ACCEL') or { 'tcg' }, '-cpu', 'max', '-m', '2048', '-smp', cpus_text, '-drive', 'if=pflash,format=raw,unit=0,readonly=on,file=' + firmware, '-cdrom', iso, '-display', 'none', '-monitor', 'none', '-serial', 'stdio', '-no-reboot']
 out.core_text('==> Starting amd64 QEMU core feature boot\n')
 unsafe { C.__atomic_store_n(&i32(C.VINIX_AGX_VM_INTERRUPTED), i32(0), C.__ATOMIC_RELAXED) }
 previous := unsafe { C.signal(C.SIGINT, voidptr(vm_signal)) }
 defer { unsafe { C.signal(C.SIGINT, previous) } }
 previous_pipe := unsafe { C.signal(C.SIGPIPE, C.SIG_IGN) }
 defer { unsafe { C.signal(C.SIGPIPE, previous_pipe) } }
 pid, master := core_spawn(command, os.environ(), '', python, binding, out.host_arch, true)!
 mut state := CoreState{}
 mut failed := false
 mut failure := IError(none)
 out.core_drive(pid, master, timeout_text, timeout_kind, false, true, mut state) or { failed = true; failure = err }
 unsafe { C.__atomic_store_n(&i32(C.VINIX_AGX_VM_INTERRUPTED), i32(0), C.__ATOMIC_RELAXED); C.signal(C.SIGINT, C.SIG_IGN) }
 if C.kill(pid, C.SIGTERM) < 0 && C.errno != C.ESRCH { cleanup_failure := vm_os_error(); C.close(master); return cleanup_failure }
 vm_wait(pid, 0) or { if err.code() != C.ECHILD { C.close(master); return err } }
 if C.close(master) < 0 { return vm_os_error() }
 if failed { return failure }
 return out.core_finish(state, false, true, false, '')
}
