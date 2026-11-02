// SPDX-License-Identifier: GPL-2.0-or-later
module anscore

#define vinix_ans_stack_alloc __builtin_alloca

fn C.vinix_ans_stack_alloc(size uint) voidptr

// The caller holds the ANS operation lock across both commands and copies.
// Use the existing pinned DMA bounce buffer; a failed controller must never
// have that storage cleared or reused while firmware may still own it.
pub fn a_health(a &Ans, index u32, identify &u8, data &u8) i32 {
	unsafe {
		if a.dead != 0 { return -a.error }
		if a.stopped != 0 || a.stopping != 0 { return -ans_stopped }
		if a.live == 0 || index >= a.nns { return -ans_namespace }
		if identify == nil || data == nil { return -ans_range }
		command := &u8(C.vinix_ans_stack_alloc(64))
		for step in 0 .. 2 {
			a_zero(command, 64)
			a_put64(command + 24, a.physical + u64(131072))
			if step == 0 {
				command[0] = 6 // Identify Controller, CNS=1, NSID=0.
				a_put32(command + 40, 1)
			} else {
				command[0] = 2 // Admin Get Log Page.
				a_put32(command + 4, u32(-1))
				// LID=2, RAE=1, NUMDL=127; all other fields stay zero.
				a_put32(command + 40, 0x007f8002)
			}
			bytes := uint(if step == 0 { 4096 } else { 512 })
			a_zero(a.dma + 131072, bytes)
			a_sync(a, 131072, bytes, 0)
			result := a_submit(a, 0, command, nil)
			if result != 0 { return result }
			a_sync(a, 131072, bytes, 1)
			a_copy(if step == 0 { identify } else { data }, a.dma + 131072, 512)
		}
		return 0
	}
}

pub fn health(index u32, identify &u8, data &u8) i32 {
	return a_health(unsafe { &ans_controller }, index, identify, data)
}
