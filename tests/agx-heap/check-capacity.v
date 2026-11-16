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
fn check_capacity(source string) ! {
 constructor := body(source, 'alloc__new_heap')!
 ordered(constructor, ['alloc__HeapAllocator heap = (alloc__HeapAllocator){',
  'array_new(sizeof(alloc__Allocation*), 0, 0)', 'heap.allocations.flags |= 1;', 'return heap;'])!
 require(constructor.count('array_new(') == 1 && constructor.count('flags |= 1') == 1,
  'one initial table with exclusive buffer ownership')!
 for token in ['memdup(', 'malloc(', 'vcalloc(', 'array_clone', 'array__clone'] {
  require(!constructor.contains(token), 'returned heap is a stack value without hidden clone or allocation')!
 }
 growth := body(source, 'array__ensure_cap')!
 ordered(growth, ['array__alloc_array_data_like_uninit(a, new_size)',
  'vmemcpy(new_data, a->data,',
  'if (((a->flags & 1) != 0) && !((a->flags & 64) != 0) && !array__buffer_has_slices(a))',
  'free_unaliased((array__data_header(a))->allocation)', 'free_unaliased(a->data)',
  'a->data = new_data', 'a->cap ='])!
 require(growth.count('free_unaliased(') == 2, 'exclusive managed or raw buffer is freed exactly once')!
 grown := body(source, 'array__grown')!
 ordered(grown, ['array __assoc_0 = a', 'array res = __assoc_0', 'array__ensure_cap(&res, required)', 'return res'])!
 transfer := body(source, 'array__take_buffer')!
 ordered(transfer, ['a->data = other.data', 'a->cap = other.cap', 'a->flags = other.flags'])!
 require(body(source, 'free_unaliased')!.count('v_free(ptr)') == 1
  && body(source, 'v_free')!.count('free(ptr)') == 1,
  'exclusive buffer disposal reaches the actual allocator free')!
 allocation := body(source, 'alloc__HeapAllocator__alloc')!
 ordered(allocation, ['klock__Lock__acquire(&h->lock)', 'array_push(&h->allocations', 'klock__Lock__release(&h->lock)'])!
 println('Heap capacity C: stack constructor sets exclusive ownership before return; growth copies before freeing the old buffer and preserves flags without cloning.')
}
fn compare_native(current string, old string) ! {
 check_capacity(current)!
 constructor := body(current, 'alloc__new_heap')!
 old_line := '\talloc__HeapAllocator heap = '
 flag_line := '\theap.allocations.flags |= 1;\n'
 return_line := '\treturn heap;\n'
 for token in [old_line, flag_line, return_line] { require(constructor.count(token) == 1, 'exact stack constructor transformation')! }
 restored := constructor.replace(old_line, '\treturn ').replace(flag_line, '').replace(return_line, '')
 require(restored == body(old, 'alloc__new_heap')!, 'constructor changes only local return and ownership flag')!
 for suffix in ['alloc', 'release', 'gc', 'gc_locked', 'checked_heap_align_up', 'heap_allocation_address'] {
  symbol := if suffix in ['alloc', 'release', 'gc', 'gc_locked'] { 'alloc__HeapAllocator__' + suffix } else { 'alloc__' + suffix }
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
 println('Heap capacity native C: exact constructor flag change; six heap bodies, ten owning declarations, nine GPU lifetime bodies and ten event methods match baseline.')
}
fn selftest(source string) ! {
 check_capacity(source)!
 constructor := body(source, 'alloc__new_heap')!
 growth := body(source, 'array__ensure_cap')!
 transfer := body(source, 'array__take_buffer')!
 disposer := body(source, 'free_unaliased')!
 flag := '\theap.allocations.flags |= 1;\n'
 variants := [source.replace(constructor, constructor.replace(flag, '')),
  source.replace(constructor, constructor.replace(flag, flag.replace('|= 1', '|= 2'))),
  source.replace(constructor, constructor.replace(flag, '').replace('return heap;', 'return heap;\n' + flag)),
  source.replace(constructor, constructor.replace('return heap;', 'memdup(0, 1); return heap;')),
  source.replace(growth, growth.replace('free_unaliased((array__data_header(a))->allocation);', '')),
  source.replace(growth, growth.replace('vmemcpy(new_data, a->data,', 'free_unaliased(a->data); vmemcpy(new_data, a->data,')),
  source.replace(transfer, transfer.replace('a->flags = other.flags;', '')),
  source.replace(disposer, disposer.replace('v_free(ptr);', ''))]
 for changed in variants {
  require(changed != source, 'counterexample changed source')!
  if _ := check_capacity(changed) { return error('accepted unsafe heap capacity C') }
 }
 println('Heap capacity C checker: eight constructor/allocation/free/flag-transfer mutations rejected.')
}
fn main() {
 assert os.args.len >= 3
 source := os.read_file(os.args[2])!
 match os.args[1] {
  '--host' { check_capacity(source)! }
  '--native' { assert os.args.len == 4; compare_native(source, os.read_file(os.args[3])!)! }
  '--selftest' { selftest(source)! }
  else { panic('usage: check-capacity --host|--selftest CURRENT_C or --native CURRENT_C BASELINE_C') }
 }
}
