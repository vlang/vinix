module pgtable

pub const gpu_prot_gpu_shared_rw = u64(1)
pub const gpu_prot_gpu_shared_ro = u64(2)

pub struct UatPgtable {
pub mut:
	maps int
	unmaps int
	reject_map bool
	destroyed bool
}

pub fn (mut pt UatPgtable) map(addr u64, phys u64, size u64, protection u64) bool {
	assert !pt.destroyed, 'map through a destroyed VM page table'
	pt.maps++
	return !pt.reject_map
}

pub fn (mut pt UatPgtable) unmap(addr u64, size u64) {
	assert !pt.destroyed, 'unmap through a destroyed VM page table'
	pt.unmaps++
}
