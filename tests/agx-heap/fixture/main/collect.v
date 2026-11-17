module main

import gpu.agx.alloc

fn measure_collect() {
 mut heap := alloc.new_heap('collect-measured', alloc.g13_shared_start, alloc.g13_shared_end)
 fill_capacity(mut heap, 8192)
 pin := heap.alloc(1, 0) or { panic('pinned allocation') }
 for index in 0 .. 8192 { heap.release(heap.start + u64(index) * alloc.gpu_page_size) }
 live_heap()
 before_blocks, before_bytes := live_heap()
 heap.gc()
 after_blocks, after_bytes := live_heap()
 blocks := i64(before_blocks) - i64(after_blocks)
 bytes := i64(before_bytes) - i64(after_bytes)
 C.printf(c'AGX-HEAP-COLLECT released=8192 retained_records=%lld reclaimed_blocks=%lld reclaimed_bytes=%lld\n',
  heap.allocations.len - 1, blocks, bytes)
 assert heap.allocations.len == 1 && blocks == 8192 && bytes == 262144,
  'GPU heap GC must collect released records below live allocations'
 assert heap.allocations[0].va == pin && heap.top == pin + alloc.gpu_page_size
 heap.release(pin); heap.gc()
 assert heap.top == heap.start && heap.allocations.len == 0
}

fn check_collect_pins() {
 mut cases := 0
 for offset in [u64(0), alloc.gpu_page_size, 7]! {
  for alignment in [u64(1), 2, 4, 8]! {
   for first in 0 .. 4 { for second in 0 .. 4 { for third in 0 .. 4 { for fourth in 0 .. 4 {
    if first == second || first == third || first == fourth || second == third || second == fourth || third == fourth { continue }
    start := alloc.g13_private_start + offset
    mut heap := alloc.new_heap('collect-pins', start, start + 256 * alloc.gpu_page_size)
    mut model := new_range_model(heap.start, heap.end)
    mut addresses := [4]u64{}
    mut gaps := unsafe { [4]&alloc.Allocation{} }
    mut pins := unsafe { [4]&alloc.Allocation{} }
    for index in 0 .. 4 {
     // Three pins survive a collection, then append a fourth beyond them.
     if index == 3 {
      heap.gc(); heap.gc()
      model.collect()
      assert heap.allocations.len == 3 && heap.top == model.top(),
       'GC must discard interior records while pins stay live'
      records_are_live(heap.allocations)
      for pin_index in 0 .. 3 { assert record_at(heap, addresses[pin_index]) == pins[pin_index] }
      $if agx_heap_sanitized ? {
       for gap_index in 0 .. 3 { assert C.__asan_address_is_poisoned(gaps[gap_index]) != 0 }
      }
     }
     size := u64(index + 1) * alloc.gpu_page_size
     align_bytes := alignment * alloc.gpu_page_size
     gap := reserve_checked(mut heap, mut model, size, align_bytes)
     gaps[index] = record_at(heap, gap)
     addresses[index] = reserve_checked(mut heap, mut model, 1, 0)
     pins[index] = record_at(heap, addresses[index])
     heap.release(gap); model.release(gap)
    }
    heap.gc(); heap.gc()
    model.collect()
    assert heap.allocations.len == 4 && heap.top == model.top(), 'GC preserves appended pins and frontier'
    records_are_live(heap.allocations)
    $if agx_heap_sanitized ? {
     // Earlier freed metadata can be reused by a later reservation. Only
     // the newly retired gap is guaranteed not to have been reused yet.
     assert C.__asan_address_is_poisoned(gaps[3]) != 0
    }
    mut live := [true, true, true, true]!
    for index in [first, second, third, fourth]! {
     heap.release(addresses[index]); model.release(addresses[index]); live[index] = false
     heap.gc(); heap.gc()
     model.collect()
     mut live_count := 0
     for pin_index in 0 .. 4 {
      if live[pin_index] {
       assert record_at(heap, addresses[pin_index]) == pins[pin_index]
       assert pins[pin_index].va == addresses[pin_index] && pins[pin_index].in_use
       live_count++
      }
      $if agx_heap_sanitized ? {
       assert (C.__asan_address_is_poisoned(pins[pin_index]) != 0) == !live[pin_index]
      }
     }
     assert heap.allocations.len == live_count && heap.top == model.top(),
      'GC reclaims only the released suffix VA across earlier interior collections'
     assert heap.used() == u64(live_count) * alloc.gpu_page_size && heap.available() == heap.end - model.top()
    }
    assert heap.top == start && heap.allocations.len == 0
    unsafe { heap.allocations.free(); model.records.free(); model.holes.free() }
    cases++
   } } } }
  }
 }
 assert cases == 288
 println('AGX heap collection: 288 offset/alignment/pin-order cases preserve interior-delete/append/tail-release/full-reset lifetimes')
}
