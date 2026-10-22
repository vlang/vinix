// SPDX-License-Identifier: GPL-2.0-or-later
// PID 1 for the real compositor acceptance check. No synthetic UI controller.
module main

import os
import time
import crypto.sha256
import json2
import tools.packages.pkglaunch
import tools.packages.x11auth

#include <unistd.h>
#include <fcntl.h>
#include <signal.h>
#include <sys/reboot.h>
#include <errno.h>
#include <sys/file.h>
#include <sys/wait.h>
#include <X11/Xlib.h>

@[typedef]
struct C.Display {}
@[typedef]
struct C.XEvent { type int }
fn C.XOpenDisplay(&char) &C.Display
fn C.XDefaultRootWindow(&C.Display) u64
fn C.XDefaultScreen(&C.Display) int
fn C.XDefaultDepth(&C.Display, int) int
fn C.XCreatePixmap(&C.Display, u64, u32, u32, u32) u64
fn C.XCreateGC(&C.Display, u64, u64, voidptr) voidptr
fn C.XSetForeground(&C.Display, voidptr, u64) int
fn C.XFillRectangle(&C.Display, u64, voidptr, int, int, u32, u32) int
fn C.XSetWindowBackgroundPixmap(&C.Display, u64, u64) int
fn C.XFreeGC(&C.Display, voidptr) int
fn C.XFreePixmap(&C.Display, u64) int
fn C.XCreateSimpleWindow(&C.Display, u64, int, int, u32, u32, u32, u64, u64) u64
fn C.XSetWindowBackground(&C.Display, u64, u64) int
fn C.XClearWindow(&C.Display, u64) int
fn C.XMapWindow(&C.Display, u64) int
fn C.XSelectInput(&C.Display, u64, i64) int
fn C.XSync(&C.Display, int) int
fn C.XPending(&C.Display) int
fn C.XNextEvent(&C.Display, &C.XEvent) int
fn C.flock(int, int) int
fn C.getgroups(int, &u32) int

const app_data = '/home/alex/.local/share/vinix-apps/org.fixture.x11'

struct ClientContext { pid int display string authority string }

fn wait_file(path string, seconds int) ! {
	deadline := time.sys_mono_now() + i64(seconds) * time.second
	for !os.exists(path) {
		if time.sys_mono_now() >= deadline { return error('timed out waiting for ' + path) }
		time.sleep(50 * time.millisecond)
	}
}

fn wait_contents(path string, expected string, seconds int) ! {
	deadline := time.sys_mono_now() + i64(seconds) * time.second
	for {
		contents := os.read_file(path) or { '' }
		complete := contents == expected
		unsafe { contents.free() }
		if complete { return }
		if time.sys_mono_now() >= deadline { return error('timed out waiting for exact contents: ' + path) }
		time.sleep(50 * time.millisecond)
	}
}

fn paint_client(display &C.Display, window u64, color u64) ! {
	// Software intentionally expands the top-level child over the X root.
	// A server-owned tiled background preserves both exact colors after that
	// resize and exposes actual Xlib repaint without a host-generated image.
	depth := C.XDefaultDepth(display, C.XDefaultScreen(display))
	pixmap := C.XCreatePixmap(display, window, 480, 320, u32(depth))
	if pixmap == 0 { return error('cannot create real X11 background pixmap') }
	defer { C.XFreePixmap(display, pixmap) }
	gc := C.XCreateGC(display, pixmap, 0, unsafe { nil })
	if gc == unsafe { nil } { return error('cannot create real X11 graphics context') }
	defer { C.XFreeGC(display, gc) }
	C.XSetForeground(display, gc, color)
	C.XFillRectangle(display, pixmap, gc, 0, 0, 480, 320)
	C.XSetForeground(display, gc, 0x216a43)
	C.XFillRectangle(display, pixmap, gc, 0, 0, 64, 320)
	C.XSetWindowBackgroundPixmap(display, window, pixmap)
	C.XClearWindow(display, window)
	C.XSync(display, 0)
}

fn client_diagnostic(message string) {
	C.write(2, message.str, usize(message.len))
}

fn signed_child() ! {
	client_diagnostic('SOFTWARE X11 client entered\n')
	if os.getuid() != 1000 || os.geteuid() != 1000 || os.getgid() != 1000 || os.getegid() != 1000 ||
		C.getgroups(0, unsafe { nil }) != 0 || pkglaunch.needs_isolation()! ||
		os.args.len != 2 || os.getenv('VINIX_APP_ID') != 'org.fixture.x11' ||
		os.getenv('VINIX_APP_GENERATION') != '1' || os.getenv('VINIX_APP_DATA') != app_data {
		return error('signed child identity, groups or application context differs')
	}
	display := os.getenv('DISPLAY')
	authority := os.getenv('XAUTHORITY')
	if !authority.starts_with('/run/user/1000/vinix-hosted-x11/vinix-package-') ||
		!authority.ends_with('/Xauthority') {
		return error('signed child did not receive the private authenticated display')
	}
	context_path := app_data + '/context.json'
	context := json2.encode(ClientContext{pid: os.getpid(), display: display, authority: authority})
	fd := C.open(context_path.str, C.O_WRONLY | C.O_CREAT | C.O_EXCL | C.O_CLOEXEC, 0o600)
	if fd < 0 { return error('cannot create private signed client context') }
	if C.write(fd, context.str, usize(context.len)) != context.len {
		C.close(fd)
		return error('cannot write private signed client context')
	}
	C.close(fd)
	client_diagnostic('SOFTWARE X11 client opening display\n')
	// The package sandbox grants only the exact authority and socket. The
	// observer admits their full ancestry; this restricted child proves the
	// actual cookie authentication through Xlib without reopening global parents.
	x := C.XOpenDisplay(display.str)
	if x == unsafe { nil } { return error('signed client could not authenticate') }
	client_diagnostic('SOFTWARE X11 client authenticated\n')
	root := C.XDefaultRootWindow(x)
	C.XSetWindowBackground(x, root, 0x216a43)
	C.XClearWindow(x, root)
	window := C.XCreateSimpleWindow(x, root, 0, 0, 480, 320, 0, 0, 0xb6426f)
	C.XSelectInput(x, window, i64(1 << 2))
	client_diagnostic('SOFTWARE X11 client painting\n')
	paint_client(x, window, 0xb6426f)!
	client_diagnostic('SOFTWARE X11 client mapping\n')
	C.XMapWindow(x, window)
	C.XSync(x, 0)
	os.write_file(app_data + '/ready', 'uid=1000 groups=0 generation=1 authenticated\n')!
	deadline := time.sys_mono_now() + 180 * time.second
	for {
		if time.sys_mono_now() >= deadline { return error('real X11 pointer input timed out') }
		if C.XPending(x) > 0 {
			mut event := C.XEvent{}
			C.XNextEvent(x, &event)
			if event.@type == 4 { break }
		}
		time.sleep(20 * time.millisecond)
	}
	paint_client(x, window, 0x5468c9)!
	os.write_file(app_data + '/clicked', 'real X11 ButtonPress painted blue\n')!
	// No more X requests: retain the signed process and its lease after the UI
	// closes its bridge, then finish naturally on the observer's release.
	wait_contents(app_data + '/release', 'finish\n', 180)!
	os.write_file(app_data + '/finished', 'natural exit\n')!
}

fn lease_busy() !bool {
	fd := C.open(c'/var/lib/vinix-packages/generations/1/lease', C.O_RDONLY | C.O_CLOEXEC)
	if fd < 0 { return error('installed generation lease is absent') }
	defer { C.close(fd) }
	if C.flock(fd, C.LOCK_EX | C.LOCK_NB) == 0 { C.flock(fd, C.LOCK_UN); return false }
	if C.errno != C.EWOULDBLOCK && C.errno != C.EAGAIN { return os.error_posix() }
	return true
}

fn live(pid int) !bool {
	status := os.read_file('/proc/' + pid.str() + '/status') or { return false }
	defer { unsafe { status.free() } }
	if !status.contains('State:\tZ') { return true }
	if status.contains('PPid:\t1\n') {
		mut code := 0
		if C.waitpid(pid, &code, C.WNOHANG) != pid { return error('adopted child zombie was not actually reaped') }
	}
	// Another parent's zombie is still present, and is never called reaped.
	return os.exists('/proc/' + pid.str() + '/status')
}

fn process_for(fragment string, name string, display string) !int {
	entries := os.ls('/proc')!
	defer { unsafe { entries.free() } }
	for entry in entries {
		text := os.read_file('/proc/' + entry + '/cmdline') or { continue }
		defer { unsafe { text.free() } }
		prefix := if name == 'Xvfb' { 'Xvfb\x00' + display + '\x00' } else { '/usr/bin/' + name + '\x00' + display + '\x00' + fragment + '\x00' }
		matches := if name == 'Xvfb' { text.contains('\x00-auth\x00' + fragment + '\x00') } else { text.contains('\x00--package\x00/usr/bin/vinix-package\x00run\x00org.fixture.x11\x00') }
		if matches && text.starts_with(prefix) {
			status := os.read_file('/proc/' + entry + '/status')!
			defer { unsafe { status.free() } }
			if !status.contains('Uid:\t1000\t1000\t1000\t1000') || !status.contains('Gid:\t1000\t1000\t1000\t1000') ||
				!live(entry.int())! { return error('matched hosted process identity differs') }
			return entry.int()
		}
	}
	return error('live process not found: ' + name)
}

fn require_private(path string, directory bool) ! {
	info := os.lstat(path)!
	if info.uid != 1000 || info.gid != 1000 || info.mode & 0o777 != if directory { u32(0o700) } else { u32(0o600) } ||
		info.mode & 0o170000 != if directory { u32(0o040000) } else { u32(0o100000) } {
		return error('ordinary X11 path is not private: ' + path)
	}
}

fn observe_client() ! {
	wait_contents(app_data + '/ready', 'uid=1000 groups=0 generation=1 authenticated\n', 180) or {
		println('SOFTWARE X11 client context diagnostics: ' + (os.read_file(app_data + '/context.json') or { 'absent' }))
		println('SOFTWARE X11 worker diagnostics: ' + (os.read_file('/run/vinix/x11-worker-diagnostic') or { 'absent' }))
		for name in os.ls('/run/user/1000/vinix-hosted-x11') or { []string{} } {
			if !name.ends_with('.log') { continue }
			path := '/run/user/1000/vinix-hosted-x11/' + name
			if os.file_size(path) <= 65536 {
				println('SOFTWARE X11 private launch diagnostics: ' + path)
				println(os.read_file(path) or { 'unreadable launch log' })
			}
		}
		return err
	}
	context := json2.decode[ClientContext](os.read_file(app_data + '/context.json')!)!
	status := os.read_file('/proc/' + context.pid.str() + '/status')!
	if !status.contains('Uid:\t1000\t1000\t1000\t1000') || !status.contains('Gid:\t1000\t1000\t1000\t1000') { return error('actual signed child IDs differ') }
	for directory in ['/run/user/1000', '/run/user/1000/vinix-hosted-x11', os.dir(context.authority)] {
		require_private(directory, true)!
	}
	require_private(context.authority, false)!
	require_private(app_data + '/context.json', false)!
	if !x11auth.admit(c'/', context.authority.str, context.display.str, 1000, 0) {
		return error('observer rejected exact authority and owned socket')
	}
	bridge := process_for(context.authority.all_before_last('/'), 'vinix-wine-host', context.display)!
	server := process_for(context.authority, 'Xvfb', context.display)!
	if bridge == server || !lease_busy()! { return error('live server/bridge/lease identity differs') }
	println('SOFTWARE X11 signed-client uid=1000 groups=0 generation=1 private-authority exact-socket lease-held PASS')
	println('SOFTWARE X11 painted-client ready PASS')
	wait_contents(app_data + '/clicked', 'real X11 ButtonPress painted blue\n', 180)!
	if !live(context.pid)! || !lease_busy()! { return error('signed pointer event or lease was lost') }
	println('SOFTWARE X11 actual-pointer ButtonPress repainted lease-held PASS')
	deadline := time.sys_mono_now() + 180 * time.second
	for live(bridge)! || live(server)! || os.exists(context.authority) ||
		os.exists('/tmp/.X11-unix/X' + context.display.trim_left(':')) {
		if time.sys_mono_now() >= deadline { return error('UI close did not reap bridge/server and remove authority/socket') }
		time.sleep(50 * time.millisecond)
	}
	if !live(context.pid)! || !lease_busy()! || os.exists(app_data + '/finished') {
		return error('UI close killed signed child or released its live lease')
	}
	println('SOFTWARE X11 UI-close bridge+Xvfb reaped authority+socket removed live-child-lease-held PASS')
	// Leave a bounded interval for the host's canonical closed-window capture.
	time.sleep(2 * time.second)
	os.write_file(app_data + '/release', 'finish\n')!
	os.chown(app_data + '/release', 1000, 1000)!
	wait_contents(app_data + '/finished', 'natural exit\n', 30)!
	for live(context.pid)! || lease_busy()! {
		if time.sys_mono_now() >= deadline { return error('natural signed child exit did not release lease') }
		time.sleep(50 * time.millisecond)
	}
	println('SOFTWARE X11 natural-child-exit actual-reap lease-released PASS')
}

fn C.reboot(int) int
fn C.sync()
fn C.dup2(int, int) int

fn stop_child(mut child os.Process, name string) ! {
	if child.is_alive() {
		println('SOFTWARE X11 stopping ' + name)
		if C.kill(child.pid, C.SIGKILL) != 0 { return error('cannot stop ' + name) }
		deadline := time.sys_mono_now() + 10 * time.second
		for child.is_alive() {
			if time.sys_mono_now() >= deadline { return error(name + ' did not exit after SIGKILL') }
			time.sleep(50 * time.millisecond)
		}
		child.wait()
		println('SOFTWARE X11 reaped ' + name)
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

fn command(arguments []string, input string) ! {
	mut child := os.new_process(arguments[0])
	defer { child.close() }
	child.set_args(arguments[1..])
	child.set_redirect_stdio_merged()
	child.run()
	if input != '' { child.stdin_write(input) }
	C.close(child.stdio_fd[0])
	child.stdio_fd[0] = -1
	output := child.stdout_slurp()
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
		println('SOFTWARE X11 ordinary-compositor uid=1000 home=/home/alex PASS')
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
	root := os.stat('/')!
	mounts := os.read_file('/proc/mounts')!
	defer { unsafe { mounts.free() } }
	mut disk_root := false
	lines := mounts.split_into_lines()
	for line in lines {
		fields := line.fields()
		if fields.len >= 3 && fields[0] == '/dev/root' && fields[1] == '/' && fields[2] == 'ext2' { disk_root = true }
		unsafe { fields.free() }
	}
	unsafe { lines.free() }
	if root.dev == 0 || !disk_root {
		return error('requires the installer-selected disk root')
	}
	image_id := os.read_file('/.vinix-image-id')!
	defer { unsafe { image_id.free() } }
	if image_id.trim_space() != 'vinix-software-hosted-x11-1' { return error('installed image identity differs') }
	proof := json2.decode[map[string]string](os.read_file('/usr/share/software-hosted-x11.json')!)!
	for path, expected in proof {
		info := os.lstat(path)!
		bytes := os.read_bytes(path)!
		defer { unsafe { bytes.free() } }
		if info.dev != root.dev || info.uid != 0 || info.mode & 0o170000 != 0o100000 ||
			info.mode & 0o022 != 0 || sha256.hexhash(unsafe { tos(bytes.data, bytes.len) }) != expected {
			return error('installed fixture input identity differs: ' + path)
		}
	}
	println('SOFTWARE X11 installed disk-root tools trust signed-state digests PASS')
	println('SOFTWARE X11 preparing ordinary seat account')
	command(['/usr/sbin/vinix-account', 'init'], '')!
	command(['/usr/sbin/vinix-account', 'add', 'alex', 'Alex Example', 'standard'], 'graphical acceptance password\n')!
	for path in ['/home/alex/Desktop', '/home/alex/Documents'] { os.rmdir(path)! }
	if os.exists('/home/alex/.config/user-dirs.dirs') || os.exists(app_data) {
		return error('ordinary home or signed app data already seeded')
	}
	command(['/usr/bin/vinix-wine-host', '--prepare-socket-parent'], '')!
	mut authentication := os.new_process('/usr/sbin/vinix-authd')
	defer { stop_child(mut authentication, 'authentication service') or { eprintln('SOFTWARE X11 FAIL: ' + err.msg()) } }
	authentication.set_args(['--foreground'])
	authentication.run()
	wait_file('/run/vinix/auth.sock', 20)!
	if os.exists('/run/user/1000/vinix-desktop-ready') { return error('ordinary ready marker was seeded') }
	mut desktop := os.new_process('/usr/sbin/vinix-session')
	mut compositor_pid := 0
	defer { stop_desktop(mut desktop, compositor_pid) or { eprintln('SOFTWARE X11 FAIL: ' + err.msg()) } }
	desktop.set_args(['run', '--seat', 'alex', '/usr/bin/vinix-desktop', '--open=Software'])
	desktop.run()
	deadline := time.sys_mono_now() + 180 * time.second
	for {
		if !desktop.is_alive() || time.sys_mono_now() >= deadline { return error('ordinary desktop did not become ready') }
		marker := os.read_file('/run/user/1000/vinix-desktop-ready') or { '' }
		defer { unsafe { marker.free() } }
		if marker == 'ready\n' { compositor_pid = check_compositor_identity()!; break }
		time.sleep(100 * time.millisecond)
	}
	println('vinix-desktop: ready')
	observe_client()!
	stop_desktop(mut desktop, compositor_pid)!
	stop_child(mut authentication, 'authentication service')!
	C.sync()
	println('SOFTWARE X11 INSTALLED signed-launch painted pointer close-reap lease-lifecycle PASS')
}

fn main() {
	if os.args.len == 2 && os.args[1] == '--signed-child' {
		signed_child() or { eprintln('SOFTWARE X11 FAIL signed-child: ' + err.msg()); exit(1) }
		return
	}
	// Preserve inherited fd 0 for the compositor's console capability.
	console := $if arm64 { '/dev/console' } $else { '/dev/com1' }
	fd := C.open(console.str, C.O_WRONLY)
	if fd < 0 { exit(1) }
	C.dup2(fd, 1); C.dup2(fd, 2); if fd > 2 { C.close(fd) }
	println('SOFTWARE X11 START')
	run() or { eprintln('SOFTWARE X11 FAIL: ' + err.msg()) }
	println('SOFTWARE X11 requesting guest poweroff uid=' + os.geteuid().str())
	result := C.reboot(0x4321fedc)
	saved_errno := C.errno
	eprintln('SOFTWARE X11 FAIL: guest poweroff returned result=' + result.str() + ' errno=' + saved_errno.str())
	for { time.sleep(time.second) }
}

