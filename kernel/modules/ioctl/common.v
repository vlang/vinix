// common.v: ioctl() constants.
// Code is governed by the GPL-2.0 license.
// Copyright (C) 2021-2022 The Vinix authors.

module ioctl

// https://github.com/torvalds/linux/blob/5bfc75d92efd494db37f5c4c173d3639d4772966/include/uapi/asm-generic/ioctl.h

pub const fionread = 0x541b

pub const ioc_nrbits = 8
pub const ioc_typebits = 8
pub const ioc_sizebits = 14
pub const ioc_dirbits = 2

pub const ioc_nrmask = ((1 << ioc_nrbits) - 1)
pub const ioc_typemask = ((1 << ioc_typebits) - 1)
pub const ioc_sizemask = ((1 << ioc_sizebits) - 1)
pub const ioc_dirmask = ((1 << ioc_dirbits) - 1)

pub const ioc_nrshift = 0
pub const ioc_typeshift = (ioc_nrshift + ioc_nrbits)
pub const ioc_sizeshift = (ioc_typeshift + ioc_typebits)
pub const ioc_dirshift = (ioc_sizeshift + ioc_sizebits)

[inline]
pub fn ioctl_dir(ioc u32) u32 {
	return (ioc >> ioc_dirshift) & ioc_dirmask
}

[inline]
pub fn ioctl_type(ioc u32) u32 {
	return (ioc >> ioc_typeshift) & ioc_typemask
}

[inline]
pub fn ioctl_size(ioc u32) u32 {
	return (ioc >> ioc_sizeshift) & ioc_sizemask
}

[inline]
pub fn ioctl_nr(ioc u32) u32 {
	return (ioc >> ioc_nrshift) & ioc_nrmask
}
