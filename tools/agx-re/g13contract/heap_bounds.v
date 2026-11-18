// SPDX-License-Identifier: GPL-2.0-or-later
module g13contract

fn check_heap_bounds_local(source string) ! {
 rounding := section(source, 'fn checked_heap_align_up(', 'fn heap_allocation_address(', 'GPU heap checked rounding')!
 require_order(rounding, ['alignment == 0 || (alignment & (alignment - 1)) != 0',
  'mask := alignment - 1', 'value > ~u64(0) - mask', '(value + mask) & ~mask'], 'GPU heap rounding must reject overflow before addition')!
 candidate := section(source, 'fn heap_allocation_address(', '// Zero alignment selects', 'GPU heap interval')!
 require_order(candidate, ['checked_heap_align_up(top, alignment) or { return none }',
  'address > end || size > end - address', 'return address'], 'GPU heap intervals fit by checked subtraction')!
 allocation := section(source, 'pub fn (mut h HeapAllocator) alloc(', '// Release the allocation', 'GPU heap reservation')!
 require_order(allocation, ['h.lock.acquire()', 'h.lock.release()',
  'size == 0 || (align != 0 && (align & (align - 1)) != 0)',
  'actual_align := if align < gpu_page_size', 'checked_heap_align_up(size, actual_align) or { return -22, 0 }',
  'h.find_address_locked(h.end, aligned_size, actual_align)', 'h.gc_locked()',
  'h.find_address_locked(h.end, aligned_size, actual_align)',
  'storage := memory.malloc_packed_fallible(sizeof(Allocation)) @[freed]',
  'if storage == unsafe { nil } { return -12, 0 }', 'if !h.reserve_entry_locked()',
  'unsafe { free(storage) }', 'return -12, 0',
  'if va + aligned_size > h.top { h.top = va + aligned_size }',
  'unsafe { *a = Allocation{', 'h.allocations << a',
  'for index > 0 && h.allocations[index - 1].va > va',
  'h.allocations[index] = h.allocations[index - 1]', 'index--', 'h.allocations[index] = a', 'return 0, va'],
  'GPU heap validates before mutation, retries identical bounds and preserves sorted ownership after GC')!
 require(allocation.count('memory.malloc_packed_fallible(sizeof(Allocation))') == 1 && allocation.count('h.top =') == 1,
  'GPU heap success has one frontier update and one metadata owner')!
 require(!allocation.contains('lib.align_up('), 'GPU heap cannot use unchecked global rounding')!
 search := section(source, 'fn (h &HeapAllocator) find_address_locked(', '// Zero alignment selects', 'GPU heap best fit')!
 require_order(search, ['h.start > end', 'cursor := h.start', 'best_span := ~u64(0)',
  'index <= h.allocations.len', 'h.allocations[index].va < end',
  'heap_allocation_address(cursor, gap_end, size, alignment)', 'span := gap_end - cursor',
  'if !found || span < best_span', 'best_address = address', 'best_span = span',
  'cursor = record.va + record.size', 'if !found { return none }', 'return best_address'],
  'Every complete gap is checked and ranked by raw span without overlapping deferred owners')!
 require_order(search, ['span := gap_end - cursor', 'h.head_hole_order', 'hole_order',
  'span == best_span && order > best_order', 'best_order = order'],
  'Equal-size eligible holes follow newest insertion order')!
 retire := section(source, 'fn (mut h HeapAllocator) retire_hole_order_locked(', 'fn (mut h HeapAllocator) newest_hole_order_locked(', 'GPU heap bounded hole ranks')!
 require_order(retire, ['if order == 0 { return }', 'h.head_hole_order > order', 'h.head_hole_order--',
  'for mut record in h.allocations', 'record.hole_order > order', 'record.hole_order--', 'h.hole_count--'],
  'Retired hole ranks compact without an unbounded sequence counter')!
 require_order(allocation, ['h.retire_hole_order_locked(old_order)',
  'leading_order := if va > gap_start', 'h.head_hole_order = leading_order',
  'trailing_order := if va + aligned_size < gap_end', 'hole_order: trailing_order'],
  'Split holes insert the leading remainder before the trailing remainder')!
}

fn check_heap_bounds_reference(source string) ! {
 start := source.index('fn alloc_inner(&mut self, size: usize, align: usize)') or { return error('Asahi heap allocator missing') }
 require_order(source[start..], ['align != 0 && !align.is_power_of_two()', 'return Err(EINVAL)',
  'self.min_align.max(align)', 'self.mm.insert_node_generic(', 'size_aligned as u64',
  'align as u64', 'mm::InsertMode::Best'], 'Asahi validates requested alignment and reserves through its range allocator')!
}
