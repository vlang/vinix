// SPDX-License-Identifier: GPL-2.0-or-later
module pkglaunch

import tools.packages.x11auth

fn C.setenv(&char, &char, int) int
fn C.unsetenv(&char) int

// The only forwarded display belongs to an ordinary account and to one fresh
// hosted surface. Filesystem admission below binds this syntax to the intended
// UID, private authority inode and exact owned X socket before any handoff.
fn (request &Request) validate_display_shape() ! {
	if request.format == 1 && request.display == '' && request.authority == '' { return }
	if request.format != 2 || request.arguments.len < 2 || request.arguments[0] !in ['run', 'run-args']
		|| request.display.len < 2 || request.display.len > 6 || request.display.contains('\x00')
		|| x11auth.display_number(&char(request.display.str)) < 0
		|| !request.authority.starts_with('/run/user/') || !request.authority.ends_with('/Xauthority')
		|| request.authority.len > 192 { return error('invalid isolated private display') }
	mut at := 10
	mut uid := u64(0)
	if at >= request.authority.len || request.authority[at] < `1` || request.authority[at] > `9` { return error('invalid isolated private display') }
	for at < request.authority.len && request.authority[at] >= `0` && request.authority[at] <= `9` {
		uid = uid * 10 + u64(request.authority[at] - `0`)
		if uid > 0xffff_ffff { return error('invalid isolated private display') }
		at++
	}
	prefix := '/vinix-hosted-x11/'
	if request.authority.len - at < prefix.len { return error('invalid isolated private display') }
	for index, byte in prefix { if request.authority[at + index] != byte { return error('invalid isolated private display') } }
	at += prefix.len
	length := request.authority.len - at - '/Xauthority'.len
	if length < 1 || length > 96 { return error('invalid isolated private display') }
	for index in at .. at + length {
		byte := request.authority[index]
		if !((byte >= `a` && byte <= `z`) || (byte >= `A` && byte <= `Z`) || (byte >= `0` && byte <= `9`) || byte == `-` || byte == `_`) {
			return error('invalid isolated private display')
		}
	}
}

pub fn (request &Request) validate_display(uid u32) ! {
	request.validate_display_shape()!
	if request.format == 1 { return }
	if uid == 0 || !x11auth.admit(c'/', &char(request.authority.str), &char(request.display.str), uid, 0) {
		return error('isolated launch requires the account private X11 authority and socket')
	}
}

// This is called only inside the account service's forked launch worker. The
// isolated package CLI validates the same paths again after shedding groups.
pub fn (request &Request) forward_display(uid u32) ! {
	request.validate_display(uid)!
	if request.format == 1 {
		if C.unsetenv(c'DISPLAY') != 0 || C.unsetenv(c'XAUTHORITY') != 0 { return error('cannot clear isolated display') }
	} else {
		if C.setenv(c'DISPLAY', &char(request.display.str), 1) != 0 || C.setenv(c'XAUTHORITY', &char(request.authority.str), 1) != 0 {
			return error('cannot forward isolated private display')
		}
	}
}
