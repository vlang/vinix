module main

import gpu.agx.alloc

// Only the established allocator API is used here, so the retained baseline
// compiles and demonstrates the old descending-VA removal order at runtime.
fn check_garbage_fifo_probe() {
 for reverse in [false, true]! {
 mut heap := alloc.new_heap('garbage-fifo', alloc.g13_shared_start, alloc.g13_shared_start + 6 * alloc.gpu_page_size)
 mut addresses := [6]u64{}
 for index in 0 .. 6 { addresses[index] = heap.alloc(1, 0) or { panic('FIFO reservation') } }
 first := if reverse { 4 } else { 0 }
 last := if reverse { 0 } else { 4 }
 heap.release(addresses[first]); heap.release(addresses[last]); heap.gc()
 chosen := heap.alloc(1, 0) or { panic('FIFO reuse') }
 assert chosen == addresses[last], 'GC must retire deferred ranges in release FIFO order'
 heap.release(chosen)
 for index in [1, 2, 3, 5]! { heap.release(addresses[index]) }
 heap.gc()
 assert heap.allocations.len == 0 && heap.top == heap.start
 unsafe { heap.allocations.free() }
 }
 println('AGX garbage FIFO: full collection preserves release order independently of VA order')
}

fn release_permutation(code int) [6]int {
 mut available := [0, 1, 2, 3, 4, 5]!
 mut order := [6]int{}
 mut value := code
 for index in 0 .. 6 {
  count := 6 - index
  selected := value % count
  value /= count
  order[index] = available[selected]
  for shift in selected .. count - 1 { available[shift] = available[shift + 1] }
 }
 return order
}

fn check_garbage_snapshot(mut heap alloc.HeapAllocator, model &HeapRangeModel) {
 $if agx_heap_garbage ? {
  count, bytes := heap.garbage()
  mut expected_bytes := u64(0)
  for record in model.records { if !record.in_use { expected_bytes += record.size } }
  assert count == u64(model.pending.len) && bytes == expected_bytes,
   'garbage statistics must match count and rounded deferred bytes'
  check_model_hole_orders(&heap, model)
 }
}

fn check_garbage_limits() {
 $if agx_heap_garbage ? {
  mut cases := 0
  for offset in [u64(0), 7, alloc.gpu_page_size]! {
   for code in 0 .. 720 {
    order := release_permutation(code)
    for limit in [u64(0), 1, 2, 3, 4, 5, 6, 7, ~u64(0)]! {
     start := alloc.g13_private_start + offset
     mut heap := alloc.new_heap('garbage-limits', start, start + 64 * alloc.gpu_page_size)
     mut model := new_range_model(heap.start, heap.end)
     mut addresses := [6]u64{}
     mut pointers := unsafe { [6]&alloc.Allocation{} }
     mut pins := [6]u64{}
     for index in 0 .. 6 {
      addresses[index] = reserve_checked(mut heap, mut model, u64(index % 3 + 1) * alloc.gpu_page_size, 0)
      pointers[index] = record_at(&heap, addresses[index])
      pins[index] = reserve_checked(mut heap, mut model, 1, 0)
     }
     for index in order {
      heap.release(addresses[index]); model.release(addresses[index])
      heap.release(addresses[index]); model.release(addresses[index])
     }
     heap.release(heap.end); model.release(heap.end)
     check_garbage_snapshot(mut heap, &model)
     heap.collect_garbage(limit); model.collect_count(limit)
     check_garbage_snapshot(mut heap, &model)
     collected := if limit < 6 { int(limit) } else { 6 }
     assert heap.allocations.len == 12 - collected && heap.top == model.top()
     for position, index in order {
      $if agx_heap_sanitized ? {
       assert (C.__asan_address_is_poisoned(pointers[index]) != 0) == (position < collected),
        'bounded GC must free only the oldest requested deferred prefix'
      }
      if position >= collected {
       assert record_at(&heap, addresses[index]) == pointers[index] && !pointers[index].in_use
      }
     }
     for address in pins { assert record_at(&heap, address).in_use }
     for record in model.records { heap.release(record.va); model.release(record.va) }
     heap.gc(); model.collect()
     check_garbage_snapshot(mut heap, &model)
     assert heap.top == start && heap.allocations.len == 0
     unsafe { heap.allocations.free(); model.records.free(); model.holes.free(); model.pending.free() }
     cases++
    }
   }
  }
  assert cases == 19440
  println('AGX garbage FIFO: 19440 release-permutation/count/offset cases preserve pending owners, live pins and bounded ranks')
 }
}

fn check_garbage_churn() {
 $if agx_heap_garbage ? {
  mut steps := 0
  for offset in [u64(0), 7]! {
   for seed in 0 .. 32 {
    start := alloc.g13_shared_start + offset
    mut heap := alloc.new_heap('garbage-churn', start, start + 128 * alloc.gpu_page_size)
    mut model := new_range_model(heap.start, heap.end)
    mut random := u64(seed + 1)
    for step in 0 .. 160 {
     random = (random * u64(1664525) + u64(1013904223)) & u64(0xffffffff)
     if model.records.len > 0 && (step % 3 == 0 || model.records.len > 10) {
      address := model.records[int(random % u64(model.records.len))].va
      heap.release(address); model.release(address)
     } else {
      reserve_checked(mut heap, mut model, (1 + random % 3) * alloc.gpu_page_size,
       (u64(1) << ((random >> 8) % 3)) * alloc.gpu_page_size)
     }
     limit := (random >> 16) % 5
     heap.collect_garbage(limit); model.collect_count(limit)
     check_garbage_snapshot(mut heap, &model)
     steps++
    }
    for record in model.records { heap.release(record.va); model.release(record.va) }
    heap.gc(); model.collect()
    check_garbage_snapshot(mut heap, &model)
    assert heap.top == start && heap.allocations.len == 0
    unsafe { heap.allocations.free(); model.records.free(); model.holes.free(); model.pending.free() }
   }
  }
  assert steps == 10240
  println('AGX garbage FIFO: 10240 mixed partial-collection/reuse steps match an independent pending-address FIFO')
 }
}

fn check_garbage() { check_garbage_fifo_probe(); check_garbage_limits(); check_garbage_churn() }
