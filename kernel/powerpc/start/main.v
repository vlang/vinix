// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module main

import powerpc.boot
import powerpc.cpu
import powerpc.exception
import powerpc.pages
import powerpc.serial
import powerpc.video
import powerpc.ohci
import powerpc.gem
import powerpc.runtime as _

__global physical_pages pages.Pool
__global ticks u32
__global interval u32
__global traps u32
__global startup_info &boot.Info
__global managed_pages u32
__global boot_clock u64

fn C.vinix_ppc_kernel_start(info &boot.Info)

asm ppc raw {
	".pushsection .text.vinix_ppc_entry,\"ax\"\n.balign 4\n"
	".globl vinix_ppc_entry\nvinix_ppc_entry:\n"
	"mfmsr 4\nlis 5,0\nori 5,5,0xe070\nandc 4,4,5\nsync\nmtmsr 4\nisync\nb vinix_ppc_kernel_start\n"
	".popsection\n"
}

fn halt(message &char) {
	serial.text(c'\nVINIX-PPC: PANIC ')
	serial.text(message)
	serial.text(c'\n')
	for {}
}

@[export: 'vinix_ppc_kernel_start']
fn start(info &boot.Info) {
	startup_info = info
	serial.init(info.serial_control, info.serial_data)
	serial.text(c'\nVinix PowerPC kernel: firmware takeover\n')
	if info.magic != boot.magic || info.version != boot.version || info.bytes != sizeof(boot.Info)
		|| info.available_count > 64 || info.serial_control == 0 || info.timebase_hz < 100 {
		halt(c'boot information')
	}
	if video.init(info) { serial.text(c'VINIX-PPC: PASS framebuffer console\n') }
	boot_clock = cpu.timebase()
	for i := u32(0); i < info.available_count; i++ {
		range := info.available[i]
		if !physical_pages.add(range.base, range.size) { halt(c'physical memory map') }
	}
	managed_pages = physical_pages.count
	ohci.init(info, mut physical_pages)
	gem.init(info, mut physical_pages)
	stack := physical_pages.take(16, 1)
	if stack == 0 || !exception.install(stack + 65536) { halt(c'exception stack') }
	interval = info.timebase_hz / 100
	exception.decrementer(interval)
	asm volatile ppc raw { "sc" ; ; ; memory }
	if traps != 1 { halt(c'system-call vector') }
	serial.text(c'VINIX-PPC: PASS kernel exception entry and return\n')
	mut msr := cpu.read_msr() | 0x8000
	asm volatile ppc raw {
		"mtmsr %[msr]\n\tisync"
		; ; [msr] "r" (msr)
		; memory
	}
	for unsafe { *(&u32(&ticks)) } < 3 {
		asm volatile ppc raw { "nop" ; ; ; memory }
	}
	serial.text(c'VINIX-PPC: PASS kernel decrementer interrupts\n')
	msr &= ~u32(0x8000)
	asm volatile ppc raw { "mtmsr %[msr]\nisync" ; ; [msr] "r" (msr) ; memory }
	check_userspace(info.stack.base + info.stack.size - 32)
}

@[export: 'vinix_ppc_dispatch']
fn dispatch(mut frame exception.Frame) {
	if frame.vector == 0x900 {
		ticks++
		exception.decrementer(interval)
		return
	}
	if frame.vector == 0xc00 {
		if frame.msr & 0x4000 != 0 {
			if !user_check_active {
				syscall(mut frame)
				return
			}
			if frame.gpr[0] == 20 {
				frame.gpr[3] = 1
				return
			}
			if frame.gpr[0] == 0x7f02 && user_faults == 4 && frame.pc == 0x4000003c {
				revoked_frame = user_space.translate(0x50000000, false)
				if revoked_frame == 0 || !user_space.unmap(0x50000000) { halt(c'user mapping revocation') }
				return
			}
			if frame.gpr[0] == 0x7f00 && user_faults == 5 {
				frame.pc = u32(voidptr(C.vinix_user_check_done))
				frame.msr = 0
				frame.gpr[1] = resume_stack
				return
			}
			halt(c'user syscall probe')
		}
		traps++
		return
	}
	if user_check_active && frame.msr & 0x4000 != 0 && ((frame.vector == 0x300 && user_faults == 0 && frame.dar == 0x02000000 && frame.pc == 0x40000014)
		|| (frame.vector == 0x700 && user_faults == 1 && frame.pc == 0x40000018)
		|| (frame.vector == 0x300 && user_faults == 2 && frame.dar == 0x40000000 && frame.pc == 0x40000020)
		|| (frame.vector == 0x300 && user_faults == 4 && frame.dar == 0x50000000 && frame.pc == 0x4000003c)) {
		user_faults++
		frame.pc += 4
		return
	}
	if user_check_active && frame.msr & 0x4000 != 0 && frame.vector == 0x400 && user_faults == 3
		&& frame.pc == 0x5000fff0 && frame.lr == 0x4000002c {
		user_faults++
		frame.pc = frame.lr
		return
	}
	serial.text(c'exception ')
	serial.hex(frame.vector)
	serial.text(c' pc ')
	serial.hex(frame.pc)
	serial.text(c' dar ')
	serial.hex(frame.dar)
	halt(c'unhandled exception')
}
