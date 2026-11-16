module main

import gpu.agx.alloc

// Independent division/remainder model; production uses checked bit rounding.
fn heap_bounds_model(top u64, end u64, size u64, requested u64) (bool, u64, u64) {
 if size == 0 || top > end { return false, 0, 0 }
 mut alignment := requested
 if alignment != 0 {
  mut reduced := alignment
  for reduced > 1 && reduced % 2 == 0 { reduced /= 2 }
  if reduced != 1 { return false, 0, 0 }
 }
 if alignment < alloc.gpu_page_size { alignment = alloc.gpu_page_size }
 count := size / alignment + if size % alignment == 0 { u64(0) } else { u64(1) }
 if count > ~u64(0) / alignment { return false, 0, 0 }
 rounded := count * alignment
 remainder := top % alignment
 padding := if remainder == 0 { u64(0) } else { alignment - remainder }
 free_bytes := end - top
 if padding > free_bytes || rounded > free_bytes - padding { return false, 0, 0 }
 return true, top + padding, rounded
}

fn check_heap_alignment_probe() {
 mut heap := alloc.new_heap('bad-alignment', alloc.g13_shared_start, alloc.g13_shared_end)
 if _ := heap.alloc(1, 3) { panic('invalid GPU heap alignment must not allocate') }
 assert heap.top == heap.start && heap.allocations.len == 0
}

fn check_heap_overflow_probe() {
 mut heap := alloc.new_heap('overflow', alloc.g13_shared_start, alloc.g13_shared_end)
 if _ := heap.alloc(u64(1) << 40, alloc.gpu_page_size) {
  panic('overflowing GPU heap interval must not allocate')
 }
 assert heap.top == heap.start && heap.allocations.len == 0
}

fn check_heap_bounds_matrix() {
 mut cases := u64(0)
 for base in [u64(0), 0x4000, alloc.gpu_private_start, alloc.g13_private_start,
  alloc.g13_shared_start, ~u64(0) - 0x10000, ~u64(0) - 0x3fff, ~u64(0)]! {
  for span in [u64(0), 1, 0x3fff, 0x4000, 0x4001, 0x10000, 0x400000]! {
   if span > ~u64(0) - base { continue }
   for size in [u64(0), 1, 0x3fff, 0x4000, 0x4001, 0x10000, u64(1) << 38,
    u64(1) << 40, ~u64(0) - 0xffff, ~u64(0) - 0x3fff, ~u64(0)]! {
    for alignment in [u64(0), 1, 2, 3, 0x1000, 0x4000, 0x6000, 0x8000,
     0x10000, u64(1) << 38, u64(1) << 63, ~u64(0)]! {
     mut heap := alloc.new_heap('bounds', base, base + span)
     valid, address, rounded := heap_bounds_model(base, base + span, size, alignment)
     if actual := heap.alloc(size, alignment) {
      assert valid && actual == address && heap.top == address + rounded,
       'GPU heap allocation must match bounded division model'
      assert heap.allocations.len == 1 && heap.allocations[0].size == rounded
      assert heap.used() == rounded
      heap.release(actual); heap.gc()
      assert heap.allocations.len == 0 && heap.used() == 0
     } else {
      assert !valid && heap.top == base && heap.allocations.len == 0,
       'GPU heap rejection must match bounded division model without allocating'
     }
     cases++
    }
   }
  }
 }
 C.printf(c'AGX heap bounds: %llu division-modeled address/size/alignment cases passed\n', cases)
}

fn check_invalid_heap_requests_preserve_gc_owners() {
 mut heap := alloc.new_heap('invalid-owner', alloc.g13_shared_start, alloc.g13_shared_start + 2 * alloc.gpu_page_size)
 first := heap.alloc(1, 0) or { panic('first') }
 second := heap.alloc(1, 0) or { panic('second') }
 heap.release(second)
 top := heap.top
 for size, alignment in {u64(1): u64(3), u64(0): alloc.gpu_page_size, ~u64(0): alloc.gpu_page_size} {
  if _ := heap.alloc(size, alignment) { panic('invalid heap request accepted') }
  assert heap.top == top && heap.allocations.len == 2,
   'invalid requests cannot collect or replace retained metadata'
  records_are_live(heap.allocations)
 }
 heap.release(first); heap.gc()
 assert heap.allocations.len == 0 && heap.top == heap.start
 println('AGX heap bounds: invalid requests preserve deferred GC ownership')
}

fn check_heap_bounds() {
 check_heap_alignment_probe()
 check_heap_overflow_probe()
 check_heap_bounds_matrix()
 check_invalid_heap_requests_preserve_gc_owners()
}
