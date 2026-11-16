// SPDX-License-Identifier: GPL-2.0-or-later
module g13contract

fn check_heap_metadata_local(source string) ! {
 gc := section(source, 'fn (mut h HeapAllocator) gc_locked()', '// Return the total number', 'Heap metadata GC')!
 require_order(gc, ['if a.va + a.size == h.top && !a.in_use',
  'h.top = if idx == 0 { h.start } else {', 'previous := h.allocations[idx - 1]',
  'previous.va + previous.size',
  'h.allocations.delete(idx)', 'unsafe { free(a) }', 'progress = true', 'idx--'],
  'Only unlinked free suffix records may be destroyed')!
 require(gc.count('free(a)') == 1, 'Heap metadata retires once')!
 release := section(source, 'pub fn (mut h HeapAllocator) release(', '// Compact free allocations', 'Heap release')!
 require(!release.contains('free('), 'Interior metadata stays owned until GC')!
 for method in ['alloc(', 'release(', 'gc()', 'used()', 'available()'] {
  body := section(source, 'pub fn (mut h HeapAllocator) ' + method, '\n}\n', 'Heap metadata reader serialization')!
  require_order(body, ['h.lock.acquire()', 'defer {', 'h.lock.release()'], 'All readers serialize with metadata destruction')!
 }
 require(source.count('} @[freed]') == 1, 'The shared metadata constructor retains its verified-free annotation')!
}

fn check_heap_metadata_reference(source string) ! {
 require(source.contains('pub(crate) struct HeapAllocation(Option<mm::Node<HeapAllocatorInner, HeapAllocationInner>>);'),
  'Asahi allocation owns its metadata node')!
 drop := section(source, 'impl Drop for HeapAllocation {', 'impl mm::AllocInner<HeapAllocationInner>', 'Asahi heap owner destruction')!
 require_order(drop, ['let node = self.0.take().unwrap()', 'alloc.with(|a|',
  'garbage.push(node, GFP_KERNEL)', 'Some(node)'], 'Asahi transfers metadata to garbage or drops its owner')!
}
