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

// GPU core-mask registers. Apple's readChipInfo maps these separately from the
// ordinary register accessor, but the base it uses is getGPUPhysicalAddress(),
// which probe sets to the physical address of device-memory range 0 -- the
// same SGX aperture sgx_read32 addresses. Words 0 and 1 form a 64-bit mask and
// word 2 a 32-bit one.
pub const gpu_core_mask_lo = u32(0xE01500)
pub const gpu_core_mask_hi = u32(0xE01504)
pub const gpu_core_mask_ext = u32(0xE01508)

// Apple's readChipInfo decodes the chip variant out of the version register:
// byte 3 must be the family value, and byte 2 selects the variant. That
// variant reaches the accelerator at +0x4a0 and is what the G17 power model
// switches on -- 0x21 picks one set of coefficients, 0x22 another leakage
// parameter table.
pub const gpu_id_version_family_shift = u32(24)
pub const gpu_id_version_family_agx = u32(0x0b)
pub const gpu_id_version_variant_shift = u32(16)
pub const gpu_chip_variant_g17_base = u32(0x20)

// Identity register +0x18 carries six nibbles, paired into three products.
// Apple stores them at chip-info +0x48/+0x4c/+0x50; the last is the unit count
// the firmware's late-control mask is sized from.
pub fn gpu_identity_nibble_products(identity u32) (u32, u32, u32) {
	return (identity & 0xf) * ((identity >> 16) & 0xf), ((identity >> 4) & 0xf) * ((identity >> 20) & 0xf), ((identity >> 8) & 0xf) * ((identity >> 24) & 0xf)
}

// Mask of `count` low bits. Apple shifts in 64 bits and keeps the low word, so
// any count of 32 or more yields all ones, and a count past 63 is saturated
// explicitly rather than wrapping on the shift.
pub fn gpu_unit_mask(count u32) u32 {
	if count >= 32 {
		return 0xffffffff
	}
	return u32((u64(1) << count) - 1)
}

// The late-control unit mask, read and derived the way Apple does.
pub fn (r &GpuResources) gpu_unit_count_mask() u32 {
	_, _, units := gpu_identity_nibble_products(r.sgx_read32(gpu_id_identity_18))
	return gpu_unit_mask(units)
}

// Number of enabled GPU cores, counted the way the firmware's late-control
// block does: the population count of the two core masks. Reading the
// registers rather than trusting a published topology keeps this correct on
// parts with cores fused off.
pub fn (r &GpuResources) enabled_gpu_core_count() u32 {
	low := u64(r.sgx_read32(gpu_core_mask_lo))
	high := u64(r.sgx_read32(gpu_core_mask_hi))
	extended := u64(r.sgx_read32(gpu_core_mask_ext))
	return u32(popcount64(low | (high << 32)) + popcount64(extended))
}

fn popcount64(value u64) u32 {
	mut remaining := value
	mut count := u32(0)
	for remaining != 0 {
		remaining &= remaining - 1
		count++
	}
	return count
}

// Internal GPU dimensions as Apple's readChipInfo derives them from the
// cluster-configuration register. These are the power-model column/group
// counts copied to accelerator +0x4e4/+0x4ec; they are not the public shader
// core and GPU-partition counts in GPUConfigurationVariable. In particular,
// the G17C leakage producer has only eight selectors for +0x4e4 columns and a
// two-element destination for +0x4ec groups.
pub struct GpuIdentity {
pub:
	group_count       u32
	columns_per_group u32
	column_count      u32
	units_per_column  u32
	// column_count * units_per_column, copied through accelerator +0x4b0.
	// The selected late-control producer does not use this fallback value.
	scaled_column_count u32
}

pub fn decode_gpu_identity(cluster_config u32) GpuIdentity {
	groups := (cluster_config >> 16) & 0xf
	per_group := (cluster_config >> 8) & 0xff
	units := cluster_config & 0xff
	columns := per_group * groups
	return GpuIdentity{
		group_count: groups
		columns_per_group: per_group
		column_count: columns
		units_per_column: units
		scaled_column_count: columns * units
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
