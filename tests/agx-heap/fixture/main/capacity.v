module main

import gpu.agx.alloc

fn fill_capacity(mut heap alloc.HeapAllocator, count int) {
 for index in 0 .. count {
  address := heap.alloc(1, 0) or { panic('capacity allocation') }
  assert address == heap.start + u64(index) * alloc.gpu_page_size
 }
}

fn release_capacity(mut heap alloc.HeapAllocator, count int) {
 for index in 0 .. count { heap.release(heap.start + u64(index) * alloc.gpu_page_size) }
 heap.gc()
 assert heap.top == heap.start && heap.allocations.len == 0
}

fn measure_capacity() {
 // Warm the host mutex and allocator before measuring table ownership.
 mut heap := alloc.new_heap('capacity-measured', alloc.g13_shared_start, alloc.g13_shared_end)
 fill_capacity(mut heap, 2)
 release_capacity(mut heap, 2)
 unsafe { heap.allocations.free() }
 heap.allocations = []&alloc.Allocation{}
 heap.allocations.flags |= .noslices
 live_heap()
 before_blocks, before_bytes := live_heap()
 fill_capacity(mut heap, 8192)
 release_capacity(mut heap, 8192)
 // Release the last owned buffer so both samples have an empty table.
 unsafe { heap.allocations.free() }
 after_blocks, after_bytes := live_heap()
 blocks := i64(after_blocks) - i64(before_blocks)
 bytes := i64(after_bytes) - i64(before_bytes)
 C.printf(c'AGX-HEAP-CAPACITY records=8192 retained_blocks=%lld retained_bytes=%lld\n', blocks, bytes)
 assert blocks == 0 && bytes == 0, 'GPU heap table growth must not retain discarded buffers'
}

fn check_capacity_growth() {
 mut heap := alloc.new_heap('capacity-sanitized', alloc.g13_shared_start, alloc.g13_shared_end)
 first_reader := spawn read_stats(&heap)
 second_reader := spawn read_stats(&heap)
 mut growths := 0
 for index in 0 .. 8192 {
  old_table := heap.allocations.data
  old_cap := heap.allocations.cap
  first := if index == 0 { unsafe { &alloc.Allocation(nil) } } else { heap.allocations[0] }
  address := heap.alloc(1, 0) or { panic('capacity allocation') }
  assert address == heap.start + u64(index) * alloc.gpu_page_size
  if heap.allocations.cap != old_cap {
   growths++
   $if agx_heap_sanitized ? {
    if old_cap > 0 {
     assert C.__asan_address_is_poisoned(old_table) != 0,
      'GPU heap growth must free the previous pointer buffer'
    } else { assert old_table == unsafe { nil } }
   }
   records_are_live(heap.allocations)
   for record_index, record in heap.allocations {
    assert record.va == heap.start + u64(record_index) * alloc.gpu_page_size
   }
  } else { assert heap.allocations.data == old_table }
  if index != 0 {
   assert heap.allocations[0] == first && first.va == heap.start,
    'table growth must preserve allocation pointees'
  }
 }
 first_reader.wait(); second_reader.wait()
 assert growths == 13
 release_capacity(mut heap, 8192)
 unsafe { heap.allocations.free() }
 println('AGX heap capacity: 13 growth boundaries preserve 8192 pointees, retire old pointer buffers and overlap 80000 locked statistics reads')
}
