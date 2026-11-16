// SPDX-License-Identifier: GPL-2.0-or-later
module file

import drm.asahi
import drm.gem
import drm.ioctl
import drm.syncobj
import gpu.agx.gpu
import gpu.agx.submission

fn timestamp_reference_count(file &GpuFile, id u32) u64 {
 for entry in file.timestamp_objects { if entry.id == id { return entry.references } }
 return 0
}

// Exercise the shared copied-command boundary; packet decoding is covered by
// the packet-to-pending fixtures. Distinct stage mappings expose early release.
fn submit_render_timestamps(mut file GpuFile, count int, shared_ids bool, out &syncobj.SyncObj) int {
 mut commands := []submission.Command{len: count}
 defer { unsafe { commands.free() } }
 for index in 0 .. count {
  vertex := u32(9 + index * 2)
  fragment := if shared_ids { vertex } else { vertex + 1 }
  mut timestamps := [3]asahi.Timestamps{}
  timestamps[0] = asahi.Timestamps{start: asahi.Timestamp{handle: vertex, offset: 1},
   end: asahi.Timestamp{handle: vertex, offset: 9}}
  timestamps[1] = asahi.Timestamps{start: asahi.Timestamp{handle: fragment, offset: 17},
   end: asahi.Timestamp{handle: fragment, offset: 25}}
  commands[index] = submission.Command{descriptor: ioctl.DrmAsahiCommand{cmd_type: ioctl.asahi_cmd_render,
   barriers: [ioctl.asahi_barrier_none, ioctl.asahi_barrier_none]!}, timestamps: timestamps}
 }
 captured := file.capture_submission_queue(1) or { return -2 }
 record := ioctl.DrmAsahiSync{handle: out.handle}
 code, outputs := submission.stage_sync_array(file.owner_key, u64(&record), 1, false)
 assert code == 0
 inputs := submission.SyncArray{}
 result := file.submit_g13_staged(captured, commands, &inputs, &outputs, 0)
 if result != 0 { release_submission_queue(captured) }
 return result
}

fn check_render_stage_timestamps() {
 mut stages := 0
 for count in [1, 8, 64] {
  for shared_ids in [false, true] {
   for first in 0 .. 2 {
    for shutdown in [false, true] {
     gpu.reset(); mut file := new_file()
     mut manager := gpu.get_global_manager() or { panic('manager') }
     mut objects := []gem.GemObject{len: count * 2}
     defer { unsafe { objects.free() } }
     for index in 0 .. count {
      for pipe in 0 .. (if shared_ids { 1 } else { 2 }) {
       offset := index * 2 + pipe
       file.timestamp_objects << TimestampObject{id: u32(9 + offset), va: 0x123456780000 + u64(offset) * 4096,
        size: 4096, obj: unsafe { &objects[offset] }}
      }
     }
     out := output()
     assert submit_render_timestamps(mut file, count, shared_ids, out) == 0
     service_file_work()
     for index in 0 .. count {
      assert timestamp_reference_count(file, u32(9 + index * 2)) == if shared_ids { 4 } else { 2 }
     }
     file.lock.acquire()
     for index in 0 .. file.timestamp_objects.len { file.timestamp_objects[index].detached = true }
     file.lock.release()
     // Client fences and early aggregate done cannot forge private stage bits.
     syncobj.signal(fence(out))
     for index in 0 .. count { pending_head.commands[index].done = true }
     service_file_work()
     assert manager.timestamp_unmaps == 0, 'forged completion must retain stage destinations'
     for step in 0 .. count {
      index := count - 1 - step
      manager.finish_render_stage(u32(index), u32(first))
      manager.finish_render_stage(u32(index), u32(first))
      assert objects[index * 2].references == 1, 'stage callback only publishes retirement'
      service_file_work()
      vertex := u32(9 + index * 2)
      selected := if shared_ids { vertex } else { vertex + u32(first) }
      peer := if shared_ids { vertex } else { vertex + u32(1 - first) }
      assert timestamp_reference_count(file, selected) == if shared_ids { 2 } else { 0 },
       'completed stage releases exactly its selected pair'
      assert timestamp_reference_count(file, peer) == 2, 'active peer retains both timestamp destinations'
      assert manager.timestamp_unmaps == if shared_ids { 0 } else { step + 1 }
      assert manager.g13_render_jobs.len == count && pending_count == 1
       && pending_head.callbacks_remaining == u32(count) && file.inflight_by_vm[1] == u64(count + 1),
       'shared render metadata and aggregate owners remain retained'
      service_file_work()
      assert manager.timestamp_unmaps == if shared_ids { 0 } else { step + 1 }, 'stage mapping release is one-shot'
      stages++
     }
     if shutdown { manager.stop(); service_file_work() }
     else {
      for index in 0 .. count {
       manager.finish_render_stage(u32(index), u32(1 - first))
       service_file_work()
       assert timestamp_reference_count(file, u32(9 + index * 2)) == 0
        && timestamp_reference_count(file, u32(10 + index * 2)) == 0, 'second stage releases its own pair'
       assert pending_head.callbacks_remaining == u32(count), 'stage release preserves aggregate callback backing'
      }
      assert file.timestamp_objects.len == 0 && manager.g13_render_jobs.len == count
      for index in 0 .. count { manager.finish_render_at(u32(index), 0) }
      service_file_work()
     }
     assert file.timestamp_objects.len == 0
     assert manager.timestamp_unmaps == count * if shared_ids { 1 } else { 2 }
     for index, object in objects {
      assert object.references == if shared_ids && index % 2 == 1 { 1 } else { 0 }
     }
     assert_drained(file)
    }
   }
  }
 }
 assert stages == 584
 println('AGX render stage timestamps: 584 independent stage releases, both orders, distinct/shared IDs, repeated polls, forged completion and shutdown passed')
}
