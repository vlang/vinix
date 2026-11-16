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

fn check_bounds(source string) ! {
 rounding := body(source, 'alloc__checked_heap_align_up')!
 require(rounding.starts_with('__v_option_u64 alloc__checked_heap_align_up(u64 value, u64 alignment)'), 'full-width stack result')!
 ordered(rounding, ['alignment == 0', 'alignment & (alignment - 1)', 'mask = alignment - 1',
  'value > (~(u64)(0) - mask)', '.ok = false', '(value + mask) & ~mask'])!
 address := body(source, 'alloc__heap_allocation_address')!
 require(address.starts_with('__v_option_u64 alloc__heap_allocation_address(u64 top, u64 end, u64 size, u64 alignment)'), 'full-width interval values')!
 ordered(address, ['alloc__checked_heap_align_up(top, alignment)',
  '(address > end) || (size > (end - address))', '.ok = false', '.value = address'])!
 for method in [rounding, address] {
  for token in ['memdup(', 'malloc(', 'vcalloc(', 'array_new(', 'IError'] { require(!method.contains(token), 'pure bounds helpers cannot allocate')! }
 }
 allocation := body(source, 'alloc__HeapAllocator__alloc')!
 candidate := 'alloc__heap_allocation_address(h->top, h->end, aligned_size, actual_align)'
 ordered(allocation, ['klock__Lock__acquire(&h->lock)', '(size == 0)',
  '(align != 0) && ((align & (align - 1)) != 0)', 'actual_align =',
  'alloc__checked_heap_align_up(size, actual_align)', candidate, 'alloc__HeapAllocator__gc_locked(h)',
  candidate, 'h->top = va + aligned_size', 'memdup(&(alloc__Allocation)', 'array_push(&h->allocations',
  'klock__Lock__release(&h->lock)'])!
 require(allocation.count(candidate) == 2 && allocation.count('memdup(') == 1
  && allocation.count('array_push(') == 1 && allocation.count('h->top =') == 1,
  'one owning reservation after two identical checked candidates')!
 for token in ['memdup_noscan(', 'malloc(', 'vcalloc(', 'array_new('] { require(!allocation.contains(token), 'only explicit metadata may allocate')! }
}

fn compare_native(current string, old string) ! {
 check_bounds(current)!
 for suffix in ['release', 'gc', 'gc_locked'] {
  symbol := 'alloc__HeapAllocator__' + suffix
  require(body(current, symbol)! == body(old, symbol)!, 'heap lifetime body changed: ' + symbol)!
 }
 require(body(current, 'alloc__new_heap')! == body(old, 'alloc__new_heap')!, 'heap construction changed')!
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
 println('Heap bounds native C: four heap lifetime bodies, ten owning declarations, nine GPU lifetime bodies and ten event methods match baseline.')
}

fn selftest(source string) ! {
 check_bounds(source)!
 allocation := body(source, 'alloc__HeapAllocator__alloc')!
 gc := allocation.index('alloc__HeapAllocator__gc_locked(h)') or { return error('GC') }
 late := allocation[..gc] + allocation[gc..].replace('h->top, h->end, aligned_size', 'h->top, (u64)(-1), aligned_size')
 variants := [source.replace('value > (~(u64)(0) - mask)', 'false'),
  source.replace('(address > end) || (size > (end - address))', 'false'),
  source.replace('(align != 0) && ((align & (align - 1)) != 0)', 'false'),
  source.replace(allocation, late),
  source.replace('u64 mask = alignment - 1;', 'memdup(0, 1); u64 mask = alignment - 1;')]
 for changed in variants {
  require(changed != source, 'counterexample unchanged')!
  if _ := check_bounds(changed) { return error('accepted unsafe bounds C') }
 }
 println('Heap bounds C checker: five overflow/alignment/retry/temporary-allocation mutations rejected.')
}

fn main() {
 assert os.args.len >= 3
 source := os.read_file(os.args[2])!
 match os.args[1] {
  '--host' { check_bounds(source)! }
  '--native' { assert os.args.len == 4; compare_native(source, os.read_file(os.args[3])!)! }
  '--selftest' { selftest(source)! }
  else { panic('usage: check-bounds --host|--selftest CURRENT_C or --native CURRENT_C BASELINE_C') }
 }
 println('Heap bounds C: checked u64 rounding, subtraction bounds, identical GC retry and one explicit metadata owner; helpers allocate no temporaries.')
}
