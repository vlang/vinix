// SPDX-License-Identifier: GPL-2.0-or-later
module browserlaunch

import crypto.rand
import nativeaccountauth
import os
import time

#include <sys/socket.h>
#include <sys/wait.h>
#include <poll.h>
#include <signal.h>
#include <errno.h>

fn C.socketpair(i32, i32, i32, &i32) i32
fn C.fcntl(i32, i32, ...i32) i32
fn C.poll(&C.pollfd, uint, i32) i32
fn C.recv(i32, voidptr, uint, i32) i32
fn C.write(i32, voidptr, usize) isize
fn C.fork() i32
fn C._exit(i32)
fn C.kill(i32, i32) i32
fn C.umask(u32) u32
fn C.mkdir(&char, u32) i32
fn C.getgid() i32
fn C.getegid() i32
fn C.getresuid(&u32, &u32, &u32) i32
fn C.getresgid(&u32, &u32, &u32) i32
fn C.getgroups(i32, voidptr) i32
fn C.dup2(i32, i32) i32
fn C.dup(i32) i32
fn C.waitpid(i32, &i32, i32) i32

$if linux {
	#include <sys/prctl.h>
	fn C.prctl(i32, u64, u64, u64, u64) i32
}

struct C.pollfd {
pub mut:
	fd i32
	events i16
	revents i16
}

fn cloexec(fd i32, enabled bool) ! {
	flags := C.fcntl(fd, C.F_GETFD)
	if flags < 0 || C.fcntl(fd, C.F_SETFD, if enabled { flags | C.FD_CLOEXEC } else { flags & ~C.FD_CLOEXEC }) != 0 {
		return error('cannot protect browser descriptor inheritance')
	}
}

fn control_pair() ![2]i32 {
	mut pair := [2]i32{}
	if C.socketpair(C.AF_UNIX, C.SOCK_STREAM, 0, &pair[0]) != 0 { return error('cannot create private browser channel') }
	cloexec(pair[0], true) or { C.close(pair[0]); C.close(pair[1]); return err }
	cloexec(pair[1], true) or { C.close(pair[0]); C.close(pair[1]); return err }
	return pair
}

fn close_unrelated(keep []i32) ! {
	$if linux {
		for name in os.ls('/proc/self/fd')! {
			if name.len == 0 || !name.bytes().all(it >= `0` && it <= `9`) { continue }
			fd := i32(name.int())
			if fd >= 3 && fd !in keep { C.close(fd) }
		}
	} $else {
		return error('browser supervisor requires Linux /proc/self/fd')
	}
}

fn (config Config) dropped_identity() ! {
	$if linux {
		mut real, mut effective, mut saved := u32(0), u32(0), u32(0)
		if config.uid < 10000 || config.uid > 19999 || config.gid < 10000 || config.gid > 19999
			|| C.getresuid(&real, &effective, &saved) != 0 || real != config.uid
			|| effective != config.uid || saved != config.uid { return error('browser requires the permanently dropped app UID') }
		if C.getresgid(&real, &effective, &saved) != 0 || real != config.gid || effective != config.gid
			|| saved != config.gid || C.getgroups(0, unsafe { nil }) != 0
			|| C.prctl(39, 0, 0, 0, 0) != 1 { return error('browser requires dropped groups and no_new_privs') }
	} $else {
		return error('browser launch requires Linux credential enforcement')
	}
}

fn private_directory(path string, uid u32, gid u32, create bool) ! {
	if !clean_path(path, true) || os.real_path(os.dir(path)) != os.dir(path) { return error('browser profile path must be canonical') }
	if create && unsafe { C.mkdir(&char(path.str), 0o700) } != 0 && C.errno != C.EEXIST {
		return error('cannot create private browser directory')
	}
	info := os.lstat(path)!
	if info.get_filetype() != .directory || info.mode & 0o7777 != 0o700
		|| info.uid != uid || info.gid != gid || os.real_path(path) != path {
		return error('browser directory must be canonical, app-owned and mode 0700: ' + path)
	}
}

fn profile(data string, uid u32, gid u32) !string {
	private_directory(data, uid, gid, false)!
	mut parent := os.dir(data)
	for {
		info := os.lstat(parent)!
		if info.get_filetype() != .directory || info.uid !in [u32(0), uid]
			|| info.mode & 0o022 != 0 { return error('browser data directory has an unprotected ancestor') }
		if parent == '/' { break }
		parent = os.dir(parent)
	}
	path := data + '/webview'
	private_directory(path, uid, gid, true)!
	return path
}

// Preserve VBR1 bytes for the helper. HUP wins over queued commands.
fn await_command(fd i32, timeout int) !bool {
	mut ready := C.pollfd{fd: fd, events: C.POLLIN}
	result := C.poll(&ready, 1, i32(timeout))
	if result < 0 && C.errno == C.EINTR { return false }
	if result < 0 || ready.revents & (C.POLLHUP | C.POLLERR | C.POLLNVAL) != 0 { return error('browser client disconnected') }
	if result == 0 { return false }
	mut byte := u8(0)
	n := C.recv(fd, &byte, 1, C.MSG_PEEK | C.MSG_DONTWAIT)
	if n < 0 && C.errno in [C.EINTR, C.EAGAIN, C.EWOULDBLOCK] { return false }
	if n != 1 { return error('browser client reached EOF') }
	return true
}

fn client_alive(fd i32) bool {
	mut ready := C.pollfd{fd: fd}
	result := C.poll(&ready, 1, 0)
	if result < 0 || ready.revents & (C.POLLHUP | C.POLLERR | C.POLLNVAL) != 0 { return false }
	mut byte := u8(0)
	n := C.recv(fd, &byte, 1, C.MSG_PEEK | C.MSG_DONTWAIT)
	return n > 0 || (n < 0 && C.errno in [C.EINTR, C.EAGAIN, C.EWOULDBLOCK])
}

fn authority_record(display string, cookie []u8) []u8 {
	mut bytes := [u8(255), 255, 0, 0, 0, u8(display.len)]
	bytes << display.bytes()
	bytes << [u8(0), 18]
	bytes << 'MIT-MAGIC-COOKIE-1'.bytes()
	bytes << [u8(0), 16]
	bytes << cookie
	return bytes
}

fn authority(path string, display string, cookie []u8) ! {
	fd := unsafe { C.open(&char(path.str), C.O_WRONLY | C.O_CREAT | C.O_EXCL | C.O_NOFOLLOW | C.O_CLOEXEC, 0o600) }
	if fd < 0 { return error('cannot create private browser Xauthority') }
	defer { C.close(fd) }
	bytes := authority_record(display, cookie)
	mut offset := 0
	for offset < bytes.len {
		n := unsafe { C.write(fd, &bytes[offset], usize(bytes.len - offset)) }
		if n < 0 && C.errno == C.EINTR { continue }
		if n <= 0 { return error('cannot write browser Xauthority') }
		offset += int(n)
	}
}

fn setup_packet(cookie []u8) []u8 {
	mut bytes := [u8(`l`), 0, 11, 0, 0, 0, 18, 0, u8(cookie.len), 0, 0, 0]
	bytes << 'MIT-MAGIC-COOKIE-1'.bytes()
	bytes << [u8(0), 0]
	bytes << cookie
	return bytes
}

fn authenticated(display string, cookie []u8, pid int, uid u32, gid u32) !bool {
	return authenticated_socket('/tmp/.X11-unix/X' + display, cookie, pid, uid, gid)
}

fn authenticated_socket(path string, cookie []u8, pid int, uid u32, gid u32) !bool {
	fd := x11_connect(path, 250)!
	defer { C.close(fd) }
	peer := nativeaccountauth.peer_credentials(int(fd))!
	if peer.pid != pid || peer.uid != uid || peer.gid != gid {
		return error('private browser display belongs to another process')
	}
	header := x11_exchange(fd, setup_packet(cookie))!
	if header[0] == 0 { return false }
	if header[0] != 1 || header[2] != 11 || header[3] != 0 { return error('invalid X11 setup response') }
	return true
}

fn choose_display() !string {
	// Xvfb itself atomically claims the name. Authentication below rejects a
	// competing/pre-existing server, even if it won the race after this check.
	for number in 120 .. 240 {
		value := number.str()
		if !os.exists('/tmp/.X11-unix/X' + value) && !os.is_link('/tmp/.X11-unix/X' + value)
			&& !os.exists('/tmp/.X' + value + '-lock') && !os.is_link('/tmp/.X' + value + '-lock') { return value }
	}
	return error('no unused private browser display')
}

fn (config Config) browser_environment(session string, profile_path string, display string) map[string]string {
	mut directories := []string{}
	for relative in config.libraries { directories << config.root + '/' + relative }
	// Construct from zero. ART's LD_PRELOAD, Bionic paths, authority descriptors,
	// DBus addresses and user-controlled GTK/WebKit overrides cannot leak in.
	return {
		'HOME': session + '/home'
		'PATH': config.root + '/usr/bin:' + config.root + '/bin'
		'LANG': 'C.UTF-8'
		'DISPLAY': ':' + display
		'XAUTHORITY': session + '/Xauthority'
		'LD_LIBRARY_PATH': directories.join(':')
		'XDG_RUNTIME_DIR': session + '/runtime'
		'XDG_CONFIG_HOME': session + '/config'
		'XDG_DATA_HOME': session + '/data'
		'XDG_CACHE_HOME': profile_path + '/cache'
		'XDG_DATA_DIRS': config.root + '/usr/share'
		'GIO_MODULE_DIR': config.root + '/usr/lib/gio/modules'
		'FONTCONFIG_FILE': config.root + '/' + config.fontconfig
		'FONTCONFIG_PATH': config.root + '/' + os.dir(config.fontconfig)
		'GDK_BACKEND': 'x11'
		'GSK_RENDERER': 'cairo'
		'GSETTINGS_BACKEND': 'memory'
		'LIBGL_ALWAYS_SOFTWARE': '1'
		'GALLIUM_DRIVER': 'softpipe'
		'WEBKIT_DISABLE_DMABUF_RENDERER': '1'
	}
}

fn child(loader string, arguments []string, environment map[string]string) &os.Process {
	mut process := os.new_process(loader)
	process.use_pgroup = true
	process.set_args(arguments)
	process.set_environment(environment)
	process.set_stdin_path('/dev/null')
	// Inherit the supervisor's private log, without pipe back pressure.
	process.run()
	return process
}

fn stop(mut process os.Process) {
	if process.status == .not_started || process.status == .closed { return }
	if process.pid > 0 { C.kill(i32(-process.pid), C.SIGTERM) }
	deadline := time.sys_mono_now() + u64(time.second)
	for process.is_alive() && time.sys_mono_now() < deadline { time.sleep(10 * time.millisecond) }
	// Kill the group even when its original leader has already exited.
	if process.pid > 0 { C.kill(i32(-process.pid), C.SIGKILL) }
	process.wait()
	process.close()
}

fn (mut config Config) session(fd i32, profile_path string) ! {
	defer { C.close(fd); config.close() }
	for {
		if await_command(fd, 500)! { break }
	}
	// The root administrator may have replaced a deployment while this unused
	// channel slept. Revalidate the same dirfd/inode and every pin before exec.
	config.verify_snapshot()!
	config.close()
	if !client_alive(fd) { return error('browser client exited during admission') }
	private_directory(profile_path, config.uid, config.gid, false)!
	for name in ['data', 'cache'] { private_directory(profile_path + '/' + name, config.uid, config.gid, true)! }
	session_path := profile_path + '/session-' + rand.bytes(16)!.hex()
	private_directory(session_path, config.uid, config.gid, true)!
	defer { os.rmdir_all(session_path) or {} }
	for name in ['home', 'runtime', 'config', 'data'] {
		private_directory(session_path + '/' + name, config.uid, config.gid, true)!
	}
	log_path := session_path + '/session.log'
	log := unsafe { C.open(&char(log_path.str), C.O_WRONLY | C.O_CREAT | C.O_EXCL | C.O_CLOEXEC | C.O_NOFOLLOW, 0o600) }
	if log < 0 { return error('cannot create private browser session log') }
	if C.dup2(log, 1) < 0 || C.dup2(log, 2) < 0 { C.close(log); return error('cannot redirect browser session log') }
	C.close(log)
	display := choose_display()!
	mut cookie := rand.bytes(16)!
	defer { for index in 0 .. cookie.len { cookie[index] = 0 } }
	authority(session_path + '/Xauthority', display, cookie)!
	environment := config.browser_environment(session_path, profile_path, display)
	loader := config.root + '/' + config.loader
	libraries := environment['LD_LIBRARY_PATH']
	mut server := child(loader, ['--library-path', libraries, config.root + '/' + config.xvfb, ':' + display,
		'-screen', '0', '800x600x24', '-auth', session_path + '/Xauthority', '-nolisten', 'tcp', '-noreset',
		'-xkbdir', config.root + '/' + config.xkb, '-fp', config.root + '/' + config.fonts], environment)
	defer { stop(mut server) }
	deadline := time.sys_mono_now() + u64(30 * time.second)
	mut ready := false
	for time.sys_mono_now() < deadline {
		if !client_alive(fd) || !server.is_alive() { return error('browser client/Xvfb exited before readiness') }
		ready = authenticated(display, cookie, server.pid, config.uid, config.gid) or { false }
		if ready { break }
		time.sleep(50 * time.millisecond)
	}
	if !ready { return error('private browser display authentication timed out') }
	mut wrong := cookie.clone()
	wrong[0] ^= 255
	if authenticated(display, wrong, server.pid, config.uid, config.gid)! { return error('private browser display accepted an invalid cookie') }
	if !client_alive(fd) { return error('browser client exited before engine startup') }
	// Only this child exec inherits the engine endpoint. Xvfb and WebProcesses
	// cannot keep an app channel alive after its owner has exited.
	cloexec(fd, false)!
	mut engine := child(loader, ['--library-path', libraries, config.root + '/' + config.engine,
		'--control-fd', fd.str(), '--profile', profile_path], environment)
	cloexec(fd, true) or { stop(mut engine); return err }
	defer { stop(mut engine) }
	for client_alive(fd) {
		if !server.is_alive() { return error('private browser display exited') }
		if !engine.is_alive() { return error('browser engine exited') }
		time.sleep(25 * time.millisecond)
	}
}

// Called only after nativeidentity.activate irreversibly drops privileges. No
// socketpair created as root may masquerade as an app-owned peer via an env UID.
// Consumes admission fds. Returns only the ART endpoint; all failures are fatal
// to the explicitly configured launch, never a fake browser/login success.
pub fn (mut config Config) launch() !int {
	defer { config.close() }
	if !config.enabled { return -1 }
	config.dropped_identity()!
	C.umask(0o077)
	profile_path := profile(config.data, config.uid, config.gid)!
	pair := control_pair()!
	pid := C.fork()
	if pid < 0 { C.close(pair[0]); C.close(pair[1]); return error('cannot start lazy browser supervisor') }
	if pid == 0 {
		C.close(pair[0])
		// The intermediate is reaped before ART exec. Its orphaned supervisor
		// is reaped by init, avoiding a zombie child in the Android process.
		supervisor := C.fork()
		if supervisor < 0 { C._exit(1) }
		if supervisor > 0 { C._exit(0) }
		diagnostics := C.dup(2)
		if diagnostics < 3 { C._exit(1) }
		cloexec(diagnostics, true) or { C._exit(1) }
		close_unrelated([pair[1], config.manifest_fd, config.root_fd, diagnostics]) or { C._exit(1) }
		config.session(pair[1], profile_path) or {
			C.dup2(diagnostics, 2)
			eprintln('run-android browser: ${err}')
			C._exit(1)
		}
		C._exit(0)
	}
	C.close(pair[1])
	mut status := i32(0)
	mut waited := C.waitpid(pid, &status, 0)
	for waited < 0 && C.errno == C.EINTR { waited = C.waitpid(pid, &status, 0) }
	if waited != pid || status != 0 { C.close(pair[0]); return error('cannot detach browser supervisor') }
	cloexec(pair[0], false) or { C.close(pair[0]); return err }
	return int(pair[0])
}
