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

// G13/G14 identity uses a different register contract from G14X/G17. These
// names follow the v12.3 Asahi decoder and are kept separate from the modern
// identity helpers below.
pub const g13_id_counts_1 = u32(0xd04010)
pub const g13_id_counts_2 = u32(0xd04014)
pub const g13_id_clusters = u32(0xd0401c)
pub const g13_core_mask_0 = u32(0xd01500)
pub const g13_core_mask_1 = u32(0xd01514)

pub struct G13Identity {
pub:
	revision_code         u32
	num_clusters          u32
	num_cores_per_cluster u32
	num_frags_per_cluster u32
	num_gps_per_cluster   u32
	total_active_cores    u32
	core_masks            [4]u32
}

// Decode the six G13 identity registers without touching MMIO. Keeping this
// pure makes fused-core configurations (including the 7-core base M1 Air)
// deterministic and independently testable.
pub fn decode_g13_identity(version u32, counts_1 u32, counts_2 u32, clusters_reg u32,
	core_mask_0 u32, core_mask_1 u32) ?G13Identity {
	if (version >> 24) & 0xff != 4 || (version >> 16) & 0xff != 2 {
		return none
	}
	revision_code := (version >> 8) & 0xff
	if revision_code != 0x00 && revision_code != 0x01 && revision_code != 0x10
		&& revision_code != 0x11 && revision_code != 0x20 && revision_code != 0x21 {
		return none
	}
	num_clusters := (clusters_reg >> 12) & 0xff
	num_cores := counts_1 & 0xff
	num_gps := (counts_2 >> 16) & 0xff
	if num_clusters == 0 || num_clusters > 4 || num_cores == 0 || num_cores > 32
		|| num_gps == 0 || num_clusters * num_cores > 64 {
		return none
	}

	packed_masks := u64(core_mask_0) | (u64(core_mask_1) << 32)
	cluster_mask := if num_cores == 32 {
		u64(0xffff_ffff)
	} else {
		(u64(1) << num_cores) - 1
	}
	mut masks := [4]u32{}
	mut active := u32(0)
	for cluster := u32(0); cluster < num_clusters; cluster++ {
		mask := u32((packed_masks >> (cluster * num_cores)) & cluster_mask)
		masks[cluster] = mask
		active += popcount64(mask)
	}
	used_bits := num_clusters * num_cores
	if used_bits < 64 && packed_masks >> used_bits != 0 {
		return none
	}
	if active == 0 {
		return none
	}

	return G13Identity{
		revision_code: revision_code
		num_clusters: num_clusters
		num_cores_per_cluster: num_cores
		num_frags_per_cluster: num_cores
		num_gps_per_cluster: num_gps
		total_active_cores: active
		core_masks: masks
	}
}

pub fn validate_g13_identity_decoder() bool {
	base_air := decode_g13_identity(0x04020100, 8, u32(4) << 16, u32(1) << 12, 0x7f, 0) or { return false }
	full_m1 := decode_g13_identity(0x04020100, 8, u32(4) << 16, u32(1) << 12, 0xff, 0) or { return false }
	if base_air.total_active_cores != 7 || base_air.core_masks[0] != 0x7f
		|| full_m1.total_active_cores != 8 || full_m1.core_masks[0] != 0xff {
		return false
	}
	if _ := decode_g13_identity(0x04020100, 8, u32(4) << 16, u32(1) << 12, 0x17f, 0) {
		return false
	}
	return true
}

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

// Number of enabled shader units in one internal power-model column. Apple's
// G17C getEnabledNumUSCs() slices `units_per_column` bits out of the 96-bit
// hardware mask and population-counts that slice. Keep the register words
// separate so a column crossing a 32-bit boundary is handled without a
// language-level 128-bit integer (which the freestanding V toolchain lacks).
pub fn (r &GpuResources) enabled_gpu_usc_count(column u32, units_per_column u32) ?u32 {
	if units_per_column == 0 || units_per_column > 32 || column >= 8
		|| column * units_per_column >= 96
		|| units_per_column > 96 - column * units_per_column {
		return none
	}
	words := [r.sgx_read32(gpu_core_mask_lo), r.sgx_read32(gpu_core_mask_hi),
		r.sgx_read32(gpu_core_mask_ext)]!
	start := column * units_per_column
	mut count := u32(0)
	for offset := u32(0); offset < units_per_column; offset++ {
		bit := start + offset
		if words[bit / 32] & (u32(1) << (bit % 32)) != 0 {
			count++
		}
	}
	return count
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
	sgx                 u64 // SGX block base
	asc                 u64 // Primary ASC block base (firmware role 0)
	secondary_asc       u64 // Secondary ASC block base (firmware role 1)
	firmware_role_count u32
}

// Fault information from GPU fault registers
pub struct FaultInfo {
pub:
	address     u64
	sideband    u8
	vm_slot     u32
	unit_code   u8
	level       u8
	unknown_5   u8
	read        bool
	reason_code u8
}

// ASC and SGX are separate named resources in the Apple GPU device tree.

pub fn new_resources(asc_base u64, asc_size u64, secondary_asc_base u64,
	secondary_asc_size u64, firmware_role_count u32, sgx_base u64, sgx_size u64) GpuResources {
	// Apple places both apertures far above the 4 GiB direct-map window. Map
	// them explicitly as Device-nGnRnE before any ASC or SGX register access.
	secondary_asc := if firmware_role_count == 2 {
		memory.map_mmio(secondary_asc_base, secondary_asc_size)
	} else {
		u64(0)
	}
	return GpuResources{
		sgx: memory.map_mmio(sgx_base, sgx_size)
		asc: memory.map_mmio(asc_base, asc_size)
		secondary_asc: secondary_asc
		firmware_role_count: firmware_role_count
	}
}

fn (r &GpuResources) asc_for_role(role u32) ?u64 {
	if role == 0 && r.firmware_role_count >= 1 {
		return r.asc
	}
	if role == 1 && r.firmware_role_count == 2 && r.secondary_asc != 0 {
		return r.secondary_asc
	}
	return none
}

fn read_asc32(base u64, offset u32) u32 {
	return kio.mmin32(unsafe { &u32(base + offset) })
}

fn write_asc32(base u64, offset u32, value u32) {
	kio.mmout32(unsafe { &u32(base + offset) }, value)
}

// Read a 32-bit value from a register offset relative to base
pub fn (r &GpuResources) read32(offset u32) u32 {
	return read_asc32(r.asc, offset)
}

// Write a 32-bit value to a register offset relative to base
pub fn (r &GpuResources) write32(offset u32, value u32) {
	write_asc32(r.asc, offset, value)
}

// Access an ASC register for one firmware role. G17C has two independent
// ASC wrappers; treating the second mailbox as an offset in the first wrapper
// would address unrelated MMIO.
pub fn (r &GpuResources) read32_for_role(role u32, offset u32) ?u32 {
	base := r.asc_for_role(role) or { return none }
	return read_asc32(base, offset)
}

pub fn (r &GpuResources) write32_for_role(role u32, offset u32, value u32) bool {
	base := r.asc_for_role(role) or { return false }
	write_asc32(base, offset, value)
	return true
}

// Read a 32-bit value from SGX register space
pub fn (r &GpuResources) sgx_read32(offset u32) u32 {
	return kio.mmin32(unsafe { &u32(r.sgx + offset) })
}

pub fn (r &GpuResources) sgx_read64(offset u32) u64 {
	return kio.mmin(unsafe { &u64(r.sgx + offset) })
}

// Write a 32-bit value to SGX register space
pub fn (r &GpuResources) sgx_write32(offset u32, value u32) {
	kio.mmout32(unsafe { &u32(r.sgx + offset) }, value)
}

// Start the GPU coprocessor CPU via ASC_CTL
pub fn (r &GpuResources) start_cpu(role u32) bool {
	mut ctl := r.read32_for_role(role, asc_ctl) or { return false }
	ctl |= asc_ctl_cpu_run
	if !r.write32_for_role(role, asc_ctl, ctl) {
		return false
	}
	cpu.dsb_sy()
	cpu.isb()
	println('agx: GPU ASC role ${role} CPU started')
	return true
}

// Stop the GPU coprocessor CPU
pub fn (r &GpuResources) stop_cpu(role u32) bool {
	mut ctl := r.read32_for_role(role, asc_ctl) or { return false }
	ctl &= ~asc_ctl_cpu_run
	if !r.write32_for_role(role, asc_ctl, ctl) {
		return false
	}
	cpu.dsb_sy()
	return true
}

// Decode the pre-G14X MMU fault register. G13 stores validity, reason, unit,
// context, sideband, and the address (in 64-byte units) in one u64.
pub fn decode_g13_fault_info(raw u64) ?FaultInfo {
	if raw & 1 == 0 {
		return none
	}
	return FaultInfo{
		address: (raw >> 30) << 6
		sideband: u8((raw >> 23) & 0x7f)
		vm_slot: u32((raw >> 17) & 0x3f)
		unit_code: u8((raw >> 9) & 0xff)
		level: u8((raw >> 7) & 3)
		unknown_5: u8((raw >> 5) & 3)
		read: raw & (u64(1) << 4) != 0
		reason_code: u8((raw >> 1) & 7)
	}
}

pub fn validate_g13_fault_decoder() bool {
	address := u64(0x123440)
	raw := u64(1) | (u64(3) << 1) | (u64(1) << 4) | (u64(2) << 5) | (u64(1) << 7) | (u64(0xa1) << 9) | (u64(5) << 17) | (u64(0x12) << 23) | ((address >> 6) << 30)
	info := decode_g13_fault_info(raw) or { return false }
	if info.address != address || info.sideband != 0x12 || info.vm_slot != 5
		|| info.unit_code != 0xa1 || info.level != 1 || info.unknown_5 != 2 || !info.read
		|| info.reason_code != 3 {
		return false
	}
	if _ := decode_g13_fault_info(0) {
		return false
	}
	return true
}

// Read fault info after a G13 GPU fault.
pub fn (r &GpuResources) get_g13_fault_info() ?FaultInfo {
	return decode_g13_fault_info(r.sgx_read64(sgx_fault_info))
}

// Get GPU ID: returns (version, core_count)
pub fn (r &GpuResources) get_gpu_id() (u32, u32) {
	version := r.sgx_read32(gpu_id_version)
	core_count := r.sgx_read32(gpu_id_count)
	return version, core_count
}

pub fn (r &GpuResources) get_g13_identity() ?G13Identity {
	return decode_g13_identity(r.sgx_read32(gpu_id_version), r.sgx_read32(g13_id_counts_1), r.sgx_read32(g13_id_counts_2), r.sgx_read32(g13_id_clusters), r.sgx_read32(g13_core_mask_0), r.sgx_read32(g13_core_mask_1))
}
