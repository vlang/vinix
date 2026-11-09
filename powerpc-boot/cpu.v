// SPDX-License-Identifier: GPL-2.0-or-later
module main

import powerpc.cpu

fn check_cpu() bool {
	puts(c'VINIX-PPC: PVR ')
	hex(cpu.read_pvr())
	puts(c' MSR ')
	hex(cpu.read_msr())
	puts(c'\r\n')
	before := cpu.timebase()
	mut word := u32(7)
	if cpu.compare_exchange32(unsafe { &word }, 7, 9) != 7 || word != 9 { return false }
	if cpu.compare_exchange32(unsafe { &word }, 7, 11) != 9 || word != 9 { return false }
	cpu.sync()
	cpu.io_barrier()
	cpu.publish_code(u32(voidptr(C.vinix_ppc_read_pvr)), 8)
	if cpu.timebase() <= before || cpu.read_pvr() == 0 { return false }
	puts(c'VINIX-PPC: PASS cpu clock atomics cache\r\n')
	return true
}

fn C.vinix_ppc_read_pvr() u32
