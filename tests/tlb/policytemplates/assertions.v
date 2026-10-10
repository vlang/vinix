
fn main() {
 for features in 0 .. 3 {
 cpu.feature_bits = u8(features); pcid_available = true; cpu.control = pcid_enable_bit
 enable_pcid()
 assert !pcid_available && cpu.control & pcid_enable_bit == 0 && take_pcid() == 0
 }
 cpu.feature_bits = 3; pcid_available = true; enable_pcid()
 assert cpu.control & pcid_enable_bit != 0 && flush_kind == 2
 tlb_shootdown = shootdown
 for tag := u16(1); tag < 4096; tag++ { assert take_pcid() == tag }
 assert take_pcid() == 0 && pcid_used[0] & 1 == 0
 mut map_ := Pagemap{top_level: unsafe { &u64(0x12345000) }, tlb_tag: 127}
 switch_cr3(map_.tagged_root()); assert cpu.hardware_root == (u64(0x1234507f) | cr3_no_flush)
 cpu.hardware_root = 0x88888000 // CPU switched away, so the old tag is inactive
 invalidate_local_tlb(map_.tagged_root(), 0x400000, false)
 assert flush_kind == 1 && flush_tag == 127
 map_.prepare_tlb_teardown(); assert shootdowns == 1 && pcid_used[1] & (u64(1) << 63) != 0
 map_.release_tlb_tag(); assert map_.tlb_tag == 0 && shootdowns == 2
 assert take_pcid() == 127 && take_pcid() == 0
 for tag := u16(1); tag < 4096; tag++ { map_.tlb_tag = tag; map_.release_tlb_tag() }
 for word in pcid_used { assert word == 0 }
 pcid_selftest()
 for word in pcid_used { assert word == 0 }
 switch_cr3(0x100000); assert cpu.hardware_root == 0x100000 // fallback never suppresses flushing
 assert small_leaf_flags(pte_present | amd64_large_page | large_pat) == pte_present | amd64_large_page
 assert !direct_cache_uniform(direct_large_size) // unverified CPU must use small pages
 direct_cache_valid = true; direct_default_wb = true
 assert !direct_cache_uniform(0) && direct_cache_uniform(direct_large_size)
 physical_mask := u64(0xffffffff000)
 assert record_direct_mtrr(0x200000 | 6, (physical_mask & ~u64(0xfffff)) | 0x800, physical_mask)
 assert !direct_cache_uniform(direct_large_size) // an MTRR boundary bisects the candidate
 direct_mtrr_count = 0
 assert record_direct_mtrr(0x200000 | 0, (physical_mask & ~u64(0x1fffff)) | 0x800, physical_mask)
 assert !direct_cache_uniform(direct_large_size) // uniformly UC is deliberately not promoted
 direct_mtrr_count = 0; direct_default_wb = false
 assert record_direct_mtrr(0x200000 | 6, (physical_mask & ~u64(0x1fffff)) | 0x800, physical_mask)
 assert direct_cache_uniform(direct_large_size) && !direct_cache_uniform(2 * direct_large_size)
 direct_mtrr_count = 0
 assert !record_direct_mtrr(0x201000 | 6, (physical_mask & ~u64(0x1fffff)) | 0x800, physical_mask)
 assert !record_direct_mtrr(6, (physical_mask & ~u64(0x101fff)) | 0x800, physical_mask)
 direct_default_wb = true
 assert !direct_large_eligible(direct_large_size) // missing firmware map
 mut ram := limine.LimineMemmapEntry{base: direct_large_size, length: direct_large_size, @type: 1}
 entries := [unsafe { &ram }]!
 mut firmware := limine.LimineMemmapResponse{entry_count: 1, entries: unsafe { &entries[0] }}
 memmap_req.response = unsafe { &firmware }
 assert !direct_large_eligible(direct_large_size) // reserved/MMIO
 ram.@type = 0; ram.base++
 assert !direct_large_eligible(direct_large_size) // entry starts inside candidate
 ram.base--; ram.length--
 assert !direct_large_eligible(direct_large_size) // entry ends inside candidate
 ram.length++
 assert direct_large_eligible(direct_large_size)
 kernel_pagemap.top_level = pmm_alloc_fallible(1)
 map_direct_span(direct_large_size, 2 * direct_large_size)
 assert direct_large_entries == 1 && live_pages == 3 && reserved_pages == 2
 entry := kernel_pagemap.kernel_pde(direct_large_size, false) or { panic('PDE') }
 original := unsafe { *entry }
 assert kernel_pagemap.virt2phys(direct_large_size + 4096 + 19) or { 0 } == direct_large_size + 4096
 kernel_pagemap.map_page(direct_large_size + 4096, direct_large_size + 4096,
 pte_present | pte_writable | pte_noexec) or { panic('unchanged block') }
 assert live_pages == 3 && reserved_pages == 2 && unsafe { *entry } == original
 fail_pages = true
 kernel_pagemap.map_page(direct_large_size + 4096, 0x400000, pte_present | pte_noexec) or {}
 assert live_pages == 3 && reserved_pages == 2 && unsafe { *entry } == original
 fail_pages = false; vmm_initialised = true
 kernel_pagemap.map_page(direct_large_size + 4096, 0x400000, pte_present | pte_noexec) or { panic('split') }
 assert live_pages == 4 && reserved_pages == 3 && direct_large_entries == 0
 assert kernel_pagemap.virt2phys(direct_large_size + 4096) or { 0 } == 0x400000
 neighbor := kernel_pagemap.virt2pte(direct_large_size + 8192, false) or { panic('neighbor') }
 assert unsafe { *neighbor } & pte_writable != 0
 kernel_pagemap.flag_page(direct_large_size + 8192, pte_present | pte_noexec) or { panic('protect') }
 assert unsafe { *neighbor } & pte_writable == 0
 kernel_pagemap.unmap_page(direct_large_size + 4096) or { panic('partial unmap') }
 if _ := kernel_pagemap.virt2phys(direct_large_size + 4096) { assert false }
 assert kernel_pagemap.virt2phys(direct_large_size + 8192) or { 0 } == direct_large_size + 8192
 for i := u64(0); i < 512; i++ {
 if i != 1 { kernel_pagemap.unmap_page(direct_large_size + i * page_size) or { panic('cleanup') } }
 }
 assert live_pages == 1 && reserved_pages == 0 // the root is caller-owned
 pmm_free(kernel_pagemap.top_level, 1); assert live_pages == 0
 println('TLB host: PCID ownership, inactive invalidation, fallback, MTRR boundaries, large split and rollback PASS')
}
