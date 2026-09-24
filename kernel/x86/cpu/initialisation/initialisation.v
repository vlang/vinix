module initialisation

import x86.gdt
import x86.idt
import x86.cpu
import x86.msr
import x86.cpu.local as cpulocal
import limine
import x86.apic
import katomic
import sched
import memory
import x86.hypervisor
// The syscall module supplies the C symbols syscall_entry calls into, and
// pin_syscall_entry_callees() (called below) is what actually keeps them
// linked in.
import syscall

// Hand-written in kernel/asm/x86_64/syscall_entry.S rather than V -- it has
// to be genuinely prologue-free (the CPU hands control here with the live
// user stack pointer still active), which @[_naked] does not actually
// guarantee for V 0.5.2's C backend. See that file's own comment for the
// full story.
fn C.syscall_entry()

const cpuid7_ebx_smep = u32(1) << 7
const cpuid7_ecx_umip = u32(1) << 2
const cr0_write_protect = u64(1) << 16
const cr4_umip = u64(1) << 11
const cr4_smep = u64(1) << 20

pub fn initialise(smp_info &limine.LimineSMPInfo) {
	mut cpu_local := unsafe { &cpulocal.Local(smp_info.extra_argument) }
	cpu_number := cpu_local.cpu_number

	cpu_local.lapic_id = smp_info.lapic_id

	gdt.reload()
	idt.reload()

	// No userspace port I/O: place the bitmap beyond the inclusive TSS limit (0x67).
	// A zero base would interpret the TSS itself as I/O permission bits.
	cpu_local.tss.unused3 = 0
	cpu_local.tss.iopb = u16(sizeof(cpulocal.TSS))
	gdt.load_tss(voidptr(&cpu_local.tss))

	cpu_local.tss.ist4 = u64(&cpu_local.abort_stack[cpulocal.abort_stack_size - 1])

	// EFER is per-CPU. APs must enable NXE before switching to Vinix page
	// tables, just as the BSP does during vmm_init().
	memory.enable_nx()
	kernel_pagemap.switch_to()

	unsafe {
		stack_size := u64(0x200000)

		common_int_stack_phys := memory.pmm_alloc(stack_size / page_size)
		mut common_int_stack := &u64(u64(common_int_stack_phys) + stack_size + higher_half)
		cpu_local.tss.rsp0 = u64(common_int_stack)

		sched_stack_phys := memory.pmm_alloc(stack_size / page_size)
		mut sched_stack := &u64(u64(sched_stack_phys) + stack_size + higher_half)
		cpu_local.tss.ist1 = u64(sched_stack)
	}
	// Enable syscall
	mut efer := msr.rdmsr(0xc0000080)
	efer |= 1
	msr.wrmsr(0xc0000080, efer)
	msr.wrmsr(0xc0000081, 0x0033002800000000)

	// Entry address
	// Real statement, not a global initializer expression: see
	// pin_syscall_entry_callees's own comment for why that distinction
	// mattered here.
	syscall.pin_syscall_entry_callees()
	msr.wrmsr(0xc0000082, u64(voidptr(C.syscall_entry)))

	// Flags mask
	msr.wrmsr(0xc0000084, u64(~u32(0x002)))

	// Enable PAT (write-combining/write-protect)
	mut pat_msr := msr.rdmsr(0x277)
	pat_msr &= 0xffffffff
	pat_msr |= u64(0x0105) << 32
	msr.wrmsr(0x277, pat_msr)

	cpu.set_gs_base(u64(&cpu_local.cpu_number))
	cpu.set_kernel_gs_base(u64(&cpu_local.cpu_number))

	// Enable SSE/SSE2 and make supervisor writes obey read-only PTEs. OpenBSD
	// explicitly enables CR0.WP so kernel text and rodata cannot be modified
	// merely because the access originates at ring 0.
	mut cr0 := cpu.read_cr0()
	cr0 &= ~(1 << 2)
	cr0 |= (1 << 1) | cr0_write_protect
	cpu.write_cr0(cr0)

	mut cr4 := cpu.read_cr4()
	cr4 |= (3 << 9)
	cpu.write_cr4(cr4)

	// OpenBSD enables SMEP on every CPU that advertises it. This makes a
	// supervisor-mode instruction fetch from a userspace page fault even when
	// that page is legitimately executable at CPL3.
	smep_supported, _, smep_ebx, _, _ := cpu.cpuid(7, 0)
	if smep_supported && smep_ebx & cpuid7_ebx_smep != 0 {
		cr4 = cpu.read_cr4()
		cr4 |= cr4_smep
		cpu.write_cr4(cr4)
		if cpu_number == 0 {
			println('security: SMEP enabled')
		}
	}

	// OpenBSD also enables UMIP when CPUID advertises it. SGDT, SIDT, SLDT,
	// SMSW and STR then fault in userspace instead of disclosing privileged
	// descriptor-table state that is useful for kernel-address discovery.
	umip_supported, _, _, umip_ecx, _ := cpu.cpuid(7, 0)
	if umip_supported && umip_ecx & cpuid7_ecx_umip != 0 {
		cr4 = cpu.read_cr4()
		cr4 |= cr4_umip
		cpu.write_cr4(cr4)
		if cpu_number == 0 {
			println('security: UMIP enabled')
		}
	}

	mut success, _, mut b, mut c, _ := cpu.cpuid(1, 0)
	if success == true && c & cpu.cpuid_xsave != 0 {
		if cpu_number == 0 {
			println('fpu: xsave supported')
		}

		// Enable XSAVE and x{get, set}bv
		cr4 = cpu.read_cr4()
		cr4 |= (1 << 18)
		cpu.write_cr4(cr4)

		mut xcr0 := u64(0)
		if cpu_number == 0 {
			println('fpu: Saving x87 state using xsave')
		}
		xcr0 |= (1 << 0)
		if cpu_number == 0 {
			println('fpu: Saving SSE state using xsave')
		}
		xcr0 |= (1 << 1)

		if c & cpu.cpuid_avx != 0 {
			if cpu_number == 0 {
				println('fpu: Saving AVX state using xsave')
			}
			xcr0 |= (1 << 2)
		}

		success, _, b, c, _ = cpu.cpuid(7, 0)
		if success == true && b & cpu.cpuid_avx512 != 0 {
			if cpu_number == 0 {
				println('fpu: Saving AVX-512 state using xsave')
			}
			xcr0 |= (1 << 5)
			xcr0 |= (1 << 6)
			xcr0 |= (1 << 7)
		}

		cpu.wrxcr(0, xcr0)

		success, _, _, c, _ = cpu.cpuid(0xd, 0)
		if success == false {
			panic('CPUID failure')
		}

		fpu_storage_size = u64(c)
		fpu_save = cpu.xsave
		fpu_restore = cpu.xrstor
	} else {
		if cpu_number == 0 {
			println('fpu: Using legacy fxsave')
		}
		fpu_storage_size = u64(512)
		fpu_save = cpu.fxsave
		fpu_restore = cpu.fxrstor
	}

	// VMXON is local to each logical CPU. Failure is deliberately non-fatal:
	// Vinix must still boot when firmware disables VT-x or a host does not
	// expose nested virtualisation.
	hypervisor.initialise_cpu(cpu_number)

	apic.lapic_enable(0xff)

	apic.lapic_timer_calibrate(mut cpu_local)

	print('smp: CPU ${cpu_local.cpu_number} online!\n')

	katomic.inc(mut &cpu_local.online)

	if cpu_number != 0 {
		for katomic.load(&scheduler_vector) == 0 {}
		sched.await()
	}
}
