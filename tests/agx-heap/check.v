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
 mut position := 0
 for token in tokens {
  position = (source.index_after(token, position) or { return error('missing or out-of-order: ' + token) }) + token.len
 }
}

fn check_gc(source string) ! {
 gc := body(source, 'alloc__HeapAllocator__gc_locked')!
 ordered(gc, ['a->va + a->size', '!a->in_use', 'h->top = a->va',
  'array_delete(&h->allocations, idx)', 'v_free(a)', 'progress = true', 'idx--'])!
 require(gc.count('v_free(a)') == 1, 'one destruction per unlinked record')!
 for token in ['memdup(', 'malloc(', 'vcalloc(', 'array_new('] { require(!gc.contains(token), 'GC adds no allocation')! }
 release := body(source, 'alloc__HeapAllocator__release')!
 require(!release.contains('v_free('), 'release retains interior records')!
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
}

fn declaration(source string, name string) !string {
 start := source.index('struct ' + name + ' {') or { return error(name) }
 end := source.index_after('\n};', start) or { return error(name) }
 return source[start..end + 3]
}

fn check_native(current string, old string) ! {
 check_gc(current)!
 for name in ['alloc', 'release', 'gc'] {
  symbol := 'alloc__HeapAllocator__' + name
  require(body(current, symbol)! == body(old, symbol)!, 'unchanged allocator method: ' + symbol)!
 }
 require(body(current, 'alloc__new_heap')! == body(old, 'alloc__new_heap')!, 'constructor unchanged')!
 gc := body(current, 'alloc__HeapAllocator__gc_locked')!
 free_block := '\t\t\t\t{\n\t\t\t\t\tv_free(a);\n\t\t\t\t}\n'
 require(gc.count(free_block) == 1, 'exact unlinked-record free')!
 require(gc.replace(free_block, '') == body(old, 'alloc__HeapAllocator__gc_locked')!, 'GC differs only by record destruction')!
 for name in ['alloc__Allocation', 'alloc__HeapAllocator', 'gpu__agx__gpu__G13RenderJobResources',
  'gpu__agx__gpu__G13ComputeJobResources', 'gpu__agx__gpu__G13QueueResources', 'gpu__agx__event__WorkQueueEvents',
  'gpu__agx__event__TicketBlock', 'gpu__agx__event__PendingTicket', 'gpu__agx__event__Ticket', 'fw__G13JobTimestamps'] {
  require(declaration(current, name)! == declaration(old, name)!, 'owning declaration unchanged: ' + name)!
 }
 for suffix in ['prepare_g13_render_job_with_timestamps', 'prepare_g13_compute_job_with_timestamps',
  'free_g13_render_job_locked', 'free_g13_compute_job_locked', 'reap_g13_render_jobs', 'reap_g13_compute_jobs',
  'release_g13_queue_resources', 'submit_g13_batch', 'retire_g13_render_stages_locked'] {
  symbol := 'gpu__agx__gpu__GpuManager__' + suffix
  require(body(current, symbol)! == body(old, symbol)!, 'GPU lifetime body unchanged: ' + symbol)!
 }
 for suffix in ['retain', 'release', 'ticket', 'resolve_initial', 'can_submit', 'admit', 'can_publish_batch', 'can_publish', 'publish', 'record_completion'] {
  symbol := 'gpu__agx__event__WorkQueueEvents__' + suffix
  require(body(current, symbol)! == body(old, symbol)!, 'event ownership unchanged: ' + symbol)!
 }
 println('Heap native C: GC adds exactly one unlink-before-free; four allocator bodies, ten owning declarations, nine GPU lifetime bodies and ten event methods match baseline.')
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
  source.replace(available, available.replace('klock__Lock__release(&h->lock);', ''))]
 for changed in variants {
  require(changed != source, 'counterexample changed source')!
  if _ := check_host(changed) { return error('accepted unsafe heap C') }
 }
 println('Heap C checker: five missing/doubled/early-free and unlocked-reader counterexamples rejected.')
}

fn main() {
 assert os.args.len >= 3
 source := os.read_file(os.args[2])!
 match os.args[1] {
  '--host' { check_host(source)!; println('Heap host C: unlinked records free once; every statistics reader serializes with GC without temporary allocations.') }
  '--selftest' { selftest(source)! }
  '--native' { assert os.args.len == 4; check_native(source, os.read_file(os.args[3])!)! }
  else { panic('usage: check --host|--selftest CURRENT_C or --native CURRENT_C BASELINE_C') }
 }
}
