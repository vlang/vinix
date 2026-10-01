// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
module resource

// The file attributes chattr(1) sets with FS_IOC_SETFLAGS that the kernel
// keeps and enforces: Linux's FS_IMMUTABLE_FL and FS_APPEND_FL, the bits ext2
// keeps in i_flags, and OpenBSD's schg and sappnd. See fs/attributes.v.
pub const attribute_immutable = u32(0x10)
pub const attribute_append = u32(0x20)
pub const attributes_kept = attribute_immutable | attribute_append

// A file that keeps them: tmpfs's and ext2's. Others have none to set. The
// method names stay clear of this module's free functions below, which V
// would otherwise take for the methods when it checks `res is
// AttributeResource`.
pub interface AttributeResource {
mut:
	attribute_bits() u32
	set_attribute_bits(bits u32) ?
}

pub fn attributes(mut res Resource) u32 {
	if mut res is AttributeResource {
		return res.attribute_bits()
	}
	return 0
}

pub fn can_have_attributes(mut res Resource) bool {
	return res is AttributeResource
}

pub fn set_attributes(mut res Resource, bits u32) ? {
	if mut res is AttributeResource {
		return res.set_attribute_bits(bits)
	}
	return none
}

// Whether nothing may change the file, its data or its name: not a write,
// not a truncation, not chmod, chown, utimes or an extended attribute, not an
// unlink, a rename or a hard link. In a directory, no entry comes or goes.
pub fn is_immutable(mut res Resource) bool {
	return attributes(mut res) & attribute_immutable != 0
}

// Whether the file may only grow at its end: it opens for writing only with
// O_APPEND, and otherwise is as an immutable one. In a directory, entries
// can be made but not removed or renamed.
pub fn is_append_only(mut res Resource) bool {
	return attributes(mut res) & attribute_append != 0
}

// Either, which is what most changes need to rule out.
pub fn is_protected(mut res Resource) bool {
	return attributes(mut res) & attributes_kept != 0
}
