// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
module resource

// The asm-generic open flags, which x86_64 uses unchanged. aarch64 overrides
// these four; see flags_arm64.v.
pub const o_directory = 0o200000

pub const o_nofollow = 0o400000

pub const o_direct = 0o40000

pub const o_largefile = 0o100000
