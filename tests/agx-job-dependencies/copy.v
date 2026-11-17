// SPDX-License-Identifier: GPL-2.0-or-later
module submission

import drm.syncobj
import memory

fn C.__builtin_alloca(uint) voidptr

fn dependency_case(contexts [4]u64, sequences [4]u64, nils u32, done u32, trace bool) {
 mut leaves := unsafe { &syncobj.DmaFence(C.__builtin_alloca(4 * sizeof(syncobj.DmaFence))) }
 mut source := SyncArray{count: 4}
 for index in 0 .. 4 {
  unsafe {
   leaves[index] = syncobj.DmaFence{context: contexts[index], seqno: sequences[index], signaled: done & (u32(1) << index) != 0, error: -5}
   source.fences[index] = if nils & (u32(1) << index) != 0 { nil } else { &leaves[index] }
   source.timeline[index] = index % 2 != 0
   source.timeline_values[index] = u64(index + 1)
  }
 }
 code, copied := copy_job_dependencies(unsafe { &source })
 assert code == 0 && memory.outstanding() == 0
 assert source.count == 4
 mut ready := true
 mut previous_first := -1
 for out := u32(0); out < copied.count; out++ {
  item := (unsafe { &copied }).item(out)
  assert item.fence != unsafe { nil }, 'nil dependencies must be dropped'
  selected := int(item.timeline_value) - 1
  assert selected >= 0 && selected < 4 && voidptr(item.fence) == voidptr(source.fences[selected])
  assert item.timeline == source.timeline[selected]
  mut first := 4
  for index in 0 .. 4 {
   leaf := source.fences[index]
   if leaf == unsafe { nil } || leaf.context != item.fence.context { continue }
   if index < first { first = index }
   assert item.fence.seqno >= leaf.seqno, 'context keeps greatest unsigned sequence'
   if item.fence.seqno == leaf.seqno { assert selected <= index, 'equal sequences keep the first record' }
  }
  assert first > previous_first, 'first context positions stay ordered'
  previous_first = first
  ready = ready && syncobj.queue_dependency_ready(item.fence, 0)
 }
 for index in 0 .. 4 {
  leaf := source.fences[index]
  assert source.timeline_values[index] == u64(index + 1)
  if nils & (u32(1) << index) != 0 { assert leaf == unsafe { nil }; continue }
  assert voidptr(leaf) == unsafe { voidptr(&leaves[index]) }, 'private compaction must not change source'
  mut represented := false
  for out := u32(0); out < copied.count; out++ { if (unsafe { &copied }).item(out).fence.context == leaf.context { represented = true } }
  assert represented, 'every nonnil context must be represented'
 }
 if trace {
  C.printf(c'%u %u %u', nils, done, copied.count)
  for out := u32(0); out < copied.count; out++ { C.printf(c' %llu', (unsafe { &copied }).item(out).timeline_value) }
  C.printf(c' ready=%u\n', u32(ready))
 }
 release_sync_array(copied)
}

pub fn check_dependency_matrix(trace bool) {
 mut cases := 0
 for contexts in [[u64(0), 0, 0, 0]!, [u64(1), 2, 1, 2]!, [~u64(0), u64(1), ~u64(0), u64(0)]!, [u64(1), 2, 3, 4]!]! {
  for sequences in [[u64(0), 1, ~u64(0), u64(2)]!, [~u64(0), ~u64(0), u64(1), 1]!, [u64(1), 1, 1, 1]!, [u64(0x7fff_ffff_ffff_ffff), 0x8000_0000_0000_0000, 0, ~u64(0)]!]! {
   for nils := u32(0); nils < 16; nils++ { for done := u32(0); done < 16; done++ {
    dependency_case(contexts, sequences, nils, done, trace); cases++
   } }
  }
 }
 assert cases == 4096
}

pub fn trace_job_dependencies() { check_dependency_matrix(true) }

pub fn check_dynamic_dependencies() {
 mut leaves := unsafe { &syncobj.DmaFence(C.__builtin_alloca(3 * sizeof(syncobj.DmaFence))) }
 unsafe { leaves[0] = syncobj.DmaFence{context: 1, seqno: 1}; leaves[1] = syncobj.DmaFence{context: 2, seqno: 1}; leaves[2] = syncobj.DmaFence{context: 1, seqno: ~u64(0)} }
 for count in [u32(0), 1, 2, 64, 65, 129, 1025]! {
  mut source := SyncArray{count: count}
  if count > 64 {
   storage := memory.malloc_packed_fallible(u64(count) * sizeof(SyncItem))
   unsafe { source.items = &SyncItem(storage) }
  }
  for index := u32(0); index < count; index++ {
   item := SyncItem{fence: unsafe { &leaves[index % 3] }, timeline_value: index}
   if count > 64 { unsafe { source.items[index] = item } }
   else { unsafe { source.fences[index] = item.fence; source.timeline_values[index] = index } }
  }
  before := memory.outstanding()
  if count > 64 {
   memory.fail_at(0)
   code, failed := copy_job_dependencies(unsafe { &source })
   assert code == -12 && failed.count == 0 && memory.outstanding() == before, 'failed dependency copy must preserve caller ownership'
   memory.fail_at(-1)
  }
  code, copied := copy_job_dependencies(unsafe { &source })
  assert code == 0 && copied.count == if count < 2 { count } else { u32(2) }
  if count > 64 { assert voidptr(copied.items) != voidptr(source.items), 'private dependency copy must own its storage' }
  for index := u32(0); index < count; index++ { assert (unsafe { &source }).item(index).timeline_value == index }
  if count > 64 {
   for index := u32(0); index < count; index++ { unsafe { source.items[index] = SyncItem{} } }
   empty_code, empty_copy := copy_job_dependencies(unsafe { &source })
   assert empty_code == 0 && empty_copy.count == 0 && empty_copy.items != unsafe { nil }
   assert voidptr(empty_copy.items) != voidptr(source.items)
   release_sync_array(empty_copy)
   assert memory.outstanding() == before + 1, 'zero-count result must still release its original allocation'
  }
  release_sync_array(source)
  if copied.count > 0 { assert voidptr((unsafe { &copied }).item(0).fence) == unsafe { voidptr(&leaves[if count >= 3 { 2 } else { 0 }]) } }
  release_sync_array(copied)
  assert memory.outstanding() == 0
 }
}
