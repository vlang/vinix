// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

import os
import net.unix
import tools.packages.appsdk
import tools.packages.x11auth

fn test_x11_launch_grants_only_the_authenticated_display_socket_and_authority() {
	root := '/tmp/vinix-x11-plan-' + os.getpid().str()
	os.mkdir(root)!
	os.chmod(root, 0o700)!
	defer { os.rmdir_all(root) or {} }
	uid := u32(C.geteuid())
	account := if uid == 0 { root + '/run' } else { root + '/run/user/' + uid.str() }
	os.mkdir_all(account)!
	os.chmod(account, 0o700)!
	prefix := root + '/'
	surface := account + '/vinix-hosted-x11/private'
	fd := x11auth.open_surface(prefix.str, surface.str, uid, uid, true)
	assert fd >= 0
	defer { C.close(fd) }
	assert x11auth.create_authority(fd, c':71')
	os.mkdir(root + '/tmp')!
	os.chmod(root + '/tmp', 0o1777)!
	sockets := x11auth.prepare_socket_parent(prefix.str, uid)
	assert sockets >= 0
	C.close(sockets)
	socket_path := root + '/tmp/.X11-unix/X71'
	mut socket := unix.listen_stream(socket_path, unix.ListenOptions{})!
	defer { socket.close() or {} }
	authority := surface + '/Xauthority'
	old_display := os.getenv('DISPLAY')
	old_authority := os.getenv('XAUTHORITY')
	defer { os.setenv('DISPLAY', old_display, true); os.setenv('XAUTHORITY', old_authority, true) }
	os.setenv('DISPLAY', ':71', true)
	os.setenv('XAUTHORITY', authority, true)
	mut args := []string{}
	launch_x11(mut args, int(uid), prefix, uid)!
	assert args == ['--unveil', socket_path, 'rw', '--unveil', authority, 'r',
		'--env', 'DISPLAY=:71', '--env', 'XAUTHORITY=' + authority]
	appsdk.free_values(mut args)
	for invalid in ['', root + '/ambient-authority', surface + '/../Xauthority'] {
		os.setenv('XAUTHORITY', invalid, true)
		if _ := launch_x11(mut args, int(uid), prefix, uid) { assert false }
		assert args.len == 0
	}
	os.setenv('XAUTHORITY', authority, true)
	for display in [':72', ':071', ':71.0', 'hostname:71'] {
		os.setenv('DISPLAY', display, true)
		if _ := launch_x11(mut args, int(uid), prefix, uid) { assert false }
		assert args.len == 0
	}
	os.setenv('DISPLAY', ':71', true)
	if _ := launch_x11(mut args, int(uid)+1, prefix, uid) { assert false }
	assert args.len == 0
	println('X11 LAUNCH PASS: exact socket/authority grants and explicit environment; ambient, foreign, missing and noncanonical display refusal before mutation')
}
