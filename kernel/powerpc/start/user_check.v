// SPDX-License-Identifier: GPL-2.0-or-later
module main

import powerpc.cpu
import powerpc.exception
import powerpc.mmu
import powerpc.hash32
import powerpc.runtime
import powerpc.serial

__global bootstrap_space mmu.Space
__global user_space &mmu.Space
__global user_faults u32
__global resume_stack u32
__global user_check_active bool
__global revoked_frame u32

fn C.vinix_user_check()
fn C.vinix_user_check_end()
fn C.vinix_user_check_done()

fn check_userspace(stack u32) {
	user_space = unsafe { &bootstrap_space }
	user_check_active = true
	resume_stack = stack
	table := physical_pages.take(hash32.bytes / 4096, hash32.bytes / 4096)
	code := physical_pages.take(1, 1)
	user_stack := physical_pages.take(16, 1)
	if table == 0 || code == 0 || user_stack == 0 || !user_space.init(table) {
		halt(c'user allocation')
	}
	size := u32(voidptr(C.vinix_user_check_end)) - u32(voidptr(C.vinix_user_check))
	if size > 4096 { halt(c'user test size') }
	runtime.fill(voidptr(code), 0, 4096)
	runtime.copy(voidptr(code), voidptr(C.vinix_user_check), size)
	runtime.fill(voidptr(user_stack), 0, 65536)
	if !user_space.map(0x40000000, code, false) { halt(c'user code mapping') }
	for i := u32(0); i < 16; i++ {
		if !user_space.map(0x50000000 + i * 4096, user_stack + i * 4096, true) {
			halt(c'user stack mapping')
		}
	}
	cpu.publish_code(code, size)
	user_space.activate()
	serial.text(c'VINIX-PPC: entering protected userspace\n')
	exception.enter_user(0x40000000, 0x5000fff0)
	halt(c'user return')
}

@[export: 'vinix_user_check_done']
fn user_check_done() {
	serial.text(c'VINIX-PPC: PASS userspace MMU syscall and protection\n')
	user_check_active = false
	// The CPU is back in real mode with interrupts disabled. Revoke the old
	// mappings before reusing the probe's frames, then flush on activation.
	old_count := user_space.count
	if revoked_frame == 0 || !physical_pages.give(revoked_frame, 1) { halt(c'revoked probe frame ownership') }
	if !user_space.init(user_space.table) { halt(c'user address space reset') }
	for i := u32(0); i < old_count; i++ {
		if !physical_pages.give(user_space.mappings[i].physical, 1) {
			halt(c'probe frame ownership')
		}
	}
	launch_init()
}

// Position-independent fixture executes exclusively through the user mapping.
// Kernel memory access, privileged instruction and text writes must fault.
asm ppc raw {
	".pushsection .text.vinix_user_check,\"ax\"\n.balign 4\n"
	".globl vinix_user_check\nvinix_user_check:\n"
	"li 0,20\nsc\ncmpwi 3,1\nbne 1f\n"
	"lis 4,0x0200\nlwz 5,0(4)\nmfmsr 5\n"
	"lis 4,0x4000\nstw 5,0(4)\nmtctr 1\nbctrl\n"
	// Populate a data TLB entry, revoke it through a fixture-only syscall,
	// then require a DSI at the following load (PC 0x4000003c).
	"lis 4,0x5000\nlwz 5,0(4)\nli 0,0x7f02\nsc\nlwz 5,0(4)\n"
	"li 0,0x7f00\nsc\n"
	"1: li 0,0x7f01\nsc\nb 1b\n"
	".globl vinix_user_check_end\nvinix_user_check_end:\n.popsection\n"
}
