// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os
import net.unix
import tools.packages.x11auth

fn C.geteuid() i32
fn C.close(int) int
fn C.umask(u32) u32

fn check() ! {
	root := '/tmp/vinix-x11-auth-' + os.getpid().str()
	os.mkdir(root)!
	os.chmod(root, 0o700)!
	defer { os.rmdir_all(root) or {} }
	uid := u32(C.geteuid())
	account := if uid == 0 { root + '/run' } else { root + '/run/user/' + uid.str() }
	os.mkdir_all(account)!
	os.chmod(account, 0o700)!
	prefix := root + '/'
	surface := account + '/vinix-hosted-x11/first'
	fd := x11auth.open_surface(prefix.str, surface.str, uid, uid, true)
	assert fd >= 0
	defer { C.close(fd) }
	assert x11auth.create_authority(fd, c':123')
	assert x11auth.authority_matches(fd, c':123', uid)
	assert !x11auth.authority_matches(fd, c':124', uid)
	assert !x11auth.authority_matches(fd, c':123', uid+1)
	assert !x11auth.create_authority(fd, c':123')
	assert x11auth.open_surface(prefix.str, surface.str, uid, uid, true) < 0
	for display in ['', ':', '::1', ':01', ':65536', ':1.0', 'unix:1', 'localhost:1', ':1;touch /tmp/bad'] {
		assert x11auth.display_number(display.str) < 0
	}
	for display in [':0', ':1', ':65535'] { assert x11auth.display_number(display.str) >= 0 }
	assert x11auth.open_surface(prefix.str, (surface+'/../other').str, uid, uid, true) < 0
	os.chmod(surface, 0o755)!
	assert x11auth.open_surface(prefix.str, surface.str, uid, uid, false) < 0
	os.chmod(surface, 0o700)!
	os.chmod(surface+'/Xauthority', 0o644)!
	assert !x11auth.authority_matches(fd, c':123', uid)
	os.chmod(surface+'/Xauthority', 0o600)!
	valid := os.read_bytes(surface+'/Xauthority')!
	assert valid.len == 47
	os.write_file_array(surface+'/Xauthority', valid[..valid.len-1])!
	assert !x11auth.authority_matches(fd, c':123', uid)
	os.write_file_array(surface+'/Xauthority', [...valid, u8(0)])!
	assert !x11auth.authority_matches(fd, c':123', uid)
	os.rm(surface+'/Xauthority')!
	os.symlink('/dev/zero', surface+'/Xauthority')!
	assert !x11auth.authority_matches(fd, c':123', uid)
	os.rm(surface+'/Xauthority')!
	assert !x11auth.authority_matches(fd, c':123', uid)
	assert x11auth.create_authority(fd, c':123')
	fresh := os.read_bytes(surface+'/Xauthority')!
	assert fresh[31..] != valid[31..]
	os.mkdir(root+'/tmp')!
	os.chmod(root+'/tmp', 0o1777)!
	assert x11auth.socket_parent(prefix.str, uid) < 0
	old_mask := C.umask(0)
	prepared := x11auth.prepare_socket_parent(prefix.str, uid)
	C.umask(old_mask)
	assert prepared >= 0
	C.close(prepared)
	assert os.stat(root+'/tmp/.X11-unix')!.mode & 0o1777 == 0o1777
	assert x11auth.prepare_socket_parent(prefix.str, uid+1) < 0
	mut socket := unix.listen_stream(root+'/tmp/.X11-unix/X123', unix.ListenOptions{})!
	defer { socket.close() or {} }
	authority := surface+'/Xauthority'
	assert x11auth.admit(prefix.str, authority.str, c':123', uid, uid)
	assert !x11auth.admit(prefix.str, authority.str, c':124', uid, uid)
	assert !x11auth.admit(prefix.str, authority.str, c':123', uid+1, uid)
	os.chmod(root+'/tmp/.X11-unix', 0o777)!
	assert !x11auth.admit(prefix.str, authority.str, c':123', uid, uid)
	assert x11auth.prepare_socket_parent(prefix.str, uid) < 0
	assert os.stat(root+'/tmp/.X11-unix')!.mode & 0o1777 == 0o777
	os.chmod(root+'/tmp/.X11-unix', 0o1777)!
	os.chmod(root+'/tmp', 0o777)!
	assert !x11auth.admit(prefix.str, authority.str, c':123', uid, uid)
	os.chmod(root+'/tmp', 0o1777)!
	os.rename(root+'/tmp/.X11-unix', root+'/tmp/real-sockets')!
	os.symlink(root+'/tmp/real-sockets', root+'/tmp/.X11-unix')!
	assert !x11auth.admit(prefix.str, authority.str, c':123', uid, uid)
	os.rm(root+'/tmp/.X11-unix')!
	os.rename(root+'/tmp/real-sockets', root+'/tmp/.X11-unix')!
	os.link(authority, surface+'/linked-authority')!
	assert !x11auth.admit(prefix.str, authority.str, c':123', uid, uid)
	os.rm(surface+'/linked-authority')!
	assert x11auth.admit(prefix.str, authority.str, c':123', uid, uid)
	for parent in [root, root+'/run', account, account+'/vinix-hosted-x11'] {
		original := os.stat(parent)!.mode & 0o777
		os.chmod(parent, 0o777)!
		assert !x11auth.admit(prefix.str, authority.str, c':123', uid, uid)
		os.chmod(parent, int(original))!
	}
	os.rename(surface, surface+'-moved')!
	os.symlink(surface+'-moved', surface)!
	assert x11auth.open_surface(prefix.str, surface.str, uid, uid, false) < 0
	os.rm(surface)!
	os.rename(surface+'-moved', surface)!
	os.chmod(account+'/vinix-hosted-x11', 0o777)!
	assert x11auth.open_surface(prefix.str, surface.str, uid, uid, false) < 0
	println('X11 AUTH PASS: fresh private surfaces, secure independent cookies, exact display/socket/identity, bounded malformed reads, safe sticky preparation, no existing/symlink/insecure surface adoption')
}

fn main() { check() or { eprintln(err); exit(1) } }
