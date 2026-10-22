// SPDX-License-Identifier: GPL-2.0-or-later
// PID 1 and independent ordinary-account clients for the production desktop.
module main

import desktop.sessionipc
import desktop.windowfb
import os
import time

#include <sys/socket.h>
#include <fcntl.h>
#include <unistd.h>

fn C.dup2(int, int) int

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
	print(output)
	if child.code != 0 { return error(arguments.join(' ') + ' exited ' + child.code.str()) }
}

fn selected_directory(uid u32) !string {
	if u32(C.getuid()) != uid || u32(C.geteuid()) != uid {
		return error('client did not drop both user IDs')
	}
	os.unsetenv('VINIX_SESSION_RUNTIME')
	os.unsetenv('VINIX_WINDOW_SOCKET')
	os.setenv('XDG_RUNTIME_DIR', '/tmp/forged-runtime', true)
	broker := sessionipc.session_runtime_directory()
	framebuffer := windowfb.runtime_directory()
	expected := '/run/user/' + uid.str() + '/vinix-session.' + uid.str()
	if broker != expected || framebuffer != expected {
		return error('broker and framebuffer defaults disagree with the account runtime')
	}
	return expected
}

fn account_client() ! {
	_ = selected_directory(1000)!
	fd := sessionipc.session_connect() or { return error('ordinary broker connection failed') }
	peer := sessionipc.session_peer(fd) or {
		C.close(fd)
		return error('broker did not present same-user credentials')
	}
	C.close(fd)
	if peer.pid <= 0 || peer.uid != 1000 { return error('invalid broker credentials') }
	reply := sessionipc.session_call('ping', [])!
	if reply != 'ok' { return error('broker ping did not return ok') }
	println('HWTEST INFO external-broker uid=1000 ping=ok PASS')
	mut window := windowfb.open('Ordinary runtime proof', 96, 64)!
	defer { window.close() }
	for frame in 0 .. 3 {
		for i in 0 .. window.surface.width * window.surface.height {
			unsafe { window.surface.back[i] = u32(0xff307050 + frame * 0x10100) }
		}
		window.present()!
		deadline := time.sys_mono_now() + 5 * time.second
		mut event := windowfb.Message{}
		for window.frame_pending {
			if time.sys_mono_now() >= deadline { return error('frame acknowledgement timed out') }
			window.connection.wait(100)!
			for window.receive(unsafe { &event })! {}
		}
	}
	println('HWTEST INFO external-framebuffer uid=1000 frames=3 acknowledged PASS')
}

fn isolated_client() ! {
	_ = selected_directory(1001)!
	if fd := sessionipc.session_connect() {
		C.close(fd)
		return error('second account connected to an unstarted broker')
	}
	if mut connection := windowfb.connect(windowfb.socket_path()) {
		connection.close()
		return error('second account connected to an unstarted framebuffer service')
	}
	victim := '/run/user/1000/vinix-session.1000'
	if mut connection := windowfb.connect(victim + '/windows') {
		connection.close()
		return error('second account reached the first framebuffer socket')
	}
	address := sessionipc.session_address(victim + '/broker') or { return error('invalid victim address') }
	fd := C.socket(C.AF_UNIX, C.SOCK_STREAM, 0)
	if fd < 0 { return error('cannot create isolation probe socket') }
	defer { C.close(fd) }
	if C.connect(fd, unsafe { voidptr(&address) }, u32(sizeof(sessionipc.SessionAddress))) == 0 {
		return error('second account reached the first broker socket')
	}
	println('HWTEST INFO account-isolation uid=1001 broker+framebuffer refused PASS')
}

fn private_node(path string, uid u32, directory bool) ! {
	info := os.lstat(path)!
	expected := if directory { os.FileType.directory } else { os.FileType.socket }
	if info.uid != uid || info.mode & 0o077 != 0 || info.get_filetype() != expected {
		return error('wrong runtime owner/type/mode: ' + path)
	}
}

fn run() ! {
	for directory in ['/run', '/root', '/home', '/tmp', '/var/log'] { os.mkdir_all(directory)! }
	os.chmod('/root', 0o700)!
	os.chmod('/tmp', 0o1777)!
	os.setenv('PATH', '/usr/sbin:/usr/bin:/sbin:/bin', true)
	os.setenv('HOME', '/root', true)
	os.setenv('VINIX_SYSTEM_SESSION', '1', true)
	os.unsetenv('VINIX_SESSION_RUNTIME')
	os.unsetenv('VINIX_WINDOW_SOCKET')
	println('HWTEST INFO initializing account database')
	command(['/usr/sbin/vinix-account', 'init'], '')!
	for name in ['alex', 'blair'] {
		println('HWTEST INFO creating ordinary account ' + name)
		command(['/usr/sbin/vinix-account', 'add', name, name, 'standard'], 'runtime qualification password\n')!
	}
	if os.exists('/run/vinix-session.1000') || os.exists('/run/vinix-session.1001') {
		return error('legacy ordinary runtime existed before startup')
	}
	ready := '/run/user/1000/vinix-desktop-ready'
	if os.exists(ready) || os.exists('/run/vinix-desktop-ready') {
		return error('desktop readiness marker existed before startup')
	}
	mut desktop := os.new_process('/usr/sbin/vinix-session')
	defer {
		if desktop.is_alive() { desktop.signal_kill(); desktop.wait() }
		desktop.close()
	}
	desktop.set_args(['run', '--seat', 'alex', '/usr/bin/vinix-desktop'])
	desktop.run()
	deadline := time.sys_mono_now() + 120 * time.second
	base := '/run/user/1000/vinix-session.1000'
	for !os.exists(base + '/broker') || !os.exists(base + '/windows') ||
		(os.read_file(ready) or { '' }) != 'ready\n' {
		if !desktop.is_alive() { return error('ordinary compositor exited') }
		if time.sys_mono_now() >= deadline { return error('ordinary sockets were not published') }
		time.sleep(50 * time.millisecond)
	}
	private_node(base, 1000, true)!
	private_node(base + '/broker', 1000, false)!
	private_node(base + '/windows', 1000, false)!
	marker := os.lstat(ready)!
	if marker.uid != 1000 || marker.get_filetype() != .regular || marker.mode & 0o022 != 0 ||
		os.exists('/run/vinix-desktop-ready') {
		return error('ordinary desktop readiness was not published privately by its account')
	}
	println('HWTEST INFO ordinary-desktop ready uid=1000 account-runtime PASS')
	command(['/usr/sbin/vinix-session', 'run', 'alex', '/sbin/init', '--client'], '')!
	command(['/usr/sbin/vinix-session', 'run', 'blair', '/sbin/init', '--isolated'], '')!
	private_node('/run/user/1001/vinix-session.1001', 1001, true)!
	if os.exists('/run/vinix-session.1000') || os.exists('/run/vinix-session.1001') {
		return error('ordinary session created a legacy root runtime')
	}
	println('HWTEST INFO numeric-runtime private owners=1000,1001 legacy-ordinary-paths=absent PASS')
	println('HWTEST PASS session-runtime')
	for { time.sleep(time.second) }
}

fn main() {
	if os.args.len > 1 {
		if os.args[1] == '--client' {
			account_client() or { eprintln('HWTEST FAIL account client: ' + err.msg()); exit(1) }
			return
		}
		if os.args[1] == '--isolated' {
			isolated_client() or { eprintln('HWTEST FAIL isolation client: ' + err.msg()); exit(1) }
			return
		}
	}
	// Keep stdin attached to the real console: the ordinary seat compositor
	// inherits it for its kernel-authorized graphics claim. On x86 the serial
	// observation channel is separate from that framebuffer console.
	console := $if arm64 { '/dev/console' } $else { '/dev/com1' }
	fd := C.open(console.str, C.O_WRONLY)
	if fd >= 0 {
		C.dup2(fd, 1)
		C.dup2(fd, 2)
		if fd > 2 { C.close(fd) }
	}
	println('HWTEST START session-runtime')
	run() or { eprintln('HWTEST FAIL session-runtime: ' + err.msg()) }
	for { time.sleep(time.second) }
}
