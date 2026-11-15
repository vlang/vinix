@[has_globals]
module pgtable

pub const uat_pgsz = u64(0x4000)
pub const uat_pg_mask = uat_pgsz - 1
pub const gpu_prot_gpu_shared_rw = u64(1)
pub const gpu_prot_fw_gpu_cached_rw = u64(2)

pub struct UatPgtable {
pub mut:
	maps int
	unmaps int
	reject_next bool
	last_address u64
	last_size u64
	last_protection u64
}

__global live = 0
__global attempts = 0
__global reject_new = false
__global reject_dummy = false

pub fn active() int { return live }
pub fn calls() int { return attempts }
pub fn fail_new() { reject_new = true }
pub fn fail_dummy() { reject_dummy = true }

pub fn new_pgtable(_ias u32, _oas u32) ?&UatPgtable {
	attempts++
	if reject_new { reject_new = false; return none }
	live++
	return &UatPgtable{ reject_next: reject_dummy }
}

pub fn destroy(table &UatPgtable) {
	live--
	assert live >= 0
	unsafe { free(table) }
}

pub fn (mut table UatPgtable) map(address u64, _phys u64, size u64, protection u64) bool {
	assert address % uat_pgsz == 0 && size % uat_pgsz == 0
	table.maps++
	if table.reject_next { table.reject_next = false; reject_dummy = false; return false }
	table.last_address = address
	table.last_size = size
	table.last_protection = protection
	return true
}

pub fn (mut table UatPgtable) unmap(_address u64, _size u64) { table.unmaps++ }
pub fn is_cached_noncoherent(protection u64) bool { return protection == gpu_prot_fw_gpu_cached_rw }
