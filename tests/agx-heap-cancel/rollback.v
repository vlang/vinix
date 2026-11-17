@[has_globals]
module gpu

import gpu.agx.alloc
import gpu.agx.pgtable
import gpu.agx.tlb
import memory

#include <sanitizer/asan_interface.h>
fn C.__asan_address_is_poisoned(voidptr) int

__global higher_half = u64(0)
__global cancel_host_page_size = u64(16384)
__global uat_mgr = unsafe { &HostUat(nil) }
__global active_heap = unsafe { &alloc.HeapAllocator(nil) }
__global canceled = unsafe { &alloc.Allocation(nil) }
__global cancel_pending_record = unsafe { &alloc.Allocation(nil) }
__global physical = u64(0)
__global rolled_back = false
__global returned_pages = 0
__global cancel_partial_witness = false
struct HostUat { pt &pgtable.UatPgtable }

fn (host &HostUat) map_kernel(va u64, phys u64, size u64, protection u64) bool {
	for record in active_heap.allocations { if record.va == va { canceled = record } }
	physical = phys
	mut pt := unsafe { host.pt }
	pte := pt.get_pte(va, false) or { panic('primed first leaf table') }
	tlb.observe(pte, unsafe { nil }); tlb.clear()
	assert !pt.map(va, phys, size, protection)
	assert cancel_partial_witness, 'failure must occur after two leaves have been installed'
	for i in 0 .. 3 { if _ := pt.translate(va + u64(i) * alloc.gpu_page_size) { panic('partial mapping survived rollback') } }
	calls := tlb.calls()
	assert calls.len == 1 && calls[0].pte == 0, 'partial leaves must be invalidated before VA cancellation'
	unsafe { calls.free() }
	rolled_back = true
	return false
}
fn observe_partial_mapping() {
	pt := uat_mgr.pt
	assert pt.translate(canceled.va) or { u64(0) } == physical
	assert pt.translate(canceled.va + alloc.gpu_page_size) or { u64(0) } == physical + alloc.gpu_page_size
	if _ := pt.translate(canceled.va + 2 * alloc.gpu_page_size) { panic('third leaf must still be absent at the injected failure') }
	cancel_partial_witness = true
}
fn check_free(pointer voidptr, pages u64) {
	assert u64(pointer) == physical && pages == 3 && rolled_back
	assert C.__asan_address_is_poisoned(cancel_pending_record) == 0, 'rollback must preserve unrelated pending ranges'
	assert C.__asan_address_is_poisoned(canceled) != 0, 'unpublished metadata must retire before physical backing'
	count, bytes := active_heap.garbage(); assert count == 1 && bytes == alloc.gpu_page_size
	returned_pages++
}

pub fn check_rollback() {
	mut cases := 0
	for cycle in 0 .. 32 { for global in [false, true]! { for explicit in [false, true]! {
		start := alloc.g13_private_start + (u64(cycle + 1) << 25) - 4 * alloc.gpu_page_size
		mut heap := if explicit { alloc.new_heap_with_explicit_gc('rollback', start, start + 8 * alloc.gpu_page_size) }
			else { alloc.new_heap('rollback', start, start + 8 * alloc.gpu_page_size) }
		old := heap.alloc(1, 0) or { panic('pending') }; cancel_pending_record = heap.allocations[0]
		pin := heap.alloc(1, 0) or { panic('pin') }; pin_record := heap.allocations[1]
		target := heap.alloc(3 * alloc.gpu_page_size, 0) or { panic('target') }
		high := heap.alloc(1, 0) or { panic('upper pin') }; high_record := heap.allocations[3]
		heap.cancel_unpublished(target); heap.release(old)
		mut pt := pgtable.new_pgtable(39, 48) or { panic('page table') }
		pt.non_global = !global; pt.bind_tlb(7)
		assert pt.map(pin, 0x200000, alloc.gpu_page_size, pgtable.gpu_prot_fw_shared_rw)
		mut host := HostUat{pt: pt}; uat_mgr = unsafe { &host }; active_heap = unsafe { &heap }
		rolled_back = false; returned_pages = 0; canceled = unsafe { nil }; cancel_partial_witness = false
		memory.observe_failure(observe_partial_mapping)
		memory.observe_free(check_free); memory.fail_after(1)
		if _ := alloc_buffer_from_heap(mut heap, 3 * alloc.gpu_page_size, pgtable.gpu_prot_fw_shared_rw, 0) { panic('failed mapping published a buffer') }
		assert returned_pages == 1 && heap.allocations.len == 3 && heap.top == high + alloc.gpu_page_size
		assert heap.allocations[1] == pin_record && heap.allocations[2] == high_record
		assert pt.translate(pin) or { u64(0) } == 0x200000
		memory.observe_free(fn (_ voidptr, _ u64) {}); memory.observe_failure(fn () {}); memory.fail_after(-1)
		reused := heap.alloc(3 * alloc.gpu_page_size, 0) or { panic('canceled range reuse') }; assert reused == target
		assert pt.map(reused, 0x300000, 3 * alloc.gpu_page_size, pgtable.gpu_prot_fw_shared_rw)
		assert pt.translate(pin) or { u64(0) } == 0x200000
		pt.unmap(reused, 3 * alloc.gpu_page_size); pt.unmap(pin, alloc.gpu_page_size)
		heap.release(reused); heap.release(pin); heap.release(high); heap.gc()
		tlb.observe(unsafe { nil }, unsafe { nil }); tlb.clear(); pt.unbind_tlb(); pgtable.destroy(pt)
		unsafe { free(pt); heap.allocations.free() }; assert memory.live_pages() == 0
		active_heap = unsafe { nil }; uat_mgr = unsafe { nil }; cases++
	} } }
	assert cases == 128
	println('AGX rollback: 128 real page-table failures invalidate partial leaves before cancellation and PMM free, preserve pending/live owners, then reuse the canceled hole')
}
