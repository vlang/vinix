// SPDX-License-Identifier: GPL-2.0-or-later
// Real Xvfb, account-service isolation and the signed package launcher.
module main

import os
import time
import tools.packages.pkglaunch
import tools.packages.x11auth

#include <X11/Xlib.h>
#include <sys/file.h>
#include <signal.h>
#include <unistd.h>
#include <fcntl.h>

@[typedef]
struct C.Display {}
fn C.XOpenDisplay(&char) &C.Display
fn C.XDefaultRootWindow(&C.Display) u64
fn C.XCreateSimpleWindow(&C.Display, u64, int, int, u32, u32, u32, u64, u64) u64
fn C.XSetWindowBackground(&C.Display, u64, u64) int
fn C.XClearWindow(&C.Display, u64) int
fn C.XMapWindow(&C.Display, u64) int
fn C.XSync(&C.Display, int) int
fn C.XCloseDisplay(&C.Display) int
fn C.dup2(int, int) int
fn C.flock(int, int) int

const display = ':115'
const surface = '/run/user/1000/vinix-hosted-x11/qualification'
const authority = surface + '/Xauthority'
const app_data = '/home/alex/.local/share/vinix-apps/org.fixture.x11'
const document = "/home/alex/a space; $(literal) 'é'.txt"

fn wait_file(path string, seconds int) ! {
	deadline := time.sys_mono_now() + i64(seconds) * time.second
	for !os.exists(path) {
		if time.sys_mono_now() > deadline { return error('timed out waiting for ' + path) }
		time.sleep(20 * time.millisecond)
	}
}

fn signed_child() ! {
	if os.getuid() != 1000 || os.geteuid() != 1000 || pkglaunch.needs_isolation()! {
		return error('signed child retained a privileged identity or supplementary groups')
	}
	if os.args.len != 3 || os.args[2] != document || os.getenv('VINIX_APP_ID') != 'org.fixture.x11'
		|| os.getenv('VINIX_APP_GENERATION') != '1' || os.getenv('VINIX_APP_DATA') != app_data
		|| os.getenv('DISPLAY') != display || os.getenv('XAUTHORITY') != authority {
		return error('signed child lost its literal document or authenticated application context')
	}
	if os.read_file(document)! != 'literal document\n' { return error('document grant changed') }
	x := C.XOpenDisplay(display.str)
	if x == unsafe { nil } { return error('sandboxed signed client could not authenticate') }
	root := C.XDefaultRootWindow(x)
	C.XSetWindowBackground(x, root, 0x216a43)
	C.XClearWindow(x, root)
	window := C.XCreateSimpleWindow(x, root, 0, 0, 480, 320, 0, 0, 0x216a43)
	C.XMapWindow(x, window)
	C.XSync(x, 0)
	os.write_file(app_data + '/ready', 'uid=1000 groups=0 literal-document context authenticated\n')!
	// Do not issue another X request after bridge shutdown: this intentionally
	// keeps the signed CLI and its generation lease alive without a live server.
	wait_file(app_data + '/release', 60)!
	os.write_file(app_data + '/finished', 'natural exit\n')!
}

fn cookie_refusal(path string) ! {
	os.setenv('DISPLAY', display, true)
	os.setenv('XAUTHORITY', path, true)
	x := C.XOpenDisplay(display.str)
	if x != unsafe { nil } { C.XCloseDisplay(x); return error('Xvfb accepted an unauthenticated client') }
}

fn lease_busy() !bool {
	fd := C.open(c'/var/lib/vinix-packages/generations/1/lease', C.O_RDONLY | C.O_CLOEXEC)
	if fd < 0 { return error('cannot inspect the installed generation lease') }
	defer { C.close(fd) }
	if C.flock(fd, C.LOCK_EX | C.LOCK_NB) == 0 {
		C.flock(fd, C.LOCK_UN)
		return false
	}
	return true
}

fn drain_host(mut host os.Process) {
	for {
		text := host.pipe_read(.stdout) or { break }
		eprint(text)
		unsafe { text.free() }
	}
}

fn account_client() ! {
	if os.getuid() != 1000 || os.geteuid() != 1000 || !pkglaunch.needs_isolation()! {
		return error('fixture bypassed the real ordinary-account isolation transport')
	}
	os.write_file(document, 'literal document\n')!
	mut host := os.new_process('/usr/bin/vinix-wine-host')
	defer { if host.is_alive() { host.signal_kill(); host.wait() }; host.close() }
	host.set_args([display, surface, '480x320x24', '--package', '/usr/bin/vinix-package', 'run', 'org.fixture.x11', document])
	host.set_redirect_stdio_merged()
	host.run()
	eprintln('HWTEST INFO ordinary host started; waiting for signed client')
	ready_deadline := time.sys_mono_now() + 60 * time.second
	for !os.exists(app_data + '/ready') {
		drain_host(mut host)
		if !host.is_alive() { return error('authenticated host exited before its signed client became ready') }
		if time.sys_mono_now() > ready_deadline { return error('authenticated host timed out before signed client ready') }
		time.sleep(20 * time.millisecond)
	}
	if os.read_file(app_data + '/ready')! != 'uid=1000 groups=0 literal-document context authenticated\n' {
		return error('signed child did not report its actual admitted context')
	}
	if !host.is_alive() || !x11auth.admit(c'/', authority.str, display.str, 1000, 0) {
		return error('real server did not publish its private authority and exact owned socket')
	}
	mut wrong := os.read_bytes(authority)!
	wrong[wrong.len - 1] ^= 0xff
	bad := '/home/alex/wrong-Xauthority'
	os.write_file_array(bad, wrong)!
	os.chmod(bad, 0o600)!
	cookie_refusal(bad)!
	cookie_refusal('/home/alex/missing-Xauthority')!
	os.setenv('XAUTHORITY', authority, true)
	x := C.XOpenDisplay(display.str)
	if x == unsafe { nil } { return error('correct cookie was refused outside the signed sandbox') }
	C.XCloseDisplay(x)
	deadline := time.sys_mono_now() + 10 * time.second
	mut painted := false
	for !painted && time.sys_mono_now() < deadline {
		bytes := os.read_bytes(surface + '/Xvfb_screen0')!
		mut pixels := 0
		for i := 0; i + 3 < bytes.len; i += 4 {
			if bytes[i] == 0x43 && bytes[i + 1] == 0x6a && bytes[i + 2] == 0x21 { pixels++ }
		}
		damage := os.read_bytes(surface + '/damage')!
		painted = pixels > 480 * 320 / 2 && damage.len == 4 && damage.any(it != 0)
		if !painted { time.sleep(50 * time.millisecond) }
	}
	if !painted { return error('signed X11 window did not paint the shared framebuffer and damage counter') }
	if !lease_busy()! { return error('live signed child did not hold a generation lease') }
	// The isolation probe uses another real account while the server is live.
	os.write_file('/home/alex/server-ready', 'ready\n')!
	wait_file('/home/alex/isolation-done', 60)!
	C.close(host.stdio_fd[0]); host.stdio_fd[0] = -1
	host.wait()
	if host.code != 0 || os.exists(authority) || os.exists('/tmp/.X11-unix/X115') {
		return error('host did not reap Xvfb and remove only its own private surface')
	}
	if !lease_busy()! || os.exists(app_data + '/finished') {
		return error('closing the bridge terminated the signed CLI or released its live-child lease')
	}
	os.write_file(app_data + '/release', 'finish\n')!
	wait_file(app_data + '/finished', 10)!
	end := time.sys_mono_now() + 10 * time.second
	for lease_busy()! {
		if time.sys_mono_now() > end { return error('natural signed child exit did not release the generation lease') }
		time.sleep(20 * time.millisecond)
	}
	drain_host(mut host)
}

fn isolated_client() ! {
	if os.getuid() != 1001 || os.geteuid() != 1001 { return error('isolation client did not become the second account') }
	if x11auth.admit(c'/', authority.str, display.str, 1001, 0) { return error('second account admitted foreign authority') }
	cookie_refusal(authority)!
}

fn command(args []string, input string) ! {
	mut child := os.new_process(args[0])
	defer { child.close() }
	child.set_args(args[1..]); child.set_redirect_stdio(); child.run()
	if input != '' { child.stdin_write(input) }
	C.close(child.stdio_fd[0]); child.stdio_fd[0] = -1
	print(child.stdout_slurp()); print(child.stderr_slurp()); child.wait()
	if child.code != 0 { return error(args.join(' ') + ' exited ' + child.code.str()) }
}

fn run() ! {
	os.setenv('PATH', '/usr/sbin:/usr/bin:/sbin:/bin', true)
	os.setenv('HOME', '/root', true)
	for directory in ['/tmp', '/run', '/root', '/home', '/var/log'] { os.mkdir_all(directory)! }
	os.chmod('/tmp', 0o1777)!
	println('HWTEST INFO initializing account database')
	command(['/usr/sbin/vinix-account', 'init'], '')!
	for name in ['alex', 'blair'] {
		println('HWTEST INFO creating ordinary X11 account ' + name)
		command(['/usr/sbin/vinix-account', 'add', name, name, 'standard'], 'X11 qualification password\n')!
	}
	command(['/usr/bin/vinix-wine-host', '--prepare-socket-parent'], '')!
	mut authd := os.new_process('/usr/sbin/vinix-authd')
	defer { if authd.is_alive() { authd.signal_kill(); authd.wait() }; authd.close() }
	authd.run()
	wait_file('/run/vinix/auth.sock', 20)!
	mut account := os.new_process('/usr/sbin/vinix-session')
	defer { if account.is_alive() { account.signal_kill(); account.wait() }; account.close() }
	account.set_args(['run', 'alex', '/sbin/init', '--client'])
	account.set_redirect_stdio_merged()
	account.run()
	account_deadline := time.sys_mono_now() + 90 * time.second
	for !os.exists('/home/alex/server-ready') {
		drain_host(mut account)
		if !account.is_alive() { return error('ordinary host client exited before server-ready') }
		if time.sys_mono_now() > account_deadline { return error('timed out waiting for ordinary host client') }
		time.sleep(20 * time.millisecond)
	}
	command(['/usr/sbin/vinix-session', 'run', 'blair', '/sbin/init', '--isolated'], '')!
	os.write_file('/home/alex/isolation-done', 'done\n')!
	os.chown('/home/alex/isolation-done', 1000, 1000)!
	for account.is_alive() { drain_host(mut account); time.sleep(20 * time.millisecond) }
	drain_host(mut account)
	account.wait()
	if account.code != 0 { return error('ordinary signed-host client failed') }
	authd.signal_kill(); authd.wait()
	// Emit receipts only after the checked clients and server have stopped:
	// active X socket diagnostics otherwise interleave individual serial bytes.
	for marker in ['signed-X11 ordinary-groups transport sandbox-context literal-document PASS',
		'real-Xvfb correct-cookie accepted wrong+missing-cookie refused PASS',
		'signed-X11 framebuffer colored-window damage-observed PASS',
		'real-Xvfb second-account authority+socket refused PASS',
		'signed-X11 bridge-closed server-reaped live-child-lease-held PASS',
		'signed-X11 natural-child-exit lease-released PASS'] {
		println('HWTEST INFO ' + marker)
	}
	println('HWTEST PASS hosted-X11')
}

fn main() {
	if os.args.len > 1 {
		match os.args[1] {
			'--client' { account_client() or { eprintln('HWTEST FAIL hosted-X11 client: ' + err.msg()); exit(1) }; return }
			'--isolated' { isolated_client() or { eprintln('HWTEST FAIL hosted-X11 isolation: ' + err.msg()); exit(1) }; return }
			'--signed-child' { signed_child() or { eprintln('HWTEST FAIL hosted-X11 signed child: ' + err.msg()); exit(1) }; return }
			else {}
		}
	}
	console := $if arm64 { '/dev/console' } $else { '/dev/com1' }
	fd := C.open(console.str, C.O_WRONLY)
	if fd >= 0 { C.dup2(fd, 1); C.dup2(fd, 2); if fd > 2 { C.close(fd) } }
	println('HWTEST START hosted-X11')
	run() or { eprintln('HWTEST FAIL hosted-X11: ' + err.msg()) }
	for { time.sleep(time.second) }
}
