// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
module security

import errno
import proc
import resource
import stat

pub const mac_label_name = 'security.vinix'

// Canonical decimal type IDs only. The three fixed kernel types cannot be
// forged through an on-disk label; malformed persisted labels deny access.
pub fn mac_parse_label(value []u8) ?u32 {
	if value.len < 1 || value.len > 2 || (value.len > 1 && value[0] == `0`) {
		errno.set(errno.einval); return none
	}
	mut kind := u32(0)
	for byte in value {
		if byte < `0` || byte > `9` { errno.set(errno.einval); return none }
		kind = kind * 10 + u32(byte - `0`)
	}
	if kind >= proc.mac_label_types { errno.set(errno.einval); return none }
	return kind
}

pub fn mac_object_type(mut res resource.Resource) ?u32 {
	mode := res.stat.mode
	if stat.ischr(mode) || stat.isblk(mode) { return proc.mac_device_type }
	if stat.issock(mode) || stat.isifo(mode) || mode & stat.ifmt == stat.ifpipe { return proc.mac_ipc_type }
	if !resource.has_xattrs(mut res) { return proc.mac_kernel_type }
	mut label := []u8{cap: 2} @[freed]
	label.flags |= .noslices
	defer { unsafe { label.free() } }
	resource.get_xattr(mut res, mac_label_name, mut label) or {
		if errno.get() == errno.enodata { return u32(0) }
		return none
	}
	return mac_parse_label(label) or { errno.set(errno.eacces); return none }
}

pub fn mac_require(mut res resource.Resource, access u32) ? {
	domain := proc.mac_current_domain()
	if domain == 0 { return }
	// Access to raw block storage would bypass every inode label on it.
	if stat.isblk(res.stat.mode) { errno.set(errno.eacces); return none }
	kind := mac_object_type(mut res)?
	if !proc.mac_allows(domain, kind, access) { errno.set(errno.eacces); return none }
}

pub fn mac_permitted(mut res resource.Resource, access u32) bool {
	mac_require(mut res, access) or { return false }
	return true
}

// New files receive their directory's label before the name is published.
// Zero is represented by an absent xattr, preserving the unconfigured boot.
pub fn mac_inherit(mut parent resource.Resource, mut child resource.Resource) ? {
	kind := mac_object_type(mut parent)?
	if kind == 0 { return }
	if kind >= proc.mac_label_types {
		if proc.mac_trusted() { return }
		errno.set(errno.eacces); return none
	}
	if stat.ischr(child.stat.mode) || stat.isblk(child.stat.mode) || stat.isifo(child.stat.mode) || stat.issock(child.stat.mode) { return }
	if !resource.has_xattrs(mut child) {
		errno.set(errno.eacces); return none
	}
	mut raw := [2]u8{}
	mut length := 1
	if kind >= 10 { raw[0] = u8(`0` + kind / 10); raw[1] = u8(`0` + kind % 10); length = 2 }
	else { raw[0] = u8(`0` + kind) }
	view := unsafe { (&raw[0]).vbytes(length) }
	resource.set_xattr(mut child, mac_label_name, view, 0)?
}
