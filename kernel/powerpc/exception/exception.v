// SPDX-License-Identifier: GPL-2.0-or-later
module exception

import powerpc.cpu
import powerpc.runtime

// Must match the assembly frame beginning 32 bytes above r1. The remaining
// 32 bytes are the SysV caller linkage/argument area, not saved registers.
pub struct Frame {
pub mut:
	gpr    [32]u32
	lr     u32
	ctr    u32
	xer    u32
	cr     u32
	pc     u32
	msr    u32
	dar    u32
	dsisr  u32
	vector u32
}

fn C.vinix_vector_template()
fn C.vinix_vector_common()
fn C.vinix_vector_end()
fn C.vinix_ppc_dispatch(frame &Frame)
fn C.vinix_enter_user(entry u32, stack u32)

pub fn install(stack_top u32) bool {
	size := u32(voidptr(C.vinix_vector_end)) - u32(voidptr(C.vinix_vector_common))
	if size > 0x1000 || sizeof(Frame) != 164 || stack_top & 15 != 0 { return false }
	runtime.copy(voidptr(0x2000), voidptr(C.vinix_vector_common), size)
	for vector := u32(0x100); vector < 0x1800; vector += 0x100 {
		runtime.copy(voidptr(vector), voidptr(C.vinix_vector_template), 12)
		unsafe { *(&u32(vector + 4)) = 0x38000000 | vector }
	}
	cpu.publish_code(0x100, 0x2f00)
	asm volatile ppc raw {
		"mtspr 272,%[stack]\n\tsync\n\tisync"
		; ; [stack] "r" (stack_top)
		; memory
	}
	return true
}

pub fn enter_user(entry u32, stack u32) {
	C.vinix_enter_user(entry, stack)
}

pub fn decrementer(value u32) {
	asm volatile ppc raw {
		"mtdec %[value]"
		; ; [value] "r" (value)
	}
}

// Exception entry always has IR/DR/EE/PR cleared. The initial kernel executes
// at physical addresses, with a separate interrupt stack and no nesting.
asm ppc raw {
	".pushsection .text.vinix_vectors,\"ax\"\n.balign 4\n"
	".globl vinix_vector_template\nvinix_vector_template:\n"
	"mtspr 273,0\nli 0,0\nba 0x2000\n"
	".globl vinix_vector_common\nvinix_vector_common:\n"
	"mtspr 274,1\nmfspr 1,272\nstwu 1,-224(1)\n"
	"stw 0,192(1)\nmfspr 0,273\nstw 0,32(1)\nmfspr 0,274\nstw 0,36(1)\n"
	"stmw 2,40(1)\nmflr 0\nstw 0,160(1)\nmfctr 0\nstw 0,164(1)\n"
	"mfxer 0\nstw 0,168(1)\nmfcr 0\nstw 0,172(1)\n"
	"mfsrr0 0\nstw 0,176(1)\nmfsrr1 0\nstw 0,180(1)\n"
	"mfdar 0\nstw 0,184(1)\nmfdsisr 0\nstw 0,188(1)\n"
	"addi 3,1,32\nlis 12,vinix_ppc_dispatch@ha\naddi 12,12,vinix_ppc_dispatch@l\nmtctr 12\nbctrl\n"
	"lwz 0,176(1)\nmtsrr0 0\nlwz 0,180(1)\nmtsrr1 0\n"
	"lwz 0,160(1)\nmtlr 0\nlwz 0,164(1)\nmtctr 0\n"
	"lwz 0,168(1)\nmtxer 0\nlwz 0,172(1)\nmtcr 0\n"
	"lmw 2,40(1)\nlwz 0,32(1)\nlwz 1,36(1)\nrfi\n"
	".globl vinix_vector_end\nvinix_vector_end:\n"
	".globl vinix_enter_user\nvinix_enter_user:\n"
	// The initial kernel forbids implicit FP and has one process. User FPRs
	// survive traps untouched. Initialize every register before first entry;
	// scheduling will require an explicit per-thread FPU context.
	"mfmsr 5\nori 5,5,0x2000\nmtmsr 5\nisync\n"
	"lis 5,vinix_fpu_zero@ha\nlfd 0,vinix_fpu_zero@l(5)\nmtfsf 255,0\n"
	"fmr 1,0\nfmr 2,0\nfmr 3,0\nfmr 4,0\nfmr 5,0\nfmr 6,0\nfmr 7,0\n"
	"fmr 8,0\nfmr 9,0\nfmr 10,0\nfmr 11,0\nfmr 12,0\nfmr 13,0\nfmr 14,0\nfmr 15,0\n"
	"fmr 16,0\nfmr 17,0\nfmr 18,0\nfmr 19,0\nfmr 20,0\nfmr 21,0\nfmr 22,0\nfmr 23,0\n"
	"fmr 24,0\nfmr 25,0\nfmr 26,0\nfmr 27,0\nfmr 28,0\nfmr 29,0\nfmr 30,0\nfmr 31,0\n"
	"mtsrr0 3\nli 0,0\nmtlr 0\nmtctr 0\nmtxer 0\nmtcr 0\n"
	"mr 1,4\nli 0,0\nori 0,0,0xe030\nmtsrr1 0\n"
	"li 2,0\nli 3,0\nli 4,0\nli 5,0\nli 6,0\nli 7,0\nli 8,0\nli 9,0\nli 10,0\nli 11,0\nli 12,0\nli 13,0\n"
	"li 14,0\nli 15,0\nli 16,0\nli 17,0\nli 18,0\nli 19,0\nli 20,0\nli 21,0\nli 22,0\nli 23,0\nli 24,0\nli 25,0\nli 26,0\nli 27,0\nli 28,0\nli 29,0\nli 30,0\nli 31,0\nli 0,0\nrfi\n"
	".popsection\n"
	".pushsection .rodata.vinix_fpu_zero,\"a\"\n.balign 8\nvinix_fpu_zero: .long 0,0\n.popsection\n"
}
