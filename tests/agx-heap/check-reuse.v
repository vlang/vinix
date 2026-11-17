// SPDX-License-Identifier: GPL-2.0-or-later
import os

fn require(ok bool, message string) ! { if !ok { return error(message) } }
fn body(source string, name string) !string {
 for line in source.split_into_lines() {
  if line.len == 0 || line[0].is_space() || !line.contains(' ' + name + '(') || !line.ends_with(' {') { continue }
  start := source.index(line) or { return error(name) }
  end := source.index_after('\n}\n', start) or { return error(name) }
  return source[start..end + 3]
 }
 return error('missing definition: ' + name)
}
fn ordered(source string, tokens []string) ! {
 mut cursor := 0
 for token in tokens { cursor = (source.index_after(token, cursor) or { return error(token) }) + token.len }
}
fn declaration(source string, name string) !string {
 start := source.index('struct ' + name + ' {') or { return error(name) }
 end := source.index_after('\n};', start) or { return error(name) }
 return source[start..end + 3]
}
fn check_reuse(source string) ! {
 rounding := body(source, 'alloc__checked_heap_align_up')!
 ordered(rounding, ['alignment == 0', 'alignment & (alignment - 1)', 'mask = alignment - 1',
  'value > (~(u64)(0) - mask)', '.ok = false', '(value + mask) & ~mask'])!
 candidate := body(source, 'alloc__heap_allocation_address')!
 ordered(candidate, ['alloc__checked_heap_align_up(top, alignment)', '(address > end) || (size > (end - address))', '.ok = false', '.value = address'])!
 search := body(source, 'alloc__HeapAllocator__find_address_locked')!
 require(search.starts_with('__v_option_u64 alloc__HeapAllocator__find_address_locked(alloc__HeapAllocator* h, u64 end, u64 size, u64 alignment)'), 'full-width scalar search result')!
 ordered(search, ['h->start > end', 'u64 cursor = h->start', 'u64 best_span = ~(u64)(0)',
  'v_index <= h->allocations.len', '->va < end', 'alloc__heap_allocation_address(cursor, gap_end, size, alignment)',
  'u64 span = gap_end - cursor', 'if (!found || (span < best_span))', 'best_address = address', 'best_span = span',
  'cursor = record->va + record->size', 'if (!found)', '.ok = false', '.value = best_address'])!
 require(!search.contains('in_use') && !search.contains('gc_locked('), 'pending records remain occupied until explicit GC retry')!
 for helper in [rounding, candidate, search] {
  for token in ['memdup(', 'malloc(', 'vcalloc(', 'array_new(', 'IError'] { require(!helper.contains(token), 'placement helpers allocate no temporaries')! }
 }
 allocation := body(source, 'alloc__HeapAllocator__alloc')!
 call := 'alloc__HeapAllocator__find_address_locked(h, h->end, aligned_size, actual_align)'
 ordered(allocation, ['klock__Lock__acquire(&h->lock)', '(size == 0)',
  '(align != 0) && ((align & (align - 1)) != 0)', 'alloc__checked_heap_align_up(size, actual_align)', call,
  'alloc__HeapAllocator__gc_locked(h)', call, 'if ((va + aligned_size) > h->top)', 'h->top = va + aligned_size',
  'memdup(&(alloc__Allocation)', 'array_push(&h->allocations', 'v_index = h->allocations.len - 1',
  'while ((v_index > 0)', '->va > va', 'array__set(', 'v_index--', 'array__set(',
  'klock__Lock__release(&h->lock)'])!
 require(allocation.count(call) == 2 && allocation.count('gc_locked(') == 1
  && allocation.count('memdup(') == 1 && allocation.count('array_push(') == 1
  && allocation.count('array__set(') == 2 && allocation.count('h->top =') == 1,
  'one owner, one conditional high frontier, two identical attempts and stack pointer rotation')!
 for token in ['malloc(', 'vcalloc(', 'array_new(', 'array_insert('] { require(!allocation.contains(token), 'reservation allocates only its explicit record')! }
 println('Heap reuse C: three allocation-free u64 helpers; identical bounded retry, monotonic frontier and sorted rotation of one explicit metadata owner.')
}
fn compare_native(current string, old string) ! {
 check_reuse(current)!
 for suffix in ['release', 'gc', 'gc_locked', 'new_heap', 'checked_heap_align_up', 'heap_allocation_address'] {
  symbol := if suffix in ['release', 'gc', 'gc_locked'] { 'alloc__HeapAllocator__' + suffix } else { 'alloc__' + suffix }
  require(body(current, symbol)! == body(old, symbol)!, 'heap body changed: ' + symbol)!
 }
 for name in ['alloc__Allocation', 'alloc__HeapAllocator', 'gpu__agx__gpu__G13RenderJobResources',
  'gpu__agx__gpu__G13ComputeJobResources', 'gpu__agx__gpu__G13QueueResources', 'gpu__agx__event__WorkQueueEvents',
  'gpu__agx__event__TicketBlock', 'gpu__agx__event__PendingTicket', 'gpu__agx__event__Ticket', 'fw__G13JobTimestamps'] {
  require(declaration(current, name)! == declaration(old, name)!, 'owning layout changed: ' + name)!
 }
 for suffix in ['prepare_g13_render_job_with_timestamps', 'prepare_g13_compute_job_with_timestamps',
  'free_g13_render_job_locked', 'free_g13_compute_job_locked', 'reap_g13_render_jobs', 'reap_g13_compute_jobs',
  'release_g13_queue_resources', 'submit_g13_batch', 'retire_g13_render_stages_locked'] {
  symbol := 'gpu__agx__gpu__GpuManager__' + suffix
  require(body(current, symbol)! == body(old, symbol)!, 'GPU lifetime body changed: ' + symbol)!
 }
 for suffix in ['retain', 'release', 'ticket', 'resolve_initial', 'can_submit', 'admit', 'can_publish_batch', 'can_publish', 'publish', 'record_completion'] {
  symbol := 'gpu__agx__event__WorkQueueEvents__' + suffix
  require(body(current, symbol)! == body(old, symbol)!, 'event ownership changed: ' + symbol)!
 }
 println('Heap reuse native C: six heap bodies, ten owning declarations, nine GPU lifetime bodies and ten event methods match baseline.')
}
fn selftest(source string) ! {
 check_reuse(source)!
 allocation := body(source, 'alloc__HeapAllocator__alloc')!
 search := body(source, 'alloc__HeapAllocator__find_address_locked')!
 gc := allocation.index('alloc__HeapAllocator__gc_locked(h)') or { return error('GC') }
 late := allocation[..gc] + allocation[gc..].replace('h, h->end, aligned_size', 'h, (u64)(-1), aligned_size')
 variants := [source.replace('value > (~(u64)(0) - mask)', 'false'),
  source.replace('(address > end) || (size > (end - address))', 'false'),
  source.replace('(align != 0) && ((align & (align - 1)) != 0)', 'false'), source.replace(allocation, late),
  source.replace(search, search.replace('span < best_span', 'false')),
  source.replace(search, search.replace('u64 span = gap_end - cursor', 'u64 span = gap_end - address')),
  source.replace(search, search.replace('u64 cursor = h->start', 'u64 cursor = h->top')),
  source.replace(search, search.replace('cursor = record->va + record->size;', 'if (record->in_use) cursor = record->va + record->size;')),
  source.replace(allocation, allocation.replace('if ((va + aligned_size) > h->top)', 'if (true)')),
  source.replace(allocation, allocation.replace('while ((v_index > 0)', 'while ((v_index < 0)')),
  source.replace(search, search.replace('u64 best_span =', 'memdup(0, 1); u64 best_span =')),
  source.replace(allocation, allocation.replace('array_push(&h->allocations', 'memdup(0, 1); array_push(&h->allocations'))]
 for changed in variants {
  require(changed != source, 'counterexample changed source')!
  if _ := check_reuse(changed) { return error('accepted unsafe heap reuse C') }
 }
 println('Heap reuse C checker: twelve bounds/retry/ranking/deferred-owner/frontier/sorting/temporary-allocation mutations rejected.')
}
fn check_reference(allocator string, mm string) ! {
 ordered(allocator, ['fn alloc_inner(&mut self, size: usize, align: usize)', 'align != 0 && !align.is_power_of_two()',
  'self.min_align.max(align)', 'self.mm.insert_node_generic(', 'mm::InsertMode::Best'])!
 ordered(mm, ['static struct drm_mm_node *best_hole(', 'if (size <= node->hole_size)', 'best = node;', 'rb = rb->rb_right;'])!
 ordered(mm, ['int drm_mm_insert_node_in_range(', 'hole = first_hole(', 'hole->hole_size', 'if (alignment)', 'node->start = adj_start;'])!
 println('Asahi allocation selects DRM MM best fit by complete hole size, then checks aligned placement. Equal-size tree ordering remains an explicit Vinix tie-policy difference.')
}
fn main() {
 assert os.args.len >= 3
 source := os.read_file(os.args[2])!
 match os.args[1] {
  '--host' { check_reuse(source)! }
  '--native' { assert os.args.len == 4; compare_native(source, os.read_file(os.args[3])!)! }
  '--selftest' { selftest(source)! }
  '--reference' { assert os.args.len == 4; check_reference(source, os.read_file(os.args[3])!)! }
  else { panic('usage: check-reuse --host|--selftest C, --native C BASELINE_C or --reference ALLOC_RS DRM_MM_C') }
 }
}
