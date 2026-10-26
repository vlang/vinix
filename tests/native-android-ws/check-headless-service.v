// SPDX-License-Identifier: GPL-2.0-or-later
// Execute the production lifetime/channel helpers with deterministic syscall
// responses. This is a host contract check; the APK fixture supplies ART proof.
module main

import os

fn block(source string, name string) !string {
	start := source.index('fn ' + name + '(') or { return error('missing ' + name) }
	end := source[start..].index('\n}') or { return error('unclosed ' + name) }
	return source[start..start + end + 2]
}

fn before(source string, a string, b string) bool {
	x := source.index(a) or { return false }
	y := source.index(b) or { return false }
	return x < y
}

fn startup(entry string, service string, bootstrap string) bool {
	entry_main := block(entry, 'main') or { return false }
	launch := block(entry, 'service_launch') or { return false }
	host := block(service, 'ws_service_main') or { return false }
	run := block(service, 'ws_service_run') or { return false }
	shutdown := block(service, 'ws_service_shutdown') or { return false }
	if !before(entry_main, 'service_launch()', 'C.dlopen(')
		|| !before(launch, 'verify_service_frame(', 'C.FD_CLOEXEC')
		|| !before(host, 'ws_service_channel(control_fd)', 'ws_bootstrap(')
		|| !host.contains('ws_bootstrap(root, apk, false)')
		|| !before(host, 'ws_service_manifest(', 'ws_ensure_application(')
		|| !host.contains("C.getenv(c'ANDROID_APP_DATA_DIR')")
		|| !before(run, 'binder == nil', 'ANDROID-SERVICE-READY')
		|| !before(shutdown, "c'stopService'", "c'unbind'")
		|| !run.contains('ws_service_control(control_fd, 16)')
		|| !run.contains('state == 0') || !run.contains('state < 0')
		|| !run.contains('state_after == 0') || !run.contains('state_after < 0')
		|| !run.all_after('pop_frame(e)').contains('if ws_service_control(control_fd, 0) != 1')
		|| !host.contains('return ws_service_shutdown(e, loaded, binding, intent, application, callback, status)') {
		return false
	}
	for forbidden in ['ws_egl_init(', 'ws_draw_init(', 'ws_fonts_init(', 'ws_frames_init(',
		'vinixPerformCreate', "c'android/app/Activity'"] {
		if host.contains(forbidden) { return false }
	}
	for forbidden in ['ws_ensure_application(', 'ws_egl_init(', 'ws_draw_init(', 'vinixPerformCreate',
		"c'onCreate'"] {
		if bootstrap.contains(forbidden) { return false }
	}
	return true
}

fn main() {
	assert os.args.len in [1, 2], 'usage: check-headless-service [REPO]'
	repo := if os.args.len == 2 { os.real_path(os.args[1]) } else { os.getwd() }
	entry := os.read_file(repo + '/build-support/android/native-entry.v')!
	service := os.read_file(repo + '/build-support/android/nativews/headless.v')!
	bootstrap := os.read_file(repo + '/build-support/android/nativews/bootstrap.v')!
	assert startup(entry, service, bootstrap), 'headless startup contract'
	for mutation in [service.replace('ws_service_channel(control_fd)', 'true'),
		service.replace('ws_bootstrap(root, apk, false)', 'ws_bootstrap(root, apk, true)'),
		service.replace('ws_service_manifest(', 'unchecked_manifest('),
		service.replace('binder == nil', 'false'), service.replace('state < 0', 'false'),
		service.replace('state == 0', 'false'),
		service.replace("C.getenv(c'ANDROID_APP_DATA_DIR')", "C.getenv(c'UNSET_ENV')"),
		service.replace('return ws_service_shutdown(', 'return skipped_shutdown('),
		service.replace('state_after == 0', 'false'), service.replace('state_after < 0', 'false')] {
		assert mutation != service && !startup(entry, mutation, bootstrap)
	}
	assert !startup(entry.replace('service_launch()', 'unchecked_launch()'), service, bootstrap)
	assert !startup(entry, service, bootstrap + '\nws_ensure_application(e, loaded)')
	mut helpers := block(service, 'ws_service_control')! + '\n' + block(service, 'ws_service_channel')!
	for name in ['poll', 'recv', '__errno_location', 'getsockopt', 'getsockname', 'getpeername',
		'fcntl'] {
		helpers = helpers.replace('C.' + name, 'probe_' + name)
	}
	// Production uses the Linux ABI even though this executable runs on macOS.
	// Map only errno constants; the helper's literal Linux socket/flag values
	// are checked by the mock and retained in the separately compiled native DSO.
	helpers = helpers.replace('C.EINTR', '4').replace('C.EAGAIN', '11')
	work := os.join_path(os.temp_dir(), 'vinix-headless-check-' + os.getpid().str())
	assert !os.exists(work)
	os.mkdir_all(work)!
	defer { os.rmdir_all(work) or {} }
	os.write_file(work + '/main.v', probe_source + helpers + probe_cases)!
	compiler := os.getenv_opt('VINIX_V_COMPILER') or { 'v' }
	result := os.exec([compiler, '-w', '-enable-globals', '-cc', 'cc', 'run', work + '/main.v'])
	if result.exit_code != 0 { panic(result.output) }
	assert result.output.trim_space() == 'HEADLESS-CHANNEL-PASS cases=29'
	println(result.output.trim_space())
	println('HEADLESS-STARTUP-PASS trust-before-dlopen manifest-before-application binder-before-ready common-teardown no-display negative-mutations=12')
}

const probe_source = '
module main
#include <alloca.h>
#include <string.h>
fn C.alloca(u64) voidptr
fn C.memset(voidptr, int, u64) voidptr
struct C.sockaddr { sa_family u16 }
struct WsPoll { mut: fd i32 events i16 revents i16 }
struct WsNoticeAddress { mut: family u16 path [108]u8 }
struct WsServicePeer { mut: pid i32 uid u32 gid u32 }
struct Probe {
mut:
 poll_result i32 = 1
 recv_result int = -1
 error_code i32 = 11
 kind i32 = 1
 kind_size u32 = 4
 local_family u16 = 1
 remote_family u16 = 1
 local_size u32 = 110
 remote_size u32 = 110
 peer_pid i32 = 42
 peer_uid u32
 peer_size u32 = 12
 fail_sockopt int
 fail_local bool
 fail_remote bool
 get_flags i32
 set_error i32
 set_flags i32
 peek_count int
}
__global p = Probe{}
fn probe_poll(value voidptr, count int, timeout i32) i32 {
 unsafe {
  item := &WsPoll(value)
  assert count == 1 && item.fd == 7 && item.events == 1 && timeout in [0,16]
 }
 return p.poll_result
}
fn probe_recv(fd i32, data voidptr, count int, flags int) int {
 assert fd == 7 && data != unsafe { nil } && count == 1 && flags == 0x42
 p.peek_count++
 return p.recv_result
}
fn probe___errno_location() &i32 { return unsafe { &p.error_code } }
fn probe_getsockopt(fd i32, level int, option int, data voidptr, size &u32) i32 {
 assert fd == 7 && level == 1 && option in [3,17]
 if p.fail_sockopt == option { return -1 }
 unsafe {
  if option == 3 { *(&i32(data)) = p.kind; *size = p.kind_size }
  else { *(&WsServicePeer(data)) = WsServicePeer{p.peer_pid,p.peer_uid,0}; *size = p.peer_size }
 }
 return 0
}
fn probe_getsockname(fd i32, data voidptr, size &u32) i32 {
 assert fd == 7
 unsafe { (&WsNoticeAddress(data)).family = p.local_family; *size = p.local_size }
 return if p.fail_local { -1 } else { 0 }
}
fn probe_getpeername(fd i32, data voidptr, size &u32) i32 {
 assert fd == 7
 unsafe { (&WsNoticeAddress(data)).family = p.remote_family; *size = p.remote_size }
 return if p.fail_remote { -1 } else { 0 }
}
fn probe_fcntl(fd i32, op int, flags ...i32) i32 {
 assert fd == 7 && op in [1,2]
 if op == 1 { assert flags.len == 0; return p.get_flags }
 assert flags.len == 1
 p.set_flags = flags[0]
 return p.set_error
}
'

const probe_cases = '
fn main() {
 p = Probe{poll_result:0}; assert ws_service_control(7,16) == 1 && p.peek_count == 0
 p = Probe{poll_result:-1,error_code:4}; assert ws_service_control(7,16) == 1
 p = Probe{poll_result:-1,error_code:5}; assert ws_service_control(7,16) == -1
 p = Probe{recv_result:0}; assert ws_service_control(7,16) == 0
 p = Probe{recv_result:1}; assert ws_service_control(7,16) == -1
 p = Probe{error_code:11}; assert ws_service_control(7,16) == 1
 p = Probe{error_code:4}; assert ws_service_control(7,16) == 1
 p = Probe{error_code:88}; assert ws_service_control(7,16) == -1
 p = Probe{}; assert !ws_service_channel(2)
 p = Probe{}; assert ws_service_channel(7) && p.set_flags == 1 && p.peek_count == 1
 p = Probe{get_flags:8}; assert ws_service_channel(7) && p.set_flags == 9
 p = Probe{kind:2}; assert !ws_service_channel(7)
 p = Probe{kind_size:8}; assert !ws_service_channel(7)
 p = Probe{fail_sockopt:3}; assert !ws_service_channel(7)
 p = Probe{fail_local:true}; assert !ws_service_channel(7)
 p = Probe{fail_remote:true}; assert !ws_service_channel(7)
 p = Probe{local_size:1}; assert !ws_service_channel(7)
 p = Probe{local_size:111}; assert !ws_service_channel(7)
 p = Probe{remote_size:1}; assert !ws_service_channel(7)
 p = Probe{remote_size:111}; assert !ws_service_channel(7)
 p = Probe{local_family:2}; assert !ws_service_channel(7)
 p = Probe{remote_family:2}; assert !ws_service_channel(7)
 p = Probe{fail_sockopt:17}; assert !ws_service_channel(7)
 p = Probe{peer_size:16}; assert !ws_service_channel(7)
 p = Probe{peer_pid:0}; assert !ws_service_channel(7)
 p = Probe{peer_uid:10000}; assert !ws_service_channel(7)
 p = Probe{get_flags:-1}; assert !ws_service_channel(7)
 p = Probe{set_error:-1}; assert !ws_service_channel(7)
 p = Probe{recv_result:1}; assert !ws_service_channel(7)
 println("HEADLESS-CHANNEL-PASS cases=29")
}
'
