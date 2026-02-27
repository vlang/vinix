@[has_globals]
module regs

// Apple AGX GPU MMIO register definitions and access
// Translates the Asahi Linux driver gpu.rs register parts

import aarch64.kio
import aarch64.cpu
import memory

// Register block offsets from GPU base
pub const sgx_base = u64(0x2000000)

// ASC (Apple Silicon Controller) registers
pub const asc_ctl = u32(0x44)
pub const asc_ctl_cpu_run = u32(1 << 4)

// SGX timer/control registers
pub const sgx_fast_timer_ul = u32(0x10000)
pub const sgx_idle_timer = u32(0x10004)
pub const sgx_fault_info = u32(0x17030)
pub const sgx_doa_outstanding_acks = u32(0x17400)

// GPU ID registers
pub const gpu_id_version = u32(0xD04000)
pub const gpu_id_count = u32(0xD04008)
pub const gpu_id_clustercfg = u32(0xD04010)

// GPU resource handle -- encapsulates base addresses for MMIO access
pub struct GpuResources {
pub mut:
	base u64 // MMIO base (HHDM-mapped)
	sgx  u64 // SGX block base
	asc  u64 // ASC block base
}

// Fault information from GPU fault registers
pub struct FaultInfo {
pub:
	addr      u64
	write     bool
	vm_slot   u32
	unit_code u8
}

// Create a new GpuResources from a physical base address
pub fn new_resources(base u64) GpuResources {
	mapped_base := base + higher_half
	return GpuResources{
		base: mapped_base
		sgx:  mapped_base + sgx_base
		asc:  mapped_base
	}
}

// Read a 32-bit value from a register offset relative to base
pub fn (r &GpuResources) read32(offset u32) u32 {
	return kio.mmin32(unsafe { &u32(r.base + offset) })
}

// Write a 32-bit value to a register offset relative to base
pub fn (r &GpuResources) write32(offset u32, value u32) {
	kio.mmout32(unsafe { &u32(r.base + offset) }, value)
}

// Read a 32-bit value from SGX register space
pub fn (r &GpuResources) sgx_read32(offset u32) u32 {
	return kio.mmin32(unsafe { &u32(r.sgx + offset) })
}

// Write a 32-bit value to SGX register space
pub fn (r &GpuResources) sgx_write32(offset u32, value u32) {
	kio.mmout32(unsafe { &u32(r.sgx + offset) }, value)
}

// Start the GPU coprocessor CPU via ASC_CTL
pub fn (r &GpuResources) start_cpu() {
	mut ctl := r.read32(asc_ctl)
	ctl |= asc_ctl_cpu_run
	r.write32(asc_ctl, ctl)
	cpu.dsb_sy()
	cpu.isb()
	println('agx: GPU ASC CPU started')
}

// Stop the GPU coprocessor CPU
pub fn (r &GpuResources) stop_cpu() {
	mut ctl := r.read32(asc_ctl)
	ctl &= ~asc_ctl_cpu_run
	r.write32(asc_ctl, ctl)
	cpu.dsb_sy()
}

// Read fault info after a GPU fault
pub fn (r &GpuResources) get_fault_info() FaultInfo {
	status := r.sgx_read32(sgx_fault_info)
	addr_lo := r.sgx_read32(sgx_fault_info + 4)
	addr_hi := r.sgx_read32(sgx_fault_info + 8)

	return FaultInfo{
		addr:      u64(addr_lo) | (u64(addr_hi) << 32)
		write:     (status & (1 << 1)) != 0
		vm_slot:   (status >> 8) & 0xff
		unit_code: u8(status >> 24)
	}
}

// Get GPU ID: returns (version, core_count)
pub fn (r &GpuResources) get_gpu_id() (u32, u32) {
	version := r.sgx_read32(gpu_id_version)
	core_count := r.sgx_read32(gpu_id_count)
	return version, core_count
}
