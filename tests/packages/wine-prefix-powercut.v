// SPDX-License-Identifier: GPL-2.0-or-later
// Guest PID1; test-only -Dfsync=vinix_wine_cut_fsync pauses after a real sync.
module main

import os
import time
import tools.packages.wineadapter

#include <unistd.h>
#include <sys/syscall.h>
#include <sys/reboot.h>
#include <sys/mount.h>
#include <sys/wait.h>
#include <fcntl.h>
#include <grp.h>
fn C.syscall(i64, ...) i64
fn C.getpid() i32
fn C.open(&char, i32, ...i32) i32
fn C.close(i32) i32
fn C.dup2(i32, i32) i32
fn C.fork() i32
fn C.waitpid(i32, &i32, i32) i32
fn C._exit(i32)
fn C.setgroups(u64, voidptr) i32
fn C.setgid(u32) i32
fn C.setuid(u32) i32
fn C.mount(&char, &char, &char, u64, voidptr) i32
fn C.sync()
fn C.reboot(i32) i32

__global (
	cut_point int
	cut_calls int
)

@[export: 'vinix_wine_cut_fsync']
fn cut_fsync(fd i32) i32 {
	result := i32(C.syscall(i64(C.SYS_fsync), fd))
	if result == 0 && cut_point > 0 {
		cut_calls++
		if cut_calls == cut_point {
			println('WINE POWER CUT READY point=${cut_point}')
			// The controller kills QEMU. Do not return, sync or shut down.
			for { time.sleep(time.second) }
		}
	}
	return result
}

fn point_from_fixture() !int {
	text := os.read_file('/etc/wine-cut-point')!
	if text !in ['1', '2', '3'] { return error('expected cut point 1, 2 or 3') }
	return text.int()
}

fn persistent_mount() !string {
	$if arm64 {
		if !os.read_file('/proc/mounts')!.contains(' /root qemu-persist ') {
			return error('prepared ARM ext2 home was not mounted')
		}
		return '/root'
	} $else {
		os.mkdir_all('/persist')!
		for device in ['/dev/vda', '/dev/vdb', '/dev/sd0', '/dev/sd1', '/dev/sd2', '/dev/sd3']! {
			if C.mount(device.str, c'/persist', c'ext2', 0, unsafe { nil }) == 0 {
				if !os.read_file('/proc/mounts')!.contains(' /persist ext2 ') { return error('mount is not ext2') }
				return '/persist'
			}
		}
		return error('cannot mount prepared ext2 prefix disk; devices: ' + os.ls('/dev')!.str())
	}
}

fn ordinary(root string, point int) ! {
	store := root + '/store'
	old := store + '/generations/1/apps/wine/root/usr/lib/wine/x86_64-windows'
	selected := store + '/generations/2/apps/wine/root/usr/lib/wine/x86_64-windows'
	data := root + '/private'
	system := data + '/wine/drive_c/windows/system32'
	stage := data + '/wine/.vinix-builtin-next'
	if !os.exists(root + '/armed') {
		os.mkdir_all(old)!; os.mkdir_all(selected)!; os.mkdir(data)!; os.chmod(data, 0o700)!
		for name in ['a.dll', 'b.dll']! {
			os.write_file(old + '/' + name, 'old bytes')!
			os.write_file(selected + '/' + name, 'selected bytes')!
		}
		os.write_file(selected + '/c.dll', 'added bytes')!
		mut prefix := wineadapter.prepare_prefix(data, old)!; prefix.close()
		os.write_file(data + '/sentinel', 'private contents')!
		os.write_file(root + '/armed', point.str())!
		C.sync() // Durable fixture baseline, before capture and the cut window.
		mut owner := wineadapter.capture_idle_binding_review(data, selected, store)!
		defer { owner.close() }
		cut_point = point; cut_calls = 0
		owner.migrate_bindings()!
		return error('migration returned without the selected power cut')
	}
	if os.read_file(root + '/armed')! != point.str() { return error('reboot cut identity differs') }
	if os.read_file(data + '/sentinel')! != 'private contents' { return error('reboot lost private data') }
	for name in ['a.dll', 'b.dll']! {
		target := os.readlink(system + '/' + name)!
		if target != old + '/' + name && target != selected + '/' + name { return error('reboot binding is neither old nor selected') }
		if os.read_file(old + '/' + name)! != 'old bytes' || os.read_file(selected + '/' + name)! != 'selected bytes' {
			return error('reboot changed runtime payload bytes')
		}
	}
	if os.exists(system + '/c.dll') || os.is_link(system + '/c.dll') { return error('cut advanced past the first replacement') }
	if os.readlink(system + '/b.dll')! != old + '/b.dll' { return error('cut advanced into the second replacement') }
	if point == 1 {
		if os.readlink(stage)! != selected + '/a.dll' || os.readlink(system + '/a.dll')! != old + '/a.dll' {
			return error('reboot did not retain the synced pending stage')
		}
	} else if os.readlink(system + '/a.dll')! != selected + '/a.dll' { return error('reboot lost the synced first replacement') }
	println('WINE POWER CUT OBSERVED point=${point} ext2 private-data old-new-bindings')
	mut resumed := wineadapter.capture_idle_binding_review(data, selected, store)!
	defer { resumed.close() }
	resumed.migrate_bindings()!; resumed.migrate_bindings()!; resumed.recheck()!
	if resumed.review.prior_generation != 0 || resumed.review.bindings.len != 3
		|| !resumed.review.bindings.all(it.operation == .keep) { return error('reboot recovery inventory differs') }
	for name in ['a.dll', 'b.dll', 'c.dll']! {
		if os.readlink(system + '/' + name)! != selected + '/' + name { return error('reboot recovery target differs') }
	}
	if os.exists(stage) || os.is_link(stage) || os.read_file(data + '/sentinel')! != 'private contents' {
		return error('reboot recovery left staging or changed private data')
	}
	resumed.close()
	// Let ordinary deferred unlink cleanup finish before the final orderly
	// shutdown. There is no such wait in the interrupted boot.
	time.sleep(6 * time.second)
	C.sync()
	println('WINE POWER CUT SETTLED point=${point} grace-seconds=6')
	println('WINE POWER CUT RECOVERY PASS point=${point} fresh-capture repeat private-data')
}

fn run() ! {
	point := point_from_fixture()!
	os.mkdir_all('/tmp')!; os.chmod('/tmp', 0o1777)!
	mount := persistent_mount()!
	root := mount + '/wine-cut'
	if !os.exists(root) { os.mkdir(root)!; os.chown(root, 1000, 1000)!; os.chmod(root, 0o700)! }
	pid := C.fork()
	if pid == 0 {
		if C.setgroups(0, unsafe { nil }) != 0 || C.setgid(1000) != 0 || C.setuid(1000) != 0 { C._exit(90) }
		ordinary(root, point) or { eprintln('HWTEST FAIL wine-prefix-powercut: ' + err.msg()); C._exit(91) }
		C._exit(0)
	}
	mut status := i32(0)
	if pid <= 0 || C.waitpid(pid, &status, 0) != pid || status != 0 { return error('ordinary powercut fixture failed') }
	println('HWTEST PASS wine-prefix-powercut')
	C.sync()
	if C.reboot(C.RB_POWER_OFF) != 0 { return error('cannot power off recovered guest') }
}

fn main() {
	if C.getpid() != 1 { eprintln('requires guest PID 1'); exit(2) }
	console := $if arm64 { '/dev/console' } $else { '/dev/com1' }
	fd := C.open(console.str, C.O_WRONLY)
	if fd >= 0 { C.dup2(fd, 1); C.dup2(fd, 2); if fd > 2 { C.close(fd) } }
	run() or { eprintln('HWTEST FAIL wine-prefix-powercut: ' + err.msg()) }
	for { time.sleep(time.second) }
}
