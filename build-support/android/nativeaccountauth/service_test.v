module nativeaccountauth

import time

fn C.socketpair(i32, i32, i32, &i32) i32

fn service_frame() string {
	return service_header + '\tcom.example.auth\tcom.example.auth.Outer$Service\tcom.example.AUTH\t' + 'a'.repeat(64) + '\n'
}

fn test_service_frame_is_one_bounded_exact_selector() {
	frame := service_frame()
	launch := parse_service_frame(frame)!
	assert launch.package_name == 'com.example.auth'
	assert launch.service == 'com.example.auth.Outer$Service'
	assert launch.action == 'com.example.AUTH'
	assert launch.apk_sha256 == 'a'.repeat(64)
	for bad in ['', frame.trim_right('\n'), frame + frame, frame + 'x', frame.replace('\n', '\r\n'),
		frame.replace(service_header, 'vinix-android-service-host-v2'), frame.replace('com.example.auth\t', 'auth\t'),
		frame.replace('com.example.AUTH', 'com.example.$AUTH'), frame.replace('a'.repeat(64), 'A'.repeat(64)),
		frame.replace('com.example.AUTH', 'com.example.AUTH\x00'), 'x'.repeat(max_service_frame) + '\n'] {
		mut rejected := false
		parse_service_frame(bad) or { rejected = true }
		assert rejected
	}
}

fn test_service_frame_socket_rejects_trailing_data_and_closed_controller() {
	for content in [service_frame(), service_frame() + 'x', service_frame() + service_frame()] {
		mut sockets := [2]i32{}
		assert C.socketpair(C.AF_UNIX, C.SOCK_STREAM, 0, &sockets[0]) == 0
		assert C.send(sockets[1], content.str, usize(content.len), 0) == content.len
		mut rejected := false
		result := read_service_frame(sockets[0]) or { rejected = true; '' }
		assert rejected == (content != service_frame())
		if !rejected { assert result == service_frame() }
		C.close(sockets[0])
		C.close(sockets[1])
	}
	mut sockets := [2]i32{}
	assert C.socketpair(C.AF_UNIX, C.SOCK_STREAM, 0, &sockets[0]) == 0
	frame := service_frame()
	assert C.send(sockets[1], frame.str, usize(frame.len), 0) == frame.len
	C.close(sockets[1])
	mut rejected := false
	read_service_frame(sockets[0]) or { rejected = true }
	assert rejected
	C.close(sockets[0])
}

fn test_service_role_requires_a_root_peer_and_selected_current_identity() {
	mut sockets := [2]i32{}
	assert C.socketpair(C.AF_UNIX, C.SOCK_STREAM, 0, &sockets[0]) == 0
	defer { C.close(sockets[0]); C.close(sockets[1]) }
	mut rejected := false
	verify_root_channel(sockets[0]) or { rejected = true }
	assert rejected == (C.getuid() != 0)
	for uid in [u32(0), 9999, 20000] {
		mut bad_identity := false
		verify_service_frame(sockets[0], Registry{}, '/missing.apk', uid, uid) or { bad_identity = true }
		assert bad_identity
	}
}

fn test_partial_service_frame_has_one_monotonic_deadline() {
	mut sockets := [2]i32{}
	assert C.socketpair(C.AF_UNIX, C.SOCK_STREAM, 0, &sockets[0]) == 0
	defer { C.close(sockets[0]); C.close(sockets[1]) }
	assert C.send(sockets[1], c'v', 1, 0) == 1
	started := time.sys_mono_now()
	mut rejected := false
	read_service_frame(sockets[0]) or { rejected = true }
	assert rejected
	assert time.sys_mono_now() - started < 10 * time.second
}
