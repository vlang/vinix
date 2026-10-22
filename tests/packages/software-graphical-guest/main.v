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
		println('SOFTWARE GRAPHICAL stopping ' + name)
		if C.kill(child.pid, C.SIGKILL) != 0 { return error('cannot stop ' + name) }
		deadline := time.sys_mono_now() + 10 * time.second
		for child.is_alive() {
			if time.sys_mono_now() >= deadline { return error(name + ' did not exit after SIGKILL') }
			time.sleep(50 * time.millisecond)
		}
		child.wait()
		println('SOFTWARE GRAPHICAL reaped ' + name)
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
	println('SOFTWARE GRAPHICAL native Counter launch child closed PASS')
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

fn check_compositor_identity(ready bool, first_run bool) !int {
	for pid in os.ls('/proc')! {
		line := os.read_file('/proc/' + pid + '/cmdline') or { continue }
		if !line.starts_with('/usr/bin/vinix-desktop\x00') ||
			(first_run && line.contains('--open=')) || (!first_run && !line.contains('--open=Software')) {
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
		if ready {
			marker := os.lstat('/run/user/1000/vinix-desktop-ready')!
			if marker.uid != 1000 || marker.mode & 0o170000 != 0o100000 || marker.mode & 0o022 != 0 {
				return error('ordinary compositor did not publish an account-owned ready marker')
			}
		}
		runtime := os.lstat('/run/user/1000')!
		if runtime.uid != 1000 || runtime.mode & 0o170000 != 0o040000 || runtime.mode & 0o077 != 0 {
			return error('ordinary compositor readiness directory is not account-private')
		}
		println(if ready { 'SOFTWARE GRAPHICAL ordinary-compositor uid=1000 home=/home/alex PASS' }
			else { 'SOFTWARE FIRST RUN pre-ready compositor uid=1000 home=/home/alex runtime=0700 PASS' })
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
	installed := os.exists('/etc/software-graphical-installed')
	first_run := os.exists('/etc/software-graphical-first-run')
	fresh := if installed { installed_root()! } else { true }
	if first_run { check_first_run_inputs(fresh)! }
	if fresh {
		if installed { require_uninstalled()! }
		println('SOFTWARE GRAPHICAL preparing ordinary administrator account')
		command(['/usr/sbin/vinix-account', 'init'], '')!
		command(['/usr/sbin/vinix-account', 'add', 'alex', 'Alex Example', 'admin'], 'graphical acceptance password\n')!
		println('SOFTWARE GRAPHICAL ordinary administrator account prepared')
		command(['/usr/bin/vinix-package', 'update'], '')!
		if !installed {
			command(['/usr/bin/vinix-package', 'install', 'org.vinix.counter', 'org.vinix.memo'], '')!
		} else { require_uninstalled()! }
	}
	ordinary := (os.read_file('/etc/software-graphical-mode') or { '' }) == 'ordinary\n'
	if ordinary && fresh {
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
	// Root compositor mode retains the legacy registration format. An ordinary
	// seat must start from its account home without a registration record.
	if !ordinary {
		os.write_file('/root/.vinix-user', 'version=1\nname=47726170686963616c2054657374\nkdf=scrypt\nn=16384\nr=8\np=1\nsalt=00112233445566778899aabbccddeeff\nhash=00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff\n')!
		os.chmod('/root/.vinix-user', 0o600)!
	}
	mut authentication := os.new_process('/usr/sbin/vinix-authd')
	defer {
		stop_child(mut authentication, 'authentication service') or { eprintln('SOFTWARE GRAPHICAL FAIL: ' + err.msg()) }
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
	if ordinary && os.exists('/run/user/1000/vinix-desktop-ready') {
		previous_marker = os.open('/run/user/1000/vinix-desktop-ready')!
		previous_inode = (os.lstat('/run/user/1000/vinix-desktop-ready')!).inode
	}
	defer { if previous_marker.is_opened { previous_marker.close() } }
	mut desktop := os.new_process(if ordinary {
		'/usr/sbin/vinix-session'
	} else {
		'/usr/bin/vinix-desktop'
	})
	mut compositor_pid := 0
	defer {
		stop_desktop(mut desktop, compositor_pid) or { eprintln('SOFTWARE GRAPHICAL FAIL: ' + err.msg()) }
	}
	desktop.set_args(if ordinary {
		if first_run { ['run', '--seat', 'alex', '/usr/bin/vinix-desktop'] }
		else { ['run', '--seat', 'alex', '/usr/bin/vinix-desktop', '--open=Software'] }
	} else {
		['--open=Software']
	})
	desktop.run()
	println('SOFTWARE GRAPHICAL waiting for real Counter pointer input')
	path := '/home/alex/.local/share/vinix-apps/org.vinix.counter/counter.txt'
	deadline := time.sys_mono_now() + 1200 * time.second
	mut ready := !ordinary
	mut saved := false
	mut acquired := false
	mut before_choice := !first_run || !fresh
	mut reviewed := !first_run || !fresh
	mut ready_at := i64(0)
	for {
		if !desktop.is_alive() { return error('compositor exited') }
		if time.sys_mono_now() >= deadline {
			return error('Counter did not save two pointer increments')
		}
		if !before_choice && os.exists('/home/alex/.config/user-dirs.dirs') && os.is_dir('/run/user/1000') {
			compositor_pid = check_compositor_identity(false, true)!
			check_first_run_inputs(true)!
			before_choice = true
		}
		marker_inode := if !ready {
			(os.lstat('/run/user/1000/vinix-desktop-ready') or { os.Stat{} }).inode
		} else { u64(0) }
		if !ready && marker_inode != 0 && marker_inode != previous_inode &&
			(os.read_file('/run/user/1000/vinix-desktop-ready') or { '' }) == 'ready\n' {
			compositor_pid = check_compositor_identity(true, first_run)!
			if first_run {
				check_first_run_decision()!
				if !fresh {
					println('SOFTWARE FIRST RUN private decision owner=1000 mode=0600 value=review PASS')
					println('SOFTWARE FIRST RUN BOOT 2 retained review decision no repeated prompt PASS')
				}
			}
			if previous_marker.is_opened { previous_marker.close() }
			println('vinix-desktop: ready')
			ready = true
			ready_at = time.sys_mono_now()
		}
		if ready && !reviewed && time.sys_mono_now() - ready_at >= 3 * time.second {
			first_run_proposal()!
			println('SOFTWARE FIRST RUN review handed to Software without activation or approval PASS')
			reviewed = true
		}
		if installed && fresh && !acquired && os.exists('/var/lib/vinix-packages/current/state.json') &&
			(os.read_file('/var/log/vinix/auth.log') or { '' }).contains('uid=1000 run packages-change as alex: exit 0') {
			verify_graphical_install()!
			acquired = true
		}
		value := os.read_file(path) or { '' }
		if !saved && value == '2' {
			stat := os.stat(path)!
			if stat.uid != 1000 {
				return error('native Counter wrote data with the wrong account owner')
			}
			private := os.stat(os.dir(path))!
			if private.uid != 1000 || private.mode & 0o077 != 0 {
				return error('native Counter data directory is not private to alex')
			}
			println('SOFTWARE GRAPHICAL ordinary-counter two-pointer-events persisted uid=' + stat.uid.str() + ' PASS')
			saved = true
			if !installed { break }
		}
		if installed && value == if fresh { '3' } else { '4' } {
			if fresh && (!saved || !acquired) { return error('installed UI acquisition/save evidence is incomplete') }
			if (os.stat(path)!).uid != 1000 || (os.stat(os.dir(path))!).mode & 0o077 != 0 {
				return error('installed Counter private data lost ordinary ownership/mode')
			}
			wait_counter_closed(mut desktop)!
			stop_desktop(mut desktop, compositor_pid)!
			stop_child(mut authentication, 'authentication service')!
			if fresh { retain_installed()! }
			C.sync()
			println(if fresh {
				'SOFTWARE GRAPHICAL INSTALLED BOOT 1 acquired pointer-saved cold-boot checkpoint PASS'
			} else {
				'SOFTWARE GRAPHICAL INSTALLED BOOT 2 retained Counter reopened and pointer-saved PASS'
			})
			return
		}
		time.sleep(100 * time.millisecond)
	}
	// Keep the compositor alive for the host's reopen and framebuffer checks.
	for !os.exists('/run/software-graphical-finish') { time.sleep(100 * time.millisecond) }
}

fn main() {
	// x86 console output is graphical. Keep fd 0 as the inherited seat-console
	// capability while routing fixture and child diagnostics to the serial log.
	console := $if arm64 { '/dev/console' } $else { '/dev/com1' }
	fd := C.open(console.str, C.O_WRONLY)
	if fd >= 0 { C.dup2(fd, 1); C.dup2(fd, 2); if fd > 2 { C.close(fd) } }
	println('SOFTWARE GRAPHICAL START')
	run() or { eprintln('SOFTWARE GRAPHICAL FAIL: ' + err.msg()) }
	println('SOFTWARE GRAPHICAL requesting guest poweroff uid=' + os.geteuid().str())
	result := C.reboot(0x4321fedc)
	saved_errno := C.errno
	eprintln('SOFTWARE GRAPHICAL FAIL: guest poweroff returned result=' + result.str() +
		' errno=' + saved_errno.str())
	// PID 1 must not silently exit when shutdown is refused. The host retains
	// the failure and will reap this diagnostic guest through its bounded path.
	for { time.sleep(time.second) }
}
