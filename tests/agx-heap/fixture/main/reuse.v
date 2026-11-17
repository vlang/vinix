module main

import gpu.agx.alloc

fn check_reuse_probe() {
 mut heap := alloc.new_heap('reuse-probe', alloc.g13_shared_start, alloc.g13_shared_start + 4 * alloc.gpu_page_size)
 low := heap.alloc(1, 0) or { panic('low allocation') }
 pin := heap.alloc(3 * alloc.gpu_page_size, 0) or { panic('pin allocation') }
 heap.release(low); heap.gc()
 reused := heap.alloc(1, 0) or { panic('GPU heap must reuse a collected interior range') }
 assert reused == low && heap.top == heap.end && heap.allocations.len == 2,
  'interior reuse must preserve the highest reservation'
 assert heap.allocations[0].va == low && heap.allocations[1].va == pin,
  'reused records must remain in VA order'
 heap.release(reused); heap.gc()
 assert heap.top == heap.end && heap.allocations.len == 1 && heap.allocations[0].va == pin
 heap.release(pin); heap.gc()
 assert heap.top == heap.start && heap.allocations.len == 0
 println('AGX heap reuse: collected interior range succeeds below a live allocation at full capacity')
}

fn check_reuse_model() {
 mut cases := 0
 for offset in [u64(0), 7, alloc.gpu_page_size]! {
  for mask in 0 .. 16 {
   for size_pages in 1 .. 9 {
    for alignment in [u64(1), 2, 4, 8]! {
     for collect_first in [false, true]! {
      start := alloc.g13_private_start + offset
      mut heap := alloc.new_heap('reuse-model', start, start + 32 * alloc.gpu_page_size)
      mut model := new_range_model(heap.start, heap.end)
      sizes := [u64(3), 1, 2, 1, 4, 1, 6, 1]!
      mut addresses := [8]u64{}
      mut records := unsafe { [8]&alloc.Allocation{} }
      for index in 0 .. 8 {
       addresses[index] = reserve_checked(mut heap, mut model, sizes[index] * alloc.gpu_page_size, 0)
       records[index] = record_at(heap, addresses[index])
      }
      for index in 0 .. 4 {
       if mask & (1 << index) != 0 {
        heap.release(addresses[index * 2]); model.release(addresses[index * 2])
       }
      }
      if collect_first { heap.gc(); model.collect() }
      $if agx_heap_sanitized ? {
       for index in 0 .. 8 {
        retired := collect_first && index % 2 == 0 && mask & (1 << (index / 2)) != 0
        assert (C.__asan_address_is_poisoned(records[index]) != 0) == retired
       }
      }
      reserve_checked(mut heap, mut model, u64(size_pages) * alloc.gpu_page_size, alignment * alloc.gpu_page_size)
      for index in 0 .. 8 {
       released := index % 2 == 0 && mask & (1 << (index / 2)) != 0
       if !released { assert record_at(heap, addresses[index]) == records[index] && records[index].in_use }
      }
      for record in model.records { heap.release(record.va) }
      heap.gc(); heap.gc()
      assert heap.top == start && heap.allocations.len == 0 && heap.used() == 0
      unsafe { heap.allocations.free(); model.records.free(); model.holes.free() }
      cases++
     }
    }
   }
  }
 }
 assert cases == 3072
 println('AGX heap reuse: 3072 fragmented/aligned/pending-release cases match candidate enumeration and preserve live records')
}

fn check_raw_hole_ranking() {
 mut heap := alloc.new_heap('raw-holes', alloc.g13_shared_start, alloc.g13_shared_start + 32 * alloc.gpu_page_size)
 prefix := heap.alloc(7 * alloc.gpu_page_size, 0) or { panic('prefix') }
 wide := heap.alloc(4 * alloc.gpu_page_size, 0) or { panic('wide') }
 middle := heap.alloc(5 * alloc.gpu_page_size, 0) or { panic('middle') }
 narrow := heap.alloc(3 * alloc.gpu_page_size, 0) or { panic('narrow') }
 high := heap.alloc(1, 0) or { panic('high') }
 high_record := record_at(heap, high)
 heap.release(wide); heap.release(narrow); heap.gc()
 selected := heap.alloc(1, 2 * alloc.gpu_page_size) or { panic('aligned gap') }
 assert selected == narrow, 'best fit must rank complete holes before alignment padding'
 assert record_at(heap, high) == high_record && heap.top == high + alloc.gpu_page_size
 for address in [prefix, middle, selected, high]! { heap.release(address) }
 heap.gc()
 assert heap.allocations.len == 0 && heap.top == heap.start
 unsafe { heap.allocations.free() }
 println('AGX heap reuse: raw hole ranking selects the smaller higher gap despite equal aligned residual space')
}

fn check_heap_reuse() { check_reuse_probe(); check_raw_hole_ranking(); check_reuse_model() }
