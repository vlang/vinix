// SPDX-License-Identifier: GPL-2.0-or-later
module submission

// drm_sched_job_add_dependency semantics for native 64-bit fence contexts:
// skip nil, preserve each context's first position, replace only with a later
// sequence, and keep the first fence on ties. Only private INPUT copies enter
// this path; pointers borrow retained metadata, never output reservations.
pub fn copy_job_dependencies(source &SyncArray) (int, SyncArray) {
 code, copied := copy_sync_array(source)
 if code != 0 { return code, SyncArray{} }
 mut count := u32(0)
 for index := u32(0); index < source.count; index++ {
  incoming := source.item(index)
  if incoming.fence == unsafe { nil } { continue }
  mut target := count
  mut replace := true
  for existing := u32(0); existing < count; existing++ {
   previous := if copied.items != unsafe { nil } { unsafe { copied.items[existing].fence } } else { copied.fences[existing] }
   if previous.context != incoming.fence.context { continue }
   target = existing
   replace = incoming.fence.seqno > previous.seqno
   break
  }
  if !replace { continue }
  // Read the original snapshot, then write the independent copy. Taking the
  // copied header's address for a setter/item() would heap-box it in V.
  unsafe {
   if copied.items != nil { copied.items[target] = incoming }
   else {
    copied.objects[target] = incoming.object
    copied.fences[target] = incoming.fence
    copied.timeline[target] = incoming.timeline
    copied.timeline_values[target] = incoming.timeline_value
    copied.chains[target] = incoming.chain
   }
  }
  if target == count { count++ }
 }
 unsafe { copied.count = count }
 return 0, copied
}
