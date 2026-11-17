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
fn release_bookkeeping() string {
 return '\t\t\t\t\th->garbage_count++;\n' +
  '\t\t\t\t\t(*(a))->release_order = h->garbage_count;\n' +
  '\t\t\t\t\th->garbage_bytes += (*a)->size;\n'
}
fn check_garbage(source string, host bool) ! {
 release := body(source, 'alloc__HeapAllocator__release')!
 require(release.count(release_bookkeeping()) == 1, 'one scalar bookkeeping update per first release')!
 ordered(release, ['klock__Lock__acquire(&h->lock)', 'if (((*a)->va == va) && (*a)->in_use)',
  '(*(a))->in_use = false', release_bookkeeping(), 'klock__Lock__release(&h->lock)'])!
 require(!release.contains('v_free('), 'released records stay owned until collection')!
 full := body(source, 'alloc__HeapAllocator__gc_locked')!
 require(full == 'void alloc__HeapAllocator__gc_locked(alloc__HeapAllocator* h) {\n\talloc__HeapAllocator__collect_garbage_locked(h, h->garbage_count);\n}\n', 'full GC delegates the entire pending count')!
 collect := body(source, 'alloc__HeapAllocator__collect_garbage_locked')!
 ordered(collect, ['u64 collect_left = (u64)((count < h->garbage_count ? count : h->garbage_count))',
  'while (collect_left > 0)', 'i64 idx = 0', 'while (idx < h->allocations.len)',
  'if (!a->in_use && (a->release_order == 1))', 'break;', 'idx++',
  'if (idx == h->allocations.len)', 'return;',
  'alloc__HeapAllocator__retire_hole_order_locked(h, a->hole_order)', 'a->hole_order = 0',
  'if (idx == 0)', 'h->head_hole_order = alloc__HeapAllocator__newest_hole_order_locked(h)',
  'previous->hole_order = alloc__HeapAllocator__newest_hole_order_locked(h)',
  'if ((a->va + a->size) == h->top)', 'previous->va + previous->size',
  'h->garbage_count--', 'h->garbage_bytes -= a->size',
  '__for_idx_1 < h->allocations.len', 'if ((*pending)->release_order > 1)', '(*pending)->release_order--',
  'array_delete(&h->allocations, idx)', 'v_free(a)', 'collect_left--'])!
 require(collect.count('return;') == 1 && collect.count('break;') == 1
  && collect.count('v_free(') == 1 && collect.count('array_delete(') == 1
  && collect.count('collect_left--') == 1, 'one bounded FIFO removal with no live-prefix exit or duplicate destruction')!
 for method in [release, full, collect] {
  for token in ['memdup(', 'malloc(', 'vcalloc(', 'array_new(', 'IError'] { require(!method.contains(token), 'deferred FIFO operations allocate no hidden storage')! }
 }
 if host {
  for name in ['collect_garbage', 'garbage', 'used', 'available'] {
   method := body(source, 'alloc__HeapAllocator__' + name)!
   ordered(method, ['klock__Lock__acquire(&h->lock)', 'klock__Lock__release(&h->lock)'])!
   require(!method.contains('memdup('), 'scalar API has no hidden allocation')!
  }
  ordered(body(source, 'alloc__HeapAllocator__collect_garbage')!, ['u64 count)', 'klock__Lock__acquire(&h->lock)',
   'alloc__HeapAllocator__collect_garbage_locked(h, count)', 'klock__Lock__release(&h->lock)'])!
  statistics := body(source, 'alloc__HeapAllocator__garbage')!
  require(statistics.starts_with('multi_return_u64_u64 '), 'full-width stack tuple statistics')!
  ordered(statistics, ['multi_return_u64_u64 _t1', 'h->garbage_count,', 'h->garbage_bytes', 'return _t1'])!
 }
 println('Heap garbage C: bounded FIFO/count/rounded-byte bookkeeping, idempotent locked release, scalar statistics, allocation-free compaction and unlink-before-free.')
}
fn compare_native(current string, old string) ! {
 check_garbage(current, false)!
 for symbol in ['alloc__HeapAllocator__alloc', 'alloc__new_heap', 'alloc__HeapAllocator__gc',
  'alloc__HeapAllocator__find_address_locked', 'alloc__HeapAllocator__retire_hole_order_locked',
  'alloc__HeapAllocator__newest_hole_order_locked', 'alloc__checked_heap_align_up', 'alloc__heap_allocation_address'] {
  require(body(current, symbol)! == body(old, symbol)!, 'unchanged heap body: ' + symbol)!
 }
 require(body(current, 'alloc__HeapAllocator__release')!.replace(release_bookkeeping(), '') == body(old, 'alloc__HeapAllocator__release')!, 'release changes only exact scalar FIFO bookkeeping')!
 old_gc := body(old, 'alloc__HeapAllocator__gc_locked')!
 start := old_gc.index('\t\t\talloc__HeapAllocator__retire_hole_order_locked(h, a->hole_order);') or { return error('old coalescing') }
 end := old_gc.index_after('\t\t\tarray_delete(&h->allocations, idx);', start) or { return error('old unlink') }
 mut fragment := ''
 for line in old_gc[start..end].split_into_lines() { if line != '' { require(line.starts_with('\t'), 'coalescing indentation')!; fragment += line[1..] + '\n' } }
 require(body(current, 'alloc__HeapAllocator__collect_garbage_locked')!.count(fragment) == 1,
  'coalescing/frontier body is exactly preserved apart from one nesting level')!
 for name in ['alloc__Allocation', 'alloc__HeapAllocator', 'gpu__agx__gpu__G13RenderJobResources',
  'gpu__agx__gpu__G13ComputeJobResources', 'gpu__agx__gpu__G13QueueResources', 'gpu__agx__event__WorkQueueEvents',
  'gpu__agx__event__TicketBlock', 'gpu__agx__event__PendingTicket', 'gpu__agx__event__Ticket', 'fw__G13JobTimestamps'] {
  actual := declaration(current, name)!.replace('\tu64 release_order;\n', '').replace('\tu64 garbage_count;\n', '').replace('\tu64 garbage_bytes;\n', '')
  require(actual == declaration(old, name)!, 'owning layout changed beyond three FIFO scalars: ' + name)!
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
 println('Heap garbage native C: eight heap bodies, restored release, exact coalescing/frontier, ten owning layouts, nine GPU lifetime bodies and ten event methods preserve baseline ownership.')
}
fn selftest(source string) ! {
 check_garbage(source, true)!
 collect := body(source, 'alloc__HeapAllocator__collect_garbage_locked')!
 variants := [source.replace('count < h->garbage_count ? count : h->garbage_count', 'h->garbage_count'),
  source.replace('a->release_order == 1', 'a->release_order == h->garbage_count'),
  source.replace('if (((*a)->va == va) && (*a)->in_use)', 'if ((*a)->va == va)'),
  source.replace('(*(a))->release_order = h->garbage_count', '(*(a))->release_order = 0'),
  source.replace('h->garbage_bytes += (*a)->size', 'h->garbage_bytes += 1'),
  source.replace('h->garbage_bytes -= a->size;', ''), source.replace('h->garbage_count--;', ''),
  source.replace('(*pending)->release_order--;', ''), source.replace('if ((*pending)->release_order > 1)', 'if (true)'),
  source.replace('collect_garbage_locked(h, h->garbage_count)', 'collect_garbage_locked(h, 0)'),
  source.replace('multi_return_u64_u64 _t1', 'multi_return_u32_u32 _t1'),
  source.replace('array_delete(&h->allocations, idx);', 'v_free(a); array_delete(&h->allocations, idx);'),
  source.replace(collect, collect.replace('i64 idx = 0;', 'memdup(0, 1); i64 idx = 0;')),
  source.replace('if (!a->in_use && (a->release_order == 1))', 'if (a->in_use) return; if (!a->in_use && (a->release_order == 1))'),
  source.replace('collect_left--;', 'collect_left -= 2;')]
 for changed in variants {
  require(changed != source, 'counterexample changed C')!
  if _ := check_garbage(changed, true) { return error('accepted invalid deferred FIFO C') }
 }
 println('Heap garbage C checker: fifteen limit/FIFO/release/accounting/compaction/width/ownership/allocation mutations rejected.')
}
fn check_reference(allocator string, kvec string, drain string) ! {
 ordered(allocator, ['impl Drop for HeapAllocation {', 'garbage.push(node, GFP_KERNEL)', 'a.total_garbage += size as usize'])!
 ordered(allocator, ['fn collect_garbage(&mut self, mut count: usize)', 'let block = count.min(garbage.capacity())',
  'for node in g.drain(0..block)', 'inner.total_garbage -= node.size() as usize', 'count -= block', 'garbage.clear()'])!
 ordered(kvec, ['pub fn clear(&mut self)', 'self.truncate(0)'])!
 ordered(kvec, ['pub fn truncate(&mut self, len: usize)', 'ptr::drop_in_place(ptr)'])!
 ordered(drain, ['fn next(&mut self)', 'self.iter', '.next()', 'ptr::read(elt as *const _)'])!
 println('Asahi deferred GC: appended releases, oldest count-limited drain, rounded-byte subtraction and ordered slice destruction via KVec clear/truncate.')
}
fn main() {
 assert os.args.len >= 3
 source := os.read_file(os.args[2])!
 match os.args[1] {
  '--host' { check_garbage(source, true)! }
  '--native' { assert os.args.len == 4; compare_native(source, os.read_file(os.args[3])!)! }
  '--selftest' { selftest(source)! }
  '--reference' { assert os.args.len == 5; check_reference(source, os.read_file(os.args[3])!, os.read_file(os.args[4])!)! }
  else { panic('usage: check-garbage --host|--selftest C, --native C BASELINE_C or --reference ALLOC_RS KVEC_RS DRAIN_RS') }
 }
}
