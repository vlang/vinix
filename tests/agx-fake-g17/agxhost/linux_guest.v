// SPDX-License-Identifier: GPL-2.0-or-later
module agxhost

import encoding.hex
import hosttest
import json2
import time
import os

pub struct GuestBindingFailure {
pub:
 value map[string]json2.Any
}
pub fn (e GuestBindingFailure) msg() string { return 'guest library primitive failed' }
pub fn (e GuestBindingFailure) code() int { return 0 }

fn guest_call(method string, arguments map[string]json2.Any) !json2.Any {
 println(json2.encode({'callback': json2.Any(method), 'arguments': json2.Any(arguments)}, escape_unicode: true))
 reply := hosttest.decode_json(os.get_raw_line())!.as_map()
 if 'error' in reply { return GuestBindingFailure{reply['error']!.as_map()} }
 return reply['value']!
}
fn guest_path(text string) json2.Any { return json2.Any(hex.encode(text.bytes())) }
fn guest_decode(value json2.Any) !string { return hex.decode(value.str())!.bytestr() }
fn guest_resolve(text string) !string { return guest_decode(guest_call('resolve', {'path': guest_path(text)})!)! }
fn guest_mkdir(text string, parents bool, exist_ok bool) ! {
 guest_call('mkdir', {'path': guest_path(text), 'parents': json2.Any(parents), 'exist_ok': json2.Any(exist_ok)})!
}
fn guest_run(argv []string, environment map[string]string, explicit bool, quiet bool) ! {
 mut entries := []json2.Any{}
 for key, value in environment { entries << json2.Any([json2.Any(hex.encode(key.bytes())), json2.Any(hex.encode(value.bytes()))]) }
 guest_call('run', {'argv': json2.Any(argv.map(json2.Any(hex.encode(it.bytes())))), 'environment': if explicit { json2.Any(entries) } else { json2.Any(json2.Null{}) }, 'quiet': json2.Any(quiet)})!
}
fn guest_output(serial string) !string {
 if !guest_call('exists', {'path': guest_path(serial)})!.bool() { return '' }
 return guest_call('read_text', {'path': guest_path(serial)})!.str()
}
fn guest_poll() !bool { return guest_call('poll', {})! !is json2.Null }
fn guest_wait() ! {
 guest_call('wait', {'timeout': json2.Any(5)}) or {
  if err is GuestBindingFailure {
   if (err.value['binding_kind'] or { json2.Any('') }).str() == 'TimeoutExpired' {
    guest_call('kill', {})!
    guest_call('wait', {'timeout': json2.Any(json2.Null{})})!
    return
   }
  }
  return err
 }
}
fn guest_stop() ! {
 if !guest_poll()! {
  guest_call('retiring', {})!
  guest_call('terminate', {})!
  guest_wait()!
 }
}
fn guest_failure(message string) IError { return NativeFailure{'RuntimeError', message} }
fn guest_contains(output string, marker json2.Any) !bool {
 if marker is string { return output.contains(marker) }
 return guest_call('contains', {'haystack': json2.Any(output), 'needle': marker})!.bool()
}
fn guest_failed(output string) bool { return ['KERNEL PANIC', 'FATAL EXCEPTION', 'self-test failed'].any(output.contains(it)) }

pub fn guest_metadata() !map[string]json2.Any { return hosttest.decode_json(linux_guest_manifest)!.as_map() }

fn guest_drive(serial string, qemu_log string, timeout_text string, no_linuxkpi bool, mmap_test bool, topology_test bool) !int {
 deadline := vm_now() + core_timeout(timeout_text, 'number')!
 mut failure_started := f64(0)
 mut has_failure := false
 for vm_now() < deadline || has_failure {
  output := guest_output(serial)!
  if has_failure || guest_failed(output) {
   if !has_failure { failure_started = vm_now(); has_failure = true }
   if vm_now() - failure_started >= 1 || guest_poll()! { return guest_failure('guest failed; see ' + serial) }
   time.sleep(100 * time.millisecond)
   continue
  }
  metadata := guest_call('metadata', {})!.as_map()
  markers := metadata['MARKERS']!.as_array()
  mut expected := if no_linuxkpi { markers[if markers.len > 0 { markers.len - 1 } else { 0 }..].clone() } else { markers.clone() }
  topology_marker := metadata['TOPOLOGY_MARKER']!
  if topology_test { expected << topology_marker } else if guest_contains(output, topology_marker)! { return guest_failure('PCI topology fixture unexpectedly enabled; see ' + serial) }
  mmap_marker := metadata['MMAP_LEASE_MARKER']!
  if mmap_test { expected << mmap_marker } else if guest_contains(output, mmap_marker)! { return guest_failure('mapping fixture unexpectedly enabled; see ' + serial) }
  mut has_all := true
  for marker in expected { if !guest_contains(output, marker)! { has_all = false; break } }
  if has_all {
   if no_linuxkpi && output.contains('linuxkpi:') { return guest_failure('API layer unexpectedly enabled; see ' + serial) }
   guest_call('retiring', {})!
   guest_call('terminate', {})!
   guest_wait()!
   final_output := guest_call('read_text', {'path': guest_path(serial)})!.str()
   if guest_failed(final_output) { return guest_failure('guest failed after startup; see ' + serial) }
   guest_call('print', {'lines': json2.Any([
    json2.Any(hex.encode((if no_linuxkpi { 'Default guest: PASS (4 CPUs, Linux ABI)' } else { 'LinuxKPI guest: PASS (4 CPUs, user-copy prefixes/demand faults/COW, allocator/object caches, logging/formatting, locks, per-CPU storage, task waits/references, synchronization/sequence counters, clocks/timed waits, timers, ordered/delayed/unbound/bound work, priority/system queues, SRCU, wound/wait, bit/variable/I/O waits, scheduler, i915 copy/FPU)' }).bytes())),
    json2.Any(hex.encode(('Serial log: ' + serial).bytes()))
   ])})!
   return 0
  }
  if guest_poll()! { return guest_failure('QEMU exited; see ' + qemu_log) }
  time.sleep(200 * time.millisecond)
 }
 return guest_failure('guest timed out; see ' + serial)
}

pub fn linux_guest(row map[string]json2.Any) !int {
 previous := unsafe { C.signal(C.SIGINT, C.SIG_IGN) }
 defer { unsafe { C.signal(C.SIGINT, previous) } }
 root := guest_decode(row['root']!)!
 state := guest_resolve(guest_decode(row['state_dir']!)!)!
 // Caller-owned state must be new; it can contain another live guest otherwise.
 guest_mkdir(state, true, false)!
 qemu_name := row['qemu']!.str()
 found := guest_call('which', {'name': json2.Any(qemu_name)})!
 qemu := guest_decode(guest_call('path', {'path': guest_path(if found is json2.Null { qemu_name } else { found.str() })})!)!
 firmware := if row['firmware']! is json2.Null {
  base := guest_decode(guest_call('parent_parent', {'path': guest_path(qemu)})!)!
  guest_decode(guest_call('join', {'base': guest_path(base), 'name': json2.Any('share/qemu/edk2-x86_64-code.fd')})!)!
 } else { guest_decode(row['firmware']!)! }
 rootfs := state + '/rootfs'
 guest_mkdir(rootfs + '/sbin', true, false)!
 for name in ['dev', 'proc', 'sys', 'root'] { guest_mkdir(rootfs + '/' + name, false, false)! }
 generated := state + '/guest_init.c'
 python := guest_decode(row['python']!)!
 guest_run([python, root + '/tests/kernel-gaps/compile-v-fixture.py', generated, '--arch', 'x86_64', '--module', root + '/tests/linuxkpi/initfixture'], {}, false, false)!
 guest_run([row['cc']!.str(), '--target=x86_64-linux-musl', '-std=gnu11', '-O2', '-nostdlib', '-ffreestanding', '-fno-stack-protector', '-fno-pie', '-Wno-unused-function', '-Wno-unused-parameter', '-I', root + '/kernel/c', '-isystem', root + '/kernel/freestnd-c-hdrs', '-static', '-fuse-ld=lld', '-Wl,-e,_start', '-Wl,--build-id=none', generated, root + '/tests/linuxkpi/initfixture/entry.S', '-o', rootfs + '/sbin/init'], {}, false, false)!
 initramfs := state + '/initramfs.tar'
 guest_call('archive', {'path': guest_path(initramfs), 'rootfs': guest_path(rootfs)})!
 iso := state + '/test.iso'
 if row['limine_dir']! !is json2.Null {
  limine := guest_resolve(guest_decode(row['limine_dir']!)!)!
  guest_call('copytree', {'source': guest_path(limine), 'destination': guest_path(state + '/iso-build/limine')})!
 }
 environment := native_environment(row['environment']!.str())!
 mut overrides := environment.clone()
 overrides['VINIX_AMD64_ISO_BUILD_DIR'] = state + '/iso-build'
 overrides['VINIX_AMD64_KERNEL'] = guest_resolve(guest_decode(row['kernel']!)!)!
 overrides['VINIX_AMD64_INITRAMFS'] = initramfs
 overrides['VINIX_AMD64_ISO'] = iso
 guest_run([root + '/build-support/build-amd64-iso.sh'], overrides, true, true)!
 serial := state + '/serial.log'
 qemu_log := state + '/qemu.log'
 command := [qemu, '-M', 'q35,smm=off', '-m', '512', '-smp', '4', '-accel', 'tcg', '-cpu', row['cpu']!.str(), '-display', 'none', '-monitor', 'none', '-drive', 'if=pflash,format=raw,unit=0,readonly=on,file=' + firmware, '-cdrom', iso, '-serial', 'file:' + serial, '-no-reboot']
 guest_call('start', {'argv': json2.Any(command.map(json2.Any(hex.encode(it.bytes())))), 'log': guest_path(qemu_log)})!
 mut failed := false
 mut failure := IError(none)
 result := guest_drive(serial, qemu_log, row['timeout_text']!.str(), row['no_linuxkpi']!.bool(), row['mmap_lease_test']!.bool(), row['pci_topology_test']!.bool()) or { failed = true; failure = err; 0 }
 guest_stop()!
 if failed { return failure }
 return result
}
