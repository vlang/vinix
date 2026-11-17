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
fn declaration(source string, name string) !string {
 start := source.index('struct ' + name + ' {') or { return error(name) }
 end := source.index_after('\n};', start) or { return error(name) }
 return source[start..end + 3]
}
fn ordered(source string, tokens []string) ! {
 mut cursor := 0
 for token in tokens { cursor = (source.index_after(token, cursor) or { return error(token) }) + token.len }
}
fn immediate_block() string {
 return '\t\t\t\tif (!h->keep_garbage) {\n\t\t\t\t\talloc__HeapAllocator__collect_garbage_locked(h, 1);\n\t\t\t\t}\n'
}
fn wrapper() string {
 return 'alloc__HeapAllocator alloc__new_heap_with_garbage(string name, u64 start, u64 end, bool keep_garbage) {\n' +
  '\talloc__HeapAllocator heap = alloc__new_heap(name, start, end);\n' +
  '\theap.keep_garbage = keep_garbage;\n\treturn heap;\n}\n'
}
fn check_policy(source string) ! {
 require(declaration(source, 'alloc__HeapAllocator')!.count('\tbool keep_garbage;\n') == 1, 'one nonowning policy flag')!
 require(body(source, 'alloc__new_heap_with_garbage')! == wrapper(), 'exact stack-only construction policy forwarding without clone or extra allocation')!
 constructor := body(source, 'alloc__new_heap')!
 ordered(constructor, ['alloc__HeapAllocator heap =', '.keep_garbage = true', 'heap.allocations.flags |= 1', 'return heap'])!
 release := body(source, 'alloc__HeapAllocator__release')!
 ordered(release, ['klock__Lock__acquire(&h->lock)', 'if (((*a)->va == va) && (*a)->in_use)',
  '(*(a))->in_use = false', 'h->garbage_count++', '(*(a))->release_order = h->garbage_count',
  'h->garbage_bytes += (*a)->size', immediate_block()])!
 require(release.count(immediate_block()) == 1 && release.count('collect_garbage_locked(') == 1,
  'only a one-record immediate collection on the nondeferred branch')!
 require(release.count('klock__Lock__release(&h->lock)') == 2, 'immediate collection completes before the established return unlock')!
 offset := release.index(immediate_block()) or { return error('immediate branch') }
 after := release[offset + immediate_block().len..]
 tail := '\t\t\t\t{\n\t\t\t\t\tklock__Lock__release(&h->lock);\n\t\t\t\t}\n\t\t\t\treturn;\n'
 require(after.starts_with(tail), 'no record or table alias is read after immediate retirement')!
 for method in [constructor, body(source, 'alloc__new_heap_with_garbage')!, release] {
  for token in ['memdup(', 'vcalloc(', 'malloc(', 'array__clone', 'array_clone('] {
   require(!method.contains(token), 'policy introduces no allocation or clone')!
  }
 }
 println('Heap policy C: deferred default, exact stack constructor, locked one-owner collection and direct unlock/return without reading retired aliases.')
}
fn restore_manager(source string) !string {
 mut manager := body(source, 'gpu__agx__gpu__new_gpu_manager')!
 require(manager.count('alloc__new_heap_with_garbage(') == 2, 'only two G13 class policy selections')!
 for class in ['shared', 'readonly'] {
  field := '.g13_' + class + ' = alloc__new_heap_with_garbage('
  start := manager.index(field) or { return error(field) }
  end := manager.index_after(', false)', start) or { return error('nondeferred shared class') }
  selected := manager[start..end + ', false)'.len]
  require(selected.contains('alloc__g13_' + class + '_start, alloc__g13_' + class + '_end'), 'exact shared class interval')!
  restored := selected.replace('alloc__new_heap_with_garbage(', 'alloc__new_heap(').replace(', false)', ')')
  manager = manager.replace(selected, restored)
 }
 return manager
}
fn compare_native(current string, old string) ! {
 check_policy(current)!
 require(body(current, 'alloc__new_heap')!.replace('.keep_garbage = true, ', '') == body(old, 'alloc__new_heap')!, 'constructor differs only by the deferred default')!
 require(body(current, 'alloc__HeapAllocator__release')!.replace(immediate_block(), '') == body(old, 'alloc__HeapAllocator__release')!, 'release differs only by the exact immediate branch')!
 for symbol in ['alloc__HeapAllocator__alloc', 'alloc__HeapAllocator__collect_garbage_locked',
  'alloc__HeapAllocator__gc', 'alloc__HeapAllocator__gc_locked', 'alloc__HeapAllocator__find_address_locked',
  'alloc__HeapAllocator__retire_hole_order_locked', 'alloc__HeapAllocator__newest_hole_order_locked',
  'alloc__checked_heap_align_up', 'alloc__heap_allocation_address'] {
  require(body(current, symbol)! == body(old, symbol)!, 'heap ownership changed: ' + symbol)!
 }
 require(restore_manager(current)! == body(old, 'gpu__agx__gpu__new_gpu_manager')!, 'manager changes only the two shared class policies')!
 for name in ['alloc__Allocation', 'alloc__HeapAllocator', 'gpu__agx__gpu__GpuManager', 'gpu__agx__gpu__G13RenderJobResources',
  'gpu__agx__gpu__G13ComputeJobResources', 'gpu__agx__gpu__G13QueueResources', 'gpu__agx__event__WorkQueueEvents',
  'gpu__agx__event__TicketBlock', 'gpu__agx__event__PendingTicket', 'gpu__agx__event__Ticket', 'fw__G13JobTimestamps'] {
  require(declaration(current, name)!.replace('\tbool keep_garbage;\n', '') == declaration(old, name)!, 'owning layout changed beyond one flag: ' + name)!
 }
 for suffix in ['prepare_g13_render_job_with_timestamps', 'prepare_g13_compute_job_with_timestamps',
  'free_g13_render_job_locked', 'free_g13_compute_job_locked', 'reap_g13_render_jobs', 'reap_g13_compute_jobs',
  'release_g13_queue_resources', 'submit_g13_batch', 'retire_g13_render_stages_locked',
  'free_shared_buffer', 'release_shared_buffer_backing', 'invalidate_g13_shared_buffer'] {
  symbol := 'gpu__agx__gpu__GpuManager__' + suffix
  require(body(current, symbol)! == body(old, symbol)!, 'GPU lifetime changed: ' + symbol)!
 }
 for symbol in ['gpu__agx__gpu__alloc_buffer_from_heap', 'gpu__agx__gpu__unmap_shared_buffer'] {
  require(body(current, symbol)! == body(old, symbol)!, 'unmap/rollback changed: ' + symbol)!
 }
 for suffix in ['retain', 'release', 'ticket', 'resolve_initial', 'can_submit', 'admit', 'can_publish_batch', 'can_publish', 'publish', 'record_completion'] {
  symbol := 'gpu__agx__event__WorkQueueEvents__' + suffix
  require(body(current, symbol)! == body(old, symbol)!, 'event ownership changed: ' + symbol)!
 }
 println('Heap policy native C: nine unchanged heap bodies, exact constructor/release/class transformations, eleven owning layouts, fourteen GPU lifetime bodies and ten event methods preserve baseline gates.')
}
fn selftest(source string) ! {
 check_policy(source)!
 release := body(source, 'alloc__HeapAllocator__release')!
 variants := [source.replace('if (!h->keep_garbage)', 'if (h->keep_garbage)'),
  source.replace('collect_garbage_locked(h, 1)', 'collect_garbage_locked(h, 0)'),
  source.replace('.keep_garbage = true', '.keep_garbage = false'),
  source.replace('heap.keep_garbage = keep_garbage;', 'heap.keep_garbage = true;'),
  source.replace(immediate_block(), immediate_block() + '\t\t\t\t(void)(*a)->size;\n'),
  source.replace('if (!h->keep_garbage)', 'klock__Lock__release(&h->lock); if (!h->keep_garbage)'),
  source.replace(wrapper(), wrapper().replace('return heap;', 'memdup(0, 1); return heap;')),
  source.replace('collect_garbage_locked(h, 1)', 'gc_locked(h)'),
  source.replace(wrapper(), wrapper().replace('return heap;', 'return alloc__new_heap(name, start, end);')),
  source.replace('\tbool keep_garbage;', '\tu64 keep_garbage;')]
 require(release.contains(immediate_block()), 'mutation anchor')!
 for changed in variants {
  require(changed != source, 'counterexample changed C')!
  if _ := check_policy(changed) { return error('accepted invalid release policy C') }
 }
 println('Heap policy C checker: ten default/forwarding/branch/retired-alias/lock/allocation/width mutations rejected.')
}
fn native_selftest(current string, old string) ! {
 compare_native(current, old)!
 variants := [current.replace('alloc__g13_shared_end, false)', 'alloc__g13_shared_end, true)'),
  current.replace('alloc__g13_readonly_end, false)', 'alloc__g13_readonly_end, true)'),
  current.replace('alloc__g13_private_start, alloc__g13_private_end)', 'alloc__g13_private_start, alloc__g13_shared_end)'),
  current.replace(body(current, 'gpu__agx__gpu__unmap_shared_buffer')!, 'void gpu__agx__gpu__unmap_shared_buffer(gpu__agx__gpu__SharedBuffer* buffer) {\n\treturn;\n}\n')]
 for changed in variants {
  require(changed != current, 'counterexample changed native C')!
  if _ := compare_native(changed, old) { return error('accepted changed native class/lifetime gate') }
 }
 println('Heap policy native checker: four class/private-window/unmap-gate mutations rejected.')
}
fn main() {
 assert os.args.len >= 3
 source := os.read_file(os.args[2])!
 match os.args[1] {
  '--host' { check_policy(source)! }
  '--selftest' { selftest(source)! }
  '--native' { assert os.args.len == 4; compare_native(source, os.read_file(os.args[3])!)! }
  '--native-selftest' { assert os.args.len == 4; native_selftest(source, os.read_file(os.args[3])!)! }
  else { panic('usage: check-policy --host|--selftest C or --native|--native-selftest C BASELINE_C') }
 }
}
