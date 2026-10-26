// SPDX-License-Identifier: GPL-2.0-or-later
module browserlaunch

import net.unix
import os
import time

fn C.getpid() i32

fn test_lazy_channel_preserves_first_frame_and_marks_both_endpoints_cloexec() {
	pair := control_pair()!
	defer { C.close(pair[0]); C.close(pair[1]) }
	for fd in pair { assert C.fcntl(fd, C.F_GETFD) & C.FD_CLOEXEC != 0 }
	assert !await_command(pair[1], 0)!
	assert client_alive(pair[1])
	frame := 'VBR1-first-command'.bytes()
	assert C.write(pair[0], frame.data, usize(frame.len)) == frame.len
	assert await_command(pair[1], 0)!
	assert await_command(pair[1], 0)!
	mut received := []u8{len: frame.len}
	assert C.recv(pair[1], received.data, uint(received.len), C.MSG_DONTWAIT) == frame.len
	assert received == frame
	assert !await_command(pair[1], 0)!
	cloexec(pair[0], false)!
	assert C.fcntl(pair[0], C.F_GETFD) & C.FD_CLOEXEC == 0
	cloexec(pair[0], true)!
}

fn test_closed_client_cancels_even_with_queued_command() {
	for queued in [false, true] {
		// Production requires Linux: its HUP wins even with queued bytes.
		$if !linux { if queued { continue } }
		pair := control_pair()!
		if queued { assert C.write(pair[0], c'VBR1', 4) == 4 }
		C.close(pair[0])
		assert !client_alive(pair[1])
		mut rejected := false
		await_command(pair[1], 0) or { rejected = true }
		C.close(pair[1])
		assert rejected
	}
	cloexec(-1, true) or { return }
	assert false, 'invalid descriptor was accepted'
}

fn test_helper_environment_is_constructed_without_art_or_caller_authority() {
	config := Config{root: '/opt/browser', libraries: ['lib', 'usr/lib'], fontconfig: 'etc/fonts/fonts.conf'}
	os.setenv('LD_PRELOAD', '/opt/android/libcompat.so', true)
	os.setenv('WEBKIT_DISABLE_SANDBOX_THIS_IS_DANGEROUS', '1', true)
	defer { os.unsetenv('LD_PRELOAD'); os.unsetenv('WEBKIT_DISABLE_SANDBOX_THIS_IS_DANGEROUS') }
	env := config.browser_environment('/app/webview/session', '/app/webview', '123')
	assert env['DISPLAY'] == ':123' && env['GDK_BACKEND'] == 'x11'
	assert env['XAUTHORITY'] == '/app/webview/session/Xauthority'
	assert env['LD_LIBRARY_PATH'] == '/opt/browser/lib:/opt/browser/usr/lib'
	assert env['FONTCONFIG_FILE'] == '/opt/browser/etc/fonts/fonts.conf'
	assert env['XDG_CACHE_HOME'] == '/app/webview/cache'
	for forbidden in ['LD_PRELOAD', 'BIONIC_LD_LIBRARY_PATH', 'VINIX_ANDROID_WEBVIEW_FD',
		'VINIX_WS_INPUT_FD', 'VINIX_ANDROID_SERVICE_FD', 'DBUS_SESSION_BUS_ADDRESS',
		'GTK_PATH', 'WEBKIT_DISABLE_SANDBOX_THIS_IS_DANGEROUS'] {
		assert forbidden !in env
	}
}

fn test_private_directories_reject_permission_owner_and_symlink_bypasses() {
	base := os.real_path(os.temp_dir()) + '/vinix-browser-profile-${C.getpid()}'
	assert !os.exists(base)
	os.mkdir(base)!
	os.chmod(base, 0o700)!
	defer { os.rmdir_all(base) or {} }
	uid, gid := C.getuid(), os.stat(base)!.gid
	private_directory(base, uid, gid, false)!
	private_directory(base + '/child', uid, gid, true)!
	mut refused := false
	private_directory(base, uid + 1, gid, false) or { refused = true }
	assert refused
	os.chmod(base + '/child', 0o755)!
	refused = false
	private_directory(base + '/child', uid, gid, false) or { refused = true }
	assert refused
	os.symlink(base + '/child', base + '/link')!
	refused = false
	private_directory(base + '/link', uid, gid, false) or { refused = true }
	assert refused
	os.write_file(base + '/regular', '')!
	refused = false
	private_directory(base + '/regular', uid, gid, false) or { refused = true }
	assert refused
	// /tmp is shared and writable; a private leaf cannot authorize that ancestor.
	refused = false
	profile(base, uid, gid) or { refused = true }
	assert refused
}

fn test_xauthority_is_exclusive_private_and_contains_the_exact_cookie() {
	base := os.real_path(os.temp_dir()) + '/vinix-browser-auth-${C.getpid()}'
	os.mkdir(base)!
	os.chmod(base, 0o700)!
	defer { os.rmdir_all(base) or {} }
	cookie := []u8{len: 16, init: u8(index)}
	path := base + '/authority'
	authority(path, '123', cookie)!
	assert os.stat(path)!.mode & 0o7777 == 0o600
	assert os.read_bytes(path)! == authority_record('123', cookie)
	mut rejected := false
	authority(path, '123', cookie) or { rejected = true }
	assert rejected
	packet := setup_packet(cookie)
	assert packet.len == 48 && packet[0] == `l` && packet[2] == 11
	assert packet[12..30].bytestr() == 'MIT-MAGIC-COOKIE-1'
	assert packet[32..] == cookie
}

fn test_x11_rejects_wrong_kernel_peer_before_disclosing_cookie() {
	path := os.real_path(os.temp_dir()) + '/vinix-browser-peer-${C.getpid()}.sock'
	mut listener := unix.listen_stream(path, unix.ListenOptions{})!
	defer { listener.close() or {}; os.rm(path) or {} }
	mut rejected := false
	authenticated_socket(path, []u8{len: 16}, int(C.getpid()) + 1, C.getuid(), u32(C.getgid())) or {
		rejected = true
	}
	assert rejected
	mut connection := listener.accept()!
	defer { connection.close() or {} }
	mut probe := []u8{len: 1}
	// Peer rejection happens before any MIT cookie bytes are written.
	assert connection.read(mut probe) or { 0 } == 0
}

fn test_process_cleanup_terminates_and_reaps_the_child() {
	mut process := child('/bin/sleep', ['30'], map[string]string{})
	assert process.is_alive()
	started := time.sys_mono_now()
	stop(mut process)
	assert time.sys_mono_now() - started < u64(3 * time.second)
	assert process.status == .closed
	stop(mut process)
}

fn test_disabled_launch_never_creates_a_supervisor_or_descriptor() {
	mut config := Config{}
	assert config.launch()! == -1
	assert config.manifest_fd == -1 && config.root_fd == -1
}
