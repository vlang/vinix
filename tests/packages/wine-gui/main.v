// SPDX-License-Identifier: GPL-2.0-or-later
// Private authenticated X11, real USER32 painting/input and natural GUI close.
module main

import os
import time
import tools.packages.x11auth
import tests.packages.winegui

#include <fcntl.h>
#include <unistd.h>
#include <grp.h>
#include <sys/file.h>
#include <sys/wait.h>
#include <X11/Xlib.h>
#include <X11/Xutil.h>
#include <X11/extensions/XTest.h>
fn C.dup2(i32, i32) i32
fn C.chown(&char, i32, i32) i32
fn C.setgroups(u32, voidptr) i32
fn C.setresgid(u32, u32, u32) i32
fn C.setresuid(u32, u32, u32) i32
fn C.sethostname(&char, uint) i32
fn C.flock(i32, i32) i32
@[typedef]
struct C.Display {}
@[typedef]
struct C.XErrorEvent { error_code u8 }
type XErrorHandler = fn (&C.Display, &C.XErrorEvent) i32
fn C.XSetErrorHandler(XErrorHandler) XErrorHandler
@[typedef]
struct C.XImage {}
@[typedef]
struct C.XWindowAttributes { x i32 y i32 width i32 height i32 map_state i32 }
@[typedef]
struct C.XClientData { mut: l [5]i64 }
@[typedef]
struct C.XClientMessageEvent { mut: @type i32 window u64 message_type u64 format i32 data C.XClientData }
@[typedef]
struct C.XEvent { mut: xclient C.XClientMessageEvent }
fn C.XOpenDisplay(&char) &C.Display
fn C.XCloseDisplay(&C.Display) i32
fn C.XDefaultRootWindow(&C.Display) u64
fn C.XQueryTree(&C.Display, u64, voidptr, voidptr, voidptr, voidptr) i32
fn C.XFetchName(&C.Display, u64, voidptr) i32
fn C.XGetWindowProperty(&C.Display, u64, u64, i64, i64, i32, u64, voidptr, voidptr, voidptr, voidptr, voidptr) i32
fn C.XGetWindowAttributes(&C.Display, u64, &C.XWindowAttributes) i32
fn C.XFree(voidptr) i32
fn C.XSync(&C.Display, i32) i32
fn C.XGetImage(&C.Display, u64, i32, i32, u32, u32, u64, i32) &C.XImage
fn C.XGetPixel(&C.XImage, i32, i32) u64
fn C.XDestroyImage(&C.XImage) i32
fn C.XTestFakeMotionEvent(&C.Display, i32, i32, i32, u64) i32
fn C.XTestFakeButtonEvent(&C.Display, u32, i32, u64) i32
fn C.XInternAtom(&C.Display, &char, i32) u64
fn C.XSendEvent(&C.Display, u64, i32, i64, &C.XEvent) i32

const app = 'org.vinix.wine-calculator'
const surface = '/run/user/1000/vinix-hosted-x11/calculator'
const authority = surface + '/Xauthority'
const ready = 'VINIX WIN64 CALCULATOR READY\n'

// A root-tree snapshot may contain a window destroyed before its property
// query. Treat only that X11 race as an absent window; other errors still
// fail the observer. Wine's independently executing Xlib is unaffected.
fn observer_x_error(_ &C.Display, event &C.XErrorEvent) i32 {
	if event.error_code == 3 { return 0 } // BadWindow
	eprintln('WINE GUI FAIL unexpected X11 error ' + event.error_code.str())
	C._exit(1)
	return 0
}

fn drop_identity() ! {
	if C.setgroups(0, unsafe { nil }) != 0 || C.setresgid(1000, 1000, 1000) != 0
		|| C.setresuid(1000, 1000, 1000) != 0 || os.geteuid() != 1000 || os.getegid() != 1000 {
		return error('ordinary identity failed')
	}
	os.setenv('HOME', '/home/alex', true)
	os.unsetenv('VINIX_ALLOW_WX')
}

fn command(args []string, input string) !string {
	mut child := os.new_process(args[0])
	defer { child.close() }
	child.set_args(args[1..]); child.set_redirect_stdio_merged(); child.run()
	if input != '' { child.stdin_write(input) }
	C.close(child.stdio_fd[0]); child.stdio_fd[0] = -1
	text := child.stdout_slurp()
	child.wait()
	if child.code != 0 { return error('command failed: ' + text) }
	return text
}

fn nonblocking(mut child os.Process) ! {
	C.close(child.stdio_fd[0]); child.stdio_fd[0] = -1
	fd := child.stdio_fd[1]
	flags := C.fcntl(fd, C.F_GETFL)
	if flags < 0 || C.fcntl(fd, C.F_SETFL, flags | C.O_NONBLOCK) < 0 { return error('nonblocking pipe failed') }
}

fn drain(mut child os.Process, mut bytes []u8) ! {
	mut buffer := [4096]u8{}
	for {
		n := C.read(child.stdio_fd[1], &buffer[0], uint(buffer.len))
		if n <= 0 { break }
		if bytes.len + int(n) > 1024 * 1024 { return error('child log exceeds bound') }
		for i in 0 .. int(n) { bytes << buffer[i] }
	}
}

fn failure_snapshot() {
	for name in os.ls('/proc') or { []string{} } {
		text := os.read_file('/proc/' + name + '/cmdline') or { continue }
		defer { unsafe { text.free() } }
		eprintln('WINE GUI DIAGNOSTIC process ' + name + ' ' + text.replace('\x00', ' '))
		for file in ['status', 'stat', 'wchan'] {
			status := os.read_file('/proc/' + name + '/' + file) or { continue }
			eprintln('WINE GUI DIAGNOSTIC ' + file + ' ' + status)
			unsafe { status.free() }
		}
	}
	display := C.XOpenDisplay(c':71')
	if display == unsafe { nil } { return }
	defer { C.XCloseDisplay(display) }
	mut root := u64(0); mut parent := u64(0); mut children := &u64(unsafe { nil }); mut count := u32(0)
	if C.XQueryTree(display, C.XDefaultRootWindow(display), &root, &parent, &children, &count) == 0 { return }
	defer { if children != unsafe { nil } { C.XFree(children) } }
	for i in 0 .. int(count) {
		if i >= 1024 { break }
		window := unsafe { children[i] }
		mut name := &char(unsafe { nil }); mut info := C.XWindowAttributes{}
		C.XGetWindowAttributes(display, window, &info)
		if C.XFetchName(display, window, &name) != 0 && name != unsafe { nil } {
			eprintln('WINE GUI DIAGNOSTIC window ' + window.str() + ' name=' + unsafe { cstring_to_vstring(name) }
				+ ' state=' + info.map_state.str() + ' geometry=' + info.width.str() + 'x' + info.height.str())
			C.XFree(name)
		} else { eprintln('WINE GUI DIAGNOSTIC unnamed window ' + window.str() + ' state=' + info.map_state.str() + ' geometry=' + info.width.str() + 'x' + info.height.str()) }
	}
}

fn wait_marker(mut child os.Process, mut bytes []u8, marker string) ! {
	deadline := time.sys_mono_now() + 120 * time.second
	for {
		drain(mut child, mut bytes)!
		if unsafe { tos(bytes.data, bytes.len) }.contains(marker) { return }
		if !child.is_alive() || time.sys_mono_now() > deadline {
			eprintln('WINE GUI DIAGNOSTIC observer child pid=' + child.pid.str() + ' code=' + child.code.str() + ' alive=' + child.is_alive().str())
			failure_snapshot()
			return error('missing ' + marker + ': ' + unsafe { tos(bytes.data, bytes.len) })
		}
		time.sleep(20 * time.millisecond)
	}
}

fn calculator_title(display &C.Display, window u64) bool {
	mut kind := u64(0); mut format := i32(0); mut count := u64(0); mut remaining := u64(0)
	mut data := &u8(unsafe { nil })
	utf8 := C.XInternAtom(display, c'UTF8_STRING', 0)
	status := C.XGetWindowProperty(display, window, C.XInternAtom(display, c'_NET_WM_NAME', 0),
		0, 64, 0, utf8, &kind, &format, &count, &remaining, &data)
	defer { if data != unsafe { nil } { C.XFree(data) } }
	if status == 0 && kind == utf8 && format == 8 && count == 10 && remaining == 0 && data != unsafe { nil }
		&& unsafe { tos(data, 10) } == 'Calculator' { return true }
	mut name := &char(unsafe { nil })
	if C.XFetchName(display, window, &name) == 0 || name == unsafe { nil } { return false }
	defer { C.XFree(name) }
	return unsafe { cstring_to_vstring(name) } == 'Calculator'
}

fn calculator_window(display &C.Display) !u64 {
	mut root := u64(0); mut parent := u64(0); mut children := &u64(unsafe { nil }); mut count := u32(0)
	if C.XQueryTree(display, C.XDefaultRootWindow(display), &root, &parent, &children, &count) == 0
		|| count > 1024 { return error('X11 root query failed') }
	defer { if children != unsafe { nil } { C.XFree(children) } }
	mut found := u64(0)
	for i in 0 .. int(count) {
		window := unsafe { children[i] }
		if calculator_title(display, window) {
				mut attributes := C.XWindowAttributes{}
				if C.XGetWindowAttributes(display, window, &attributes) != 0 && attributes.map_state == 2 {
					if found != 0 { return error('multiple mapped calculator windows') }
					found = window
				}
		}
	}
	return found
}

fn capture(display &C.Display, window u64, name string) ! {
	C.XSync(display, 0)
	mut info := C.XWindowAttributes{}
	if C.XGetWindowAttributes(display, window, &info) == 0 || info.width < 300 || info.width > 400
		|| info.height < 350 || info.height > 500 { return error('calculator window geometry differs') }
	image := C.XGetImage(display, window, 0, 0, u32(info.width), u32(info.height), ~u64(0), 2)
	if image == unsafe { nil } { return error('X11 window capture failed') }
	defer { C.XDestroyImage(image) }
	mut rgb := []u8{len: int(info.width) * int(info.height) * 3}
	defer { unsafe { rgb.free() } }
	for y in 0 .. int(info.height) {
		for x in 0 .. int(info.width) {
			pixel := C.XGetPixel(image, i32(x), i32(y))
			at := (y * int(info.width) + x) * 3
			rgb[at] = u8(pixel >> 16); rgb[at + 1] = u8(pixel >> 8); rgb[at + 2] = u8(pixel)
		}
	}
	println(winegui.frame_line(name, int(info.width), int(info.height), rgb)!)
}

fn click(display &C.Display, window u64, index int) ! {
	mut info := C.XWindowAttributes{}
	if C.XGetWindowAttributes(display, window, &info) == 0 { return error('button window disappeared') }
	x := info.x + 16 + i32(index % 4) * 71 + 32 + 4
	y := info.y + 92 + i32(index / 4) * 70 + 30 + 24
	if C.XTestFakeMotionEvent(display, 0, x, y, 0) == 0 { return error('pointer motion failed') }
	C.XSync(display, 0)
	if C.XTestFakeButtonEvent(display, 1, 1, 0) == 0 { return error('pointer press failed') }
	C.XSync(display, 0); time.sleep(60 * time.millisecond)
	if C.XTestFakeButtonEvent(display, 1, 0, 0) == 0 { return error('pointer release failed') }
	C.XSync(display, 0); time.sleep(100 * time.millisecond)
}

fn observe() ![]string {
	mut found := []string{}
	mut client := false; mut server := false
	for name in os.ls('/proc')! {
		text := os.read_file('/proc/' + name + '/cmdline') or { continue }
		defer { unsafe { text.free() } }
		if !text.contains('/apps/org.vinix.wine-runtime/root/usr/libexec/vinix-wine/wine') { continue }
		status := os.read_file('/proc/' + name + '/status')!
		defer { unsafe { status.free() } }
		mut credentials := 0
		for line in status.split_into_lines() {
			if line.starts_with('Uid:') || line.starts_with('Gid:') {
				fields := line.fields()
				if fields.len != 5 || fields[1..] != ['1000', '1000', '1000', '1000'] { return error('privileged Wine process') }
				credentials++
			}
		}
		if credentials != 2 { return error('Wine process credentials missing') }
		client = client || text.contains('/vinix-wine/wine\x00')
		server = server || text.contains('/vinix-wine/wineserver\x00')
		found << name.clone()
	}
	if !client || !server { return error('ordinary Wine client/server pair missing') }
	return found
}

fn launch_refusal() ! {
	mut child := os.new_process('/usr/bin/vinix-package')
	defer { if child.is_alive() { child.signal_kill(); child.wait() }; child.close() }
	child.set_args(['run', app]); child.set_redirect_stdio_merged(); child.run(); nonblocking(mut child)!
	mut bytes := []u8{cap: 4096}
	defer { unsafe { bytes.free() } }
	deadline := time.sys_mono_now() + 10 * time.second
	for child.is_alive() {
		drain(mut child, mut bytes)!
		if time.sys_mono_now() > deadline { return error('display refusal did not terminate') }
		time.sleep(20 * time.millisecond)
	}
	child.wait(); drain(mut child, mut bytes)!
	text := unsafe { tos(bytes.data, bytes.len) }
	if child.code == 0 || !text.contains('graphical launch requires an authenticated private display')
		|| text.contains(ready) { return error('display admission did not refuse: ' + text) }
}

fn ordinary() ! {
	drop_identity()!
	fd := x11auth.open_surface(c'/', surface.str, 1000, 0, true)
	if fd < 0 { return error('private surface failed') }
	defer { C.unlinkat(fd, c'Xauthority', 0); C.close(fd); os.rmdir(surface) or {} }
	if !x11auth.create_authority(fd, c':71') { return error('private authority failed') }
	os.setenv('DISPLAY', ':71', true); os.setenv('XAUTHORITY', authority, true)
	os.setenv('XKB_CONFIG_ROOT', '/usr/share/X11/xkb', true)
	mut server := os.new_process('/usr/bin/Xvfb')
	defer { if server.is_alive() { server.signal_term(); server.wait() }; server.close() }
	server.set_args([':71', '-screen', '0', '800x600x24', '-auth', authority, '-nolisten', 'tcp', '-noreset',
		'-extension', 'MIT-SHM', '-fp', '/usr/share/fonts/misc'])
	server.set_redirect_stdio_merged(); server.run(); nonblocking(mut server)!
	mut server_log := []u8{cap: 4096}
	deadline := time.sys_mono_now() + 20 * time.second
	for !x11auth.admit(c'/', authority.str, c':71', 1000, 0) {
		drain(mut server, mut server_log)!
		if !server.is_alive() || time.sys_mono_now() > deadline { return error('Xvfb startup failed: ' + server_log.bytestr()) }
		time.sleep(20 * time.millisecond)
	}
	// Socket publication precedes Xvfb's completed font/keyboard startup.
	// Keep the same authenticated endpoint and bound the readiness wait.
	mut display := C.XOpenDisplay(c':71')
	for display == unsafe { nil } {
		drain(mut server, mut server_log)!
		if !server.is_alive() || time.sys_mono_now() > deadline {
			return error('authenticated X11 connection failed: ' + server_log.bytestr())
		}
		time.sleep(20 * time.millisecond)
		display = C.XOpenDisplay(c':71')
	}
	defer { C.XCloseDisplay(display) }
	println('WINE GUI authenticated ordinary display PASS')
	previous_handler := C.XSetErrorHandler(observer_x_error)
	defer { C.XSync(display, 0); C.XSetErrorHandler(previous_handler) }
	os.unsetenv('XAUTHORITY'); launch_refusal()!
	os.setenv('XAUTHORITY', authority, true); os.setenv('DISPLAY', ':72', true); launch_refusal()!
	os.setenv('DISPLAY', ':71', true)
	println('WINE GUI missing-authority mismatched-display refusals PASS')
	mut child := os.new_process('/usr/bin/vinix-package')
	defer { if child.is_alive() { child.signal_kill(); child.wait() }; child.close() }
	child.set_args(['run', app]); child.set_redirect_stdio_merged(); child.run(); nonblocking(mut child)!
	mut output := []u8{cap: 16384}
	wait_marker(mut child, mut output, ready)!
	pids := observe()!
	lease := C.open(c'/var/lib/vinix-packages/generations/1/lease', C.O_RDONLY | C.O_CLOEXEC)
	if lease < 0 { return error('generation lease missing') }
	defer { C.close(lease) }
	if C.flock(lease, C.LOCK_EX | C.LOCK_NB) == 0 { return error('live calculator lease is free') }
	mut window := calculator_window(display)!
	window_deadline := time.sys_mono_now() + 10 * time.second
	for window == 0 {
		drain(mut child, mut output)!
		if !child.is_alive() || time.sys_mono_now() > window_deadline {
			failure_snapshot()
			return error('mapped calculator window missing: ' + output.bytestr())
		}
		time.sleep(20 * time.millisecond)
		window = calculator_window(display)!
	}
	time.sleep(200 * time.millisecond)
	capture(display, window, 'before')!
	for index in [8, 10, 15, 9, 2, 14]! { click(display, window, index)! } // 13+29=42.
	wait_marker(mut child, mut output, 'VINIX WIN64 CALCULATOR RESULT 42\n')!
	capture(display, window, 'after')!
	mut event := C.XEvent{}
	event.xclient.@type = 33; event.xclient.window = window
	event.xclient.message_type = C.XInternAtom(display, c'WM_PROTOCOLS', 0)
	event.xclient.format = 32; event.xclient.data.l[0] = i64(C.XInternAtom(display, c'WM_DELETE_WINDOW', 0))
	if C.XSendEvent(display, window, 0, 0, &event) == 0 { return error('WM_DELETE_WINDOW failed') }
	C.XSync(display, 0)
	wait_marker(mut child, mut output, 'VINIX WIN64 CALCULATOR CLOSED\n')!
	exit_deadline := time.sys_mono_now() + 20 * time.second
	for child.is_alive() {
		if time.sys_mono_now() > exit_deadline { return error('calculator did not exit naturally') }
		time.sleep(20 * time.millisecond)
	}
	child.wait(); drain(mut child, mut output)!
	println(output.bytestr())
	if child.code != 0 { return error('calculator exit status differs') }
	for marker in [ready, 'VINIX WIN64 CALCULATOR RESULT 42\n', 'VINIX WIN64 CALCULATOR CLOSED\n']! {
		if output.bytestr().count(marker) != 1 { return error('calculator marker missing or duplicated') }
	}
	if calculator_window(display)! != 0 { return error('closed calculator remains mapped') }
	// PID1 assists detached-server reaping after this ordinary observer retires.
	println('WINE GUI Windows pointer arithmetic close ordinary lease PASS')
	for pid in pids { println('WINE GUI RETIRE ' + pid) }
}

fn run() ! {
	$if wine_gui_numeric_hostname ? {
		if C.sethostname(c'127.0.0.1', 9) != 0 { return error('diagnostic numeric hostname failed') }
		println('WINE GUI DIAGNOSTIC numeric hostname; not ordinary-host qualification')
	}
	os.setenv('PATH', '/usr/sbin:/usr/bin:/sbin:/bin', true)
	for directory in ['/tmp', '/run/user', '/root', '/home', '/var/log'] { os.mkdir_all(directory)! }
	os.chmod('/tmp', 0o1777)!
	os.write_file('/etc/passwd', 'root:x:0:0:root:/root:/bin/sh\n')!
	os.write_file('/etc/group', 'root:x:0:\n')!
	command(['/usr/sbin/vinix-account', 'init'], '')!
	command(['/usr/sbin/vinix-account', 'add', 'alex', 'Alex', 'standard'], 'Wine GUI qualification password\n')!
	os.mkdir_all('/run/user/1000')!; os.chmod('/run/user/1000', 0o700)!
	if C.chown(c'/run/user/1000', 1000, 1000) != 0 { return error('account run directory failed') }
	sockets := x11auth.prepare_socket_parent(c'/', 0)
	if sockets < 0 { return error('X11 socket parent failed') }
	C.close(sockets)
	mut child := os.new_process('/sbin/init')
	defer { child.close() }
	child.set_args(['--ordinary']); child.run(); child.wait()
	if child.code != 0 { return error('ordinary GUI observer failed') }
	deadline := time.sys_mono_now() + 20 * time.second
	for {
		mut status := i32(0)
		for C.waitpid(-1, &status, C.WNOHANG) > 0 {}
		mut alive := false
		for name in os.ls('/proc')! {
			text := os.read_file('/proc/' + name + '/cmdline') or { continue }
			alive = alive || text.contains('/apps/org.vinix.wine-runtime/root/usr/libexec/vinix-wine/wine')
			unsafe { text.free() }
		}
		if !alive { break }
		if time.sys_mono_now() > deadline { return error('Wine processes did not retire') }
		time.sleep(20 * time.millisecond)
	}
	lease := C.open(c'/var/lib/vinix-packages/generations/1/lease', C.O_RDONLY | C.O_CLOEXEC)
	if lease < 0 || C.flock(lease, C.LOCK_EX | C.LOCK_NB) != 0 { return error('retired GUI lease is busy') }
	C.close(lease)
	if os.exists(authority) || os.exists('/tmp/.X11-unix/X71') { return error('GUI service left authority or socket') }
	println('HWTEST PASS packaged-Wine-GUI')
}

fn main() {
	if os.args.len == 2 && os.args[1] == '--ordinary' {
		ordinary() or { eprintln('WINE GUI FAIL ' + err.msg()); exit(1) }; return
	}
	console := $if arm64 { '/dev/console' } $else { '/dev/com1' }
	fd := C.open(console.str, C.O_WRONLY)
	if fd >= 0 { C.dup2(fd, 1); C.dup2(fd, 2); if fd > 2 { C.close(fd) } }
	run() or { eprintln('HWTEST FAIL packaged-Wine-GUI: ' + err.msg()) }
	for { time.sleep(time.second) }
}
