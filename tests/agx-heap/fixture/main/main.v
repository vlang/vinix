module main

import os
import gpu.agx.alloc

#include <sanitizer/asan_interface.h>

fn C.__asan_address_is_poisoned(voidptr) int

fn churn(mut heap alloc.HeapAllocator, count int) {
 for _ in 0 .. count {
  address := heap.alloc(1, alloc.gpu_page_size) or { panic('heap allocation') }
  heap.release(address)
  heap.gc()
 }
}

fn measure() {
 mut heap := alloc.new_heap('measured', alloc.g13_shared_start, alloc.g13_shared_end)
 churn(mut heap, 1000)
 live_heap()
 for round in 0 .. 3 {
  before_blocks, before_bytes := live_heap()
  churn(mut heap, 10000)
  after_blocks, after_bytes := live_heap()
  blocks := i64(after_blocks) - i64(before_blocks)
  bytes := i64(after_bytes) - i64(before_bytes)
  C.printf(c'AGX-HEAP round=%lld operations=10000 retained_blocks=%lld retained_bytes=%lld\n',
   round, blocks, bytes)
  assert blocks == 0 && bytes == 0, 'AGX heap repeated allocation retains metadata'
  assert heap.top == heap.start && heap.allocations.len == 0
 }
}

fn records_are_live(records []&alloc.Allocation) {
 $if agx_heap_sanitized ? {
  for record in records { assert C.__asan_address_is_poisoned(record) == 0, 'retained heap metadata must stay live' }
 }
}

fn check_delayed_gc() {
 for mask in 0 .. 8 {
  mut heap := alloc.new_heap('ordered', alloc.g13_private_start, alloc.g13_private_end)
  mut addresses := [3]u64{}
  mut records := unsafe { [3]&alloc.Allocation{} }
  for index in 0 .. 3 {
   addresses[index] = heap.alloc(u64(index + 1), alloc.gpu_page_size) or { panic('allocation') }
   records[index] = heap.allocations[index]
  }
  for index in 0 .. 3 {
   if mask & (1 << index) != 0 { heap.release(addresses[index]) }
  }
  records_are_live(heap.allocations)
  heap.gc()
  mut retained := 3
  for retained > 0 && mask & (1 << (retained - 1)) != 0 { retained-- }
  assert heap.allocations.len == retained && heap.top == heap.start + u64(retained) * alloc.gpu_page_size
  records_are_live(heap.allocations)
  $if agx_heap_sanitized ? {
   for index in retained .. 3 {
    assert C.__asan_address_is_poisoned(records[index]) != 0, 'trimmed heap metadata is freed'
   }
  }
  for address in addresses { heap.release(address) }
  heap.gc()
  heap.gc()
  assert heap.allocations.len == 0 && heap.top == heap.start && heap.used() == 0
  assert heap.available() == heap.end - heap.start
  $if agx_heap_sanitized ? {
   for record in records { assert C.__asan_address_is_poisoned(record) != 0, 'each reclaimed record retires once' }
  }
 }
 println('AGX heap: eight release masks retain live interiors and free only trimmed suffix records; repeated GC is idempotent')
}

fn check_allocation_gc() {
 mut heap := alloc.new_heap('allocation-gc', alloc.g13_shared_start, alloc.g13_shared_start + 2 * alloc.gpu_page_size)
 first := heap.alloc(1, alloc.gpu_page_size) or { panic('first') }
 second := heap.alloc(1, alloc.gpu_page_size) or { panic('second') }
 assert heap.available() == 0 && heap.used() == 2 * alloc.gpu_page_size,
  'full-heap statistics release the lock on their early return'
 record := heap.allocations[1]
 heap.release(second)
 third := heap.alloc(1, alloc.gpu_page_size) or { panic('automatic GC') }
 assert third == second && heap.allocations.len == 2
 records_are_live(heap.allocations)
 $if agx_heap_sanitized ? {
  assert C.__asan_address_is_poisoned(record) != 0, 'allocation-triggered GC frees old suffix metadata'
 }
 heap.release(first); heap.release(third); heap.gc()
 assert heap.used() == 0 && heap.top == heap.start && heap.allocations.len == 0
 println('AGX heap: allocation-triggered GC reclaims metadata and reuses the VA suffix')
}

fn read_stats(heap &alloc.HeapAllocator) {
 mut owned := unsafe { heap }
 for _ in 0 .. 20000 {
  assert owned.used() <= owned.end - owned.start
  assert owned.available() <= owned.end - owned.start
 }
}

fn check_concurrent_stats() {
 mut heap := alloc.new_heap('concurrent', alloc.g13_shared_start, alloc.g13_shared_end)
 first := spawn read_stats(&heap)
 second := spawn read_stats(&heap)
 churn(mut heap, 10000)
 first.wait(); second.wait()
 assert heap.used() == 0 && heap.allocations.len == 0 && heap.top == heap.start
 println('AGX heap: 10000 reclaim cycles overlap 80000 locked statistics reads')
}

fn main() {
 if os.args.len == 2 && os.args[1] == '--measure' { measure(); return }
 check_delayed_gc()
 check_allocation_gc()
 check_concurrent_stats()
 println('AGX heap ownership: PASS')
}
