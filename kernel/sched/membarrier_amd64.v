// SPDX-License-Identifier: GPL-2.0-or-later
module sched

pub fn membarrier_supported() bool {
	return tlb_vector != 0 && cpu_locals.len > 0 && cpu_locals.len <= max_tlb_cpus
}

// CPUID serializes the instruction stream on every x86-64 CPU, including
// CPUs without SERIALIZE. The memory clobber also orders compiler accesses.
fn serialize_instruction_stream() {
	mut leaf := u32(0)
	asm volatile amd64 {
		cpuid
		; =a (leaf)
		; a (u32(0))
		; rbx
		  rcx
		  rdx
		  memory
	}
}

pub fn synchronize_core() {
	cpu_rendezvous(0, 0, .sync_core)
}

pub fn synchronize_memory() {
	cpu_rendezvous(0, 0, .memory_barrier)
}
