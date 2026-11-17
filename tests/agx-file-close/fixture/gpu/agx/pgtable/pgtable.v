module pgtable

pub const uat_pgsz = u64(0x4000)
pub const uat_pg_mask = u64(0x3fff)

pub const gpu_prot_gpu_shared_rw = u64(1)
pub const gpu_prot_gpu_shared_ro = u64(2)
pub const gpu_prot_gpu_shared_wo = u64(3)
pub const gpu_prot_fw_shared_rw = u64(9)

pub struct UatPgtable {
pub mut:
	maps int
	tlb_bound bool = true
	unmaps int
	reject_map bool
	reject_prepare bool
	prepares int
	destroyed bool
	last_protection u64
	last_phys u64
	last_size u64
	repeated bool
	last_unmap_size u64
	last_unmap_addr u64
	watch_start u64
	leaves [32]u64
	protections [32]u64
}

pub fn (mut pt UatPgtable) prepare_map_range(addr u64, size u64) bool {
	assert !pt.destroyed
	pt.prepares++
	return !pt.reject_prepare
}

fn (mut pt UatPgtable) watch_map(addr u64, phys u64, size u64, repeated bool) {
	if pt.watch_start == 0 { return }
	for i in 0 .. 32 {
		va := pt.watch_start + u64(i) * uat_pgsz
		if va >= addr && va - addr < size {
			pt.leaves[i] = phys + if repeated { u64(0) } else { va - addr }
			pt.protections[i] = pt.last_protection
		}
	}
}

pub fn (mut pt UatPgtable) map(addr u64, phys u64, size u64, protection u64) bool {
	assert !pt.destroyed, 'map through a destroyed VM page table'
	pt.maps++
	pt.last_protection = protection
	pt.last_phys = phys; pt.last_size = size; pt.repeated = false
	if !pt.reject_map { pt.watch_map(addr, phys, size, false) }
	return !pt.reject_map
}

pub fn (mut pt UatPgtable) map_repeated_page(addr u64, phys u64, size u64, protection u64) bool {
	assert !pt.destroyed, 'repeated map through a destroyed VM page table'
	pt.maps++; pt.last_protection = protection
	pt.last_phys = phys; pt.last_size = size; pt.repeated = true
	if !pt.reject_map { pt.watch_map(addr, phys, size, true) }
	return !pt.reject_map
}

pub fn (mut pt UatPgtable) unmap(addr u64, size u64) {
	assert !pt.destroyed, 'unmap through a destroyed VM page table'
	pt.unmaps++
	pt.last_unmap_size = size
	pt.last_unmap_addr = addr
	if pt.watch_start != 0 {
		for i in 0 .. 32 {
			va := pt.watch_start + u64(i) * uat_pgsz
			if va >= addr && va - addr < size { pt.leaves[i] = 0; pt.protections[i] = 0 }
		}
	}
}
