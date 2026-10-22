// SPDX-License-Identifier: MIT
// Shared paths for the private session broker and framebuffer transport.
module sessionruntime

import os

#include <errno.h>
#include <sys/stat.h>
#include <unistd.h>

fn C.lstat(&char, &C.stat) int

fn directory_for(uid u32, base string, overridden bool) string {
	text := uid.str()
	defer { unsafe { text.free() } }
	if overridden { return base + '/vinix-session.' + text }
	if uid == 0 { return '/run/vinix-session.' + text }
	return '/run/user/' + text + '/vinix-session.' + text
}

// XDG_RUNTIME_DIR is application input. Session paths instead use the same
// numeric identity checked by the local socket peer policy.
pub fn directory() string {
	if base := os.getenv_opt('VINIX_SESSION_RUNTIME') {
		defer { unsafe { base.free() } }
		return directory_for(u32(C.getuid()), base, true)
	}
	return directory_for(u32(C.getuid()), '', false)
}

fn owned_directory(path string, uid u32, private bool) bool {
	mut info := &C.stat{}
	defer { unsafe { free(info) } }
	if unsafe { C.lstat(&char(path.str), info) } != 0 { return false }
	mask := if private { u32(0o077) } else { u32(0o022) }
	return u32(info.st_mode) & C.S_IFMT == C.S_IFDIR && u32(info.st_uid) == uid
		&& u32(info.st_mode) & mask == 0
}

fn ordinary_parents(run string, uid u32, system_uid u32) bool {
	users := run + '/user'
	text := uid.str()
	parent := users + '/' + text
	defer { unsafe { users.free() text.free() parent.free() } }
	return owned_directory(run, system_uid, false)
		&& owned_directory(users, system_uid, false)
		&& owned_directory(parent, uid, true)
}

fn trusted_parent(path string, uid u32) bool {
	if uid == 0 { return true }
	expected := directory_for(uid, '', false)
	defer { unsafe { expected.free() } }
	// Explicit development locations and private service log directories retain
	// their existing policy. Only the canonical ordinary runtime has this chain.
	return path != expected || (owned_directory('/', 0, false)
		&& ordinary_parents('/run', uid, 0))
}

// The account/session service creates /run/user/<uid> while privileged. Never
// create or repair those parents from an application, or follow a replacement
// symlink. Generic private directories keep the same leaf ownership policy.
pub fn private_directory(path string) bool {
	uid := u32(C.getuid())
	if !trusted_parent(path, uid) { return false }
	if unsafe { C.mkdir(&char(path.str), u32(0o700)) } != 0 && C.errno != C.EEXIST {
		return false
	}
	return owned_directory(path, uid, true)
}

// A caller can explicitly connect/listen elsewhere. The selected session
// socket always validates its private directory first, including for clients.
pub fn socket_directory(path string, name string) bool {
	parent := directory()
	expected := parent + '/' + name
	defer { unsafe { parent.free() expected.free() } }
	return path != expected || private_directory(parent)
}
