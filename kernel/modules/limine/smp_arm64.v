module limine

// AArch64 SMP structures for Limine protocol.
// On ARM64 the SMP info uses MPIDR instead of LAPIC ID.

pub struct LimineSMPInfo {
pub mut:
	processor_id   u32
	gic_iface_no   u32
	mpidr          u64
	goto_address   fn (&LimineSMPInfo) = unsafe { nil }
	extra_argument u64
}

pub struct LimineSMPResponse {
pub mut:
	revision  u64
	flags     u32
	bsp_mpidr u64
	cpu_count u64
	cpus      &&LimineSMPInfo
}

pub struct LimineSMPRequest {
pub mut:
	id       [4]u64 = [
	u64(0xc7b1dd30df4c8b88),
	0x0a82e883a194f07b,
	0x95a67b819a1b857e,
	0xa0b61b723b6a73e0,
]!
	revision u64
	response &LimineSMPResponse
	flags    u64
}
