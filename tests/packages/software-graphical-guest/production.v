// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os
import time

fn proc_read(pid string, name string) string {
	path := '/proc/' + pid + '/' + name
	defer { unsafe { path.free() } }
	return os.read_file(path) or { '' }
}

fn live_status(status string) bool {
	return status != '' && !status.contains('State:\tZ (zombie)') &&
		!status.contains('State:\tT (stopped)')
}

fn seat_alive(pid int) bool {
	entry := pid.str()
	defer { unsafe { entry.free() } }
	status := proc_read(entry, 'status')
	defer { unsafe { status.free() } }
	return live_status(status)
}

fn status_ids(status string, key string, expected string, count int) bool {
	lines := status.split_into_lines()
	defer { unsafe { lines.free() } }
	for line in lines {
		if !line.starts_with(key) { continue }
		values := line.fields()
		defer { unsafe { values.free() } }
		return values.len == count + 1 && values[1..].all(it == expected)
	}
	return false
}

fn find_session_process(command string, uid string, parent string) !int {
	entries := os.ls('/proc')!
	defer { unsafe { entries.free() } }
	for entry in entries {
		if entry.int() <= 1 { continue }
		args := proc_read(entry, 'cmdline')
		defer { unsafe { args.free() } }
		if args != command { continue }
		status := proc_read(entry, 'status')
		defer { unsafe { status.free() } }
		if live_status(status) && status_ids(status, 'Uid:', uid, 4) &&
			(parent == '' || status_ids(status, 'PPid:', parent, 1)) {
			return entry.int()
		}
	}
	return 0
}

fn wait_session_process(command string, uid string, parent string, deadline i64) !int {
	for time.sys_mono_now() < deadline {
		pid := find_session_process(command, uid, parent)!
		if pid > 0 { return pid }
		time.sleep(100 * time.millisecond)
	}
	return error('production session process did not appear: ' + command.replace('\x00', ' '))
}

fn observe_production_init() ! {
	if os.geteuid() != 0 || os.getppid() != 1 ||
		os.getenv('VINIX_SYSTEM_SESSION') != '1' || os.getenv('HOME') != '/root' {
		return error('production observer requires the optional helper context of PID 1')
	}
	$if arm64 {
		if os.readlink('/proc/1/exe')! != '/sbin/init' { return error('unexpected production PID 1 executable') }
	} $else {
		if !proc_read('1', 'cmdline').contains('/sbin/init\x00') {
			return error('production PID 1 did not start the init script')
		}
	}
	fresh := installed_root()!
	check_first_run_inputs(fresh)!
	if fresh && (os.exists('/root/.vinix-user') || os.exists('/home/alex') ||
		(os.read_file('/etc/passwd') or { '' }).contains('\nalex:')) {
		return error('production registration requires a new installed account database')
	}
	println('SOFTWARE GRAPHICAL PRODUCTION PID1 installed inputs and observer parent PASS')
	deadline := time.sys_mono_now() + 1200 * time.second
	manager := wait_session_process('/usr/sbin/vinix-session\x00graphical\x00--desktop\x00/usr/bin/vinix-desktop\x00',
		'0', '1', deadline)!
	lock_path := '/run/vinix/graphical-manager.lock'
	for !os.exists(lock_path) && time.sys_mono_now() < deadline {
		if !seat_alive(manager) { return error('production graphical manager exited before locking the seat') }
		time.sleep(100 * time.millisecond)
	}
	lock_info := os.lstat(lock_path)!
	if lock_info.uid != 0 || lock_info.gid != 0 || lock_info.mode & 0o170777 != 0o100600 {
		return error('production graphical manager lock is not root private')
	}
	println('SOFTWARE GRAPHICAL PRODUCTION direct-child graphical manager PASS')
	if fresh {
		wait_session_process('/usr/bin/vinix-desktop\x00--register-only\x00', '0', manager.str(), deadline)!
		println('SOFTWARE GRAPHICAL PRODUCTION root registration READY')
	}
	wait_session_process('/usr/bin/vinix-desktop\x00--greeter\x00', '101', '', deadline)!
	if find_session_process('/usr/bin/vinix-desktop\x00', '1000', '')! != 0 {
		return error('ordinary compositor already exists before login')
	}
	registration := os.lstat('/root/.vinix-user')!
	if registration.uid != 0 || registration.mode & 0o170777 != 0o100600 {
		return error('registration did not produce a root-private record')
	}
	home := os.lstat('/home/alex')!
	if home.uid != 1000 || home.gid != 1000 || home.mode & 0o170777 != 0o040700 {
		return error('registration did not prepare an ordinary private home')
	}
	ready := '/run/user/1000/vinix-desktop-ready'
	mut previous_marker := os.File{}
	mut previous_inode := u64(0)
	if os.exists(ready) {
		previous_marker = os.open(ready)!
		previous_inode = (os.lstat(ready)!).inode
	}
	defer { if previous_marker.is_opened { previous_marker.close() } }
	println('SOFTWARE GRAPHICAL PRODUCTION ordinary greeter uid=101 READY')
	wait_session_process('/usr/bin/vinix-desktop\x00', '1000', '', deadline)!
	observe_graphical_seat(GraphicalSeat{
		pid: manager, ordinary: true, installed: true, first_run: true, fresh: fresh,
		previous_inode: previous_inode, production: true,
	})!
	if staged_catalog_enabled() { check_staged_catalog_installed()! }
	save_graphical_checkpoint(fresh)!
}
