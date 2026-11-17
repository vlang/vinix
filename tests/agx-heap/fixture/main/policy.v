module main

import gpu.agx.alloc

fn new_policy_heap(start u64, end u64, deferred bool) alloc.HeapAllocator {
 $if agx_heap_release_policy ? {
  return alloc.new_heap_with_garbage('release-policy', start, end, deferred)
 } $else {
  // The baseline uses exactly the constructor its shared manager used.
  return alloc.new_heap('release-policy-baseline', start, end)
 }
}

fn check_immediate_release_probe() {
 mut heap := new_policy_heap(alloc.g13_shared_start, alloc.g13_shared_start + 4 * alloc.gpu_page_size, false)
 low := heap.alloc(1, 0) or { panic('policy low') }
 pin := heap.alloc(3 * alloc.gpu_page_size, 0) or { panic('policy pin') }
 retired := heap.allocations[0]
 pinned := heap.allocations[1]
 heap.release(low)
 $if agx_heap_sanitized ? {
  assert C.__asan_address_is_poisoned(retired) != 0,
   'nondeferred release must retire metadata before returning'
 }
 assert heap.allocations.len == 1 && heap.allocations[0] == pinned && pinned.in_use
 reused := heap.alloc(1, 0) or { panic('immediate interior reuse') }
 assert reused == low && heap.allocations[1] == pinned && heap.top == heap.end
 heap.release(reused); heap.release(pin)
 assert heap.allocations.len == 0 && heap.top == heap.start
 heap.gc()
 unsafe { heap.allocations.free() }
 println('AGX release policy: immediate metadata retirement and lower-hole reuse preserve a live pin without explicit GC')
}

fn check_default_release_probe() {
 mut heap := alloc.new_heap('default-policy', alloc.g13_private_start, alloc.g13_private_start + 4 * alloc.gpu_page_size)
 address := heap.alloc(1, 0) or { panic('default allocation') }
 record := heap.allocations[0]
 heap.release(address)
 assert heap.allocations.len == 1 && !record.in_use,
  'the ordinary heap constructor must retain deferred owners'
 $if agx_heap_sanitized ? { assert C.__asan_address_is_poisoned(record) == 0 }
 heap.gc()
 $if agx_heap_sanitized ? { assert C.__asan_address_is_poisoned(record) != 0 }
 assert heap.allocations.len == 0 && heap.top == heap.start
 unsafe { heap.allocations.free() }
 println('AGX release policy: ordinary constructor retains deferred ownership until GC')
}

fn policy_churn(mut heap alloc.HeapAllocator, count int) {
 for _ in 0 .. count {
  address := heap.alloc(1, 0) or { panic('immediate churn') }
  heap.release(address)
 }
}

fn measure_release_policy() {
 mut heap := new_policy_heap(alloc.g13_shared_start, alloc.g13_shared_end, false)
 policy_churn(mut heap, 1000)
 live_heap()
 for round in 0 .. 3 {
  before_blocks, before_bytes := live_heap()
  policy_churn(mut heap, 10000)
  after_blocks, after_bytes := live_heap()
  blocks := i64(after_blocks) - i64(before_blocks)
  bytes := i64(after_bytes) - i64(before_bytes)
  C.printf(c'AGX-HEAP-POLICY round=%lld operations=10000 retained_blocks=%lld retained_bytes=%lld retained_records=%lld\n',
   round, blocks, bytes, heap.allocations.len)
  assert blocks == 0 && bytes == 0 && heap.allocations.len == 0 && heap.top == heap.start,
   'immediate release churn must retain no records without explicit GC'
 }
 unsafe { heap.allocations.free() }
}

fn check_release_policy_matrix() {
 $if agx_heap_release_policy ? {
  mut cases := 0
  for deferred in [false, true]! {
   for offset in [u64(0), 7, alloc.gpu_page_size]! {
    for code in 0 .. 720 {
     start := alloc.g13_private_start + offset
     mut heap := new_policy_heap(start, start + 128 * alloc.gpu_page_size, deferred)
     mut model := new_range_model(heap.start, heap.end)
     model.keep_garbage = deferred
     mut addresses := [6]u64{}
     mut pointers := unsafe { [6]&alloc.Allocation{} }
     for index in 0 .. 6 {
      addresses[index] = reserve_checked(mut heap, mut model,
       u64(index % 3 + 1) * alloc.gpu_page_size, (u64(1) << (index % 3)) * alloc.gpu_page_size)
      pointers[index] = record_at(&heap, addresses[index])
     }
     order := release_permutation(code)
     mut released := [6]bool{}
     for index in order {
      heap.release(addresses[index]); model.release(addresses[index]); released[index] = true
      // Duplicate and unknown releases must not enqueue or retire another owner.
      heap.release(addresses[index]); heap.release(heap.end)
      check_garbage_snapshot(mut heap, &model)
      assert heap.top == model.top() && heap.allocations.len == model.records.len
      for check in 0 .. 6 {
       $if agx_heap_sanitized ? {
        assert (C.__asan_address_is_poisoned(pointers[check]) != 0) == (!deferred && released[check]),
         'release policy must retire only immediate owners and retain deferred owners'
       }
       if !released[check] || deferred { assert record_at(&heap, addresses[check]) == pointers[check] }
      }
     }
     heap.collect_garbage(2); model.collect_count(2)
     check_garbage_snapshot(mut heap, &model)
     heap.gc(); model.collect()
     check_garbage_snapshot(mut heap, &model)
     assert heap.top == start && heap.allocations.len == 0
     unsafe { heap.allocations.free(); model.records.free(); model.holes.free(); model.pending.free() }
     cases++
    }
   }
  }
  assert cases == 4320
  println('AGX release policy: 4320 policy/offset/release-permutation cases preserve pending ownership, holes, statistics and live records')
 }
}

fn check_policy_churn() {
 $if agx_heap_release_policy ? {
  mut steps := 0
  for deferred in [false, true]! {
   for offset in [u64(0), 7]! {
    for seed in 0 .. 32 {
     start := alloc.g13_shared_start + offset
     mut heap := new_policy_heap(start, start + 128 * alloc.gpu_page_size, deferred)
     mut model := new_range_model(heap.start, heap.end); model.keep_garbage = deferred
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
      if step % 4 == 0 {
       limit := (random >> 16) % 5
       heap.collect_garbage(limit); model.collect_count(limit)
      }
      check_garbage_snapshot(mut heap, &model)
      steps++
     }
     // Immediate release mutates the model reservation list, so retire from
     // its tail rather than iterating a view across those deletions.
     for model.records.len > 0 {
      address := model.records.last().va
      heap.release(address); model.release(address)
      if deferred { heap.gc(); model.collect() }
     }
     check_garbage_snapshot(mut heap, &model)
     assert heap.top == start && heap.allocations.len == 0
     unsafe { heap.allocations.free(); model.records.free(); model.holes.free(); model.pending.free() }
    }
   }
  }
  assert steps == 20480
  println('AGX release policy: 20480 mixed policy/reuse/partial-GC steps match the independent interval and FIFO model')
 }
}

fn check_release_policy() { check_immediate_release_probe(); check_default_release_probe(); check_release_policy_matrix(); check_policy_churn() }
