// SPDX-License-Identifier: GPL-2.0-or-later
module agxhost

import os
import time
import json2
import hosttest
import encoding.hex
import math

#flag -I @DIR
#flag linux -lutil
#include "vm_abi.h"
@[typedef]
struct C.vinix_agx_ip_address { mut: s_addr u32 }
@[typedef]
struct C.vinix_agx_inet_address { mut:
	sin_len u8
	sin_family u16
	sin_port u16
	sin_addr C.vinix_agx_ip_address
}
@[typedef]
struct C.vinix_agx_unix_address { mut:
	sun_len u8
	sun_family u16
	sun_path [108]char
}

fn C.socket(i32, i32, i32) i32
fn C.bind(i32, voidptr, u32) i32
fn C.getsockname(i32, voidptr, &u32) i32
fn C.ntohs(u16) u16
fn C.inet_addr(&char) u32
fn C.connect(i32, voidptr, u32) i32
fn C.send(i32, voidptr, usize, i32) i32
fn C.recv(i32, voidptr, usize, i32) i32
fn C.setsockopt(i32, i32, i32, voidptr, u32) i32
fn C.getsockopt(i32, i32, i32, voidptr, &u32) i32
fn C.forkpty(&i32, &char, voidptr, voidptr) i32
fn C.killpg(i32, i32) i32
fn C.WIFSIGNALED(i32) i32
fn C.strtod(&char, &&char) f64
fn C.__atomic_store_n(&i32, i32, i32)
fn C.__atomic_load_n(&i32, i32) i32

fn vm_signal(_signal i32) {
	unsafe { C.__atomic_store_n(&i32(C.VINIX_AGX_VM_INTERRUPTED), i32(1), C.__ATOMIC_RELAXED) }
}

fn vm_interrupt_check() ! {
	if unsafe { C.__atomic_load_n(&i32(C.VINIX_AGX_VM_INTERRUPTED), C.__ATOMIC_RELAXED) } != 0 {
		return NativeFailure{'KeyboardInterrupt', ''}
	}
}

fn vm_os_error() IError {
	return hosttest.ModuleFileError{'', int(C.errno), os.get_error_msg(int(C.errno))}
}

pub fn vm_available_port() !string {
	fd := C.socket(C.AF_INET, C.SOCK_STREAM, 0)
	if fd < 0 { return vm_os_error() }
	defer { C.close(fd) }
	mut address := C.vinix_agx_inet_address{}
	address.sin_family = C.AF_INET
	address.sin_addr.s_addr = C.inet_addr(c'127.0.0.1')
	$if darwin { address.sin_len = u8(sizeof(C.vinix_agx_inet_address)) }
	if C.bind(fd, &address, u32(sizeof(C.vinix_agx_inet_address))) < 0 { return vm_os_error() }
	mut length := u32(sizeof(C.vinix_agx_inet_address))
	if C.getsockname(fd, &address, &length) < 0 { return vm_os_error() }
	return C.ntohs(address.sin_port).str()
}

fn vm_socket_ready(fd i32, writing bool, deadline f64) !bool {
	if fd < 0 { return NativeFailure{'ValueError', 'file descriptor cannot be a negative integer (' + fd.str() + ')'} }
	if fd >= C.FD_SETSIZE { return NativeFailure{'ValueError', 'filedescriptor out of range in select()'} }
	for {
		vm_interrupt_check()!
		left := deadline - vm_now()
		if left <= 0 { return false }
		mut set := C.fd_set{}
		C.FD_ZERO(&set)
		C.FD_SET(fd, &set)
		seconds := u64(left)
		mut timeout := C.timeval{tv_sec: seconds, tv_usec: u64((left - f64(seconds)) * 1e6)}
		ready := C.select(fd + 1, if writing { unsafe { nil } } else { &set }, if writing { &set } else { unsafe { nil } }, unsafe { nil }, &timeout)
		if ready >= 0 { return ready > 0 }
		if C.errno != C.EINTR { return vm_os_error() }
	}
}

fn vm_socket_send(fd i32, text string) !bool {
	deadline := vm_now() + 2
	mut sent := 0
	for sent < text.len {
		if !vm_socket_ready(fd, true, deadline)! { return false }
		count := unsafe { C.send(fd, text.str + sent, usize(text.len - sent), 0) }
		if count < 0 {
			if C.errno == C.EINTR { continue }
			return false
		}
		if count == 0 { return false }
		sent += count
	}
	return true
}

fn vm_socket_recv(fd i32) !bool {
	deadline := vm_now() + 2
	mut buffer := [4096]u8{}
	for {
		if !vm_socket_ready(fd, false, deadline)! { return false }
		count := C.recv(fd, &buffer[0], buffer.len, 0)
		if count >= 0 { return true }
		if C.errno !in [C.EINTR, C.EAGAIN] { return false }
	}
	return false
}

pub fn vm_quit_monitor(path string) !bool {
	if path.len >= int(C.VINIX_AGX_UNIX_PATH_SIZE) { return false }
	fd := C.socket(C.AF_UNIX, C.SOCK_STREAM, 0)
	if fd < 0 { return false }
	defer { C.close(fd) }
	$if darwin {
		mut no_pipe := i32(1)
		C.setsockopt(fd, C.SOL_SOCKET, C.SO_NOSIGPIPE, &no_pipe, u32(sizeof(i32)))
	}
	mut address := C.vinix_agx_unix_address{}
	address.sun_family = C.AF_UNIX
	$if darwin { address.sun_len = u8(sizeof(C.vinix_agx_unix_address)) }
	unsafe { C.memcpy(&address.sun_path[0], path.str, usize(path.len)) }
	if C.fcntl(fd, C.F_SETFL, C.O_NONBLOCK) < 0 { return false }
	if C.connect(fd, &address, u32(sizeof(C.vinix_agx_unix_address))) < 0 {
		if C.errno !in [C.EINPROGRESS, C.EAGAIN] { return false }
		if !vm_socket_ready(fd, true, vm_now() + 2)! { return false }
		mut failure := i32(0)
		mut length := u32(sizeof(i32))
		if C.getsockopt(fd, C.SOL_SOCKET, C.SO_ERROR, &failure, &length) < 0 || failure != 0 { return false }
	}
	if !vm_socket_recv(fd)! { return false }
	if !vm_socket_send(fd, '{"execute":"qmp_capabilities"}\n')! { return false }
	if !vm_socket_recv(fd)! { return false }
	return vm_socket_send(fd, '{"execute":"quit"}\n')!
}

fn vm_now() f64 { return f64(time.sys_mono_now()) / 1e9 }

fn vm_wait(pid i32, options i32) !(bool, int) {
	mut status := i32(0)
	for {
		waited := C.waitpid(pid, &status, options)
		if waited >= 0 { return waited == pid, int(status) }
		if C.errno != C.EINTR { return vm_os_error() }
		vm_interrupt_check()!
	}
}

// The compatibility entry point drives exactly the same retirement policy in
// the importing Python process: waitpid must run in the process owning pid.
fn vm_stop_primitive(method string, arguments []int) !json2.Any {
	println(json2.encode(json2.Any({'method': json2.Any(method), 'arguments': json2.Any(arguments.map(json2.Any(it)))})))
	C.fflush(C.stdout)
	row := hosttest.decode_json(os.get_raw_line())!.as_map()
	if number := row['errno'] { return hosttest.ModuleFileError{'', number.int(), os.get_error_msg(number.int())} }
	return row['value'] or { json2.Any(json2.Null{}) }
}

fn vm_stop_wait(pid i32, options i32, callback bool) !(bool, int) {
	if !callback { return vm_wait(pid, options) }
	value := vm_stop_primitive('waitpid', [int(pid), int(options)])!.as_array()
	return value[0].int() == int(pid), value[1].int()
}

fn vm_stop_kill(pid i32, signal i32, callback bool) ! {
	if callback { vm_stop_primitive('killpg', [int(pid), int(signal)])!; return }
	if C.killpg(pid, signal) < 0 { return vm_os_error() }
}

pub fn vm_stop_child(pid i32, master i32, callback bool) ! {
	if callback { vm_stop_primitive('write', [int(master)]) or {} } else { C.write(master, c'\x01x', 2) }
	mut deadline := vm_now() + 5
	for vm_now() < deadline {
		waited, _ := vm_stop_wait(pid, C.WNOHANG, callback)!
		if waited { return }
		time.sleep(50 * time.millisecond)
	}
	vm_stop_kill(pid, C.SIGTERM, callback) or {
		if err.code() == C.ESRCH { return }
		return err
	}
	deadline = vm_now() + 2
	for vm_now() < deadline {
		waited, _ := vm_stop_wait(pid, C.WNOHANG, callback)!
		if waited { return }
		time.sleep(50 * time.millisecond)
	}
	vm_stop_kill(pid, C.SIGKILL, callback) or { if err.code() != C.ESRCH { return err } }
	vm_stop_wait(pid, 0, callback) or { if err.code() != C.ECHILD { return err } }
}

fn (mut out Transcript) vm_bytes(chunk []u8) ! {
	if !out.inherit { out.stdout += chunk.bytestr(); return }
	mut sent := 0
	for sent < chunk.len {
		count := unsafe { C.write(1, &chunk[sent], usize(chunk.len - sent)) }
		if count < 0 {
			if C.errno == C.EINTR { vm_interrupt_check()!; continue }
			return vm_os_error()
		}
		sent += count
	}
}

struct VmState {
mut:
 command_sent bool
 pass_seen bool
 fail_seen bool
 shutdown_sent bool
 has_status bool
 status int
 transcript []u8
}

fn (mut out Transcript) vm_drive(pid i32, master i32, monitor string, timeout_text string, timeout_kind string, mut state VmState) ! {
	if timeout_kind != 'number' {
		return NativeFailure{'TypeError', "unsupported operand type(s) for +: 'float' and '" + timeout_kind + "'"}
	}
	timeout := unsafe { C.strtod(timeout_text.str, nil) }
	if math.is_inf(timeout, 0) && timeout_text !in ['inf', '-inf', 'Infinity', '-Infinity'] {
		return NativeFailure{'OverflowError', 'int too large to convert to float'}
	}
	deadline := vm_now() + timeout
	mut buffer := []u8{len: 65536}
	for vm_now() < deadline {
		vm_interrupt_check()!
		waited, child_status := vm_wait(pid, C.WNOHANG)!
		if waited { state.has_status = true; state.status = child_status; break }
		if !vm_socket_ready(master, false, vm_now() + 0.25)! { continue }
		count := C.read(master, buffer.data, usize(buffer.len))
		if count < 0 {
			if C.errno in [C.EIO, C.EINTR] { continue }
			return vm_os_error()
		}
		if count == 0 { continue }
		state.transcript << buffer[..count]
		out.vm_bytes(buffer[..count])!
		recent := state.transcript[if state.transcript.len > 131072 { state.transcript.len - 131072 } else { 0 }..].bytestr()
		if !state.command_sent && vm_shell_prompt(recent) {
			if C.write(master, vm_guest_command.str, usize(vm_guest_command.len)) < 0 { return vm_os_error() }
			state.command_sent = true
		}
		state.pass_seen = vm_line_marker(recent, false)
		state.fail_seen = vm_line_marker(recent, true)
		if (state.pass_seen || state.fail_seen) && !state.shutdown_sent {
			if vm_quit_monitor(monitor)! { state.shutdown_sent = true; continue }
			if C.write(master, c'\x01x', 2) < 0 && C.errno != C.EIO { return vm_os_error() }
			state.shutdown_sent = true
		}
	}
	if !state.has_status {
		waited, child_status := vm_wait(pid, C.WNOHANG)!
		if waited { state.has_status = true; state.status = child_status }
	}
}

pub fn (mut out Transcript) vm_test(root string, timeout_text string, timeout_kind string, python string, child_binding string) !int {
	if !os.is_file(root + '/kernel/bin/vinix') {
		out.streams('', 'ERROR: kernel/bin/vinix is missing; build the AArch64 kernel first\n')
		return 2
	}
	scratch := private_directory(os.temp_dir(), 'vinix-fake-g17-vm.')!
	defer { hosttest.remove_work_dir(scratch) or {} }
	mut environment := os.environ()
	if 'VINIX_BOOT_DISK' !in environment { environment['VINIX_BOOT_DISK'] = scratch + '/boot.img' }
	if 'VINIX_EFIVARS' !in environment { environment['VINIX_EFIVARS'] = scratch + '/efivars.fd' }
	port := vm_available_port()!
	if 'VINIX_QEMU_PACKAGE_STORE_PORT' !in environment { environment['VINIX_QEMU_PACKAGE_STORE_PORT'] = port }
	monitor := scratch + '/qmp.sock'
	environment['VINIX_QEMU_EXTRA'] = (environment['VINIX_QEMU_EXTRA'] or { '' }) + ' -qmp unix:' + monitor + ',server=on,wait=off'
	command := [root + '/scripts/run-aarch64.sh', '--no-build', '--serial', '--fake-g17', '--no-persist', '--mem=8192']
	encoded_command := json2.encode(json2.Any(command.map(json2.Any(it))))
	mut argv := [python, child_binding, '--vinix-pty-child', hex.encode(root.bytes()), encoded_command]
	$if darwin {
		if out.host_arch in ['arm64', 'aarch64', 'x86_64', 'amd64'] {
			argv = ['/usr/bin/arch', if out.host_arch in ['arm64', 'aarch64'] { '-arm64' } else { '-x86_64' }, ...argv]
		}
	}
	mut c_arguments := []&char{}
	for item in argv { c_arguments << &char(item.str) }
	c_arguments << &char(unsafe { nil })
	mut entries := []string{}
	for key, value in environment { entries << key + '=' + value }
	mut c_environment := []&char{}
	for item in entries { c_environment << &char(item.str) }
	c_environment << &char(unsafe { nil })
	unsafe { C.__atomic_store_n(&i32(C.VINIX_AGX_VM_INTERRUPTED), i32(0), C.__ATOMIC_RELAXED) }
	previous := unsafe { C.signal(C.SIGINT, voidptr(vm_signal)) }
	defer { unsafe { C.signal(C.SIGINT, previous) } }
	previous_pipe := unsafe { C.signal(C.SIGPIPE, C.SIG_IGN) }
	defer { unsafe { C.signal(C.SIGPIPE, previous_pipe) } }
	mut master := i32(-1)
	pid := C.forkpty(&master, unsafe { nil }, unsafe { nil }, unsafe { nil })
	if pid < 0 { return vm_os_error() }
	if pid == 0 {
		unsafe { C.execve(argv[0].str, c_arguments.data, c_environment.data) }
		C._exit(127)
	}
	mut state := VmState{}
	mut loop_failed := false
	mut loop_error := IError(none)
	out.vm_drive(pid, master, monitor, timeout_text, timeout_kind, mut state) or {
		loop_failed = true
		loop_error = err
	}
	// The first interrupt ends the test, while this owner still retires its child.
	unsafe { C.__atomic_store_n(&i32(C.VINIX_AGX_VM_INTERRUPTED), i32(0), C.__ATOMIC_RELAXED) }
	// Keep further interrupts from abandoning the PID while its owner reaps it.
	unsafe { C.signal(C.SIGINT, C.SIG_IGN) }
	forced_stop := !state.has_status
	if forced_stop {
		vm_stop_child(pid, master, false) or {
			// Preserve finally's stop-error precedence while also retiring the FD.
			C.close(master)
			return err
		}
	}
	if C.close(master) < 0 { return vm_os_error() }
	if loop_failed { return loop_error }
	missing := vm_missing(state.transcript.bytestr(), state.command_sent, state.pass_seen, state.fail_seen, forced_stop, state.status, state.has_status)
	if missing.len > 0 {
		out.streams('', '\nFAIL fake G17 VM smoke test: ' + missing.join(', ') + '\n')
		return 1
	}
	out.streams('\nPASS Mesa fake-G17 depth/stencil descriptor lifecycle and adversarial in-flight GEM/VM lifetime checks\n', '')
	return 0
}
