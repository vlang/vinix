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
import aarch64.wdt
import aarch64.uart
import aarch64.virtio_input
import aarch64.virtio_net
import apple.smc
import apple.ans
import apple.typec
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
import dev.pointerdev
import dev.procdev
import dev.random
import dev.streams
import time
import userland

#include "apple_display_hotplug.h"

fn C.vinix_display_hotplug_choose_action(connected int, reboot_enabled int,
	reboot_attempted int, framebuffer_width u64, framebuffer_height u64) int

@[_linker_section: '.requests']
@[cinit]
__global (
	volatile dtb_req = limine.LimineDTBRequest{
		response: unsafe { nil }
	}
	enable_apple_gpu     = false
	enable_apple_dcp     = false
	// The SMC client is read-only and safely declines non-Apple device trees.
	enable_apple_battery = true
	enable_apple_display_hotplug = false
	apple_display_coldplug_reboot = false
	apple_display_reboot_attempted = false
	external_display_handoff = false
	force_qemu_platform  = false
	aic_timer_irq         = u32(3)
)

fn segfault_kill_process(gpr_state voidptr, status int) {
	// A fatal fault takes down the whole process, not just the faulting thread.
	userland.syscall_exit_group(gpr_state, status)
}

fn apple_display_hotplug(connected bool) {
	width, height := term.selected_framebuffer_dimensions()
	action := C.vinix_display_hotplug_choose_action(int(connected),
		int(apple_display_coldplug_reboot), int(apple_display_reboot_attempted), width,
		height)
	if action == 2 {
		apple_display_reboot_attempted = true
		println('display: first post-boot Studio Display attach; rebooting once for firmware link training')
		// Persistent ANS writes use FUA, but shut the controller down in order
		// before resetting. If it cannot be made safe, retain the internal
		// display and decline the recovery instead of risking stored data.
		if !ans.shutdown() {
			println('display: cold-attach reboot cancelled; storage shutdown failed')
			return
		}
		cpu.psci_call(cpu.psci_system_reset)
		// A successful PSCI reset does not return. Storage is already stopped,
		// so a failed conduit cannot safely resume the running desktop.
		println('display: PSCI reset failed after storage shutdown; powering off')
		cpu.psci_call(cpu.psci_system_off)
		for {}
	}
	term.display_hotplug(connected)
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

// The Apple architectural (virtual) timer is delivered as an FIQ, not an AIC
// hardware IRQ event, so it must be serviced from the FIQ dispatch path and
// gated on the timer's own ISTATUS rather than on an AIC IRQ number.
fn aic_fiq_handler(gpr_state voidptr) {
	if timer.is_pending() {
		timer_handler := sched.get_timer_handler()
		timer_handler(gpr_state)
	}
}

fn bootstrap_cpu0() {
	print('bootstrapping CPU 0...\n')
	mut cpu_local := unsafe { &cpulocal.Local(memory.malloc(sizeof(cpulocal.Local))) }
	cpu_local.cpu_number = 0
	cpu_local.timer_freq = cpu.read_cntfrq_el0()
	cpu_locals << cpu_local
	cpu.write_tpidr_el1(0)
	cpu.enable_el0_cache_access()
	cpu.init_fpu_globals()
	print('CPU 0 bootstrap done\n')
}

fn kmain_thread(qemu_platform bool) {
	boot_stage(11)
	print('kmain_thread: started\n')

	term.framebuffer_init()
	print('kmain_thread: framebuffer done\n')

	socket.initialise()
	print('kmain_thread: socket done\n')
	if qemu_platform {
		virtio_net.initialise(memory.get_hhdm_offset())
	}
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

	// Experimental, read-only SMC battery client; independent of GPU/DCP.
	if enable_apple_battery {
		smc.initialise()
	}

	if enable_apple_display_hotplug {
		typec.register_hotplug_handler(apple_display_hotplug)
		if !typec.initialise() {
			println('apple-typec: display hot-plug unavailable')
		}
	}

	// GPU and display bring-up are independent experiments. In particular,
	// probing a newly recognized GPU must not run an unrelated DCP sequence.
	if devicetree.is_available() {
		if enable_apple_gpu {
			print('kmain_thread: init GPU driver...\n')
			agx_driver.initialise()
			print('kmain_thread: GPU driver done\n')
		} else {
			print('kmain_thread: skipping GPU (not enabled)\n')
		}

		if enable_apple_dcp {
			print('kmain_thread: init DCP driver...\n')
			dcp.initialise()
			print('kmain_thread: DCP driver done\n')
		} else {
			print('kmain_thread: skipping DCP (not enabled)\n')
		}
	} else {
		print('kmain_thread: skipping GPU/DCP (no device tree)\n')
	}

	table.init_syscall_table()
	table.init_storage_syscalls()
	print('kmain_thread: syscall table done\n')

	// Register segfault handler so user-space crashes kill the process
	// instead of hanging the kernel
	exception.register_segfault_handler(segfault_kill_process)

	streams.initialise()
	print('kmain_thread: streams done\n')
	random.initialise()
	print('kmain_thread: random done\n')

	fbdev.initialise()
	fbdev.register_driver(simple.get_driver())
	print('kmain_thread: fbdev done\n')

	pointerdev.initialise()
	print('kmain_thread: pointer done\n')

	procdev.initialise()
	print('kmain_thread: processes done\n')

	console.initialise()
	print('kmain_thread: console done\n')

	// ANS is independent of the GPU, and disabled unless explicitly requested.
	// Keep the initramfs root and recovery console even if storage bring-up fails.
	kernel_file := limine.kernel_file()
	if kernel_file != unsafe { nil } && kernel_file.cmdline != unsafe { nil } {
		ans.initialise(unsafe { cstring_to_vstring(kernel_file.cmdline) })
	}
	if !ans.select_root() {
		panic('Requested ANS SSD root could not be selected safely')
	}
	boot_stage(12)

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

// Apple Silicon GPU/DCP bring-up is still experimental; keep each subsystem
// disabled by default to avoid hard resets on real hardware. Use kernel
// cmdline "vinix.apple_gpu=1" and/or "vinix.apple_dcp=1". The legacy
// "vinix.minimal_apple=0" spelling explicitly enables both.
fn configure_apple_bringup_from_cmdline() {
	kernel_file := limine.kernel_file()
	if kernel_file == unsafe { nil } {
		print('boot cmdline: unavailable, Apple GPU/DCP disabled\n')
		return
	}
	if kernel_file.cmdline == unsafe { nil } {
		print('boot cmdline: empty, Apple GPU/DCP disabled\n')
		return
	}

	cmdline := unsafe { cstring_to_vstring(kernel_file.cmdline) }
	if cmdline.len == 0 {
		print('boot cmdline: empty, Apple GPU/DCP disabled\n')
		return
	}

	// Exact token matching avoids enabling a probe for '=10' or for a
	// different parameter containing this name. Last explicit option wins.
	mut option_start := 0
	for index := 0; index <= cmdline.len; index++ {
		if index != cmdline.len && cmdline[index] !in [` `, `\t`, `\r`, `\n`] {
			continue
		}
		// Compare in place: command-line parsing does not allocate.
		option := unsafe { tos(cmdline.str + option_start, index - option_start) }
		if option == 'vinix.apple_battery=1' {
			enable_apple_battery = true
		} else if option == 'vinix.apple_battery=0' {
			enable_apple_battery = false
		} else if option == 'vinix.apple_gpu=1' {
			enable_apple_gpu = true
		} else if option == 'vinix.apple_gpu=0' {
			enable_apple_gpu = false
		} else if option == 'vinix.apple_dcp=1' {
			enable_apple_dcp = true
		} else if option == 'vinix.apple_dcp=0' {
			enable_apple_dcp = false
		} else if option == 'vinix.display_hotplug=1' {
			enable_apple_display_hotplug = true
		} else if option == 'vinix.display_hotplug=0' {
			enable_apple_display_hotplug = false
		} else if option == 'vinix.display_coldplug=reboot' {
			apple_display_coldplug_reboot = true
		} else if option == 'vinix.display_coldplug=off' {
			apple_display_coldplug_reboot = false
		} else if option == 'vinix.display=external' {
			external_display_handoff = true
		}
		option_start = index + 1
	}

	if cmdline.contains('vinix.minimal_apple=0') {
		enable_apple_gpu = true
		enable_apple_dcp = true
	}
	if cmdline.contains('vinix.minimal_apple=1') {
		enable_apple_gpu = false
		enable_apple_dcp = false
	}
	if cmdline.contains('vinix.qemu_platform=1') {
		force_qemu_platform = true
	}
	if apple_display_coldplug_reboot {
		enable_apple_display_hotplug = true
	}
	// The current DCP driver binds the M1 Air's internal panel. Starting it
	// while an external framebuffer inherited from firmware is scanning out can
	// reset the display fabric and blank the only usable output. Handoff mode
	// therefore owns the selected GOP surface and leaves DCP untouched.
	if external_display_handoff {
		enable_apple_dcp = false
		print('display: external GOP handoff active; native DCP probe disabled\n')
	}

	C.printf(c'apple bring-up: GPU=%s DCP=%s battery=%s display-hotplug=%s cold-attach=%s\n',
		if enable_apple_gpu { c'enabled' } else { c'disabled' },
		if enable_apple_dcp { c'enabled' } else { c'disabled' },
		if enable_apple_battery { c'enabled' } else { c'disabled' },
		if enable_apple_display_hotplug { c'enabled' } else { c'disabled' },
		if apple_display_coldplug_reboot { c'firmware reboot' } else { c'disabled' })
}

// Power off at a chosen stage. On a machine with no console and no usable
// framebuffer, "did it power off?" is the only bit of information available,
// so vinix.halt_at=N turns each stage marker into an observable event.
__global (
	halt_at_stage = int(-1)
)

fn boot_stage(stage u32) {
	term.early_stage_mark(stage)
	if halt_at_stage >= 0 && int(stage) == halt_at_stage {
		cpu.psci_call(cpu.psci_system_off)
		cpu.psci_call(cpu.psci_system_reset)
		// Both conduits returned, so PSCI is unavailable: nothing more can be
		// signalled from here.
		for {}
	}
}

// Read a decimal value from the boot cmdline. Like the scan above this runs
// before pmm_init, so it parses digits in place rather than allocating.
fn early_cmdline_value(prefix string) int {
	kernel_file := limine.kernel_file()
	if kernel_file == unsafe { nil } {
		return -1
	}
	if kernel_file.cmdline == unsafe { nil } {
		return -1
	}
	text := unsafe { &u8(kernel_file.cmdline) }
	for i := 0; unsafe { text[i] } != 0; i++ {
		mut j := 0
		for j < prefix.len && unsafe { text[i + j] } == prefix[j] {
			j++
		}
		if j != prefix.len {
			continue
		}
		mut value := 0
		mut digits := 0
		for k := i + prefix.len; unsafe { text[k] } >= `0` && unsafe { text[k] } <= `9`; k++ {
			value = value * 10 + int(unsafe { text[k] } - `0`)
			digits++
		}
		if digits == 0 {
			return -1
		}
		return value
	}
	return -1
}

// Scan the boot cmdline without building a V string: this runs before
// pmm_init, so the allocator is not available yet.
fn early_cmdline_contains(needle string) bool {
	kernel_file := limine.kernel_file()
	if kernel_file == unsafe { nil } {
		return false
	}
	if kernel_file.cmdline == unsafe { nil } {
		return false
	}
	text := unsafe { &u8(kernel_file.cmdline) }
	for i := 0; unsafe { text[i] } != 0; i++ {
		mut j := 0
		for j < needle.len && unsafe { text[i + j] } == needle[j] {
			j++
		}
		if j == needle.len {
			return true
		}
	}
	return false
}

// Allocation-free exact token lookup for decisions made before _vinit. Unlike
// a substring search, `vinix.display=external-test` must not change scanout.
fn early_cmdline_has_token(token string) bool {
	kernel_file := limine.kernel_file()
	if kernel_file == unsafe { nil } || kernel_file.cmdline == unsafe { nil } {
		return false
	}
	text := unsafe { &u8(kernel_file.cmdline) }
	mut start := 0
	for index := 0; ; index++ {
		value := unsafe { text[index] }
		if value != 0 && value !in [` `, `\t`, `\r`, `\n`] {
			continue
		}
		length := index - start
		if length == token.len {
			mut matches := true
			for offset := 0; offset < length; offset++ {
				if unsafe { text[start + offset] } != token[offset] {
					matches = false
					break
				}
			}
			if matches {
				return true
			}
		}
		if value == 0 {
			return false
		}
		start = index + 1
	}
	return false
}

fn kmain() {
	// Read the cmdline before touching anything else. The framebuffer used to
	// be written first, which made it impossible to tell a kernel that never
	// ran from one that faulted on the very first pixel: both leave the black
	// screen Limine hands over, and neither reaches the code that could say
	// otherwise. The cmdline only walks a Limine response, so it is the
	// cheapest thing that can run before the answer is needed.
	halt_at_stage = early_cmdline_value('vinix.halt_at=')
	skip_early_term := early_cmdline_contains('vinix.no_early_term=1')
	external_display := early_cmdline_has_token('vinix.display=external')
	term.select_framebuffer(external_display)

	// Stage 0 deliberately precedes every access to hardware state, so its
	// halt asks one question and no other: was the kernel entered at all?
	// Powering off here means Limine's handoff worked and V's globals are
	// readable, before any assumption about the display can interfere.
	if halt_at_stage == 0 {
		cpu.psci_call(cpu.psci_system_off)
		cpu.psci_call(cpu.psci_system_reset)
		for {}
	}

	// From here on a fault resets the machine instead of dying quietly, so the
	// three outcomes a stage halt can produce stay distinguishable: power off
	// means the stage was reached, reboot means something faulted before it,
	// and a black screen means a hang or no entry at all. Only armed while
	// diagnosing, since a normal boot wants a panic message, not a reset.
	if halt_at_stage >= 0 {
		cpu.install_early_fault_reset()
	}

	// Prove the signal channel itself works before trusting what it reports.
	// A deliberate null store should reboot the machine; if it does not, PSCI
	// reset is unavailable here and a quiet machine means nothing.
	if early_cmdline_contains('vinix.force_fault=1') {
		fault_probe := unsafe { &u64(voidptr(0)) }
		unsafe {
			*fault_probe = 0
		}
	}

	// Can we drive this display at all? A whole-screen fill cannot be confused
	// with a dark panel or with leftover bootloader text the way a 16-row bar
	// can. Limine clears the framebuffer before handoff, so black is its work,
	// not evidence about ours; green is. In normal boot flanterm's clear
	// immediately replaces it, so this costs one frame.
	term.early_screen_fill(1)

	// Stage 1 sits after the fill to report whether that fill survived, so
	// halting on it has to happen here rather than in boot_stage.
	if halt_at_stage == 1 {
		cpu.psci_call(cpu.psci_system_off)
		cpu.psci_call(cpu.psci_system_reset)
		for {}
	}

	// Do not hard-stop on base revision mismatch. Some real-hardware boot
	// chains may provide an older Limine build; continue and rely on feature
	// checks for individual requests.
	if limine_base_revision.revision != 0 {
		C.printf(c'limine: base revision negotiation mismatch (value=%llu), continuing\n',
			limine_base_revision.revision)
	}

	// Initialize the memory allocator.
	memory.pmm_init()
	boot_stage(2)

	// Call Vinit to initialise the runtime
	C._vinit(0, 0)
	boot_stage(3)
	// Bring up terminal as early as possible to surface boot progress
	// before we switch to kernel-owned page tables.
	if !skip_early_term {
		term.initialise()
		// 13 proves flanterm_fb_init returned; 14 proves it can render.
		// Both are drawn after its clear, so they survive on screen.
		boot_stage(13)
		print('\n=== Vinix aarch64 (early) ===\n')
		term.report_framebuffer_selection()
		boot_stage(14)
	}

	configure_apple_bringup_from_cmdline()

	// Optional QEMU virt MMIO path (PL011/GIC/Virtio-input). Keep this opt-in
	// so missing DTB on real hardware does not trigger invalid MMIO accesses.
	if force_qemu_platform {
		uart.initialise(memory.get_hhdm_offset() + 0x09000000)
		uart.puts(c'\n=== Vinix aarch64 booting (qemu mode) ===\n')
	}

	// Set up exception vectors (replaces x86 GDT/IDF/ISR)
	exception.initialise()
	boot_stage(4)

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
	boot_stage(if have_dt { u32(5) } else { u32(6) })

	// The framebuffer must survive the page-table switch: it is the first thing
	// written afterwards and the only place a panic can be shown. Map it from
	// its own span so a memory map without a FRAMEBUFFER entry cannot lose it.
	fb_phys, fb_len := term.framebuffer_phys_span()
	memory.declare_framebuffer(fb_phys, fb_len)
	memory.vmm_init()
	boot_stage(7)

	// Init terminal (after vmm_init so page tables are active and framebuffer is mapped)
	if !skip_early_term {
		term.initialise()
	}
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
			// Two channels around the call: a red bar (row 40) and a line with
			// the CPU state, so "nothing after init aic" can be pinned to the
			// call itself, to the callee, or to the text path.
			term.early_stage_mark(40)
			print('aic.0 calling initialise, CurrentEL=${cpu.read_currentel()} DAIF=0x${cpu.read_daif():x}\n')
			if aic.initialise(aic_phys) {
				if timer_irq := parse_aic_guest_virtual_timer_irq() {
					aic_timer_irq = timer_irq
				}
				// Timer is FIQ-delivered on Apple Silicon: service it from the FIQ
				// dispatch path instead of unmasking it as an AIC hardware IRQ.
				aic.register_fiq_handler(aic_fiq_handler)
				use_aic = true
				print('aic: timer via FIQ (dt irq hint ${aic_timer_irq})\n')
				print('aic done\n')
			} else {
				// Keep going on CPU 0 without an interrupt controller: the rest of
				// bring-up (PMGR, timer, scheduler) still tells us how far the
				// hardware gets, and the timer is FIQ-delivered regardless.
				print('aic: unusable, continuing without it\n')
			}
			term.early_stage_mark(47) // gray: back in kmain after the AIC
			print('aic.10 back in kmain\n')
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

		// Apple watchdog: U-Boot leaves it armed with about a minute on the
		// clock, which is why a working boot reset into macOS at the shell.
		wdt_addr := get_dt_base('apple,wdt', 0)
		if wdt_addr != 0 {
			print('init wdt...\n')
			wdt.initialise(wdt_addr)
			print('wdt done\n')
		} else {
			print('no Apple watchdog node in device tree\n')
		}
	} else {
		print('skipping Apple-specific HW init (no device tree)\n')
	}
	boot_stage(8)

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
	boot_stage(9)

	// Interrupt controller: GIC for QEMU virt, AIC for Apple Silicon
	if !use_aic && force_qemu_platform {
		print('init gic (QEMU virt)...\n')
		gic.initialise(memory.get_hhdm_offset())
		print('gic done\n')
	}

	// ARM64 PCI ECAM setup is not wired yet; skip to avoid unsafe probing.
	print('skipping PCI (ARM64 ECAM setup not implemented)\n')

	// Limine has already released every CPU represented by an MP response, so
	// the kernel does not need a device tree to finish their initialisation.
	// This matters for QEMU's UEFI boot, which exposes the CPUs to Limine but
	// does not give the kernel a usable DTB.
	if use_aic {
		print('skipping SMP (minimal Apple bring-up mode)\n')
		bootstrap_cpu0()
	} else if smp.available() {
		print('init smp...\n')
		smp.initialise()
		print('smp done\n')
	} else if have_dt {
		print('skipping SMP (no bootloader MP response; build with -d limine_mp)\n')
		bootstrap_cpu0()
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
	boot_stage(10)

	print('spawning kmain_thread via scheduler...\n')
	// Capture the early platform decision before the scheduler handoff. Limine's
	// response storage is bootloader-owned and must not be re-read later.
	spawn kmain_thread(force_qemu_platform)
	print('spawn done, calling await...\n')

	sched.await()
}
