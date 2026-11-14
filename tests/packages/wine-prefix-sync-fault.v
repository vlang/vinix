// SPDX-License-Identifier: GPL-2.0-or-later
// Compile with -cflags -Dfsync=vinix_wine_probe_fsync. Fixture interception only.
module main

import os
import time
import tools.packages.wineadapter

#include <unistd.h>
#include <sys/syscall.h>
#include <errno.h>
#include <fcntl.h>
#include <grp.h>
fn C.syscall(i64, ...) i64
fn C.getpid() i32
fn C.open(&char, i32, ...i32) i32
fn C.dup2(i32, i32) i32
fn C.close(i32) i32
fn C.setgroups(u64, voidptr) i32
fn C.setgid(u32) i32
fn C.setuid(u32) i32

__global (
	fault_at int
	sync_calls int
	fault_hits int
)

@[export: 'vinix_wine_probe_fsync']
fn probe_fsync(fd i32) i32 {
	if fault_at > 0 {
		sync_calls++
		if sync_calls == fault_at {
			fault_hits++
			C.errno = C.EIO
			return -1
		}
	}
	// Bypass the compile-time fsync alias; successful calls reach the OS.
	return i32(C.syscall(i64(C.SYS_fsync), fd))
}

fn expect_link(path string, target string) ! {
	if os.readlink(path)! != target { return error('sync fault changed an unexpected binding') }
}

fn one(root string, point int, additions bool) ! {
	store := root + '/store'
	old := store + '/generations/1/apps/wine/root/usr/lib/wine/x86_64-windows'
	selected := store + '/generations/2/apps/wine/root/usr/lib/wine/x86_64-windows'
	data := root + '/data'
	os.mkdir_all(old)!; os.mkdir_all(selected)!; os.mkdir(data)!; os.chmod(data, 0o700)!
	for name in ['a.dll', 'b.dll']! {
		os.write_file(old + '/' + name, 'old bytes')!
		os.write_file(selected + '/' + name, 'selected bytes')!
	}
	os.write_file(selected + '/c.dll', 'added bytes')!
	mut prefix := wineadapter.prepare_prefix(data, if additions { selected } else { old })!
	prefix.close()
	os.write_file(data + '/sentinel', 'private contents')!
	system := data + '/wine/drive_c/windows/system32'
	stage := data + '/wine/.vinix-builtin-next'
	if additions { os.rm(system + '/c.dll')! }
	mut owner := wineadapter.capture_idle_binding_review(data, selected, store)!
	defer { owner.close() }
	fault_at = point; sync_calls = 0; fault_hits = 0
	mut refused := false
	if additions {
		owner.complete_additions() or {
			message := err.msg()
			refused = message == 'cannot synchronize Wine builtin additions; recapture before retrying'
			unsafe { message.free(); err.free() }
		}
	} else {
		owner.migrate_bindings() or {
			message := err.msg()
			refused = message == 'cannot synchronize Wine migration; recapture before retrying'
				|| (point == 7 && message == 'cannot synchronize Wine builtin additions; recapture before retrying')
			unsafe { message.free(); err.free() }
		}
	}
	fault_at = 0
	if !refused || fault_hits != 1 || sync_calls != point { return error('sync injection did not stop the writer at the selected boundary') }
	// Inspect the real namespace before closing the failed owner or resuming.
	expect_link(system + '/a.dll', (if additions || point >= 2 { selected } else { old }) + '/a.dll')!
	expect_link(system + '/b.dll', (if additions || point >= 5 { selected } else { old }) + '/b.dll')!
	if additions || point >= 7 {
		expect_link(system + '/c.dll', selected + '/c.dll')!
	} else if os.exists(system + '/c.dll') || os.is_link(system + '/c.dll') { return error('sync refusal installed an unexpected addition') }
	if !additions && point in [1, 4] {
		expect_link(stage, selected + if point == 1 { '/a.dll' } else { '/b.dll' })!
	} else if os.exists(stage) || os.is_link(stage) { return error('sync refusal left an unexpected stage') }
	if os.read_file(data + '/sentinel')! != 'private contents' { return error('sync refusal changed private data') }
	owner.close()
	mut resumed := wineadapter.capture_idle_binding_review(data, selected, store)!
	defer { resumed.close() }
	resumed.migrate_bindings()!; resumed.migrate_bindings()!; resumed.recheck()!
	if resumed.review.prior_generation != 0 || resumed.review.bindings.len != 3
		|| !resumed.review.bindings.all(it.operation == .keep) { return error('fresh sync recovery did not complete inventory') }
	for name in ['a.dll', 'b.dll', 'c.dll']! { expect_link(system + '/' + name, selected + '/' + name)! }
	if os.exists(stage) || os.is_link(stage) || os.read_file(data + '/sentinel')! != 'private contents' {
		return error('sync recovery left staging or changed private data')
	}
	println('WINE SYNC FAULT PASS mode=${if additions { 'additions' } else { 'migration' }} point=${point} partial-state fresh-resume repeat private-data')
}

fn run() ! {
	root := $if wine_sync_guest ? { '/tmp/wine-sync-fault' } $else {
		if os.args.len != 2 { return error('usage: PROBE FRESH_ROOT') }
		os.abs_path(os.args[1])
	}
	if os.exists(root) || os.is_link(root) { return error('fresh sync fault root required') }
	os.mkdir_all(root)!
	for point in 1 .. 9 { one(root + '/migration-' + point.str(), point, false)! }
	one(root + '/additions', 1, true)!
	println('WINE SYNC FAULTS PASS migration=8 additions=1 explicit-EIO fresh-capture no-power-loss-claim')
}

fn main() {
	$if wine_sync_guest ? {
		if C.getpid() != 1 { eprintln('requires guest PID 1'); exit(2) }
		console := $if arm64 { '/dev/console' } $else { '/dev/com1' }
		fd := C.open(console.str, C.O_WRONLY)
		if fd >= 0 { C.dup2(fd, 1); C.dup2(fd, 2); if fd > 2 { C.close(fd) } }
		os.mkdir_all('/tmp') or { panic(err) }; os.chmod('/tmp', 0o1777) or { panic(err) }
		if C.setgroups(0, unsafe { nil }) != 0 || C.setgid(1000) != 0 || C.setuid(1000) != 0 { panic('cannot enter ordinary sync fixture account') }
	}
	run() or {
		eprintln('HWTEST FAIL wine-prefix-sync-fault: ' + err.msg())
		$if wine_sync_guest ? { for { time.sleep(time.second) } }
		exit(1)
	}
	$if wine_sync_guest ? {
		println('HWTEST PASS wine-prefix-sync-fault')
		for { time.sleep(time.second) }
	}
}
