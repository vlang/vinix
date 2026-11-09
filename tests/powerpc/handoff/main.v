// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module main

import powerpc.boot

__global zeroes [1024]u32

fn C.vinix_probe_data()

asm ppc raw {
	".pushsection .data.vinix_probe_data,\"aw\"\n.balign 4\n"
	".globl vinix_probe_data\nvinix_probe_data:\n.long 0x12345678\n.popsection\n"
}

@[export: 'vinix_handoff_probe']
fn probe(info &boot.Info, client voidptr) u32 {
	if info.magic != boot.magic || info.version != boot.version || info.bytes != sizeof(boot.Info)
		|| info.tree == 0 || info.available_count == 0 || client == unsafe { nil } {
		return 1
	}
	mut stack := u32(0)
	asm volatile ppc raw {
		"mr %[stack],1"
		; [stack] "=r" (stack)
	}
	if stack & 15 != 0 || stack < info.stack.base || stack >= info.stack.base + info.stack.size {
		return 2
	}
	if unsafe { *(&u32(voidptr(C.vinix_probe_data))) } != 0x12345678 { return 3 }
	if unsafe { *(&u32(info.tree)) } != 0xd00dfeed { return 4 }
	unsafe {
		mut bytes := &u32(&zeroes[0])
		for i in 0 .. 1024 {
			if bytes[i] != 0 { return 5 }
			bytes[i] = u32(i + 1)
		}
		if bytes[1023] != 1024 { return 6 }
		for i := u32(0); i < info.available_count; i++ {
			range := (&boot.MemoryRange(&info.available[0]))[i]
			if range.base < info.kernel.base + info.kernel.size && range.base + range.size > info.kernel.base {
				return 7
			}
			if range.base < info.stack.base + info.stack.size && range.base + range.size > info.stack.base {
				return 8
			}
		}
	}
	return 0x564f4b32
}
