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
fn gc_history() string {
 return '\t\t\talloc__HeapAllocator__retire_hole_order_locked(h, a->hole_order);\n' +
  '\t\t\ta->hole_order = 0;\n' +
  '\t\t\tif (idx == 0) {\n' +
  '\t\t\t\talloc__HeapAllocator__retire_hole_order_locked(h, h->head_hole_order);\n' +
  '\t\t\t\th->head_hole_order = alloc__HeapAllocator__newest_hole_order_locked(h);\n' +
  '\t\t\t} else {\n' +
  '\t\t\t\talloc__Allocation* previous = (*(alloc__Allocation**)array_get(h->allocations, idx - 1));\n' +
  '\t\t\t\talloc__HeapAllocator__retire_hole_order_locked(h, previous->hole_order);\n' +
  '\t\t\t\tprevious->hole_order = alloc__HeapAllocator__newest_hole_order_locked(h);\n' +
  '\t\t\t}\n'
}
fn check_history(source string) ! {
 rounding := body(source, 'alloc__checked_heap_align_up')!
 ordered(rounding, ['alignment == 0', 'alignment & (alignment - 1)', 'mask = alignment - 1',
  'value > (~(u64)(0) - mask)', '.ok = false', '(value + mask) & ~mask'])!
 candidate := body(source, 'alloc__heap_allocation_address')!
 ordered(candidate, ['alloc__checked_heap_align_up(top, alignment)', '(address > end) || (size > (end - address))', '.ok = false', '.value = address'])!
 search := body(source, 'alloc__HeapAllocator__find_address_locked')!
 ordered(search, ['h->start > end', 'u64 cursor = h->start', 'v_index <= h->allocations.len',
  'alloc__heap_allocation_address(cursor, gap_end, size, alignment)', 'u64 span = gap_end - cursor',
  'v_index == 0 ? h->head_hole_order', '->hole_order',
  'if (!found || (span < best_span) || ((span == best_span) && (order > best_order)))',
  'best_address = address', 'best_span = span', 'best_order = order', 'cursor = record->va + record->size',
  'if (!found)', '.value = best_address'])!
 require(!search.contains('in_use'), 'pending owners occupy their ranges')!
 retire := body(source, 'alloc__HeapAllocator__retire_hole_order_locked')!
 ordered(retire, ['if (order == 0)', 'return;', 'if (h->head_hole_order > order)', 'h->head_hole_order--',
  '__for_idx_0 < h->allocations.len', 'if ((*record)->hole_order > order)', '(*record)->hole_order--', 'h->hole_count--'])!
 newest := body(source, 'alloc__HeapAllocator__newest_hole_order_locked')!
 require(newest == 'u64 alloc__HeapAllocator__newest_hole_order_locked(alloc__HeapAllocator* h) {\n\th->hole_count++;\n\treturn h->hole_count;\n}\n', 'bounded scalar newest rank')!
 allocation := body(source, 'alloc__HeapAllocator__alloc')!
 call := 'alloc__HeapAllocator__find_address_locked(h, h->end, aligned_size, actual_align)'
 ordered(allocation, ['klock__Lock__acquire(&h->lock)', '(size == 0)',
  '(align != 0) && ((align & (align - 1)) != 0)', 'alloc__checked_heap_align_up(size, actual_align)',
  call, 'alloc__HeapAllocator__gc_locked(h)', call, 'if ((va + aligned_size) > h->top)', 'h->top = va + aligned_size',
  'u64 old_order =', 'alloc__HeapAllocator__retire_hole_order_locked(h, old_order)',
  'if (va > gap_start)', 'alloc__HeapAllocator__newest_hole_order_locked(h)', 'u64 leading_order =',
  'h->head_hole_order = leading_order', '->hole_order = leading_order',
  'if ((va + aligned_size) < gap_end)', 'alloc__HeapAllocator__newest_hole_order_locked(h)', 'u64 trailing_order =',
  'memdup(&(alloc__Allocation)', '.hole_order = trailing_order', 'array_push(&h->allocations',
  'while ((v_index > 0)', '->va > va', 'array__set(', 'v_index--', 'array__set(', 'klock__Lock__release(&h->lock)'])!
 require(allocation.count(call) == 2 && allocation.count('gc_locked(') == 1
  && allocation.count('memdup(') == 1 && allocation.count('array_push(') == 1
  && allocation.count('array__set(') == 2 && allocation.count('h->top =') == 1, 'one explicit stable record owner')!
 gc := body(source, 'alloc__HeapAllocator__gc_locked')!
 require(gc.count(gc_history()) == 1, 'exact scalar coalesced-hole history before unlink')!
 ordered(gc, ['idx = h->allocations.len - 1', 'while (idx >= 0)', 'if (!a->in_use)', gc_history(),
  'if ((a->va + a->size) == h->top)', 'previous->va + previous->size', 'array_delete(&h->allocations, idx)', 'v_free(a)', 'idx--'])!
 require(gc.count('v_free(') == 1 && gc.count('array_delete(') == 1, 'unlink before one metadata destruction')!
 constructor := body(source, 'alloc__new_heap')!
 ordered(constructor, ['start < end ? (u64)(1) : (u64)(0)', '.head_hole_order =', '.hole_count =', 'heap.allocations.flags |= 1', 'return heap'])!
 for helper in [rounding, candidate, search, retire, newest, gc] {
  for token in ['memdup(', 'malloc(', 'vcalloc(', 'array_new(', 'IError'] { require(!helper.contains(token), 'no hidden allocation in history helpers or collection')! }
 }
 for token in ['malloc(', 'vcalloc(', 'array_new(', 'array_insert('] { require(!allocation.contains(token), 'one explicit reservation record')! }
 for name in ['alloc', 'release', 'gc'] {
  ordered(body(source, 'alloc__HeapAllocator__' + name)!, ['klock__Lock__acquire(&h->lock)', 'klock__Lock__release(&h->lock)'])!
 }
 println('Heap history C: checked bounds, newest eligible equal-size hole, bounded allocation-free ranks, ordered split/coalesce, locked stable metadata ownership.')
}
fn compare_native(current string, old string) ! {
 check_history(current)!
 for symbol in ['alloc__HeapAllocator__release', 'alloc__HeapAllocator__gc', 'alloc__checked_heap_align_up', 'alloc__heap_allocation_address'] {
  require(body(current, symbol)! == body(old, symbol)!, 'unchanged heap body: ' + symbol)!
 }
 require(body(current, 'alloc__HeapAllocator__gc_locked')!.replace(gc_history(), '') == body(old, 'alloc__HeapAllocator__gc_locked')!, 'collector differs only by exact scalar hole bookkeeping')!
 for name in ['alloc__Allocation', 'alloc__HeapAllocator', 'gpu__agx__gpu__G13RenderJobResources',
  'gpu__agx__gpu__G13ComputeJobResources', 'gpu__agx__gpu__G13QueueResources', 'gpu__agx__event__WorkQueueEvents',
  'gpu__agx__event__TicketBlock', 'gpu__agx__event__PendingTicket', 'gpu__agx__event__Ticket', 'fw__G13JobTimestamps'] {
  actual := declaration(current, name)!.replace('\tu64 hole_order;\n', '').replace('\tu64 head_hole_order;\n', '').replace('\tu64 hole_count;\n', '')
  require(actual == declaration(old, name)!, 'owning layout changed beyond three scalar ranks: ' + name)!
 }
 for suffix in ['prepare_g13_render_job_with_timestamps', 'prepare_g13_compute_job_with_timestamps',
  'free_g13_render_job_locked', 'free_g13_compute_job_locked', 'reap_g13_render_jobs', 'reap_g13_compute_jobs',
  'release_g13_queue_resources', 'submit_g13_batch', 'retire_g13_render_stages_locked'] {
  symbol := 'gpu__agx__gpu__GpuManager__' + suffix
  require(body(current, symbol)! == body(old, symbol)!, 'GPU lifetime changed: ' + symbol)!
 }
 for suffix in ['retain', 'release', 'ticket', 'resolve_initial', 'can_submit', 'admit', 'can_publish_batch', 'can_publish', 'publish', 'record_completion'] {
  symbol := 'gpu__agx__event__WorkQueueEvents__' + suffix
  require(body(current, symbol)! == body(old, symbol)!, 'event ownership changed: ' + symbol)!
 }
 println('Heap history native C: four heap bodies, restored collector, ten owning declarations, nine GPU lifetime bodies and ten event methods preserve baseline ownership.')
}
fn selftest(source string) ! {
 check_history(source)!
 variants := [source.replace('order > best_order', 'order < best_order'),
  source.replace('(span == best_span) && (order > best_order)', 'false'),
  source.replace('h->hole_count--;', ''), source.replace('if (order == 0)', 'if (false)'),
  source.replace('if ((*record)->hole_order > order)', 'if (false)'),
  source.replace('if (h->head_hole_order > order)', 'if (false)'),
  source.replace('a->hole_order = 0;', ''),
  source.replace('previous->hole_order = alloc__HeapAllocator__newest_hole_order_locked(h);', 'previous->hole_order = 0;'),
  source.replace('h->head_hole_order = alloc__HeapAllocator__newest_hole_order_locked(h);', 'h->head_hole_order = 0;'),
  source.replace('if ((va + aligned_size) < gap_end)', 'if (true)'),
  source.replace('.hole_order = trailing_order', '.hole_order = 0'),
  source.replace('value > (~(u64)(0) - mask)', 'false'),
  source.replace('array_delete(&h->allocations, idx);', 'v_free(a); array_delete(&h->allocations, idx);'),
  source.replace('h->hole_count++;', 'memdup(0, 1); h->hole_count++;')]
 for changed in variants {
  require(changed != source, 'counterexample changed C')!
  if _ := check_history(changed) { return error('accepted invalid hole-history C') }
 }
 println('Heap history C checker: fourteen ranking/bounds/compaction/coalescing/ownership/allocation mutations rejected.')
}
fn check_reference(mm string) ! {
 ordered(mm, ['static void insert_hole_size(', 'if (x > rb_to_hole_size(rb))', 'link = &rb->rb_left;', 'link = &rb->rb_right;'])!
 ordered(mm, ['static struct drm_mm_node *best_hole(', 'if (size <= node->hole_size)', 'best = node;', 'rb = rb->rb_right;'])!
 ordered(mm, ['int drm_mm_insert_node_in_range(', 'if (alignment)', 'rm_hole(hole);', 'if (adj_start > hole_start)', 'add_hole(hole);', 'if (adj_start + size < hole_end)', 'add_hole(node);'])!
 ordered(mm, ['void drm_mm_remove_node(', 'if (drm_mm_hole_follows(node))', 'rm_hole(node);', 'if (drm_mm_hole_follows(prev_node))', 'rm_hole(prev_node);', 'add_hole(prev_node);'])!
 println('DRM MM source: equal-size nodes append right and best_hole selects rightmost; newest eligible tie, leading-before-trailing split and reinserted coalesced predecessor.')
}
fn main() {
 assert os.args.len >= 3
 source := os.read_file(os.args[2])!
 match os.args[1] {
  '--host' { check_history(source)! }
  '--native' { assert os.args.len == 4; compare_native(source, os.read_file(os.args[3])!)! }
  '--selftest' { selftest(source)! }
  '--reference' { check_reference(source)! }
  else { panic('usage: check-history --host|--selftest C, --native C BASELINE_C or --reference DRM_MM_C') }
 }
}
