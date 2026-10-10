@[has_globals]
module initialisation

import x86.gdt
import x86.idt
import x86.cpu
import x86.msr
// The syscall module supplies the C symbols syscall_entry calls into.
import syscall as _
import x86.cpu.local as cpulocal
import limine
import x86.apic
import katomic
import sched
import memory
import x86.hypervisor

// asm/x86_64/syscall_entry.S
fn C.syscall_entry()
fn C.vinix_x86_mitigations_initialise(number u64) bool

// asm/x86_64/segment.S
fn C.syscall32_entry()

const cpuid7_ebx_smep = u32(1) << 7
const cpuid7_ebx_smap = u32(1) << 20
const cr4_smap = u64(1) << 21
const cpuid7_ecx_umip = u32(1) << 2
const cr0_write_protect = u64(1) << 16
const cr4_umip = u64(1) << 11
const cr4_smep = u64(1) << 20

// Whether the interrupt thunks execute CLAC. They address it by its linker
// symbol: see asm/int_thunks_asm.S.
@[export: 'smap_enabled']
__global smap_enabled u8

pub fn initialise(smp_info &limine.LimineSMPInfo) {
	// No maskable entry may precede this CPU's GS and context initialization.
	asm volatile amd64 { cli; ; ; memory }
	mut cpu_local := unsafe { &cpulocal.Local(smp_info.extra_argument) }
	cpu_number := cpu_local.cpu_number
	cpu_local.maskable_irq_depth = 0
	cpu_local.maskable_irq_entries = 0
	cpu_local.maskable_irq_peak_depth = 0
	cpu_local.maskable_irq_user_entries = 0
	cpu_local.maskable_irq_scheduler_deferrals = 0

	cpu_local.lapic_id = smp_info.lapic_id

	gdt.install(&cpu_local.gdt[0])
	cpu_local.ldt = unsafe { nil }
	cpu_local.ldt_process = unsafe { nil }
	idt.reload()

	// No userspace port I/O: place the bitmap beyond the inclusive TSS limit (0x67).
	// A zero base would interpret the TSS itself as I/O permission bits.
	cpu_local.tss.unused3 = 0
	cpu_local.tss.iopb = u16(sizeof(cpulocal.TSS))
	gdt.load_tss(&cpu_local.gdt[0], voidptr(&cpu_local.tss))

	// EFER is per-CPU. APs must enable NXE before switching to Vinix page
	// tables, just as the BSP does during vmm_init().
	memory.enable_nx()
	kernel_pagemap.switch_to()
	memory.enable_pcid()

	unsafe {
		stack_size := u64(0x200000)
		cpu_local.idle_int_stack = cpu_stack_top(stack_size)
		cpu_local.tss.rsp0 = cpu_local.idle_int_stack
		cpu_local.tss.ist1 = cpu_stack_top(stack_size)
		// A fault while the page-fault stack itself is exhausted must still
		// have an independent stack for the fatal double-fault report.
		cpu_local.tss.ist2 = cpu_stack_top(0x10000)
		cpu_local.tss.ist4 = cpu_stack_top(0x10000)

		// Every thread brings its own page fault stack; this one is for the
		// CPU between threads.
		cpu_local.idle_pf_stack = cpu_stack_top(stack_size)
		cpu_local.tss.ist3 = cpu_local.idle_pf_stack
	}
	// Enable syscall
	mut efer := msr.rdmsr(0xc0000080)
	efer |= 1
	msr.wrmsr(0xc0000080, efer)
	msr.wrmsr(0xc0000081, 0x0033002800000000)

	// Entry address
	msr.wrmsr(0xc0000082, u64(voidptr(C.syscall_entry)))
	// And from 32-bit code, which an LDT code segment can run: AMD CPUs take
	// SYSCALL there to CSTAR, which left at zero had the kernel jump to
	// address 0. Intel ones refuse it with #UD.
	msr.wrmsr(0xc0000083, u64(voidptr(C.syscall32_entry)))

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

	// And SMAP, which OpenBSD has enabled since 5.3: a supervisor-mode access
	// to a userspace page faults unless EFLAGS.AC is set. The kernel never
	// sets it. Its copies to and from a process go through the direct map, so
	// what faults is a path that follows a user pointer as it stands; see
	// memory/user_guard.v.
	if memory.user_guard_requested() != memory.user_guard_off {
		if smep_supported && smep_ebx & cpuid7_ebx_smap != 0 {
			// The interrupt thunks clear AC from here on.
			smap_enabled = 1
			cr4 = cpu.read_cr4()
			cr4 |= cr4_smap
			cpu.write_cr4(cr4)
			if cpu_number == 0 {
				println(if memory.user_guard_auditing() {
					'security: SMAP enabled, auditing'
				} else {
					'security: SMAP enabled'
				})
			}
		} else {
			memory.user_guard_unsupported()
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

	// Program this logical CPU before it can run any user instruction.
	if !C.vinix_x86_mitigations_initialise(cpu_number) {
		panic('CPU speculation controls did not take effect')
	}

	// VMXON is local to each logical CPU. Failure is deliberately non-fatal:
	// Vinix must still boot when firmware disables VT-x or a host does not
	// expose nested virtualisation.
	hypervisor.initialise_cpu(cpu_number)

	apic.lapic_enable(0xff)

	apic.lapic_timer_calibrate(mut cpu_local)

	// MOVDIRI/MOVDIR64B have no extended-register-state prerequisite. Record
	// only their actual hardware bits, including zero for an absent leaf.
	// Other leaf-seven ECX bits can require separately enabled OS state.
	// IF is still clear and the online acknowledgement below publishes this
	// CPU's immutable observation to the boot compatibility policy.
	directstore_available, _, _, directstore_ecx, _ := cpu.cpuid(7, 0)
	cpu_local.directstore_ecx = if directstore_available {
		directstore_ecx & ((u32(1) << 27) | (u32(1) << 28))
	} else { u32(0) }

	C.kprintf(c'smp: CPU %llu online!\n', u64(cpu_local.cpu_number))

	katomic.inc(mut &cpu_local.online)

	if cpu_number != 0 {
		for katomic.load(&scheduler_vector) == 0 {}
		sched.enter_idle()
	}
}

// Per-CPU mappings live for the CPU's lifetime, including fatal reporting.
fn cpu_stack_top(size u64) u64 {
	base := memory.kernel_stack_alloc(size)
	if base == unsafe { nil } { panic('Cannot allocate guarded CPU stack') }
	return u64(base) + size
}
