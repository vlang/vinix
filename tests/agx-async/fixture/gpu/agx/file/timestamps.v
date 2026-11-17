// SPDX-License-Identifier: GPL-2.0-or-later
module file

import drm.asahi
import drm.gem
import drm.ioctl
import drm.syncobj
import gpu.agx.gpu
import gpu.agx.submission
import katomic
import memory

// Enter at the shared copied-input boundary; ioctl registration is separate.
// Bytes pass through the actual modern parser and canonical adapter first.
fn submit_timestamp_packet(mut file GpuFile, count u32, bad int, input &syncobj.SyncObj,
 output &syncobj.SyncObj) int {
	return submit_timestamp_packet_on_queue(mut file, 1, count, bad, input, output)
}

fn submit_timestamp_packet_on_queue(mut file GpuFile, queue u32, count u32, bad int,
 input &syncobj.SyncObj, output &syncobj.SyncObj) int {
 mut bytes := []u8{cap: 65536}
 defer { unsafe { bytes.free() } }
 for index := u32(0); index < count; index++ {
  compute := index % 2 == 0
  handle := if file.timestamp_objects.len > 1 { file.timestamp_objects[index].id } else { u32(9) }
  ts := asahi.Timestamps{start: asahi.Timestamp{handle: handle, offset: index * 8},
   end: asahi.Timestamp{handle: if int(index) == bad { u32(999) } else { handle }, offset: index * 8 + 1}}
  c := asahi.CmdCompute{ts: ts}
  r := asahi.CmdRender{width_px: 32, height_px: 32, layers: 1, samples: 1,
   utile_width_px: 32, utile_height_px: 32, ts_vtx: ts, ts_frag: ts}
  header := asahi.CmdHeader{cmd_type: if compute { asahi.cmd_compute } else { asahi.cmd_render },
   size: if compute { u16(sizeof(c)) } else { u16(sizeof(r)) },
   vdm_barrier: asahi.barrier_none, cdm_barrier: asahi.barrier_none}
  unsafe { bytes.push_many(voidptr(&header), int(sizeof(header)))
   bytes.push_many(if compute { voidptr(&c) } else { voidptr(&r) }, int(header.size)) }
 }
 mut commands := []submission.Command{len: int(count)}
 defer { unsafe { commands.free() } }
 mut workspace := submission.PacketWorkspace{}
 code, decoded := submission.decode_packet(bytes.data, u64(bytes.len), 0, mut commands, mut workspace)
 assert code == 0 && decoded == count
 captured := file.capture_submission_queue(queue) or { return -2 }
 in_record := ioctl.DrmAsahiSync{handle: if input == unsafe { nil } { 0 } else { input.handle }}
 out_record := ioctl.DrmAsahiSync{handle: if output == unsafe { nil } { 0 } else { output.handle }}
 in_code, in_syncs := submission.stage_sync_array(file.owner_key, u64(&in_record), if input == unsafe { nil } { 0 } else { 1 }, true)
 out_code, out_syncs := submission.stage_sync_array(file.owner_key, u64(&out_record), if output == unsafe { nil } { 0 } else { 1 }, false)
 assert in_code == 0 && out_code == 0
 defer { submission.release_sync_array(out_syncs) }
 result := file.submit_g13_staged(captured, commands, &in_syncs, &out_syncs, 0)
 if result != 0 { release_submission_queue(captured) }
 return result
}

fn add_timestamp(mut file GpuFile, object &gem.GemObject) {
 file.timestamp_objects << TimestampObject{id: 9, va: 0x123456780000, size: 4096, obj: unsafe { object }}
}

fn detach_timestamp(mut file GpuFile) {
 file.lock.acquire()
 file.timestamp_objects[0].detached = true
 file.reap_detached_timestamp_objects_locked()
 file.lock.release()
}

fn check_timestamp_retirement() {
 for mode in 0 .. 6 {
  gpu.reset()
  mut file := new_file()
  mut object := gem.GemObject{}
  add_timestamp(mut file, &object)
  mut mgr := gpu.get_global_manager() or { panic('manager') }
  dependency := syncobj.new_fence(1, 0)
  input := output(); syncobj.replace_fence(input, dependency)
  out := output()
  mgr.immediate_complete = mode == 3
  assert submit_timestamp_packet(mut file, 4, -1, input, out) == 0
  assert file.timestamp_objects[0].references == 12, 'all command captures retained'
  assert mgr.g13_compute_jobs[0].timestamps == [u64(0x123456780000), 0x123456780001]!, 'resolved compute destinations'
  assert mgr.g13_render_jobs[0].vertex_timestamps == [u64(0x123456780008), 0x123456780009]!, 'resolved vertex destinations'
  assert mgr.g13_render_jobs[0].fragment_timestamps == mgr.g13_render_jobs[0].vertex_timestamps, 'resolved fragment destinations'
  detach_timestamp(mut file)
  assert object.references == 1 && mgr.timestamp_unmaps == 0
  syncobj.signal(fence(out)) // user fence cannot release mappings
  service_file_work()
  assert file.timestamp_objects[0].references == 12 && mgr.published.len == 0
  if mode == 1 { mgr.stop() }
  else {
   syncobj.signal(dependency)
   mgr.ring_full = mode == 2
   service_file_work()
   if mode == 2 { assert mgr.published.len == 0; mgr.ring_full = false; service_file_work() }
   if mode == 4 { mgr.stop() }
   else if mode != 3 {
    mgr.finish_compute(if mode == 5 { u32(3) } else { u32(0) })
    service_file_work()
    assert object.references == 1 && mgr.timestamp_unmaps == 0, 'callbacks retain captures until batch retirement'
    mgr.finish_compute(0); mgr.finish_render(0); mgr.finish_render(0)
   }
  }
  for _ in 0 .. 3 { service_file_work() }
  assert file.timestamp_objects.len == 0 && object.references == 0 && mgr.timestamp_unmaps == 1, 'retirement releases detached mapping once'
  assert_drained(file)
 }
}

fn check_timestamp_failures() {
 // Every lookup position rolls back earlier command and engine captures.
 for step in 0 .. 64 {
  bad := 63 - step
  gpu.reset()
  mut file := new_file(); mut object := gem.GemObject{}
  add_timestamp(mut file, &object)
  assert submit_timestamp_packet(mut file, 64, bad, unsafe { nil }, unsafe { nil }) == -2
  assert file.timestamp_objects[0].references == 0, 'capture prefix rollback'
  assert_drained(file)
  detach_timestamp(mut file)
  assert object.references == 0
 }
 // Fallible owner/node allocation and every prepare/callback/barrier prefix.
 for mode in 0 .. 6 {
  for position in 0 .. (if mode == 0 { 2 } else { 8 }) {
   gpu.reset()
   mut file := new_file(); mut object := gem.GemObject{}
   add_timestamp(mut file, &object)
   mut mgr := gpu.get_global_manager() or { panic('manager') }
   if mode == 0 { memory.fail_at(position) }
   if mode == 1 { mgr.fail_prepare_at = position }
   if mode == 2 { mgr.fail_callback_at = position }
   if mode == 3 { mgr.fail_barrier_at = position }
   if mode == 4 { mgr.stop_callback_at = position }
   if mode == 5 { mgr.stop_barrier_at = position }
   code := submit_timestamp_packet(mut file, 8, -1, unsafe { nil }, unsafe { nil })
   memory.fail_at(-1)
   assert code < 0, 'injected failure rejected'
   assert file.timestamp_objects[0].references == 0, 'failed preparation releases captures'
   assert_drained(file)
   detach_timestamp(mut file)
  }
 }
}

fn check_pending_timestamps() {
 check_timestamp_retirement()
	check_render_stage_timestamps()
 check_command_timestamp_retirement()
 check_blocked_timestamp_retirement()
 check_timestamp_failures()
 // Repeated immediate completion with maximum-size ownership arrays.
 for _ in 0 .. 64 {
  gpu.reset(); mut file := new_file(); mut object := gem.GemObject{}
  add_timestamp(mut file, &object)
  mut mgr := gpu.get_global_manager() or { panic('manager') }
  mgr.immediate_complete = true
  assert submit_timestamp_packet(mut file, 64, -1, unsafe { nil }, unsafe { nil }) == 0
  assert file.timestamp_objects[0].references == 192
  detach_timestamp(mut file); service_file_work()
  assert file.timestamp_objects.len == 0 && object.references == 0
  assert_drained(file)
 }
 println('AGX timestamps: packet-to-pending owners, waits, forged fences, faults, shutdown, rollback and 64 maximum-batch retirement cycles passed')
}

// Distinct mappings expose per-command release while neighboring commands
// keep the aggregate node, fence and VM pin alive.
fn check_command_timestamp_retirement() {
 for count in [2, 8, 64] {
  for reverse in [false, true] {
   gpu.reset()
   mut file := new_file()
   mut mgr := gpu.get_global_manager() or { panic('manager') }
   mut objects := []gem.GemObject{len: count}
   defer { unsafe { objects.free() } }
   for index in 0 .. count {
    file.timestamp_objects << TimestampObject{id: u32(9 + index), va: u64(0x123456780000) + u64(index) * 4096,
     size: 4096, obj: unsafe { &objects[index] }}
   }
   out := output()
   assert submit_timestamp_packet(mut file, u32(count), -1, unsafe { nil }, out) == 0
   service_file_work()
   file.lock.acquire()
   for index in 0 .. count { file.timestamp_objects[index].detached = true }
   file.lock.release()
   // done is written before completion backing is discarded. Even with a
   // forged aggregate fence, it cannot authorize a timestamp mapping release.
   for index in 0 .. count { pending_head.commands[index].done = true }
   syncobj.signal(fence(out))
   service_file_work()
   assert mgr.timestamp_unmaps == 0 && file.timestamp_objects.len == count, 'early done and forged fences retain captures'
   for step in 0 .. count {
    index := if reverse { count - 1 - step } else { step }
    if index % 2 == 0 { mgr.finish_compute_at(u32(index), 0) }
    else { mgr.finish_render_at(u32(index), 0) }
    assert objects[index].references == 1, 'manager callback only publishes retirement'
    service_file_work()
    assert objects[index].references == 0 && mgr.timestamp_unmaps == step + 1, 'completed command releases its own mapping'
    assert file.timestamp_objects.len == count - step - 1
    for other in 0 .. count {
     completed := if reverse { other >= index } else { other <= index }
     assert objects[other].references == if completed { 0 } else { 1 }, 'neighboring mappings remain owned'
    }
    if step + 1 < count {
     assert pending_count == 1 && file.inflight_by_vm[1] == u64(count - step), 'aggregate owner survives partial completion'
     service_file_work()
     assert mgr.timestamp_unmaps == step + 1, 'completed command release is one-shot'
    }
   }
   assert_drained(file)
  }
 }
 println('AGX command timestamps: 148 individual retirements, forward/reverse completion, early-done/forged-fence guards and one-shot mapping release passed')
}

__global timestamp_stop_target &G13PendingSubmission = unsafe { nil }
__global timestamp_stop_calls = 0

fn stop_at_blocked_timestamp(value voidptr) {
 if value != voidptr(&timestamp_stop_target.commands[0].callback_finished) { return }
 katomic.set_load_hook(unsafe { nil })
 timestamp_stop_calls++
 mut manager := gpu.get_global_manager() or { panic('manager') }
 manager.stop()
}

fn check_blocked_timestamp_retirement() {
 gpu.reset()
 mut file := new_file()
 mut manager := gpu.get_global_manager() or { panic('manager') }
 input := output()
 syncobj.replace_fence(input, syncobj.new_fence(0, 1))
 assert submit(mut file, 1, false, input, unsafe { nil }, false) == 0
 mut objects := [2]gem.GemObject{}
 for index in 0 .. 2 {
  file.timestamp_objects << TimestampObject{id: u32(9 + index), va: u64(0x123456780000) + u64(index) * 4096,
   size: 4096, obj: unsafe { &objects[index] }}
 }
 assert submit_timestamp_packet_on_queue(mut file, 1, 2, -1, unsafe { nil }, unsafe { nil }) == 0
 file.lock.acquire()
 for index in 0 .. 2 { file.timestamp_objects[index].detached = true }
 file.lock.release()
 timestamp_stop_target = pending_tail
 timestamp_stop_calls = 0
 katomic.set_load_hook(stop_at_blocked_timestamp)
 // The older same-queue batch is waiting on an input, so the target's
 // submission poll is skipped. The per-command reaper still runs and
 // observes concurrent stop callbacks.
 service_file_work()
 katomic.set_load_hook(unsafe { nil })
 assert timestamp_stop_calls == 1, 'blocked node still polls timestamp retirements'
 assert manager.published.len == 0 && pending_count == 2
 assert file.timestamp_objects.len == 0 && objects[0].references == 0 && objects[1].references == 0
 assert manager.timestamp_unmaps == 2, 'blocked retired captures release before the next batch poll'
 service_file_work()
 assert_drained(file)
 timestamp_stop_target = unsafe { nil }
 println('AGX blocked timestamps: a FIFO-blocked batch reaps stop-completed captures while its node remains retained')
}
