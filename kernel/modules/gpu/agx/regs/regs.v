@[has_globals]
module regs

// Apple AGX GPU MMIO register definitions and access
// Translates the Asahi Linux driver gpu.rs register parts

import aarch64.kio
import aarch64.cpu
import memory

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
pub const gpu_id_identity_14 = u32(0xD04014)
pub const gpu_id_identity_18 = u32(0xD04018)
pub const gpu_id_identity_1c = u32(0xD0401C)

// Apple's readChipInfo decodes the chip variant out of the version register:
// byte 3 must be the family value, and byte 2 selects the variant. That
// variant reaches the accelerator at +0x4a0 and is what the G17 power model
// switches on -- 0x21 picks one set of coefficients, 0x22 another leakage
// parameter table.
pub const gpu_id_version_family_shift = u32(24)
pub const gpu_id_version_family_agx = u32(0x0b)
pub const gpu_id_version_variant_shift = u32(16)
pub const gpu_chip_variant_g17_base = u32(0x20)

// GPU topology as Apple's readChipInfo derives it from the cluster
// configuration register. The core count this yields matches the count the
// accelerator publishes: on Mac17,6 the register gives four clusters of ten,
// and the driver reports forty cores.
pub struct GpuIdentity {
pub:
	clusters          u32
	cores_per_cluster u32
	core_count        u32
	unit_count        u32
	// core_count * unit_count, which the firmware late-control block reads
	// back through accelerator +0x4b0.
	scaled_core_count u32
}

pub fn decode_gpu_identity(cluster_config u32) GpuIdentity {
	clusters := (cluster_config >> 16) & 0xf
	per_cluster := (cluster_config >> 8) & 0xff
	units := cluster_config & 0xff
	cores := per_cluster * clusters
	return GpuIdentity{
		clusters: clusters
		cores_per_cluster: per_cluster
		core_count: cores
		unit_count: units
		scaled_core_count: cores * units
	}
}

// Decode the chip variant, or none when the register does not describe a
// family this decode was recovered against.
pub fn decode_gpu_chip_variant(version u32) ?u32 {
	if (version >> gpu_id_version_family_shift) & 0xff != gpu_id_version_family_agx {
		return none
	}
	selector := (version >> gpu_id_version_variant_shift) & 0xff
	if selector < 2 || selector > 4 {
		return none
	}
	// Selectors 2, 3 and 4 map onto 0x20, 0x21 and 0x22.
	return gpu_chip_variant_g17_base + (selector - 2)
}

// GPU resource handle -- encapsulates base addresses for MMIO access
pub struct GpuResources {
pub mut:
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

// ASC and SGX are separate named resources in the Apple GPU device tree.

pub fn new_resources(asc_base u64, asc_size u64, sgx_base u64, sgx_size u64) GpuResources {
	// Apple places both apertures far above the 4 GiB direct-map window. Map
	// them explicitly as Device-nGnRnE before any ASC or SGX register access.
	return GpuResources{
		sgx: memory.map_mmio(sgx_base, sgx_size)
		asc: memory.map_mmio(asc_base, asc_size)
	}
}

// Read a 32-bit value from a register offset relative to base
pub fn (r &GpuResources) read32(offset u32) u32 {
	return kio.mmin32(unsafe { &u32(r.asc + offset) })
}

// Write a 32-bit value to a register offset relative to base
pub fn (r &GpuResources) write32(offset u32, value u32) {
	kio.mmout32(unsafe { &u32(r.asc + offset) }, value)
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
