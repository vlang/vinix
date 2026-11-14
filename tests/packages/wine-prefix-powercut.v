// SPDX-License-Identifier: GPL-2.0-or-later
// Guest PID1; test-only -Dfsync=vinix_wine_cut_fsync pauses after a real sync.
module main

import os
import time
import tools.packages.wineadapter
import tools.packages.pkgcore
import tests.packages.winecutservice
import tests.packages.winecutfixture

#include <unistd.h>
#include <sys/syscall.h>
#include <sys/reboot.h>
#include <sys/mount.h>
#include <sys/wait.h>
#include <fcntl.h>
#include <grp.h>
#include <sys/file.h>
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
fn C.flock(i32, i32) i32

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
	scaled := $if wine_cut_scaled ? { true } $else { false }
	point := text.int()
	if point !in winecutfixture.points(scaled, true) || text != point.str() { return error('unexpected fixture cut point') }
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

fn free_lock(fd i32) ! {
	if C.flock(fd, C.LOCK_EX | C.LOCK_NB) != 0 { return error('closed service owner retained coordination') }
	if C.flock(fd, C.LOCK_UN) != 0 { return error('cannot release coordination probe') }
}

fn ordinary(root string, point int, fresh bool) ! {
	names := winecutfixture.names($if wine_cut_scaled ? { true } $else { false })
	old_count := names.len - 1
	addition := names.last()
	store := root + '/store'
	old := $if wine_cut_service ? { '/var/lib/vinix-packages/generations/1/apps/wine/root/usr/lib/wine/x86_64-windows' } $else {
		store + '/generations/1/apps/wine/root/usr/lib/wine/x86_64-windows'
	}
	selected := $if wine_cut_service ? { '/var/lib/vinix-packages/generations/2/apps/wine/root/usr/lib/wine/x86_64-windows' } $else {
		store + '/generations/2/apps/wine/root/usr/lib/wine/x86_64-windows'
	}
	data := root + '/private'
	system := data + '/wine/drive_c/windows/system32'
	stage := data + '/wine/.vinix-builtin-next'
	if fresh {
		$if wine_cut_service ? {} $else {
		os.mkdir_all(old)!; os.mkdir_all(selected)!; os.mkdir(data)!; os.chmod(data, 0o700)!
		for name in names[..old_count] {
			os.write_file(old + '/' + name, 'old bytes')!
			os.write_file(selected + '/' + name, 'selected bytes')!
		}
		os.write_file(selected + '/' + addition, 'added bytes')!
		mut prefix := wineadapter.prepare_prefix(data, old)!; prefix.close()
		os.write_file(data + '/sentinel', 'private contents')!
		os.write_file(root + '/armed', point.str())!
		C.sync() // Durable fixture baseline, before capture and the cut window.
		}
		mut owner := $if wine_cut_service ? { (pkgcore.Service{}).wine_prefix_review('app', data)! } $else {
			wineadapter.capture_idle_binding_review(data, selected, store)!
		}
		defer { owner.close() }
		$if wine_cut_service ? {
			if owner.review.review.generation != 2 || owner.review.review.prior_generation != 1
				|| owner.review.review.bindings.len != names.len { return error('signed service cut admission differs') }
			println('WINE SERVICE POWER CUT ADMIT point=${point} generation=2 rows=${names.len}')
		}
		$if wine_cut_cli ? {
			owner.close()
			println('WINE CLI POWER CUT EXEC point=${point} command=wine-prefix-migrate')
			winecutservice.exec_cut(data, point)!
			return error('public migration exec returned unexpectedly')
		}
		cut_point = point; cut_calls = 0
		owner.migrate_bindings()!
		return error('migration returned without the selected power cut')
	}
	if os.read_file(root + '/armed')! != point.str() { return error('reboot cut identity differs') }
	if os.read_file(data + '/sentinel')! != 'private contents' { return error('reboot lost private data') }
	for name in names[..old_count] {
		target := os.readlink(system + '/' + name)!
		if target != old + '/' + name && target != selected + '/' + name { return error('reboot binding is neither old nor selected') }
		if os.read_file(old + '/' + name)! != 'old bytes' || os.read_file(selected + '/' + name)! != 'selected bytes' {
			return error('reboot changed runtime payload bytes')
		}
	}
	boundary := winecutfixture.boundary(point, old_count)!
	replaced := boundary.replaced
	added := boundary.added
	staged := boundary.staged
	for index, name in names[..old_count] {
		expected := (if index < replaced { selected } else { old }) + '/' + name
		if os.readlink(system + '/' + name)! != expected { return error('reboot replacement boundary differs') }
	}
	if added {
		if os.readlink(system + '/' + addition)! != selected + '/' + addition || os.read_file(selected + '/' + addition)! != 'added bytes' {
			return error('reboot lost the synced addition')
		}
	} else if os.exists(system + '/' + addition) || os.is_link(system + '/' + addition) { return error('cut advanced into additions') }
	if staged {
		if os.readlink(stage)! != selected + '/' + names[point / 3] {
			return error('reboot did not retain the exact pending stage')
		}
	} else if os.exists(stage) || os.is_link(stage) { return error('reboot retained an unexpected stage') }
	println('WINE POWER CUT STATE point=${point} replaced=${replaced} added=${added} staged=${staged}')
	println('WINE POWER CUT OBSERVED point=${point} ext2 private-data old-new-bindings')
	$if wine_cut_cli ? {
		for command in ['wine-prefix-migrate', 'wine-prefix-migrate', 'wine-prefix-review']! {
			winecutservice.reply(command, data)!
		}
		println('WINE CLI POWER CUT PASS point=${point} migrate-repeat review-json')
	}
	mut resumed := $if wine_cut_service ? { (pkgcore.Service{}).wine_prefix_review('app', data)! } $else {
		wineadapter.capture_idle_binding_review(data, selected, store)!
	}
	defer { resumed.close() }
	resumed.migrate_bindings()!; resumed.migrate_bindings()!; resumed.recheck()!
	review := $if wine_cut_service ? { resumed.review.review } $else { resumed.review }
	if review.generation != 2 || review.prior_generation != 0 || review.bindings.len != names.len
		|| !review.bindings.all(it.operation == .keep) { return error('reboot recovery inventory differs') }
	for name in names {
		if os.readlink(system + '/' + name)! != selected + '/' + name { return error('reboot recovery target differs') }
	}
	if os.exists(stage) || os.is_link(stage) || os.read_file(data + '/sentinel')! != 'private contents' {
		return error('reboot recovery left staging or changed private data')
	}
	$if wine_cut_service ? {
		lease := C.open(c'/var/lib/vinix-packages/generations/2/lease', C.O_RDONLY | C.O_NOFOLLOW | C.O_CLOEXEC)
		reader := C.open(c'/var/lib/vinix-packages/lock', C.O_RDONLY | C.O_NOFOLLOW | C.O_CLOEXEC)
		if lease < 0 || reader < 0 { return error('cannot capture service coordination probes') }
		defer { C.close(lease); C.close(reader) }
		if C.flock(lease, C.LOCK_EX | C.LOCK_NB) == 0 || (C.errno != C.EAGAIN && C.errno != C.EWOULDBLOCK) {
			return error('recovered service owner lost its generation lease')
		}
		free_lock(reader)!
		resumed.close()
		free_lock(lease)!; free_lock(reader)!
		println('WINE SERVICE POWER CUT PASS point=${point} signed-generation=2 lease-free reader-lock-free')
	} $else { resumed.close() }
	// Let ordinary deferred unlink cleanup finish before the final orderly
	// shutdown. There is no such wait in the interrupted boot.
	time.sleep(6 * time.second)
	C.sync()
	println('WINE POWER CUT SETTLED point=${point} grace-seconds=6')
	println('WINE POWER CUT RECOVERY PASS point=${point} fresh-capture repeat private-data')
}

fn run() ! {
	point := point_from_fixture()!
	preparing := os.exists('/etc/wine-cut-prepare')
	if preparing {
		$if wine_cut_scaled ? {} $else { return error('preparation requires scaled service mode') }
		$if wine_cut_service ? {} $else { return error('preparation requires scaled service mode') }
	}
	println('WINE POWER CUT PROFILE bindings=' + winecutfixture.names($if wine_cut_scaled ? { true } $else { false }).len.str())
	os.mkdir_all('/tmp')!; os.chmod('/tmp', 0o1777)!
	mount := persistent_mount()!
	root := mount + '/wine-cut'
	if !os.exists(root) {
		os.mkdir(root)!
		$if wine_cut_service ? { os.chmod(root, 0o755)! } $else { os.chown(root, 1000, 1000)!; os.chmod(root, 0o700)! }
	}
	fresh := $if wine_cut_service ? { winecutservice.setup(root, point, mount)! } $else { !os.exists(root + '/armed') }
	if preparing {
		time.sleep(6 * time.second)
		println('WINE POWER CUT BASELINE PASS bindings=741')
	} else {
	pid := C.fork()
	if pid == 0 {
		if C.setgroups(0, unsafe { nil }) != 0 || C.setgid(1000) != 0 || C.setuid(1000) != 0 { C._exit(90) }
		ordinary(root, point, fresh) or { eprintln('HWTEST FAIL wine-prefix-powercut: ' + err.msg()); C._exit(91) }
		C._exit(0)
	}
	mut status := i32(0)
	if pid <= 0 || C.waitpid(pid, &status, 0) != pid || status != 0 { return error('ordinary powercut fixture failed') }
	}
	println('HWTEST PASS wine-prefix-powercut')
	C.sync()
	if C.reboot(C.RB_POWER_OFF) != 0 { return error('cannot power off recovered guest') }
}

fn main() {
	$if wine_cut_scaled ? {
		$if wine_cut_cli ? { eprintln('scaled power-cut fixture does not support CLI mode'); exit(2) }
	}
	$if wine_cut_cli ? {
		$if wine_cut_service ? {} $else { eprintln('CLI power-cut mode requires service mode'); exit(2) }
	}
	if C.getpid() != 1 { eprintln('requires guest PID 1'); exit(2) }
	console := $if arm64 { '/dev/console' } $else { '/dev/com1' }
	fd := C.open(console.str, C.O_WRONLY)
	if fd >= 0 { C.dup2(fd, 1); C.dup2(fd, 2); if fd > 2 { C.close(fd) } }
	run() or { eprintln('HWTEST FAIL wine-prefix-powercut: ' + err.msg()) }
	for { time.sleep(time.second) }
}
