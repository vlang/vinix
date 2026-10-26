// SPDX-License-Identifier: GPL-2.0-or-later
module winecurrent

import crypto.sha256
import os

// This diagnostic runs on a trusted host with stopped input writers. Path
// rechecks detect changes; they do not promise hostile rename-race exclusion.
pub struct Identity {
pub:
	device u64
	inode u64
	mode u32
	links u64
	uid u32
	gid u32
	bytes u64
	mtime i64
	ctime i64
}

pub struct Selection {
pub:
	path string
	digest string
	identity Identity
}

pub struct Staged {
pub:
	path string
	previous_digest string
	selected_digest string
	identity Identity
}

pub fn requested(arguments []string) !bool {
	if arguments.len == 7 && arguments[1] in ['process', 'metadata', 'server'] { return false }
	if arguments.len == 9 && arguments[1] == 'server' { return true }
	return error('usage: wine-startup-check process|metadata|server OUTPUT KERNEL EXTRAS_OR_DASH SYSROOT GCC_RUNTIME [CURRENT_CLI EXPECTED_SHA256 (server only)]')
}

fn identity(path string) !Identity {
	st := os.lstat(path)!
	if st.get_filetype() != .regular || st.nlink != 1 || st.size < 64
		|| st.size > 64 * 1024 * 1024 || st.mode & 0o111 == 0 || st.mode & 0o6000 != 0 {
		return error('current CLI must be a bounded ordinary executable without special mode bits')
	}
	return Identity{st.dev, st.inode, st.mode, st.nlink, st.uid, st.gid, st.size, st.mtime, st.ctime}
}

fn valid_digest(value string) bool {
	if value.len != 64 { return false }
	for character in value {
		if !(character >= `0` && character <= `9`) && !(character >= `a` && character <= `f`) { return false }
	}
	return true
}

fn read_cli(path string, expected string, captured Identity) ![]u8 {
	if identity(path)! != captured { return error('current CLI identity changed') }
	bytes := os.read_bytes(path)!
	mut accepted := false
	defer { if !accepted { unsafe { bytes.free() } } }
	if u64(bytes.len) != captured.bytes || identity(path)! != captured {
		return error('current CLI changed while reading')
	}
	// Header filter for little-endian ELF64 ET_EXEC, not full ELF validation.
	if bytes[0] != 0x7f || bytes[1] != `E` || bytes[2] != `L` || bytes[3] != `F`
		|| bytes[4] != 2 || bytes[5] != 1
		|| bytes[6] != 1 || bytes[16] != 2 || bytes[17] != 0
		|| bytes[18] != 62 || bytes[19] != 0 {
		return error('current CLI must be an x86_64 ELF executable')
	}
	digest := sha256.sum(bytes).hex()
	defer { unsafe { digest.free() } }
	if digest != expected { return error('current CLI digest mismatch') }
	accepted = true
	return bytes
}

pub fn admit(path string, expected string) !Selection {
	if !os.is_abs_path(path) || path.contains('\x00') || !valid_digest(expected) {
		return error('current CLI requires an absolute path and lowercase SHA-256')
	}
	captured := identity(path)!
	bytes := read_cli(path, expected, captured)!
	unsafe { bytes.free() }
	return Selection{path.clone(), expected.clone(), captured}
}

pub fn recheck(selection Selection) ! {
	bytes := read_cli(selection.path, selection.digest, selection.identity)!
	unsafe { bytes.free() }
}

fn target_path(root string) !string {
	if !os.is_abs_path(root) { return error('CLI staging root must be absolute') }
	for suffix in ['', '/usr', '/usr/bin'] {
		path := root + suffix
		defer { unsafe { path.free() } }
		if os.lstat(path)!.get_filetype() != .directory {
			return error('CLI staging ancestry must contain ordinary directories')
		}
	}
	return root + '/usr/bin/vinix-package'
}

pub fn stage(selection Selection, root string) !Staged {
	path := target_path(root)!
	mut accepted := false
	defer { if !accepted { unsafe { path.free() } } }
	previous := identity(path)!
	if previous.device == selection.identity.device && previous.inode == selection.identity.inode {
		return error('CLI staging must not overwrite the selected input')
	}
	old_bytes := os.read_bytes(path)!
	defer { unsafe { old_bytes.free() } }
	previous_digest := sha256.sum(old_bytes).hex()
	defer { if !accepted { unsafe { previous_digest.free() } } }
	bytes := read_cli(selection.path, selection.digest, selection.identity)!
	defer { unsafe { bytes.free() } }
	if identity(path)! != previous { return error('CLI staging target changed before replacement') }
	os.write_file_array(path, bytes)!
	current := identity(path)!
	if current.device != previous.device || current.inode != previous.inode || current.mode != previous.mode
		|| current.uid != previous.uid || current.gid != previous.gid {
		return error('CLI staging changed target identity or permissions')
	}
	installed := read_cli(path, selection.digest, current)!
	unsafe { installed.free() }
	recheck(selection)!
	accepted = true
	return Staged{path, previous_digest, selection.digest.clone(), current}
}

pub fn verify_staged(selection Selection, staged Staged, root string) ! {
	recheck(selection)!
	path := target_path(root)!
	defer { unsafe { path.free() } }
	if path != staged.path || staged.selected_digest != selection.digest {
		return error('staged CLI selection differs')
	}
	bytes := read_cli(path, staged.selected_digest, staged.identity)!
	unsafe { bytes.free() }
}

pub fn close_selection(selection Selection) {
	unsafe { selection.path.free(); selection.digest.free() }
}

pub fn close_staged(staged Staged) {
	unsafe { staged.path.free(); staged.previous_digest.free(); staged.selected_digest.free() }
}
