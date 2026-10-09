module memory

import katomic

const arm64_file_tracked = u64(1) << 56
const arm64_file_dirty = u64(1) << 55

pub fn (mut map_ Pagemap) protect_file_page_unlocked(address u64) {
	mut entry := map_.virt2pte(address, false) or { return }
	old := katomic.load(entry)
	if old & arm64_file_tracked == 0 { return }
	install_arm64_pte(mut entry, address, old | arm64_pte_ap_ro, true)
}

pub fn (mut map_ Pagemap) sample_file_page_unlocked(address u64, reset bool) PageActivity {
	mut entry := map_.virt2pte(address, false) or { return PageActivity{} }
	old := katomic.load(entry)
	if reset {
		mask := arm64_pte_af | (if old & arm64_file_tracked != 0 { arm64_file_dirty } else { u64(0) })
		install_arm64_pte(mut entry, address, old & ~mask, true)
	}
	return PageActivity{ referenced: old & arm64_pte_af != 0, dirty: old & arm64_file_dirty != 0 }
}

pub fn (mut map_ Pagemap) allow_file_write_unlocked(address u64) bool {
	mut entry := map_.virt2pte(address, false) or { return false }
	old := katomic.load(entry)
	if old & arm64_file_tracked == 0 || old & arm64_pte_ap_user == 0 { return false }
	install_arm64_pte(mut entry, address,
		(old & ~arm64_pte_ap_ro) | arm64_file_dirty | arm64_pte_af, true)
	return true
}

pub fn (mut map_ Pagemap) touch_user_page_unlocked(address u64, write bool) {
	mut entry := map_.virt2pte(address, false) or { return }
	katomic.bts(mut entry, u8(10))
	if write && katomic.load(entry) & arm64_file_tracked != 0 { katomic.bts(mut entry, u8(55)) }
}

// AF is sampled with hardware updates disabled as well as with FEAT_HAFDBS.
// An access-flag fault restores only AF, retaining permissions and dirty state.
pub fn (mut map_ Pagemap) reference_file_page_unlocked(address u64) bool {
	mut entry := map_.virt2pte(address, false) or { return false }
	if katomic.load(entry) & arm64_pte_valid != arm64_pte_valid { return false }
	install_arm64_pte(mut entry, address, katomic.load(entry) | arm64_pte_af, true)
	return true
}
