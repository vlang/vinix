module main

import gpu.agx.alloc

fn check_newest_hole_probe() {
 mut heap := alloc.new_heap('hole-history', alloc.g13_shared_start, alloc.g13_shared_start + 6 * alloc.gpu_page_size)
 mut addresses := [6]u64{}
 for index in 0 .. 6 { addresses[index] = heap.alloc(1, 0) or { panic('history reservation') } }
 heap.release(addresses[0]); heap.gc()
 heap.release(addresses[4]); heap.gc()
 chosen := heap.alloc(1, 0) or { panic('history reuse') }
 assert chosen == addresses[4], 'equal-size holes must prefer the newest eligible insertion'
 heap.release(chosen); heap.gc()
 for index in [1, 2, 3, 5]! { heap.release(addresses[index]) }
 heap.gc()
 assert heap.allocations.len == 0 && heap.top == heap.start
 unsafe { heap.allocations.free() }
 println('AGX hole history: newest equal-size hole wins above an older low address')
}

fn check_split_hole_history() {
 mut heap := alloc.new_heap('split-history', alloc.g13_shared_start, alloc.g13_shared_start + 12 * alloc.gpu_page_size)
 first := heap.alloc(1, 0) or { panic('prefix') }
 gap := heap.alloc(10 * alloc.gpu_page_size, 0) or { panic('gap') }
 pin := heap.alloc(1, 0) or { panic('pin') }
 heap.release(gap); heap.gc()
 middle := heap.alloc(1, 4 * alloc.gpu_page_size) or { panic('split') }
 assert middle == heap.start + 4 * alloc.gpu_page_size
 trailing := heap.alloc(1, 0) or { panic('trailing remainder') }
 assert trailing == heap.start + 8 * alloc.gpu_page_size,
  'split must insert the trailing remainder after the equal leading remainder'
 for address in [first, middle, trailing, pin]! { heap.release(address) }
 heap.gc()
 assert heap.allocations.len == 0 && heap.top == heap.start
 unsafe { heap.allocations.free() }
 println('AGX hole history: split inserts leading before trailing equal-size remainder')
}

fn check_history_alignment_fallback() {
 mut heap := alloc.new_heap('history-alignment', alloc.g13_shared_start, alloc.g13_shared_start + 6 * alloc.gpu_page_size)
 low := heap.alloc(2 * alloc.gpu_page_size, 0) or { panic('low') }
 pin := heap.alloc(1, 0) or { panic('middle pin') }
 high := heap.alloc(2 * alloc.gpu_page_size, 0) or { panic('high') }
 last := heap.alloc(1, 0) or { panic('last pin') }
 heap.release(low); heap.gc(); heap.release(high); heap.gc()
 chosen := heap.alloc(1, 2 * alloc.gpu_page_size) or { panic('older aligned hole') }
 assert chosen == low, 'newer equal-size hole must yield to an older aligned candidate'
 for address in [chosen, pin, last]! { heap.release(address) }
 heap.gc()
 unsafe { heap.allocations.free() }
 println('AGX hole history: an ineligible newest hole falls back to the older aligned hole')
}

fn check_hole_history_model() {
 mut cases := 0
 for offset in [u64(0), 7, alloc.gpu_page_size]! {
  for seed in 0 .. 32 {
   start := alloc.g13_private_start + offset
   mut heap := alloc.new_heap('history-model', start, start + 128 * alloc.gpu_page_size)
   mut model := new_range_model(heap.start, heap.end)
   mut random := u64(seed + 1)
   for step in 0 .. 96 {
    random = (random * u64(1664525) + u64(1013904223)) & u64(0xffffffff)
    if model.records.len > 0 && (step % 3 == 0 || model.records.len > 12) {
     index := int(random % u64(model.records.len))
     address := model.records[index].va
     heap.release(address); model.release(address)
     if step % 2 == 0 { heap.gc(); model.collect() }
    } else {
     size := (1 + random % 3) * alloc.gpu_page_size
     alignment := (u64(1) << ((random >> 8) % 3)) * alloc.gpu_page_size
     reserve_checked(mut heap, mut model, size, alignment)
    }
    check_model_hole_orders(&heap, &model)
    cases++
   }
   for record in model.records { heap.release(record.va); model.release(record.va) }
   heap.gc(); model.collect()
   assert heap.top == start && heap.allocations.len == 0 && model.holes.len == 1
   unsafe { heap.allocations.free(); model.records.free(); model.holes.free() }
  }
 }
 assert cases == 9216
 println('AGX hole history: 9216 seeded split/coalesce/deferred-release steps match chronological candidate enumeration')
}

fn check_hole_history() {
 check_newest_hole_probe()
 check_split_hole_history()
 check_history_alignment_fallback()
 check_hole_history_model()
}
