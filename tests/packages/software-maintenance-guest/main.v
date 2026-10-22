// SPDX-License-Identifier: GPL-2.0-or-later
// PID 1 for the real compositor acceptance check. No synthetic UI controller.
module main

import os
import time

#include <unistd.h>
#include <fcntl.h>
#include <signal.h>
#include <sys/reboot.h>
#include <errno.h>

fn C.reboot(int) int
fn C.sync()
fn C.dup2(int, int) int

fn stop_child(mut child os.Process, name string) ! {
	if child.is_alive() {
		println('SOFTWARE MAINTENANCE stopping ' + name)
		if C.kill(child.pid, C.SIGKILL) != 0 { return error('cannot stop ' + name) }
		deadline := time.sys_mono_now() + 10 * time.second
		for child.is_alive() {
			if time.sys_mono_now() >= deadline { return error(name + ' did not exit after SIGKILL') }
			time.sleep(50 * time.millisecond)
		}
		child.wait()
		println('SOFTWARE MAINTENANCE reaped ' + name)
	}
	child.close()
}

fn stop_desktop(mut child os.Process, compositor int) ! {
	// vinix-session supervises the compositor. End the real application first
	// so its supervisor can release the seat and reap it through the normal path.
	if compositor > 0 && compositor != child.pid && child.is_alive() {
		if C.kill(compositor, C.SIGKILL) != 0 { return error('cannot stop the ordinary compositor') }
		deadline := time.sys_mono_now() + 10 * time.second
		for child.is_alive() && time.sys_mono_now() < deadline { time.sleep(50 * time.millisecond) }
	}
	stop_child(mut child, 'desktop supervisor')!
}

fn counter_child_present() !bool {
	entries := os.ls('/proc')!
	// The pinned compiler's typed []string free retires its strings as well.
	defer { unsafe { entries.free() } }
	for pid in entries {
		path := '/proc/' + pid + '/cmdline'
		defer { unsafe { path.free() } }
		line := os.read_file(path) or { continue }
		defer { unsafe { line.free() } }
		if line.starts_with('/usr/bin/vinix-package\x00') &&
			line.contains('\x00run-window\x00org.vinix.counter\x00') {
			return true
		}
		program := line.all_before('\x00')
		defer { unsafe { program.free() } }
		if program.ends_with('/bin/counter') { return true }
	}
	return false
}

fn wait_counter_closed(mut desktop os.Process) ! {
	deadline := time.sys_mono_now() + 30 * time.second
	for counter_child_present()! {
		if !desktop.is_alive() { return error('compositor exited while native Counter was closing') }
		if time.sys_mono_now() >= deadline { return error('native Counter launch child did not finish closing') }
		time.sleep(100 * time.millisecond)
	}
	println('SOFTWARE MAINTENANCE native Counter launch child closed PASS')
}

fn command(arguments []string, input string) ! {
	mut child := os.new_process(arguments[0])
	defer { child.close() }
	child.set_args(arguments[1..])
	child.set_redirect_stdio()
	child.run()
	if input != '' { child.stdin_write(input) }
	C.close(child.stdio_fd[0])
	child.stdio_fd[0] = -1
	output := child.stdout_slurp() + child.stderr_slurp()
	child.wait()
	if child.code != 0 { return error(arguments.join(' ') + ': ' + output) }
}

fn check_compositor_identity() !int {
	for pid in os.ls('/proc')! {
		line := os.read_file('/proc/' + pid + '/cmdline') or { continue }
		if !line.starts_with('/usr/bin/vinix-desktop\x00') ||
			!line.contains('--open=Software') {
			continue
		}
		status := os.read_file('/proc/' + pid + '/status')!
		mut ordinary_ids := false
		for field in status.split_into_lines() {
			if field.starts_with('Uid:') {
				ids := field.all_after(':').fields()
				if ids.len != 4 || ids.any(it != '1000') {
					return error('compositor retained privileged user IDs')
				}
				ordinary_ids = true
			}
		}
		if !ordinary_ids { return error('compositor user IDs were not reported') }
		// procfs deliberately returns an empty environ. Qualify the home through
		// files created by the real compositor after the account was prepared.
		for path in ['/home/alex/Desktop', '/home/alex/Documents',
			'/home/alex/.config/user-dirs.dirs'] {
			if (os.stat(path)!).uid != 1000 {
				return error('compositor did not prepare account-owned home artifacts: ' + path)
			}
		}
		folders := os.read_file('/home/alex/.config/user-dirs.dirs')!
		if !folders.contains('XDG_DESKTOP_DIR="/home/alex/Desktop"') ||
			!folders.contains('XDG_DOCUMENTS_DIR="/home/alex/Documents"') {
			return error('compositor prepared folders outside the account home')
		}
		if os.exists('/root/.vinix-user') || os.exists('/home/alex/.vinix-user') {
			return error('ordinary compositor created a legacy registration record')
		}
		{
			marker := os.lstat('/run/user/1000/vinix-desktop-ready')!
			if marker.uid != 1000 || marker.mode & 0o170000 != 0o100000 || marker.mode & 0o022 != 0 {
				return error('ordinary compositor did not publish an account-owned ready marker')
			}
		}
		runtime := os.lstat('/run/user/1000')!
		if runtime.uid != 1000 || runtime.mode & 0o170000 != 0o040000 || runtime.mode & 0o077 != 0 {
			return error('ordinary compositor readiness directory is not account-private')
		}
		println('SOFTWARE MAINTENANCE ordinary-compositor uid=1000 home=/home/alex PASS')
		return pid.int()
	}
	return error('ordinary compositor process was not found')
}

fn run() ! {
	for directory in ['/run', '/root', '/home', '/tmp', '/var/log'] { os.mkdir_all(directory)! }
	os.chmod('/root', 0o700)!
	os.chmod('/tmp', 0o1777)!
	os.setenv('PATH', '/usr/sbin:/usr/bin:/sbin:/bin', true)
	os.setenv('HOME', '/root', true)
	os.setenv('VINIX_SYSTEM_SESSION', '1', true)
	if !os.exists('/etc/software-maintenance-installed') ||
		os.read_file('/etc/software-maintenance-mode')! != 'ordinary\n' {
		return error('requires an installed ordinary-account fixture')
	}
	fresh := installed_root()!
	if fresh {
		require_uninstalled()!
		println('SOFTWARE MAINTENANCE preparing ordinary administrator account')
		command(['/usr/sbin/vinix-account', 'init'], '')!
		command(['/usr/sbin/vinix-account', 'add', 'alex', 'Alex Example', 'admin'], 'graphical acceptance password\n')!
		println('SOFTWARE MAINTENANCE ordinary administrator account prepared')
		command(['/usr/bin/vinix-package', 'update'], '')!
		require_uninstalled()!
	}
	if fresh {
		// Account creation supplies empty standard folders. Remove just these
		// empty directories so the compositor must recreate the observed ones.
		for path in ['/home/alex/Desktop', '/home/alex/Documents'] {
			if os.is_dir(path) { os.rmdir(path)! }
		}
		for path in ['/home/alex/Desktop', '/home/alex/Documents',
			'/home/alex/.config/user-dirs.dirs'] {
			if os.exists(path) { return error('home acceptance artifact already existed: ' + path) }
		}
	}
	mut authentication := os.new_process('/usr/sbin/vinix-authd')
	defer {
		stop_child(mut authentication, 'authentication service') or { eprintln('SOFTWARE MAINTENANCE FAIL: ' + err.msg()) }
	}
	authentication.set_args(['--foreground'])
	authentication.run()
	for !os.exists('/run/vinix/auth.sock') {
		if !authentication.is_alive() { return error('authentication service exited') }
		time.sleep(50 * time.millisecond)
	}
	// Observe replacement of the previous boot's marker without modifying it.
	// Holding its inode open prevents unlink/recreate from reusing that inode.
	mut previous_marker := os.File{}
	mut previous_inode := u64(0)
	if os.exists('/run/user/1000/vinix-desktop-ready') {
		previous_marker = os.open('/run/user/1000/vinix-desktop-ready')!
		previous_inode = (os.lstat('/run/user/1000/vinix-desktop-ready')!).inode
	}
	defer { if previous_marker.is_opened { previous_marker.close() } }
	mut desktop := os.new_process('/usr/sbin/vinix-session')
	mut compositor_pid := 0
	defer {
		stop_desktop(mut desktop, compositor_pid) or { eprintln('SOFTWARE MAINTENANCE FAIL: ' + err.msg()) }
	}
	desktop.set_args(['run', '--seat', 'alex', '/usr/bin/vinix-desktop', '--open=Software'])
	desktop.run()
	println('SOFTWARE MAINTENANCE waiting for real Counter pointer input')
	deadline := time.sys_mono_now() + 1200 * time.second
	for {
		if !desktop.is_alive() || time.sys_mono_now() >= deadline { return error('ordinary maintenance desktop did not become ready') }
		marker := os.lstat('/run/user/1000/vinix-desktop-ready') or { os.Stat{} }
		if marker.inode != 0 && marker.inode != previous_inode &&
			(os.read_file('/run/user/1000/vinix-desktop-ready') or { '' }) == 'ready\n' {
			compositor_pid = check_compositor_identity()!
			if previous_marker.is_opened { previous_marker.close() }
			println('vinix-desktop: ready')
			break
		}
		time.sleep(100 * time.millisecond)
	}
	maintenance(mut desktop, fresh)!
	stop_desktop(mut desktop, compositor_pid)!
	stop_child(mut authentication, 'authentication service')!
	if fresh { retain_installed()! }
	C.sync()
	println(if fresh {
		'SOFTWARE MAINTENANCE INSTALLED BOOT 1 acquired refreshed upgraded pointer-saved checkpoint PASS'
	} else {
		'SOFTWARE MAINTENANCE INSTALLED BOOT 2 retained rollback uninstall cache-reinstall pointer-saved PASS'
	})
}

fn main() {
	// x86 console output is graphical. Keep fd 0 as the inherited seat-console
	// capability while routing fixture and child diagnostics to the serial log.
	console := $if arm64 { '/dev/console' } $else { '/dev/com1' }
	fd := C.open(console.str, C.O_WRONLY)
	if fd >= 0 { C.dup2(fd, 1); C.dup2(fd, 2); if fd > 2 { C.close(fd) } }
	println('SOFTWARE MAINTENANCE START')
	run() or { eprintln('SOFTWARE MAINTENANCE FAIL: ' + err.msg()) }
	println('SOFTWARE MAINTENANCE requesting guest poweroff uid=' + os.geteuid().str())
	result := C.reboot(0x4321fedc)
	saved_errno := C.errno
	eprintln('SOFTWARE MAINTENANCE FAIL: guest poweroff returned result=' + result.str() +
		' errno=' + saved_errno.str())
	// PID 1 must not silently exit when shutdown is refused. The host retains
	// the failure and will reap this diagnostic guest through its bounded path.
	for { time.sleep(time.second) }
}
