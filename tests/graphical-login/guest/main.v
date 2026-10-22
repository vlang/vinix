// SPDX-License-Identifier: GPL-2.0-or-later
// PID 1 observes real processes; all credentials and session actions enter
// through the compositor's graphical input, driven by the host's QMP client.
module main

import os
import time

#include <signal.h>
#include <fcntl.h>
#include <unistd.h>
#include <sys/wait.h>

fn C.open(&char, int, ...int) int
fn C.dup2(int, int) int
fn C.close(int) int
fn C.kill(int, int) int
fn C.geteuid() u32
fn C.waitpid(int, &i32, int) int

fn retire_adopted_child(pid int, info string) bool {
	// This observer is PID 1 instead of the normal init reaper. A compositor
	// worker may finish after its parent has exited and become our child.
	// Retire the actual zombie; never classify a live task as already gone.
	if !info.contains('State:\tZ (zombie)\n') || !info.contains('PPid:\t1\n') { return false }
	mut code := i32(0)
	return C.waitpid(pid, &code, C.WNOHANG) == pid
}

fn discard(err IError) {
	unsafe { err.free() }
}

fn contents(path string) string {
	return os.read_file(path) or {
		discard(err)
		''
	}
}

fn process_text(pid string, name string) string {
	path := '/proc/' + pid + '/' + name
	defer { unsafe { path.free() } }
	return contents(path)
}

fn desktop(mode string, uid u32) int {
	entries := os.ls('/proc') or {
		discard(err)
		return 0
	}
	defer { unsafe { entries.free() } }
	expected := if mode == '' {
		'/usr/bin/vinix-desktop\x00'.clone()
	} else {
		'/usr/bin/vinix-desktop\x00' + mode + '\x00'
	}
	defer { unsafe { expected.free() } }
	for entry in entries {
		if entry.int() <= 1 { continue }
		command := process_text(entry, 'cmdline')
		if command != expected {
			unsafe { command.free() }
			continue
		}
		info := process_text(entry, 'status')
		if retire_adopted_child(entry.int(), info) {
			unsafe { info.free(); command.free() }
			continue
		}
		lines := info.split_into_lines()
		mut ids := false
		for line in lines {
			if !line.starts_with('Uid:') { continue }
			fields := line.fields()
			ids = fields.len == 5 && fields[1].u32() == uid && fields[2].u32() == uid
				&& fields[3].u32() == uid && fields[4].u32() == uid
			unsafe { fields.free() }
		}
		unsafe {
			lines.free()
			info.free()
			command.free()
		}
		if ids { return entry.int() }
	}
	return 0
}

fn wait_desktop(mode string, uid u32) !int {
	deadline := time.sys_mono_now() + 600 * time.second
	for time.sys_mono_now() < deadline {
		pid := desktop(mode, uid)
		if pid != 0 {
			time.sleep(time.second)
			return pid
		}
		time.sleep(100 * time.millisecond)
	}
	return error('desktop did not appear: ' + mode)
}

fn owned_authd_alive() bool {
	entries := os.ls('/proc') or { discard(err); return true }
	defer { unsafe { entries.free() } }
	for entry in entries {
		if entry.int() <= 1 { continue }
		command := process_text(entry, 'cmdline')
		matches := command == '/usr/sbin/vinix-authd\x00'
		unsafe { command.free() }
		if !matches { continue }
		info := process_text(entry, 'status')
		retired := retire_adopted_child(entry.int(), info)
		unsafe { info.free() }
		if !retired { return true }
	}
	return false
}

fn greeter_uid() !u32 {
	deadline := time.sys_mono_now() + 600 * time.second
	for time.sys_mono_now() < deadline {
		text := contents('/etc/passwd')
		lines := text.split_into_lines()
		mut uid := u32(0)
		for line in lines {
			fields := line.split(':')
			if fields.len == 7 && fields[0] == 'greeter' { uid = fields[2].u32() }
			unsafe { fields.free() }
		}
		unsafe {
			lines.free()
			text.free()
		}
		if uid >= 100 && uid < 1000 { return uid }
		time.sleep(100 * time.millisecond)
	}
	return error('bootstrap did not publish an ordinary greeter identity')
}

fn status(pid int) string {
	number := pid.str()
	defer { unsafe { number.free() } }
	return process_text(number, 'status')
}

fn stopped(pid int) bool {
	text := status(pid)
	defer { unsafe { text.free() } }
	return text.contains('State:\tT (stopped)')
}

fn wait_login(previous_inode u64) !int {
	deadline := time.sys_mono_now() + 600 * time.second
	for time.sys_mono_now() < deadline {
		pid := desktop('', 1000)
		active := contents('/run/vinix/session/active')
		ready := contents('/run/user/1000/vinix-desktop-ready')
		info := os.lstat('/run/user/1000/vinix-desktop-ready') or {
			discard(err)
			os.Stat{}
		}
		ok := pid > 0 && active == '1000\n' && ready == 'ready\n' && !stopped(pid) && info.inode != previous_inode
		unsafe {
			active.free()
			ready.free()
		}
		if ok { return pid }
		time.sleep(100 * time.millisecond)
	}
	return error('ordinary desktop did not become ready')
}

fn run() ! {
	if C.geteuid() != 0 { return error('PID 1 must be root') }
	if os.exists('/etc/vinix/accounts/current') || os.exists('/root/.vinix-user') {
		return error('fixture requires a fresh account database')
	}
	mut manager := os.new_process('/usr/sbin/vinix-session')
	manager.set_args(['graphical', '--desktop', '/usr/bin/vinix-desktop'])
	manager.run()
	defer {
		if manager.is_alive() {
			C.kill(manager.pid, C.SIGHUP)
			time.sleep(2 * time.second)
		}
		if manager.is_alive() { manager.signal_kill() }
		manager.wait()
		manager.close()
	}
	_ = wait_desktop('--register-only', 0)!
	println('GRAPHICAL LOGIN fresh image exclusive registration READY')
	greeter_id := greeter_uid()!
	greeter := wait_desktop('--greeter', greeter_id)!
	if desktop('', 1000) != 0 || os.exists('/run/user/1000/vinix-desktop-ready') {
		return error('ordinary desktop started before authentication')
	}
	if !os.is_dir('/home/alex') || !os.exists('/root/.vinix-user') {
		return error('real graphical registration was not imported')
	}
	println('GRAPHICAL LOGIN registered account and ordinary greeter PASS')
	deadline := time.sys_mono_now() + 600 * time.second
	mut denied := false
	for time.sys_mono_now() < deadline {
		log := contents('/var/log/vinix/auth.log')
		denied = log.contains('uid=0 verify alex: denied: wrong password')
		unsafe { log.free() }
		if denied { break }
		time.sleep(100 * time.millisecond)
	}
	if !denied || desktop('--greeter', greeter_id) != greeter || desktop('', 1000) != 0
		|| os.exists('/run/vinix/session/active') || os.exists('/run/user/1000/vinix-desktop-ready') {
		return error('wrong-password refusal did not preserve the login boundary')
	}
	println('GRAPHICAL LOGIN wrong password creates no ordinary session PASS')
	first := wait_login(0)!
	for path in ['/home/alex', '/run/user/1000'] {
		info := os.lstat(path)!
		if info.uid != 1000 || info.mode & 0o777 != 0o700 {
			return error('ordinary identity is not private: ' + path)
		}
	}
	ready := os.lstat('/run/user/1000/vinix-desktop-ready')!
	if ready.uid != 1000 || ready.mode & 0o170000 != 0o100000 || ready.mode & 0o022 != 0 {
		return error('ordinary readiness is not owned by its account')
	}
	mut held_ready := os.open('/run/user/1000/vinix-desktop-ready')!
	defer { held_ready.close() }
	first_session := contents('/proc/' + first.str() + '/sessionid')
	defer { unsafe { first_session.free() } }
	if first_session.trim_space().u32() == 0 {
		return error('ordinary compositor has no kernel login')
	}
	os.write_file('/home/alex/login-preserved', 'switch and logout preserve account data\n')!
	os.chown('/home/alex/login-preserved', 1000, 1000)!
	power := contents('/sys/power/state')
	if power.contains('mem') { println('GRAPHICAL LOGIN Account menu includes sleep') }
	unsafe { power.free() }
	println('GRAPHICAL LOGIN first ordinary desktop private home and runtime PASS')
	_ = wait_desktop('--greeter', greeter_id)!
	if !stopped(first) || os.exists('/run/vinix/session/active') {
		return error('switch did not stop and revoke the ordinary session')
	}
	println('GRAPHICAL LOGIN switch stops prior session and returns ordinary greeter PASS')
	resumed := wait_login(0)!
	resumed_session := contents('/proc/' + resumed.str() + '/sessionid')
	if resumed != first || resumed_session != first_session {
		return error('reauthentication did not resume the same kernel session')
	}
	unsafe { resumed_session.free() }
	println('GRAPHICAL LOGIN reauthentication resumes same process and kernel session PASS')
	_ = wait_desktop('--greeter', greeter_id)!
	if desktop('', 1000) != 0 || os.exists('/proc/' + first.str()) || os.exists('/run/vinix/session/active') {
		return error('logout left the prior session alive')
	}
	println('GRAPHICAL LOGIN logout reaps ordinary session and returns greeter PASS')
	fresh := wait_login(ready.inode)!
	fresh_session := contents('/proc/' + fresh.str() + '/sessionid')
	if fresh == first || fresh_session == first_session || contents('/home/alex/login-preserved') != 'switch and logout preserve account data\n' {
		return error('new login did not create a fresh session with preserved account data')
	}
	unsafe { fresh_session.free() }
	println('GRAPHICAL LOGIN new login has fresh process and preserved home PASS')
	time.sleep(3 * time.second)
	C.kill(manager.pid, C.SIGHUP)
	end := time.sys_mono_now() + 15 * time.second
	for manager.is_alive() && time.sys_mono_now() < end { time.sleep(100 * time.millisecond) }
	if manager.is_alive() { return error('manager did not stop within its cleanup bound') }
	manager.wait()
	if manager.code != 0 || desktop('', 1000) != 0 || desktop('--greeter', greeter_id) != 0 || owned_authd_alive() || os.exists('/run/vinix/session/active') {
		return error('manager shutdown left a session or active seat')
	}
	println('GRAPHICAL LOGIN manager cleanup reaps sessions PASS')
}

fn main() {
	$if amd64 {
		serial := C.open(c'/dev/com1', C.O_WRONLY)
		if serial >= 0 {
			C.dup2(serial, 1)
			C.dup2(serial, 2)
			if serial > 2 { C.close(serial) }
		}
	}
	println('HWTEST START graphical-login')
	run() or {
		eprintln('GRAPHICAL LOGIN FAIL: ' + err.msg())
		for { time.sleep(time.second) }
	}
	println('HWTEST PASS graphical-login')
	for { time.sleep(time.second) }
}
