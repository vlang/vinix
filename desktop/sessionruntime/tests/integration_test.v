// SPDX-License-Identifier: GPL-2.0-or-later
module main

import desktop.sessionipc
import desktop.windowfb
import os

#include <unistd.h>

fn test_broker_and_framebuffer_share_numeric_defaults_despite_forged_xdg() {
	previous := os.getenv_opt('VINIX_SESSION_RUNTIME')
	xdg := os.getenv_opt('XDG_RUNTIME_DIR')
	os.unsetenv('VINIX_SESSION_RUNTIME')
	os.setenv('XDG_RUNTIME_DIR', '/tmp/forged-session-owner', true)
	defer {
		if value := previous { os.setenv('VINIX_SESSION_RUNTIME', value, true) }
		else { os.unsetenv('VINIX_SESSION_RUNTIME') }
		if value := xdg { os.setenv('XDG_RUNTIME_DIR', value, true) }
		else { os.unsetenv('XDG_RUNTIME_DIR') }
	}
	broker := sessionipc.session_runtime_directory()
	framebuffer := windowfb.runtime_directory()
	socket := windowfb.socket_path()
	defer { unsafe { broker.free() framebuffer.free() socket.free() } }
	assert broker == framebuffer
	assert socket == broker + '/windows'
	uid := C.getuid().str()
	defer { unsafe { uid.free() } }
	assert broker == if C.getuid() == 0 { '/run/vinix-session.0' }
		else { '/run/user/' + uid + '/vinix-session.' + uid }
}

fn test_default_framebuffer_connect_and_listen_refuse_replaced_private_directory() {
	base := '${os.temp_dir()}/vinix-runtime-socket-${os.getpid()}'
	previous := os.getenv_opt('VINIX_SESSION_RUNTIME')
	os.mkdir(base, mode: 0o700)!
	os.setenv('VINIX_SESSION_RUNTIME', base, true)
	directory := sessionipc.session_runtime_directory()
	socket := windowfb.socket_path()
	defer {
		if value := previous { os.setenv('VINIX_SESSION_RUNTIME', value, true) }
		else { os.unsetenv('VINIX_SESSION_RUNTIME') }
		os.rmdir_all(base) or {}
		unsafe { base.free() directory.free() socket.free() }
	}
	assert sessionipc.session_private_directory(directory)
	mut listener := windowfb.listen(socket)!
	defer { listener.close() }
	os.chmod(directory, 0o755)!
	if mut connected := windowfb.connect(socket) {
		connected.close()
		assert false, 'client connected through an insecure runtime directory'
	}
	assert sessionipc.session_connect() == none
	os.chmod(directory, 0o700)!
	mut connected := windowfb.connect(socket)!
	connected.close()
	unsafe { free(connected) }
	listener.close()
	os.rmdir(directory) or {
		// The listener's persistent lock is intentionally not unlinked on close.
		os.rm(socket + '.lock')!
		os.rmdir(directory)!
	}
	os.symlink(base, directory)!
	if mut replacement := windowfb.listen(socket) {
		replacement.close()
		assert false, 'listener accepted a replacement runtime symlink'
	}
	assert sessionipc.session_connect() == none
}
