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
fn frontier_block() string {
 return '\t\t\t\tu64 __if_val_0 = {0};\n' +
  '\t\t\t\tif (idx == 0) {\n' +
  '\t\t\t\t\t__if_val_0 = h->start;\n' +
  '\t\t\t\t} else {\n' +
  '\t\t\t\t\talloc__Allocation* previous = (*(alloc__Allocation**)array_get(h->allocations, idx - 1));\n' +
  '\t\t\t\t\t__if_val_0 = previous->va + previous->size;\n' +
  '\t\t\t\t}\n' +
  '\t\t\t\th->top = __if_val_0;\n'
}
fn check_gc(source string) ! {
 gc := body(source, 'alloc__HeapAllocator__gc_locked')!
 require(gc.count(frontier_block()) == 1, 'exact stack-only reservation frontier restoration')!
 ordered(gc, ['((a->va + a->size) == h->top) && !a->in_use', frontier_block(),
  'array_delete(&h->allocations, idx)', 'v_free(a)', 'progress = true', 'idx--'])!
 require(gc.count('v_free(a)') == 1 && gc.count('h->top =') == 1, 'one frontier update and destruction per unlinked released record')!
 for token in ['memdup(', 'malloc(', 'vcalloc(', 'array_new('] { require(!gc.contains(token), 'GC allocates no temporaries')! }
 release := body(source, 'alloc__HeapAllocator__release')!
 require(!release.contains('v_free('), 'interior metadata remains owned until GC')!
 for name in ['alloc', 'release', 'gc'] {
  method := body(source, 'alloc__HeapAllocator__' + name)!
  ordered(method, ['klock__Lock__acquire(&h->lock)', 'klock__Lock__release(&h->lock)'])!
 }
}
fn check_host(source string) ! {
 check_gc(source)!
 for name in ['used', 'available'] {
  method := body(source, 'alloc__HeapAllocator__' + name)!
  ordered(method, ['klock__Lock__acquire(&h->lock)',
   if name == 'used' { 'h->allocations' } else { 'h->top' }, 'klock__Lock__release(&h->lock)'])!
  for token in ['memdup(', 'malloc(', 'array_new('] { require(!method.contains(token), 'statistics allocate no temporaries')! }
 }
 println('Heap padding host C: reservation frontiers restore; unlinked records free once; every statistics reader serializes without temporary allocations.')
}
fn compare_native(current string, old string) ! {
 check_gc(current)!
 gc := body(current, 'alloc__HeapAllocator__gc_locked')!
 require(gc.replace(frontier_block(), '\t\t\t\th->top = a->va;\n') == body(old, 'alloc__HeapAllocator__gc_locked')!,
  'GC differs only by exact scalar frontier restoration')!
 for suffix in ['alloc', 'release', 'gc', 'checked_heap_align_up', 'heap_allocation_address', 'new_heap'] {
  symbol := if suffix in ['alloc', 'release', 'gc'] { 'alloc__HeapAllocator__' + suffix } else { 'alloc__' + suffix }
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
 println('Heap padding native C: exact scalar frontier change; six heap bodies, ten owning declarations, nine GPU lifetime bodies and ten event methods match baseline.')
}
fn selftest(source string) ! {
 check_host(source)!
 gc := body(source, 'alloc__HeapAllocator__gc_locked')!
 used := body(source, 'alloc__HeapAllocator__used')!
 available := body(source, 'alloc__HeapAllocator__available')!
 variants := [source.replace(gc, gc.replace('v_free(a);', '')),
  source.replace(gc, gc.replace('v_free(a);', 'v_free(a); v_free(a);')),
  source.replace(gc, gc.replace('array_delete(&h->allocations, idx);', 'v_free(a); array_delete(&h->allocations, idx);').replace('\n\t\t\t\t\tv_free(a);', '')),
  source.replace(used, used.replace('klock__Lock__acquire(&h->lock);', '')),
  source.replace(available, available.replace('klock__Lock__release(&h->lock);', '')),
  source.replace(gc, gc.replace('idx == 0', 'idx == 1')),
  source.replace(gc, gc.replace('previous->va + previous->size', 'previous->va')),
  source.replace(gc, gc.replace(' && !a->in_use', ''))]
 for changed in variants {
  require(changed != source, 'counterexample changed source')!
  if _ := check_host(changed) { return error('accepted unsafe heap padding C') }
 }
 println('Heap padding C checker: eight ownership/locking/frontier/live-prefix mutations rejected.')
}
fn main() {
 assert os.args.len >= 3
 source := os.read_file(os.args[2])!
 match os.args[1] {
  '--host' { check_host(source)! }
  '--native' { assert os.args.len == 4; compare_native(source, os.read_file(os.args[3])!)! }
  '--selftest' { selftest(source)! }
  else { panic('usage: check-padding --host|--selftest CURRENT_C or --native CURRENT_C BASELINE_C') }
 }
}
