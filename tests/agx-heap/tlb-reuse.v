// SPDX-License-Identifier: GPL-2.0-or-later
module main

import gpu.agx.alloc
import gpu.agx.pgtable
import gpu.agx.tlb
import memory

#include <sanitizer/asan_interface.h>
fn C.__asan_address_is_poisoned(voidptr) int

fn main() {
 assert !pgtable.is_cached_noncoherent(pgtable.gpu_prot_fw_shared_rw)
 for cycle in 0 .. 100 {
  for global in [false, true]! {
   for deferred in [false, true]! {
   start := if global { alloc.g13_shared_start } else { u64(0x100000) }
   mut heap := alloc.new_heap_with_garbage('tlb-reuse', start, start + 4 * alloc.gpu_page_size, deferred)
   mut pt := pgtable.new_pgtable(39, 48) or { panic('page table') }
   pt.non_global = !global
   pt.bind_tlb(7); tlb.clear()
   low := heap.alloc(1, 0) or { panic('low') }
   pin := heap.alloc(3 * alloc.gpu_page_size, 0) or { panic('pin') }
   low_record := heap.allocations[0]
   pin_record := heap.allocations[1]
   old_physical := u64(0x200000) + u64(cycle) * 8 * alloc.gpu_page_size
   new_physical := old_physical + 4 * alloc.gpu_page_size
   assert pt.map(low, old_physical, alloc.gpu_page_size, pgtable.gpu_prot_fw_shared_rw)
   assert pt.map(pin, old_physical + alloc.gpu_page_size, 3 * alloc.gpu_page_size, pgtable.gpu_prot_fw_shared_rw)
   pte := pt.get_pte(low, false) or { panic('low PTE') }
   tlb.observe(pte, unsafe { nil }); tlb.clear()
   pt.unmap(low, alloc.gpu_page_size)
   removed := tlb.calls()
   assert removed.len == 1 && removed[0].pte == 0 && removed[0].all == global,
    'old translation must be invalidated before heap release and reuse'
   assert pt.translate(pin) or { u64(0) } == old_physical + alloc.gpu_page_size
   heap.release(low)
   if deferred {
    assert C.__asan_address_is_poisoned(low_record) == 0
    heap.gc()
   }
   assert C.__asan_address_is_poisoned(low_record) != 0 && C.__asan_address_is_poisoned(pin_record) == 0,
    'manual-free collection must retire old metadata while preserving the live pin'
   reused := heap.alloc(1, 0) or { panic('reuse') }
   assert reused == low && heap.top == heap.end
   reused_record := heap.allocations[0]
   assert heap.allocations[1] == pin_record
   tlb.clear()
   assert pt.map(reused, new_physical, alloc.gpu_page_size, pgtable.gpu_prot_fw_shared_rw)
   mapped := tlb.calls()
   assert mapped.len == 1 && mapped[0].pte == unsafe { *pte } && mapped[0].all == global
   assert pt.translate(reused) or { u64(0) } == new_physical
   assert pt.translate(pin) or { u64(0) } == old_physical + alloc.gpu_page_size
   pt.unmap(reused, alloc.gpu_page_size); heap.release(reused)
   pt.unmap(pin, 3 * alloc.gpu_page_size); heap.release(pin); heap.gc()
   assert heap.allocations.len == 0 && heap.top == heap.start
   assert C.__asan_address_is_poisoned(reused_record) != 0 && C.__asan_address_is_poisoned(pin_record) != 0
   pt.unbind_tlb(); tlb.observe(unsafe { nil }, unsafe { nil }); tlb.clear()
   pgtable.destroy(pt)
   assert C.__asan_address_is_poisoned(pt) != 0, 'destruction must release the table wrapper'
   unsafe { heap.allocations.free() }
   assert memory.live_pages() == 0
   }
  }
 }
 println('AGX heap/TLB reuse: 400 policy/global/ASID cycles invalidate old leaves before lower-hole reuse, preserve live pins and release all page tables')
}
