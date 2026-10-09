module memory

import katomic

const page_accessed = u64(1) << 5
const page_dirty = u64(1) << 6

// Caller holds l. Revoke writes on every alias before collecting dirty bits.
pub fn (mut map_ Pagemap) protect_file_page_unlocked(address u64) {
	mut entry := map_.virt2pte(address, false) or { return }
	mut old := katomic.load(entry)
	if old & pte_file_tracked == 0 { return }
	for !katomic.cas(mut entry, old, old & ~pte_writable) { old = katomic.load(entry) }
	map_.invalidate(address)
}

pub fn (mut map_ Pagemap) sample_file_page_unlocked(address u64, reset bool) PageActivity {
	mut entry := map_.virt2pte(address, false) or { return PageActivity{} }
	mut old := katomic.load(entry)
	if reset {
		mask := page_accessed | (if old & pte_file_tracked != 0 { page_dirty | pte_file_dirty } else { u64(0) })
		for !katomic.cas(mut entry, old, old & ~mask) { old = katomic.load(entry) }
		map_.invalidate(address)
	}
	return PageActivity{ referenced: old & page_accessed != 0, dirty: old & (page_dirty | pte_file_dirty) != 0 }
}

pub fn (mut map_ Pagemap) allow_file_write_unlocked(address u64) bool {
	mut entry := map_.virt2pte(address, false) or { return false }
	mut old := katomic.load(entry)
	if old & pte_file_tracked == 0 || old & pte_user == 0 { return false }
	for !katomic.cas(mut entry, old, old | pte_writable | page_dirty | page_accessed | pte_file_dirty) {
		old = katomic.load(entry)
	}
	map_.invalidate(address)
	return true
}

pub fn (mut map_ Pagemap) touch_user_page_unlocked(address u64, write bool) {
	mut entry := map_.virt2pte(address, false) or { return }
	katomic.bts(mut entry, u8(5))
	if write { katomic.bts(mut entry, u8(6)) }
}

pub fn (mut map_ Pagemap) reference_file_page_unlocked(_address u64) bool { return false }
