// SPDX-License-Identifier: GPL-2.0-or-later
module winejitstream

import os
import time

#define wine_wait_pipe pipe
fn C.wine_wait_pipe(&i32) i32
fn C.pause() i32
fn C.unlink(&char) i32

struct WaitSlot {
mut:
	before u32 = 0x45ab10ef
	status i32 = -1
	after u32 = 0xc1032a5e
}

fn wait_expect(condition bool, message string) {
	if !condition { panic('wine-native-wait control: ' + message) }
}

fn wait_slot_check(slot &WaitSlot) {
	wait_expect(sizeof(slot.status) == 4, 'status is exactly four bytes')
	wait_expect(usize(&slot.status) - usize(&slot.before) == 4
		&& usize(&slot.after) - usize(&slot.status) == 4, 'canaries are physically adjacent')
	wait_expect(slot.before == 0x45ab10ef && slot.after == 0xc1032a5e, 'adjacent canaries unchanged')
}

fn wait_owned_child(pid int) {
	// Used only while ownership has not ended in a successful reap/ECHILD.
	C.kill(pid, C.SIGKILL)
	mut discard := i32(-1)
	for {
		waited := raw_waitpid(pid, &discard, 0)
		if waited == pid || (waited < 0 && C.errno != C.EINTR) { return }
	}
}

fn test_native_wait_shared_raw_poll_and_adjacent_canaries() {
	mut descriptors := [2]i32{}
	opened := C.wine_wait_pipe(&descriptors[0])
	wait_expect(opened == 0, 'pipe opened')
	defer { C.close(descriptors[0]); C.close(descriptors[1]) }
	pid := C.fork()
	wait_expect(pid >= 0, 'fork succeeded')
	if pid == 0 {
		C.close(descriptors[1])
		mut token := u8(0)
		if C.read(descriptors[0], &token, 1) != 1 { C._exit(91) }
		C._exit(37)
	}
	mut owned := true
	defer { if owned { wait_owned_child(pid) } }
	mut slot := WaitSlot{}
	wait_slot_check(&slot)
	polled := raw_waitpid(pid, &slot.status, C.WNOHANG)
	wait_expect(polled == 0 && slot.status == -1, 'blocked child raw poll preserves negative sentinel')
	wait_slot_check(&slot)
	token := u8(1)
	written := C.write(descriptors[1], &token, 1)
	wait_expect(written == 1, 'child released')
	for {
		waited := raw_waitpid(pid, &slot.status, 0)
		if waited == pid { owned = false; break }
		if waited < 0 && C.errno == C.ECHILD { owned = false }
		wait_expect(waited < 0 && C.errno == C.EINTR, 'child reaped through shared raw path')
	}
	wait_expect(slot.status == 37 << 8 && int(slot.status) == 9472, 'exact raw exit status widens correctly')
	wait_slot_check(&slot)
	for _ in 0 .. 2 {
		slot.status = -1
		waited := raw_waitpid(pid, &slot.status, C.WNOHANG)
		wait_expect(waited == -1 && C.errno == C.ECHILD && slot.status == -1,
			'reaped child stays unowned and failed poll preserves sentinel')
		wait_slot_check(&slot)
	}
}

fn test_native_wait_signal_status_and_adjacent_canaries() {
	pid := C.fork()
	wait_expect(pid >= 0, 'signal child fork succeeded')
	if pid == 0 { for { C.pause() } }
	mut owned := true
	defer { if owned { wait_owned_child(pid) } }
	killed := C.kill(pid, C.SIGKILL)
	wait_expect(killed == 0, 'owned signal child stopped')
	mut slot := WaitSlot{}
	for {
		waited := raw_waitpid(pid, &slot.status, 0)
		if waited == pid { owned = false; break }
		if waited < 0 && C.errno == C.ECHILD { owned = false }
		wait_expect(waited < 0 && C.errno == C.EINTR, 'signal child reaped')
	}
	wait_expect(slot.status == C.SIGKILL && int(slot.status) == C.SIGKILL, 'exact raw signal status')
	wait_slot_check(&slot)
}

fn test_native_wait_both_supervisors_widen_zero_status() {
	state := os.getenv('VINIX_WINE_WAIT_STATE')
	wait_expect(state != '' && os.real_path(state) == state && os.is_dir(state)
		&& !os.is_link(state), 'explicit supervisor fixture state selected')
	root := state + '/wine-wait-supervisors-' + os.getpid().str()
		+ '-' + time.sys_mono_now().str()
	os.mkdir(root)!
	defer { os.rmdir_all(root) or { panic(err) } }
	os.mkdir(root + '/capture')!
	os.mkdir(root + '/native')!
	// A successful wait must replace the complete negative status sentinel.
	// Calling both real paths also keeps both bodies in the strict C fixture.
	guest := capture(['/usr/bin/true'], root + '/capture', false, 1000)!
	wait_expect(guest.wait_status == 0 && guest.stopped && !guest.timed_out
		&& !guest.size_limited, 'capture widens exact zero and confirms cleanup')
	host := native_guard(['/usr/bin/true'], root + '/native', 'true.log', NativeLimits{
		timeout_ms: 1000, file_bytes: 256 * 1024, total_bytes: 1024 * 1024,
		log_bytes: 256 * 1024, serial_bytes: 256 * 1024,
		min_free_kib: native_free_floor(false)
	})!
	wait_expect(host.wait_status == 0 && host.stopped && !host.timed_out
		&& !host.size_limited && host.reason == '', 'native guard widens exact zero and confirms cleanup')
}

fn test_native_wait_private_module_root_refusals() {
	state := os.getenv('VINIX_WINE_WAIT_STATE')
	wait_expect(state != '' && os.real_path(state) == state && os.is_dir(state)
		&& !os.is_link(state), 'explicit ordinary fixture state selected')
	root := state + '/wine-wait-modules-' + os.getpid().str()
		+ '-' + time.sys_mono_now().str()
	os.mkdir(root)!
	defer {
		if os.is_link(root + '/alias') {
			removed := C.unlink((root + '/alias').str)
			wait_expect(removed == 0, 'literal fixture link removed')
		}
		os.rmdir_all(root) or { panic(err) }
	}
	os.mkdir(root + '/empty')!
	native_require_empty_modules(root + '/empty')!
	os.symlink(root + '/empty', root + '/alias')!
	os.write_file(root + '/file', 'retained')!
	os.mkdir(root + '/nonempty')!
	os.write_file(root + '/nonempty/entry', 'retained')!
	for path in ['relative', root + '/missing', root + '/alias', root + '/file',
		root + '/nonempty', root + '/empty/../empty', root + '/empty' + os.path_delimiter + root] {
		mut refused := false
		native_require_empty_modules(path) or { refused = true }
		wait_expect(refused, 'unsafe or unbound module root refused')
	}
	os.write_file(root + '/empty/added', 'retained')!
	mut refused := false
	native_require_empty_modules(root + '/empty') or { refused = true }
	wait_expect(refused, 'new module entry refused on recheck')
	wait_expect(os.read_file(root + '/nonempty/entry')! == 'retained', 'refusal preserves existing input')
}

fn test_native_wait_assertions_are_active() {
	if os.getenv('VINIX_WINE_WAIT_ASSERT_SENTINEL') == '1' {
		wait_expect(false, 'wine-native-wait intentional assertion sentinel')
	}
}

fn test_native_wait_guard_scan_vanished_entries() {
	state := os.getenv('VINIX_WINE_WAIT_STATE')
	wait_expect(state != '' && os.real_path(state) == state && os.is_dir(state)
		&& !os.is_link(state), 'explicit scan fixture state selected')
	root := state + '/wine-wait-scan-' + os.getpid().str() + '-' + time.sys_mono_now().str()
	os.mkdir(root)!
	defer {
		if os.is_link(root + '/alias') {
			wait_expect(C.unlink((root + '/alias').str) == 0, 'scan fixture link removed')
		}
		os.rmdir_all(root) or { panic(err) }
	}
	os.write_file(root + '/retained', 'abc')!
	os.symlink(root + '/retained', root + '/alias')!
	limits := NativeLimits{file_bytes: 1024, total_bytes: 2048, log_bytes: 1024, serial_bytes: 1024}
	mut tree := NativeTree{}
	// These are the exact scan points after a tool unlinks an ls result.
	native_scan_entry(root, '', 'gone', limits, mut tree)!
	native_scan(root + '/gone', 'gone', limits, mut tree)!
	wait_expect(tree.entries == 1 && tree.bytes == 0 && !tree.limited, 'vanished entries preserve accounting')
	native_scan_entry(root, '', 'retained', limits, mut tree)!
	wait_expect(tree.entries == 2 && tree.bytes == 3 && !tree.limited, 'retained file counted exactly')
	mut missing_root := false
	native_scan(root + '/gone', '', limits, mut tree) or { missing_root = true }
	wait_expect(missing_root, 'missing selected root still refused')
	mut wrong_type := false
	native_scan_entry(root + '/retained', '', 'child', limits, mut tree) or { wrong_type = true }
	wait_expect(wrong_type, 'non-ENOENT stat failure still refused')
	mut link := false
	native_scan_entry(root, '', 'alias', limits, mut tree) or { link = true }
	wait_expect(link, 'literal symlink still refused')
}
