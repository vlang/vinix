// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// amd64 per-CPU hooks. Topology comes from ACPI here, which numa_acpi.v reads;
// there is no device tree on this architecture.
@[has_globals]
module numa

import acpi
import x86.cpu.local as cpulocal

fn discover_devicetree() int {
	return 0
}

// acpi.initialise() has already located the RSDP by the time the topology is
// read, so there is no reason to ask Limine for it a second time. Only its
// address is taken: the fields behind it are private to that module, and the
// ACPI walker reads them byte-wise anyway.
fn acpi_rsdp_address() u64 {
	return u64(voidptr(rsdp))
}

fn cpu_local_count() int {
	return cpu_locals.len
}

fn cpu_local_at(cpu_number int) &cpulocal.Local {
	if cpu_number < 0 || cpu_number >= cpu_locals.len {
		return unsafe { nil }
	}
	return cpu_locals[cpu_number]
}

// Firmware names a CPU by its local APIC id, which is what SRAT's processor
// affinity entries carry and what smp recorded when it numbered the CPUs.
fn cpu_local_hw_id(cpu_number int) u64 {
	entry := cpu_local_at(cpu_number)
	if entry == unsafe { nil } {
		return 0
	}
	return u64(entry.lapic_id)
}

fn set_cpu_local_node(cpu_number int, node int) {
	mut entry := cpu_local_at(cpu_number)
	if entry == unsafe { nil } {
		return
	}
	entry.numa_node = u32(node)
}

// The logical CPU number lives at the base of the per-CPU area, which GS points
// at. Read without disabling interrupts, so the answer is a preference rather
// than a promise; see the comment on numa.current_node().
fn current_cpu_number() int {
	if cpu_locals.len == 0 {
		return 0
	}
	mut number := u64(0)
	asm volatile amd64 {
		mov number, gs:[0]
		; =r (number)
	}
	if number >= u64(cpu_locals.len) {
		return 0
	}
	return int(number)
}
