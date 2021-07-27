module lib

import trace
import x86.apic
import x86.cpu.local as cpulocal
import katomic

fn C.printf_panic(charptr, ...voidptr)

pub fn kpanic(message charptr) {
	asm volatile amd64 {
		cli
	}
	for cpu_local in cpu_locals {
		if cpulocal.current().lapic_id == cpu_local.lapic_id {
			continue
		}
		apic.lapic_send_ipi(cpu_local.lapic_id, abort_vector)
		for katomic.load(cpu_local.aborted) == false {}
	}
	C.printf_panic(c'KERNEL PANIC: %s\n', message)
	trace.stacktrace(voidptr(0))
	for {
		asm volatile amd64 {
			hlt
		}
	}
}
