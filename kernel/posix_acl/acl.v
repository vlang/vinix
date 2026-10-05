// SPDX-License-Identifier: GPL-2.0-or-later
module posix_acl

pub const access_name = 'system.posix_acl_access'
pub const default_name = 'system.posix_acl_default'
pub const user_obj = u16(1)
pub const user = u16(2)
pub const group_obj = u16(4)
pub const group = u16(8)
pub const mask = u16(16)
pub const other = u16(32)
pub const undefined_id = u32(0xffffffff)

pub struct Entry {
pub:
	tag u16
	permissions u16
	id u32
}

pub fn is_name(name string) bool { return name == access_name || name == default_name }

fn le16(data []u8, offset int) u16 {
	return u16(data[offset]) | (u16(data[offset + 1]) << 8)
}

fn le32(data []u8, offset int) u32 {
	return u32(data[offset]) | (u32(data[offset + 1]) << 8)
		| (u32(data[offset + 2]) << 16) | (u32(data[offset + 3]) << 24)
}

pub fn entry(data []u8, index int) Entry {
	offset := 4 + index * 8
	return Entry{le16(data, offset), le16(data, offset + 2), le32(data, offset + 4)}
}

// Linux's userspace representation is version 2 with eight-byte entries.
// A header without entries denotes removal. IDs are sorted and unique so
// one identity never has ambiguous grants; named entries require a mask.
pub fn valid(data []u8) bool {
	if data.len < 4 || (data.len - 4) & 7 != 0 || le32(data, 0) != 2 { return false }
	if data.len == 4 { return true }
	mut stage := 0
	mut named := false
	mut previous_user := u32(0)
	mut previous_group := u32(0)
	mut users := 0
	mut groups := 0
	for i in 0 .. (data.len - 4) / 8 {
		current := entry(data, i)
		if current.permissions & ~u16(7) != 0 { return false }
		if current.tag == user || current.tag == group {
			if current.id == undefined_id { return false }
		} else if current.id != undefined_id { return false }
		match current.tag {
			user_obj { if stage != 0 { return false }; stage = 1 }
			user {
				if stage != 1 || (users > 0 && current.id <= previous_user) { return false }
				previous_user = current.id
				users++
				named = true
			}
			group_obj { if stage != 1 { return false }; stage = 2 }
			group {
				if stage != 2 || (groups > 0 && current.id <= previous_group) { return false }
				previous_group = current.id
				groups++
				named = true
			}
			mask { if stage != 2 { return false }; stage = 3 }
			other { if stage != 3 && !(stage == 2 && !named) { return false }; stage = 4 }
			else { return false }
		}
	}
	return stage == 4
}

// These operations consume validated, nonempty ACLs. The caller owns their
// byte buffers; evaluation and updates allocate nothing.
pub fn mode(data []u8, previous u32) (u32, bool) {
	mut permissions := u32(0)
	mut extended := false
	for i in 0 .. (data.len - 4) / 8 {
		current := entry(data, i)
		match current.tag {
			user_obj { permissions |= u32(current.permissions) << 6 }
			group_obj { permissions |= u32(current.permissions) << 3 }
			other { permissions |= u32(current.permissions) }
			mask { permissions = (permissions & ~u32(0o70)) | (u32(current.permissions) << 3); extended = true }
			user, group { extended = true }
			else {}
		}
	}
	return (previous & ~u32(0o777)) | permissions, extended
}

fn in_group(gid u32, primary u32, additional []u32) bool {
	if gid == primary { return true }
	for member in additional { if member == gid { return true } }
	return false
}

pub fn permits(data []u8, owner u32, owning_group u32, uid u32, gid u32,
	groups []u32, requested u32) bool {
	mut maximum := u32(7)
	for i in 0 .. (data.len - 4) / 8 {
		current := entry(data, i)
		if current.tag == mask { maximum = u32(current.permissions); break }
	}
	mut matched_group := false
	for i in 0 .. (data.len - 4) / 8 {
		current := entry(data, i)
		permissions := u32(current.permissions)
		match current.tag {
			user_obj { if uid == owner { return permissions & requested == requested } }
			user { if uid == current.id { return permissions & maximum & requested == requested } }
			group_obj, group {
				identity := if current.tag == group_obj { owning_group } else { current.id }
				if in_group(identity, gid, groups) {
					matched_group = true
					if permissions & maximum & requested == requested { return true }
				}
			}
			other { return !matched_group && permissions & requested == requested }
			else {}
		}
	}
	return false
}

fn put_permissions(mut data []u8, index int, permissions u16) {
	offset := 4 + index * 8 + 2
	data[offset] = u8(permissions)
	data[offset + 1] = u8(permissions >> 8)
}

pub fn chmod(mut data []u8, requested u32) {
	mut has_mask := false
	for i in 0 .. (data.len - 4) / 8 { if entry(data, i).tag == mask { has_mask = true } }
	for i in 0 .. (data.len - 4) / 8 {
		tag := entry(data, i).tag
		if tag == user_obj { put_permissions(mut data, i, u16((requested >> 6) & 7)) }
		if tag == other { put_permissions(mut data, i, u16(requested & 7)) }
		if tag == mask || (tag == group_obj && !has_mask) {
			put_permissions(mut data, i, u16((requested >> 3) & 7))
		}
	}
}

pub fn inherit(mut data []u8, requested u32) (u32, bool) {
	mut has_mask := false
	for i in 0 .. (data.len - 4) / 8 { if entry(data, i).tag == mask { has_mask = true } }
	for i in 0 .. (data.len - 4) / 8 {
		current := entry(data, i)
		mut allowed := u16(7)
		if current.tag == user_obj { allowed = u16((requested >> 6) & 7) }
		if current.tag == other { allowed = u16(requested & 7) }
		if current.tag == mask || (current.tag == group_obj && !has_mask) { allowed = u16((requested >> 3) & 7) }
		put_permissions(mut data, i, current.permissions & allowed)
	}
	return mode(data, requested)
}

fn append16(mut output []u8, value u16) { output << u8(value); output << u8(value >> 8) }
fn append32(mut output []u8, value u32) {
	for shift in 0 .. 4 { output << u8(value >> (shift * 8)) }
}

// ext2 stores version 1: object/mask entries have four bytes, named entries
// eight. Never reinterpret disk bytes as the userspace version 2 layout.
pub fn from_disk(data []u8, mut output []u8) bool {
	if output.len != 0 || data.len < 4 || le32(data, 0) != 1 { return false }
	append32(mut output, 2)
	mut offset := 4
	for offset < data.len {
		if data.len - offset < 4 { return false }
		tag := le16(data, offset)
		permissions := le16(data, offset + 2)
		length := if tag == user || tag == group { 8 } else { 4 }
		if data.len - offset < length { return false }
		id := if length == 8 { le32(data, offset + 4) } else { undefined_id }
		append16(mut output, tag)
		append16(mut output, permissions)
		append32(mut output, id)
		offset += length
	}
	return output.len > 4 && valid(output)
}

pub fn to_disk(data []u8, mut output []u8) bool {
	if output.len != 0 || data.len <= 4 || !valid(data) { return false }
	append32(mut output, 1)
	for i in 0 .. (data.len - 4) / 8 {
		current := entry(data, i)
		append16(mut output, current.tag)
		append16(mut output, current.permissions)
		if current.tag == user || current.tag == group { append32(mut output, current.id) }
	}
	return true
}
