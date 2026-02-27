@[has_globals]
module main

import memory
import term
import lib.stubs
import aarch64.cpu
import aarch64.cpu.local as cpulocal
import aarch64.exception
import aarch64.aic
import aarch64.gic
import aarch64.timer
import aarch64.smp
import aarch64.pmgr
import aarch64.uart
import aarch64.virtio_input
import devicetree
import initramfs
import fs
import sched
import stat
import pipe
import futex
import socket
import limine
import gpu.agx.driver as agx_driver
import gpu.dcp
import syscall as _
import syscall.table
import dev.console
import dev.fbdev
import dev.fbdev.simple
import dev.streams
import time
import userland

@[_linker_section: '.requests']
@[cinit]
__global (
	volatile dtb_req = limine.LimineDTBRequest{
		response: unsafe { nil }
	}
	volatile kernel_file_req = limine.LimineKernelFileRequest{
		response: unsafe { nil }
	}
	minimal_apple_bringup = true
	force_qemu_platform  = false
	aic_timer_irq         = u32(3)
)

fn segfault_kill_process(gpr_state voidptr, status int) {
	userland.syscall_exit(gpr_state, status)
}

fn be32(ptr voidptr) u32 {
	p := unsafe { &u8(ptr) }
	return unsafe {
		(u32(p[0]) << 24) | (u32(p[1]) << 16) | (u32(p[2]) << 8) | u32(p[3])
	}
}

// Read the AIC interrupt number for the virtual guest timer (CNTV) from
// the arm,armv8-timer node's "interrupts" property.
fn parse_aic_guest_virtual_timer_irq() ?u32 {
	timer_node := devicetree.find_compatible('arm,armv8-timer') or { return none }
	interrupts := devicetree.get_property(timer_node, 'interrupts') or { return none }
	if interrupts.len < 16 || interrupts.len % 4 != 0 {
		return none
	}

	total_cells := interrupts.len / 4
	if total_cells < 8 || total_cells % 4 != 0 {
		return none
	}

	cells_per_irq := total_cells / 4
	if cells_per_irq < 3 {
		return none
	}

	// Timer node encodes 4 interrupts in order:
	//   phys, virt, hyp-phys, hyp-virt.
	// The IRQ/FIQ number is the penultimate cell in each tuple.
	irq_cell_off := cells_per_irq - 2
	cell_index := cells_per_irq + irq_cell_off
	if cell_index >= total_cells {
		return none
	}

	return be32(unsafe { voidptr(u64(interrupts.data) + u64(cell_index * 4)) })
}

fn aic_hw_irq_handler(irq u32, gpr_state voidptr) {
	if irq != aic_timer_irq {
		return
	}
	timer_handler := sched.get_timer_handler()
	timer_handler(gpr_state)
}

fn bootstrap_cpu0() {
	print('bootstrapping CPU 0...\n')
	mut cpu_local := unsafe { &cpulocal.Local(memory.malloc(sizeof(cpulocal.Local))) }
	cpu_local.cpu_number = 0
	cpu_local.timer_freq = cpu.read_cntfrq_el0()
	cpu_locals << cpu_local
	cpu.write_tpidr_el1(0)
	cpu.init_fpu_globals()
	print('CPU 0 bootstrap done\n')
}

fn kmain_thread() {
	term.early_stage_mark(11)
	print('kmain_thread: started\n')

	term.framebuffer_init()
	print('kmain_thread: framebuffer done\n')

	socket.initialise()
	print('kmain_thread: socket done\n')
	pipe.initialise()
	print('kmain_thread: pipe done\n')
	futex.initialise()
	print('kmain_thread: futex done\n')
	fs.initialise()
	print('kmain_thread: fs done\n')

	fs.mount(vfs_root, '', '/', 'tmpfs') or {}
	print('kmain_thread: root mount done\n')
	fs.create(vfs_root, '/dev', 0o644 | stat.ifdir) or {}
	fs.mount(vfs_root, '', '/dev', 'devtmpfs') or {}
	print('kmain_thread: devtmpfs done\n')

	initramfs.initialise()
	print('kmain_thread: initramfs done\n')

	// Keep Apple bring-up minimal until interrupt/device plumbing is stable.
	if devicetree.is_available() && !minimal_apple_bringup {
		print('kmain_thread: init GPU driver...\n')
		agx_driver.initialise()
		print('kmain_thread: GPU driver done\n')

		print('kmain_thread: init DCP driver...\n')
		dcp.initialise()
		print('kmain_thread: DCP driver done\n')
	} else if devicetree.is_available() {
		print('kmain_thread: skipping GPU/DCP (minimal Apple bring-up mode)\n')
	} else {
		print('kmain_thread: skipping GPU/DCP (no device tree)\n')
	}

	table.init_syscall_table()
	print('kmain_thread: syscall table done\n')

	// Register segfault handler so user-space crashes kill the process
	// instead of hanging the kernel
	exception.register_segfault_handler(segfault_kill_process)

	streams.initialise()
	print('kmain_thread: streams done\n')

	fbdev.initialise()
	fbdev.register_driver(simple.get_driver())
	print('kmain_thread: fbdev done\n')

	console.initialise()
	print('kmain_thread: console done\n')
	term.early_stage_mark(12)

	print('\n*** aarch64: Kernel initialisation complete ***\n')
	print('*** Starting /sbin/init ***\n')

	userland.start_program(false, vfs_root, '/sbin/init', ['/sbin/init'], [],
		'/dev/console', '/dev/console', '/dev/console') or {
		panic('Could not start init process')
	}

	sched.dequeue_and_die()
}

fn get_dt_base(compat string, default_base u64) u64 {
	node := devicetree.find_compatible(compat) or { return default_base }
	regs := devicetree.get_reg(node) or { return default_base }
	if regs.len >= 2 {
		return regs[0]
	}
	return default_base
}

// Apple Silicon GPU/DCP bring-up is still experimental; keep it disabled by
// default to avoid hard resets on real hardware. Use kernel cmdline
// "vinix.apple_gpu=1" (or "vinix.minimal_apple=0") to enable it.
fn configure_apple_bringup_from_cmdline() {
	if kernel_file_req.response == unsafe { nil } {
		print('boot cmdline: unavailable, using minimal Apple bring-up\n')
		return
	}
	kernel_file := kernel_file_req.response.kernel_file
	if kernel_file == unsafe { nil } || kernel_file.cmdline == unsafe { nil } {
		print('boot cmdline: empty, using minimal Apple bring-up\n')
		return
	}

	cmdline := unsafe { cstring_to_vstring(kernel_file.cmdline) }
	if cmdline.len == 0 {
		print('boot cmdline: empty, using minimal Apple bring-up\n')
		return
	}

	if cmdline.contains('vinix.apple_gpu=1') || cmdline.contains('vinix.minimal_apple=0') {
		minimal_apple_bringup = false
	}
	if cmdline.contains('vinix.minimal_apple=1') {
		minimal_apple_bringup = true
	}
	if cmdline.contains('vinix.qemu_platform=1') {
		force_qemu_platform = true
	}

	if minimal_apple_bringup {
		print('apple bring-up: minimal mode (GPU/DCP disabled)\n')
	} else {
		print('apple bring-up: experimental GPU/DCP enabled via cmdline\n')
	}
}

fn kmain() {
	term.early_stage_mark(1)

	// Do not hard-stop on base revision mismatch. Some real-hardware boot
	// chains may provide an older Limine build; continue and rely on feature
	// checks for individual requests.
	if limine_base_revision.revision != 0 {
		C.printf(c'limine: base revision negotiation mismatch (value=%llu), continuing\n',
			limine_base_revision.revision)
	}

	// Initialize the memory allocator.
	memory.pmm_init()
	term.early_stage_mark(2)

	// Call Vinit to initialise the runtime
	C._vinit(0, 0)
	term.early_stage_mark(3)
	// Bring up terminal as early as possible to surface boot progress
	// before we switch to kernel-owned page tables.
	term.initialise()
	print('\n=== Vinix aarch64 (early) ===\n')

	configure_apple_bringup_from_cmdline()

	// Optional QEMU virt MMIO path (PL011/GIC/Virtio-input). Keep this opt-in
	// so missing DTB on real hardware does not trigger invalid MMIO accesses.
	if force_qemu_platform {
		uart.initialise(memory.get_hhdm_offset() + 0x09000000)
		uart.puts(c'\n=== Vinix aarch64 booting (qemu mode) ===\n')
	}

	// Set up exception vectors (replaces x86 GDT/IDT/ISR)
	exception.initialise()
	term.early_stage_mark(4)

	_ = stubs.toupper(0)

	// Parse device tree (replaces ACPI on Apple Silicon)
	mut have_dt := false
	mut use_aic := false
	if dtb_req.response != unsafe { nil } {
		dtb_addr := dtb_req.response.dtb_addr
		if devicetree.parse(voidptr(dtb_addr)) {
			have_dt = true
		}
	}
	term.early_stage_mark(if have_dt { u32(5) } else { u32(6) })

	memory.vmm_init()
	term.early_stage_mark(7)

	// Init terminal (after vmm_init so page tables are active and framebuffer is mapped)
	term.initialise()
	print('\n=== Vinix aarch64 ===\n')
	if !have_dt {
		print('WARNING: No usable device tree blob\n')
	}

	// Apple-specific hardware init (only with device tree / Apple Silicon)
	if have_dt {
		// Apple Interrupt Controller
		mut aic_phys := get_dt_base('apple,aic2', 0)
		if aic_phys == 0 {
			aic_phys = get_dt_base('apple,aic', 0)
		}
		if aic_phys != 0 {
			print('init aic...\n')
			aic.initialise(aic_phys)
			if timer_irq := parse_aic_guest_virtual_timer_irq() {
				aic_timer_irq = timer_irq
			}
			aic.register_hw_handler(aic_hw_irq_handler)
			aic.unmask_irq(aic_timer_irq)
			use_aic = true
			print('aic: timer irq ${aic_timer_irq}\n')
			print('aic done\n')
		} else {
			print('no Apple AIC node found in device tree\n')
		}

		// Apple Power Manager
		pmgr_addr := get_dt_base('apple,pmgr', 0)
		if pmgr_addr != 0 {
			print('init pmgr...\n')
			pmgr.initialise(pmgr_addr)
			print('pmgr done\n')
		}
	} else {
		print('skipping Apple-specific HW init (no device tree)\n')
	}
	term.early_stage_mark(8)

	// Virtio-input keyboard probe/GIC setup is for the QEMU virt machine.
	if !use_aic && force_qemu_platform {
		print('init virtio-input...\n')
		virtio_input.initialise(memory.get_hhdm_offset())
		print('virtio-input done\n')
	} else if use_aic {
		print('skipping virtio-input (Apple bring-up path)\n')
	} else {
		print('skipping qemu MMIO init (set vinix.qemu_platform=1 to enable)\n')
	}

	// ARM Generic Timer (works on both QEMU virt and Apple Silicon)
	print('init timer...\n')
	timer.initialise()
	print('timer done\n')
	term.early_stage_mark(9)

	// Interrupt controller: GIC for QEMU virt, AIC for Apple Silicon
	if !use_aic && force_qemu_platform {
		print('init gic (QEMU virt)...\n')
		gic.initialise(memory.get_hhdm_offset())
		print('gic done\n')
	}

	// ARM64 PCI ECAM setup is not wired yet; skip to avoid unsafe probing.
	print('skipping PCI (ARM64 ECAM setup not implemented)\n')

	// SMP (requires spin-table addresses from device tree)
	if use_aic {
		print('skipping SMP (minimal Apple bring-up mode)\n')
		bootstrap_cpu0()
	} else if have_dt {
		print('init smp...\n')
		smp.initialise()
		print('smp done\n')
	} else {
		print('skipping SMP (no device tree)\n')
		bootstrap_cpu0()
	}

	print('init time...\n')
	time.initialise()
	print('time done\n')

	print('init sched...\n')
	sched.initialise()
	// Wire scheduler timer callback for the active interrupt controller.
	if !use_aic && force_qemu_platform {
		gic.set_timer_handler(sched.get_timer_handler())
	}
	print('sched done\n')
	term.early_stage_mark(10)

	print('spawning kmain_thread via scheduler...\n')
	spawn kmain_thread()
	print('spawn done, calling await...\n')

	sched.await()
}
