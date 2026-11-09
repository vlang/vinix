// SPDX-License-Identifier: GPL-2.0-or-later
module main

import desktop.fbdevabi

#include <linux/fb.h>
struct C.fb_fix_screeninfo {
	smem_start   usize
	smem_len     u32
	line_length  u32
	mmio_start   usize
	capabilities u16
}

struct C.fb_var_screeninfo {
	red      fbdevabi.Bitfield
	reserved [4]u32
}

fn C._Static_assert(bool, &char)

// The C compiler checks these against the target's Linux UAPI, independently
// of V's host-side size calculations. No target execution is needed.
@[export: 'vinix_check_fbdev_abi']
fn check() {
	C._Static_assert(sizeof(fbdevabi.Fixed) == sizeof(C.fb_fix_screeninfo), c'fb fixed size')
	C._Static_assert(sizeof(fbdevabi.Variable) == sizeof(C.fb_var_screeninfo), c'fb variable size')
	C._Static_assert(__offsetof(fbdevabi.Fixed, smem_start) == __offsetof(C.fb_fix_screeninfo, smem_start), c'fb smem start')
	C._Static_assert(__offsetof(fbdevabi.Fixed, smem_len) == __offsetof(C.fb_fix_screeninfo, smem_len), c'fb smem length')
	C._Static_assert(__offsetof(fbdevabi.Fixed, line_length) == __offsetof(C.fb_fix_screeninfo, line_length), c'fb pitch')
	C._Static_assert(__offsetof(fbdevabi.Fixed, mmio_start) == __offsetof(C.fb_fix_screeninfo, mmio_start), c'fb mmio')
	C._Static_assert(__offsetof(fbdevabi.Fixed, capabilities) == __offsetof(C.fb_fix_screeninfo, capabilities), c'fb capabilities')
	C._Static_assert(__offsetof(fbdevabi.Variable, red) == __offsetof(C.fb_var_screeninfo, red), c'fb channel')
	C._Static_assert(__offsetof(fbdevabi.Variable, reserved) == __offsetof(C.fb_var_screeninfo, reserved), c'fb reserved')
}
