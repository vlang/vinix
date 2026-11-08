// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module main

import powerpc.boot
import powerpc.cpu
import powerpc.exception
import powerpc.pages
import powerpc.serial
import powerpc.runtime as _

__global physical_pages pages.Pool
__global ticks u32
__global interval u32
__global traps u32

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
	serial.init(info.serial_control, info.serial_data)
	serial.text(c'\nVinix PowerPC kernel: firmware takeover\n')
	if info.magic != boot.magic || info.version != boot.version || info.bytes != sizeof(boot.Info)
		|| info.available_count > 64 || info.serial_control == 0 || info.timebase_hz < 100 {
		halt(c'boot information')
	}
	for i := u32(0); i < info.available_count; i++ {
		range := info.available[i]
		if !physical_pages.add(range.base, range.size) { halt(c'physical memory map') }
	}
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
	for {}
}

@[export: 'vinix_ppc_dispatch']
fn dispatch(mut frame exception.Frame) {
	if frame.vector == 0x900 {
		ticks++
		exception.decrementer(interval)
		return
	}
	if frame.vector == 0xc00 {
		traps++
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
