// SPDX-License-Identifier: GPL-2.0-or-later
module file

import drm.asahi
import drm.ioctl
import drm.syncobj
import gpu.agx.gpu
import gpu.agx.submission
import memory

fn C.__builtin_alloca(uint) voidptr

fn check_job_endpoint(mut file GpuFile, a &syncobj.SyncObj, b &syncobj.SyncObj,
 modern bool, count u32, same bool, reverse bool, tie bool) {
 gpu.reset()
 mut manager := gpu.get_global_manager() or { panic('manager') }
 mut leaves := unsafe { &syncobj.DmaFence(C.__builtin_alloca(2 * sizeof(syncobj.DmaFence))) }
 unsafe {
  leaves[0] = syncobj.DmaFence{context: 200, seqno: 7}
  leaves[1] = syncobj.DmaFence{context: if same { u64(200) } else { u64(201) }, seqno: if tie { u64(7) } else { ~u64(0) }}
 }
 syncobj.replace_fence(a, unsafe { &leaves[0] }); syncobj.replace_fence(b, unsafe { &leaves[1] })
 if modern {
  mut records := []asahi.Sync{len: int(count)}
  for i in 0 .. records.len { records[i] = asahi.Sync{handle: if (i % 2 == 0) != reverse { a.handle } else { b.handle }} }
  compute := asahi.CmdCompute{}
  mut bytes := []u8{}; bytes.flags |= .noslices
  append_packet(mut bytes, asahi.cmd_compute, unsafe { &compute }, u16(sizeof(compute)), asahi.barrier_none, asahi.barrier_none)
  request := asahi.Submit{queue_id: 1, syncs: u64(records.data), in_sync_count: count, cmdbuf: u64(bytes.data), cmdbuf_size: u32(bytes.len)}
  assert file.ioctl_modern_submit(unsafe { &request }) == 0
  unsafe { C.memset(records.data, 0xff, records.len * int(sizeof(asahi.Sync))); records.free(); bytes.free() }
 } else {
  inputs := [ioctl.DrmAsahiSync{handle: if reverse { b.handle } else { a.handle }}, ioctl.DrmAsahiSync{handle: if reverse { a.handle } else { b.handle }}]!
  compute := ioctl.DrmAsahiCmdCompute{encoder_ptr: 0x12340000}
  command := ioctl.DrmAsahiCommand{cmd_type: ioctl.asahi_cmd_compute, cmd_buffer: unsafe { u64(&compute) }, cmd_buffer_size: sizeof(compute), barriers: [ioctl.asahi_barrier_none, ioctl.asahi_barrier_none]!}
  request := ioctl.DrmAsahiSubmit{queue_id: 1, commands: unsafe { u64(&command) }, command_count: 1, in_syncs: unsafe { u64(&inputs[0]) }, in_sync_count: 2}
  assert file.ioctl_submit(unsafe { &request }) == 0
 }
 assert pending_head != unsafe { nil } && pending_head.dependencies.count == if same { u32(1) } else { u32(2) }, 'pending work must own reduced dependencies'
 final := pending_head.final_fence
 service_file_work()
 assert manager.published_order.len == 0
 selected := if !same { 0 } else if tie { if reverse { 1 } else { 0 } } else { 1 }
 syncobj.signal_error(unsafe { &leaves[selected] }, -5)
 service_file_work()
 assert manager.published_order.len == if same { 1 } else { 0 }, 'latest context fence alone must release its wait'
 if !same { syncobj.signal(unsafe { &leaves[1 - selected] }); service_file_work() }
 assert manager.published_order.len == 1
 manager.finish_compute(0); service_file_work()
 assert_drained(file)
 assert syncobj.is_signaled(final) && syncobj.get_error(final) == 0
 syncobj.signal(unsafe { &leaves[1 - selected] })
 syncobj.replace_fence(a, unsafe { nil }); syncobj.replace_fence(b, unsafe { nil })
}

pub fn run_job_dependency_checks() {
 mut file := new_file()
 a, b := output(), output()
 mut cases := 0
 for modern in [false, true]! { for count in [u32(2), 65, 129]! {
  if !modern && count > 64 { continue }
  for same in [false, true]! { for reverse in [false, true]! { for tie in [false, true]! {
   check_job_endpoint(mut file, a, b, modern, count, same, reverse, tie); cases++
  } } }
 } }
 assert cases == 32
 submission.check_dependency_matrix(false)
 submission.check_dynamic_dependencies()
 println('Job dependencies: 4096 copy cases, dynamic/OOM/ownership boundaries and 32 legacy/modern pending lifecycle cases pass; latest context, stable ties, foreign waits and captured snapshots preserved.')
}

pub fn measure_job_dependencies() {
 mut leaf := syncobj.DmaFence{context: 3, seqno: 1}
 for count in [u32(4), 65, 1025]! {
  mut items := []submission.SyncItem{len: int(count), init: submission.SyncItem{fence: unsafe { &leaf }}}
  mut source := submission.SyncArray{count: count}
  if count > 64 { unsafe { source.items = &submission.SyncItem(items.data) } }
  else { for i in 0 .. int(count) { unsafe { source.fences[i] = &leaf } } }
  for batch in 0 .. 4 {
   before_blocks, before_bytes := live_record_heap()
   for _ in 0 .. 1000 {
    code, copied := submission.copy_job_dependencies(unsafe { &source })
    assert code == 0 && copied.count == 1
    submission.release_sync_array(copied)
    assert memory.outstanding() == 0
   }
   after_blocks, after_bytes := live_record_heap()
   if batch != 0 {
    assert before_blocks == after_blocks && before_bytes == after_bytes
    println('job-dependencies count=${count} batch=${batch} operations=1000 retained_blocks=0 retained_bytes=0')
   }
  }
  unsafe { items.free() }
 }
}
