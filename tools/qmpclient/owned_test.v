// SPDX-License-Identifier: GPL-2.0-or-later
module qmpclient

import hosttest
import os
import net
import net.unix
import time

fn reject_connection() bool { return true }

fn test_failed_connections_retire_exact_descriptors() {
	root := hosttest.work_dir('', 'qmp-closed-')!
	defer { hosttest.remove_work_dir(root) or {} }
	path := root + '/refused'
	address := net.resolve_addrs(path, .unix, .tcp)![0]
	fd := C.socket(C.AF_UNIX, C.SOCK_STREAM, 0)
	assert fd >= 0
	assert C.bind(fd, voidptr(&address), address.len()) == 0
	assert C.close(fd) == 0
	assert os.exists(path)
	baseline := os.ls('/dev/fd')!.len
	for _ in 0 .. 100 {
		for candidate in [root + '/missing', path] {
			assert !socket_in_use(candidate, u64(time.sys_mono_now() + time.second), unsafe { nil })!
			mut failed := false
			connect_bounded(candidate, u64(time.sys_mono_now() + time.second), unsafe { nil }) or {
				failed = true
				assert err.code() == if candidate == path { C.ECONNREFUSED } else { C.ENOENT }
				Monitor{}
			}
			assert failed && os.ls('/dev/fd')!.len == baseline
		}
		mut failed := false
		connect_bounded(path, u64(time.sys_mono_now() + time.second), reject_connection) or {
			failed = true
			Monitor{}
		}
		assert failed && os.ls('/dev/fd')!.len == baseline
		mut probe_failed := false
		socket_in_use(path, u64(time.sys_mono_now() + time.second), reject_connection) or {
			probe_failed = true
			assert err.msg().contains('interrupted')
			false
		}
		assert probe_failed && os.ls('/dev/fd')!.len == baseline
	}
}

fn test_socket_probe_preserves_live_listener_without_a_protocol_exchange() {
	root := hosttest.work_dir('', 'qmp-listening-')!
	defer { hosttest.remove_work_dir(root) or {} }
	mut listener := unix.listen_stream(root + '/qmp')!
	defer { listener.close() or {} }
	baseline := os.ls('/dev/fd')!.len
	for _ in 0 .. 100 {
		assert socket_in_use(root + '/qmp', time.sys_mono_now() + u64(time.second), unsafe { nil })!
		mut accepted := listener.accept()!
		accepted.close()!
		assert os.exists(root + '/qmp')
		assert os.ls('/dev/fd')!.len == baseline
	}
}

fn test_socket_probe_preserves_access_errors() {
	if os.geteuid() == 0 { return }
	root := hosttest.work_dir('', 'qmp-inaccessible-')!
	defer { hosttest.remove_work_dir(root) or {} }
	os.mkdir(root + '/private', mode: 0o700)!
	mut listener := unix.listen_stream(root + '/private/qmp')!
	defer { listener.close() or {} }
	os.chmod(root + '/private', 0)!
	defer { os.chmod(root + '/private', 0o700) or {} }
	mut refused := false
	socket_in_use(root + '/private/qmp', time.sys_mono_now() + u64(time.second), unsafe { nil }) or {
		refused = true
		assert err.code() == C.EACCES, err.msg()
		false
	}
	assert refused, 'an inaccessible socket is not evidence of an inactive listener'
}
