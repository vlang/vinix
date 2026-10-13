// SPDX-License-Identifier: GPL-2.0-or-later
module qmpclient

import hosttest
import os
import net
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
	}
}
