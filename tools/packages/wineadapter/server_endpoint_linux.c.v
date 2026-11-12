// SPDX-License-Identifier: GPL-2.0-or-later
module wineadapter

import os

fn endpoint_info(fd i32) !C.stat {
	mut info := C.stat{}
	if C.fstat(fd, unsafe { &info }) != 0 || u32(info.st_mode) & 0o170000 != 0o140000
		|| u32(info.st_mode) & 0o7777 != 0o600 || info.st_nlink != 1
		|| u32(info.st_uid) != u32(C.geteuid()) || u32(info.st_gid) != u32(os.getegid()) {
		return error('Wine endpoint must be an account-owned single-link socket with mode 0600')
	}
	flags := C.vinix_wine_guard_fcntl(fd, C.F_GETFD)
	status := C.vinix_wine_guard_fcntl(fd, C.F_GETFL)
	if flags < 0 || flags & C.FD_CLOEXEC == 0 || status < 0 || status & C.O_PATH == 0 {
		return error('Wine endpoint needs a close-on-exec metadata-only descriptor')
	}
	return info
}

fn (server &ServerDirectory) capture_endpoint_linux(guard &LaunchGuard, data string) !ServerEndpoint {
	server.recheck(guard, data)!
	mut endpoint := ServerEndpoint{}
	mut accepted := false
	defer { if !accepted { endpoint.close() } }
	endpoint.directory = C.vinix_wine_guard_fcntl(server.directory, C.F_DUPFD_CLOEXEC, 3)
	if endpoint.directory < 0 { return error('cannot retain Wine endpoint directory') }
	endpoint.node = i32(C.openat(endpoint.directory, c'socket', C.O_PATH | C.O_NOFOLLOW | C.O_CLOEXEC))
	if endpoint.node < 0 { return error('cannot capture Wine endpoint without following links') }
	endpoint_info(endpoint.node)!
	endpoint.recheck_linux(server, guard, data)!
	accepted = true
	return endpoint
}

fn (endpoint &ServerEndpoint) recheck_linux(server &ServerDirectory, guard &LaunchGuard, data string) ! {
	server.recheck(guard, data)!
	held_directory := server_directory_info(endpoint.directory)!
	current_directory := server_directory_info(server.directory)!
	if held_directory.st_dev != current_directory.st_dev || held_directory.st_ino != current_directory.st_ino {
		return error('Wine endpoint belongs to a different server directory')
	}
	held_node := endpoint_info(endpoint.node)!
	current := i32(C.openat(server.directory, c'socket', C.O_PATH | C.O_NOFOLLOW | C.O_CLOEXEC))
	if current < 0 { return error('Wine endpoint path was replaced') }
	defer { C.close(current) }
	current_node := endpoint_info(current)!
	if held_node.st_dev != current_node.st_dev || held_node.st_ino != current_node.st_ino {
		return error('Wine endpoint identity changed')
	}
	server.recheck(guard, data)!
}
