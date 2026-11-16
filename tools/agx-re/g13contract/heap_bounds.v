// SPDX-License-Identifier: GPL-2.0-or-later
module g13contract

fn check_heap_bounds_local(source string) ! {
 rounding := section(source, 'fn checked_heap_align_up(', 'fn heap_allocation_address(', 'GPU heap checked rounding')!
 require_order(rounding, ['alignment == 0 || (alignment & (alignment - 1)) != 0',
  'mask := alignment - 1', 'value > ~u64(0) - mask', '(value + mask) & ~mask'], 'GPU heap rounding must reject overflow before addition')!
 candidate := section(source, 'fn heap_allocation_address(', '// Zero alignment selects', 'GPU heap interval')!
 require_order(candidate, ['checked_heap_align_up(top, alignment) or { return none }',
  'address > end || size > end - address', 'return address'], 'GPU heap intervals fit by checked subtraction')!
 allocation := section(source, 'pub fn (mut h HeapAllocator) alloc(', '// Mark the allocation', 'GPU heap reservation')!
 require_order(allocation, ['h.lock.acquire()', 'h.lock.release()',
  'size == 0 || (align != 0 && (align & (align - 1)) != 0)',
  'actual_align := if align < gpu_page_size', 'checked_heap_align_up(size, actual_align) or { return none }',
  'heap_allocation_address(h.top, h.end, aligned_size, actual_align)', 'h.gc_locked()',
  'heap_allocation_address(h.top, h.end, aligned_size, actual_align)', 'h.top = va + aligned_size',
  'a := &Allocation{', '} @[freed]', 'h.allocations << a', 'return va'], 'GPU heap validates before mutation and retries identical bounds after GC')!
 require(allocation.count('a := &Allocation{') == 1 && allocation.count('h.top =') == 1,
  'GPU heap success has one frontier update and one metadata owner')!
 require(!allocation.contains('lib.align_up('), 'GPU heap cannot use unchecked global rounding')!
}

fn check_heap_bounds_reference(source string) ! {
 start := source.index('fn alloc_inner(&mut self, size: usize, align: usize)') or { return error('Asahi heap allocator missing') }
 require_order(source[start..], ['align != 0 && !align.is_power_of_two()', 'return Err(EINVAL)',
  'self.min_align.max(align)', 'self.mm.insert_node_generic(', 'size_aligned as u64',
  'align as u64', 'mm::InsertMode::Best'], 'Asahi validates requested alignment and reserves through its range allocator')!
}
