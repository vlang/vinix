module pgtable

pub const gpu_prot_gpu_shared_rw = u64(1)
pub const gpu_prot_gpu_shared_ro = u64(2)
pub const gpu_prot_gpu_shared_wo = u64(3)

pub struct UatPgtable {
pub mut:
	maps int
	unmaps int
	reject_map bool
	destroyed bool
	last_protection u64
}

pub fn (mut pt UatPgtable) map(addr u64, phys u64, size u64, protection u64) bool {
	assert !pt.destroyed, 'map through a destroyed VM page table'
	pt.maps++
	pt.last_protection = protection
	return !pt.reject_map
}

pub fn (mut pt UatPgtable) unmap(addr u64, size u64) {
	assert !pt.destroyed, 'unmap through a destroyed VM page table'
	pt.unmaps++
}
