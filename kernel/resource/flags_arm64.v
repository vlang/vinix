// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
module resource

// Open flags aarch64 does not take from asm-generic. Linux gives arm64 its own
// asm/fcntl.h, and these four differ from every other value in this module.
//
// Getting them wrong is not quiet: musl sets O_LARGEFILE on every open(), and
// under the generic numbering that bit reads as O_NOFOLLOW, so no symlink could
// ever be opened. O_DIRECTORY, meanwhile, was being looked for in the bit that
// actually carries O_DIRECT.
pub const o_directory = 0o40000

pub const o_nofollow = 0o100000

pub const o_direct = 0o200000

pub const o_largefile = 0o400000
