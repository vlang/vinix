// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// The processor that carries out a suspend to RAM, before and after.
//
// When firmware cuts the power, this processor loses every register it has.
// What it must come back with is what x86.cpu.initialisation gave it at boot
// and what the scheduler has changed since:
//
//   - the general registers a function may rely on, and the stack;
//   - CR0, CR3, CR4 and EFER: paging, the page table of the process that
//     asked for the sleep, write protection, SMEP, SMAP, UMIP, PCID, NX;
//   - the GDT and IDT registers, the task register, the LDT register and
//     the segment registers;
//   - the FS, GS and kernel GS bases: the thread's and this CPU's own data;
//   - the SYSCALL registers (STAR, LSTAR, CSTAR, SFMASK) and the PAT;
//   - XCR0, and the floating point and vector registers themselves, which
//     hold the state of the thread that is in the kernel asking for the
//     sleep: they are saved to a thread only when it is switched out;
//   - IA32_SPEC_CTRL as the mitigation policy set it, and IA32_MISC_ENABLE
//     where there is one;
//   - the local APIC: its mode, its spurious vector and its local vectors;
//   - VMX root operation, if the processor was in it.
//
// The first five are put back by x86_wake_resume() before any compiled code
// runs (asm/x86_64/wake_context.S); the rest here, straight after.
//
// The debug registers, the SYSENTER registers and IA32_TSC_AUX are not here:
// this kernel never loads them. Neither are the MTRRs and the microcode
// revision, which are firmware's to restore on the way back as they were
// firmware's to set up on the way in.
@[has_globals]
module wake

import cpufreq
import memory
import lib
import x86.apic
import x86.cpu
import x86.hypervisor
import x86.msr

const max_saved_msrs = 16

const msr_star = u32(0xc0000081)
const msr_lstar = u32(0xc0000082)
const msr_cstar = u32(0xc0000083)
const msr_sfmask = u32(0xc0000084)
const msr_fs_base = u32(0xc0000100)
const msr_gs_base = u32(0xc0000101)
const msr_kernel_gs_base = u32(0xc0000102)
const msr_pat = u32(0x277)
const msr_spec_ctrl = u32(0x48)
const msr_misc_enable = u32(0x1a0)
const cr4_osxsave = u64(1) << 18

struct SavedMsr {
mut:
	index u64
	value u64
}

// asm/x86_64/wake_context.S addresses this by offset; layout_matches() says
// whether the two agree.
struct Context {
mut:
	rbx       u64
	rbp       u64
	r12       u64
	r13       u64
	r14       u64
	r15       u64
	rsp       u64
	rflags    u64
	cr0       u64
	cr2       u64
	cr3       u64
	cr4       u64
	gdt       [16]u8
	idt       [16]u8
	tr        u16
	ldt       u16
	ds        u16
	es        u16
	fs        u16
	gs        u16
	ss        u16
	cs        u16
	rip       u64
	msr_count u64
	msrs      [max_saved_msrs]SavedMsr
}

// What the assembly does not put back.
struct Extended {
mut:
	xcr0            u64
	has_xcr0        bool
	spec_ctrl       u64
	has_spec_ctrl   bool
	misc_enable     u64
	has_misc_enable bool
	lapic           apic.LocalState
	vmx             bool
}

fn C.x86_wake_save(context &Context) u64
fn C.x86_wake_resume(context &Context)

__global (
	x86wake_context  Context
	x86wake_extended Extended
	// A page-aligned area the size the processor's extended state takes.
	x86wake_fpu voidptr
)

fn layout_matches() bool {
	return __offsetof(Context, rsp) == 48 && __offsetof(Context, cr0) == 64
		&& __offsetof(Context, gdt) == 96 && __offsetof(Context, idt) == 112
		&& __offsetof(Context, tr) == 128 && __offsetof(Context, cs) == 142
		&& __offsetof(Context, rip) == 144 && __offsetof(Context, msr_count) == 152
		&& __offsetof(Context, msrs) == 160 && sizeof(SavedMsr) == 16
}

fn read_xcr0() u64 {
	mut a := u32(0)
	mut d := u32(0)
	asm volatile amd64 {
		xgetbv
		; =a (a)
		  =d (d)
		; c (u32(0))
	}
	return (u64(d) << 32) | u64(a)
}

fn (mut context Context) keep_msr(index u32) {
	if context.msr_count >= max_saved_msrs {
		return
	}
	context.msrs[context.msr_count] = SavedMsr{
		index: u64(index)
		value: msr.rdmsr(index)
	}
	context.msr_count++
}

// Whether the processor can be saved at all: the area for the extended state
// is allocated once and kept.
fn prepare_context() bool {
	if x86wake_fpu != unsafe { nil } {
		return true
	}
	pages := lib.div_roundup(fpu_storage_size, page_size)
	area := memory.pmm_alloc_fallible(if pages == 0 { u64(1) } else { pages })
	if area == unsafe { nil } {
		return false
	}
	x86wake_fpu = voidptr(u64(area) + higher_half)
	return true
}

// Read out what x86_wake_save() does not. Interrupts off.
fn save_extended() {
	mut context := &x86wake_context
	context.msr_count = 0
	// EFER first: the others mean nothing without SYSCALL and NX enabled.
	context.keep_msr(msr_efer)
	context.keep_msr(msr_star)
	context.keep_msr(msr_lstar)
	context.keep_msr(msr_cstar)
	context.keep_msr(msr_sfmask)
	context.keep_msr(msr_pat)
	context.keep_msr(msr_fs_base)
	context.keep_msr(msr_gs_base)
	context.keep_msr(msr_kernel_gs_base)

	mut extended := &x86wake_extended
	extended.has_xcr0 = cpu.read_cr4() & cr4_osxsave != 0
	if extended.has_xcr0 {
		extended.xcr0 = read_xcr0()
	}
	extended.has_spec_ctrl = false
	if value := msr.read_safe(msr_spec_ctrl) {
		extended.spec_ctrl = value
		extended.has_spec_ctrl = true
	}
	extended.has_misc_enable = false
	if value := msr.read_safe(msr_misc_enable) {
		extended.misc_enable = value
		extended.has_misc_enable = true
	}
	extended.lapic = apic.lapic_save()
	fpu_save(x86wake_fpu)
	// Out of VMX operation: a processor in it ignores the INIT that would
	// have to start it again if the sleep is refused.
	extended.vmx = hypervisor.leave_cpu(0)
}

// Put it back. Interrupts off; the general state is already in place.
fn restore_extended() {
	extended := &x86wake_extended
	if extended.has_misc_enable {
		msr.write_safe(msr_misc_enable, extended.misc_enable)
	}
	if extended.has_spec_ctrl {
		msr.write_safe(msr_spec_ctrl, extended.spec_ctrl)
	}
	if extended.has_xcr0 {
		cpu.wrxcr(0, extended.xcr0)
	}
	fpu_restore(x86wake_fpu)
	apic.lapic_restore(&extended.lapic)
	if extended.vmx {
		hypervisor.enter_cpu(0)
	}
}

// Save this processor and call `enter`, which asks firmware for the sleep.
// True when the machine slept and this is the processor coming back through
// the trampoline; false when `enter` returned, which is the sleep not
// happening. Either way the processor is as it was. Interrupts off, on the
// boot processor, every other one parked.
@[noinline]
pub fn sleep_processor(enter fn ()) bool {
	save_extended()
	arm(u64(voidptr(C.x86_wake_resume)), 0, u64(voidptr(&x86wake_context)))
	slept := save_and_enter(enter)
	disarm()
	restore_extended()
	if slept {
		// Its frequency registers are as power-on left them: the interface
		// is off again, and the next write of a request would fault.
		cpufreq.cpu_lost_power(0)
	}
	return slept
}

// Not inlined, and nothing of its own kept on the stack across the call: the
// second return of x86_wake_save() finds the stack as the first one left it,
// less whatever `enter` did below it.
@[noinline]
fn save_and_enter(enter fn ()) bool {
	if C.x86_wake_save(&x86wake_context) == 0 {
		enter()
		return false
	}
	return true
}
