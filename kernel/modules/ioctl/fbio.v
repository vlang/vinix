// fbio.v: ioctl() constants for framebuffer I/O.
// Code is governed by the GPL-2.0 license.
// Copyright (C) 2021-2022 The Vinix authors.

module ioctl

pub const fbioget_vscreeninfo = 0x4600
pub const fbioput_vscreeninfo = 0x4601
pub const fbioget_fscreeninfo = 0x4602
pub const fbiogetcmap = 0x4604
pub const fbioputcmap = 0x4605
pub const fbiopan_display = 0x4606
