// SPDX-License-Identifier: GPL-2.0-or-later
module submission

import drm.syncobj

// Keep the newest fence in each ordered sequence and the first record on a
// tie. Independently completing queue fences deduplicate by identity only.
// The private input copy borrows the captured fence metadata.
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
   if !syncobj.same_fence_sequence(previous, incoming.fence) { continue }
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
