// SPDX-License-Identifier: GPL-2.0-or-later
module g13contract

fn check_heap_release_policy_local(allocator string, manager string) ! {
 require(allocator.contains('keep_garbage bool = true'), 'Existing heaps retain deferred release by default')!
 constructor := section(allocator, 'pub fn new_heap_with_garbage(', '\n}\n', 'Heap release policy constructor')!
 require_order(constructor, ['mut heap := new_heap(name, start, end)',
  'heap.keep_garbage = keep_garbage', 'return heap'], 'Release policy is selected only while constructing the heap')!
 release := section(allocator, 'pub fn (mut h HeapAllocator) release(', '// Collect every released record', 'Heap release policy')!
 require_order(release, ['h.lock.acquire()', 'if a.va == va && a.in_use',
  'a.in_use = false', 'h.garbage_count++', 'a.release_order = h.garbage_count', 'h.garbage_bytes += a.size',
  'if !h.keep_garbage { h.collect_garbage_locked(1) }', 'return'],
  'Only nondeferred heaps retire their one released owner before unlocking')!
 for line in [
  "g13_private: alloc.new_heap('g13-private', alloc.g13_private_start, alloc.g13_private_end)",
  "g13_gpu_readonly: alloc.new_heap('g13-gpu-readonly', alloc.g13_gpu_readonly_start, alloc.g13_gpu_readonly_end)",
  "g13_shared: alloc.new_heap_with_garbage('g13-shared', alloc.g13_shared_start, alloc.g13_shared_end, false)",
  "g13_readonly: alloc.new_heap_with_garbage('g13-readonly', alloc.g13_readonly_start, alloc.g13_readonly_end, false)"
 ] { require(manager.contains(line), 'G13 heap policy matches its firmware memory class')! }
}

fn check_heap_release_policy_reference(allocator string, manager string) ! {
 drop := section(allocator, 'impl Drop for HeapAllocation {', 'impl mm::AllocInner<HeapAllocationInner>', 'Asahi heap release policy')!
 require_order(drop, ['if let Some(garbage) = a.garbage.as_mut()', 'garbage.push(node, GFP_KERNEL)',
  'None', '} else {', 'Some(node)'], 'Asahi retains only configured garbage pools')!
 for item in [['private', 'Kernel Private', 'true'], ['shared', 'Kernel Shared', 'false'],
  ['shared_ro', 'Kernel RO Shared', 'false'], ['gpu_ro', 'Kernel GPU RO Shared', 'true']] {
  class := section(manager, item[0] + ': alloc::DefaultAllocator::new(', ')?,', 'Asahi heap class policy')!
  require_order(class, ['fmt!("' + item[1] + '")', item[2] + ','], 'Asahi class release mode')!
 }
}
