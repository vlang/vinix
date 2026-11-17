// SPDX-License-Identifier: GPL-2.0-or-later
module g13contract

fn check_heap_metadata_local(source string) ! {
 constructor := section(source, 'pub fn new_heap(', '\n}\n', 'Heap table ownership')!
 require_order(constructor, ['mut heap := HeapAllocator{',
  'heap.allocations.flags |= .noslices', 'return heap'],
  'Heap table exclusively owns its buffer before the first append')!
 gc := section(source, 'fn (mut h HeapAllocator) collect_garbage_locked(', '// Return the total number', 'Heap metadata GC')!
 require_order(gc, ['mut collect_left := if count < h.garbage_count { count } else { h.garbage_count }',
  'for collect_left > 0', 'mut idx := 0', 'for idx < h.allocations.len', 'a := h.allocations[idx]',
  'if !a.in_use && a.release_order == 1 { break }', 'idx++',
  'if idx == h.allocations.len { return }', 'mut a := h.allocations[idx]', 'if a.va + a.size == h.top {',
  'h.top = if idx == 0 { h.start } else {', 'previous := h.allocations[idx - 1]',
  'previous.va + previous.size',
  'h.garbage_count--', 'h.garbage_bytes -= a.size',
  'for mut pending in h.allocations', 'if pending.release_order > 1 { pending.release_order-- }',
  'h.allocations.delete(idx)', 'unsafe { free(a) }', 'collect_left--'],
  'Only the bounded oldest released prefix is unlinked before destruction while live frontiers remain stable')!
 require(gc.count('free(a)') == 1, 'Heap metadata retires once')!
 require(gc.count('break') == 1 && gc.count('return') == 1 && !gc.contains('continue') && gc.count('idx++') == 1
  && gc.count('collect_left--') == 1, 'Each iteration finds one oldest release and retires one bounded item')!
 full := section(source, 'fn (mut h HeapAllocator) gc_locked()', '// Return the count', 'Full metadata GC')!
 require(full.contains('h.collect_garbage_locked(h.garbage_count)'), 'Full GC delegates the complete pending count')!
 release := section(source, 'pub fn (mut h HeapAllocator) release(', '// Collect every released record', 'Heap release')!
 require(!release.contains('free('), 'Interior metadata stays owned until GC')!
 require_order(release, ['if a.va == va && a.in_use', 'a.in_use = false',
  'h.garbage_count++', 'a.release_order = h.garbage_count', 'h.garbage_bytes += a.size'],
  'A first release assigns one bounded FIFO rank and counts rounded bytes')!
 for method in ['alloc(', 'release(', 'gc()', 'used()', 'available()', 'garbage()', 'collect_garbage(count u64)'] {
  body := section(source, 'pub fn (mut h HeapAllocator) ' + method, '\n}\n', 'Heap metadata reader serialization')!
  require_order(body, ['h.lock.acquire()', 'defer {', 'h.lock.release()'], 'All readers serialize with metadata destruction')!
 }
 statistics := section(source, 'pub fn (mut h HeapAllocator) garbage()', '\n}\n', 'Heap garbage statistics')!
 require(statistics.contains('return h.garbage_count, h.garbage_bytes'), 'Garbage statistics publish rounded pending count/bytes')!
 bounded := section(source, 'pub fn (mut h HeapAllocator) collect_garbage(count u64)', '\n}\n', 'Bounded metadata GC')!
 require(bounded.contains('h.collect_garbage_locked(count)'), 'Bounded GC forwards its requested count')!
 require(source.count('} @[freed]') == 1, 'The shared metadata constructor retains its verified-free annotation')!
}

fn check_heap_metadata_reference(source string) ! {
 require(source.contains('pub(crate) struct HeapAllocation(Option<mm::Node<HeapAllocatorInner, HeapAllocationInner>>);'),
  'Asahi allocation owns its metadata node')!
 drop := section(source, 'impl Drop for HeapAllocation {', 'impl mm::AllocInner<HeapAllocationInner>', 'Asahi heap owner destruction')!
 require_order(drop, ['let node = self.0.take().unwrap()', 'alloc.with(|a|',
  'garbage.push(node, GFP_KERNEL)', 'Some(node)'], 'Asahi transfers metadata to garbage or drops its owner')!
 collect := section(source, 'fn collect_garbage(&mut self, mut count: usize)', 'impl Drop for HeapAllocatorInner', 'Asahi garbage collection')!
 require_order(collect, ['inner.garbage.as_mut()', 'for node in g.drain(0..block)',
  'inner.total_garbage -= node.size() as usize', 'garbage.clear()'],
  'Asahi drops collected range nodes independently of higher live allocations')!
}
