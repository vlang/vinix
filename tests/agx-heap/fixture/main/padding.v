module main

import gpu.agx.alloc

fn padding_pair(mut heap alloc.HeapAllocator) {
 first := heap.alloc(1, alloc.gpu_page_size) or { panic('padding first') }
 second := heap.alloc(1, 4 * alloc.gpu_page_size) or { panic('padding second') }
 heap.release(first); heap.release(second); heap.gc()
}

fn check_heap_padding_probe() {
 mut heap := alloc.new_heap('padding', alloc.g13_shared_start,
  alloc.g13_shared_start + 8 * alloc.gpu_page_size)
 padding_pair(mut heap)
 C.printf(c'AGX-PADDING-PROBE retained_va=%llu retained_records=%lld\n',
  heap.top - heap.start, heap.allocations.len)
 assert heap.top == heap.start && heap.allocations.len == 0,
  'GPU heap GC must reclaim alignment padding and released prefix'
}

fn measure_padding() {
 mut heap := alloc.new_heap('padding-measured', alloc.g13_shared_start, alloc.g13_shared_end)
 for _ in 0 .. 1000 { padding_pair(mut heap) }
 live_heap()
 before_blocks, before_bytes := live_heap()
 before_top := heap.top
 before_records := heap.allocations.len
 for _ in 0 .. 10000 { padding_pair(mut heap) }
 after_blocks, after_bytes := live_heap()
 blocks := i64(after_blocks) - i64(before_blocks)
 bytes := i64(after_bytes) - i64(before_bytes)
 C.printf(c'AGX-HEAP-PADDING operations=10000 retained_va=%llu retained_records=%lld retained_blocks=%lld retained_bytes=%lld\n',
  heap.top - before_top, heap.allocations.len - before_records, blocks, bytes)
 assert heap.top == heap.start && heap.allocations.len == 0 && blocks == 0 && bytes == 0,
  'GPU heap padding churn must not retain reservations'
}

fn check_heap_padding_matrix() {
 mut cases := u64(0)
 for offset in [u64(0), alloc.gpu_page_size, 7]! {
  for first_align in [u64(1), 2, 4, 8]! {
   for second_align in [u64(1), 2, 4, 8]! {
    for third_align in [u64(1), 2, 4, 8]! {
     for mask in 0 .. 8 {
      for order in [[0, 1, 2]!, [0, 2, 1]!, [1, 0, 2]!, [1, 2, 0]!, [2, 0, 1]!, [2, 1, 0]!]! {
       start := alloc.g13_private_start + offset
       mut heap := alloc.new_heap('padding-matrix', start, start + 32 * alloc.gpu_page_size)
       mut model := new_range_model(heap.start, heap.end)
       aligns := [first_align, second_align, third_align]!
       sizes := [u64(1), alloc.gpu_page_size + 1, 2 * alloc.gpu_page_size + 1]!
       mut addresses := [3]u64{}
       mut records := unsafe { [3]&alloc.Allocation{} }
       for index in 0 .. 3 {
        addresses[index] = reserve_checked(mut heap, mut model, sizes[index], aligns[index] * alloc.gpu_page_size)
        records[index] = record_at(heap, addresses[index])
       }
       for index in order {
        if mask & (1 << index) != 0 { heap.release(addresses[index]); model.release(addresses[index]) }
       }
       records_are_live(heap.allocations)
       heap.gc()
       model.collect()
       assert heap.top == model.top(),
        'GC restores reservation frontier including alignment padding'
       records_are_live(heap.allocations)
       mut live_index := 0
       for index in 0 .. 3 {
        if mask & (1 << index) == 0 {
         assert record_at(heap, addresses[index]) == records[index]
         live_index++
        }
       }
       assert heap.allocations.len == live_index, 'GC collects every released record including interiors'
       $if agx_heap_sanitized ? {
        for index in 0 .. 3 {
         assert (C.__asan_address_is_poisoned(records[index]) != 0) == (mask & (1 << index) != 0)
        }
       }
       for index in order { heap.release(addresses[index]) }
       heap.gc(); heap.gc()
       assert heap.top == start && heap.allocations.len == 0 && heap.used() == 0
       unsafe { model.records.free(); heap.allocations.free() }
       cases++
      }
     }
    }
   }
  }
 }
 assert cases == 9216
 println('AGX heap padding: 9216 alignment/order/release-mask cases collect all released records and restore suffix frontiers')
}

fn check_heap_padding_allocation_gc() {
 mut heap := alloc.new_heap('padding-retry', alloc.g13_shared_start,
  alloc.g13_shared_start + 8 * alloc.gpu_page_size)
 first := heap.alloc(1, 0) or { panic('first') }
 second := heap.alloc(1, 4 * alloc.gpu_page_size) or { panic('second') }
 heap.release(first); heap.release(second)
 whole := heap.alloc(8 * alloc.gpu_page_size, 0) or { panic('GC must recover the complete padded range') }
 assert whole == heap.start && heap.allocations.len == 1 && heap.available() == 0
 heap.release(whole); heap.gc()
 assert heap.top == heap.start && heap.allocations.len == 0
 println('AGX heap padding: allocation-triggered GC recovers the complete aligned range')
}

fn check_heap_padding() {
 check_heap_padding_probe()
 check_heap_padding_matrix()
 check_heap_padding_allocation_gc()
}
