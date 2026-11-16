// SPDX-License-Identifier: GPL-2.0-or-later
module gpu

import gpu.agx.event
import gpu.agx.fw
import katomic

struct ComputeRetirementCompletion {
 marker u64 = 0xc0ffee
 expected fw.G13JobTimestamps
}

__global compute_retirement_frees = 0
__global compute_retirement_ends = 0
__global compute_retirement_callbacks = 0
__global compute_retirement_success = false
__global compute_retirement_refuse = false

fn reset_compute_retirement() {
 compute_retirement_frees = 0; compute_retirement_ends = 0; compute_retirement_callbacks = 0
 compute_retirement_success = false; compute_retirement_refuse = false
}

fn compute_retirement_callback(job &G13ComputeJobResources, success bool, data voidptr) {
 assert data != unsafe { nil }, 'compute callback backing must remain one-shot'
 state := unsafe { &ComputeRetirementCompletion(data) }
 assert state.marker == 0xc0ffee
 if success { assert job.completion_ready && job.timestamp_values() == state.expected }
 compute_retirement_callbacks++; compute_retirement_success = success
 unsafe { free(state) }
}

fn (mut manager GpuManager) compute_retirement_end() bool { compute_retirement_ends++; return true }

fn (mut manager GpuManager) compute_retirement_free(mut job G13ComputeJobResources, invalidate bool) bool {
 assert invalidate
 if job.submitted {
  assert job.retirement_published && job.queue.subqueues[2].events.can_submit(1),
   'completed compute work returns event credit before disposal'
 }
 compute_retirement_frees++
 if compute_retirement_refuse || manager.state != .running { return false }
 job.released = true
 return true
}

fn compute_retirement_job(queue &G13QueueResources, sequence u64, stamp u32,
 timestamps &fw.G13JobTimestamps) &G13ComputeJobResources {
 return &G13ComputeJobResources{queue: unsafe { queue }, submitted: true, pending_counted: true,
  event_slot: 112, stamp_value: stamp, retirement_sequence: sequence,
  ring_slot: u32((sequence - 1) % fw.g13_workqueue_entries),
  timestamps: SharedBuffer{phys: u64(timestamps)}, completion: compute_retirement_callback,
  completion_data: &ComputeRetirementCompletion{expected: *timestamps}}
}

fn check_compute_retirement_matrix() {
 mut cases := 0
 for baseline in [u32(0), 0xffffff00, 0xffff8000, 0x7fffff00, 0x80000000] {
  for sequence in [u64(126), 1280, 1281, 0x100000001] {
   for refuse in [false, true] {
    reset_compute_retirement(); compute_retirement_refuse = refuse
    mut state := fw.G13WorkQueueRingState{cpu_wptr: u32((sequence + 1) % 1280),
     gpu_doneptr: u32(sequence % 1280), cpu_freeptr: u32((sequence + 1278) % 1280)}
    original := state
    mut queue := G13QueueResources{}
    queue.subqueues[0].events = event.credit_queue(110, baseline, 126)
    queue.subqueues[1].events = event.credit_queue(111, baseline, 126)
    queue.subqueues[2] = G13Subqueue{state: SharedBuffer{phys: u64(&state)}, command_sequence: sequence + 1,
     events: event.credit_queue(112, baseline, 126)}
    mut timestamps := fw.G13JobTimestamps{start: u64(sequence) + 100, end: u64(sequence) + 200}
    expected_timestamps := timestamps
    mut job := compute_retirement_job(&queue, sequence, baseline + 126 * u32(0x100), &timestamps)
    mut manager := GpuManager{g13_compute_jobs: [job]}
    event.set_completed(112, false)
    for _ in 0 .. 3 { manager.checked_reap_g13_compute_jobs() }
    assert manager.g13_compute_jobs.len == 1 && compute_retirement_frees == 0
     && compute_retirement_ends == 0 && compute_retirement_callbacks == 0,
     'running compute work must retain backing and credit'
    assert state == original && !job.completion_ready && job.pending_counted
    assert !queue.subqueues[2].events.can_submit(1)
    event.set_completed(112, true)
    manager.checked_reap_g13_compute_jobs()
    assert compute_retirement_frees == 1, 'completed compute must reach backing cleanup'
    assert queue.subqueues[2].events.can_submit(126), 'completed compute returns its full event window'
    assert !queue.subqueues[0].events.can_submit(1) && !queue.subqueues[1].events.can_submit(1)
    assert state.cpu_freeptr == u32((sequence - 1) % 1280)
     && state.cpu_wptr == original.cpu_wptr && state.gpu_doneptr == original.gpu_doneptr
    assert compute_retirement_ends == 1 && compute_retirement_callbacks == 1
    assert compute_retirement_success == !refuse
    if refuse {
     assert manager.g13_compute_jobs.len == 1 && job.quarantined && !job.released
     assert job.retirement_published && job.completion_ready && !job.pending_counted
     assert job.completion_result == expected_timestamps && job.timestamps.phys == u64(&timestamps)
     assert job.completion == unsafe { nil } && job.completion_data == unsafe { nil },
      'compute completion consumes its callback exactly once'
     for index in 0 .. 126 {
      ticket := queue.subqueues[2].events.ticket(112, baseline + u32(index + 1) * u32(0x100)) or { panic('compute retained ticket') }
      assert ticket.serial == u64(index) && ticket.sequence == u64(index)
     }
     event.set_completed(112, false)
     timestamps.start = 999; timestamps.end = 1000
     manager.checked_reap_g13_compute_jobs()
     assert job.completion_result == expected_timestamps && compute_retirement_callbacks == 1
     compute_retirement_refuse = false
     manager.checked_reap_g13_compute_jobs()
    }
    assert manager.g13_compute_jobs.len == 0 && compute_retirement_callbacks == 1 && compute_retirement_ends == 1
    manager.checked_reap_g13_compute_jobs()
    assert compute_retirement_callbacks == 1
    cases++
   }
  }
 }
 assert cases == 40
 println('G13 compute retirement: 40 ring/stamp-wrap and cleanup-refusal cases return credit before disposal, preserve peer queues and retain ticket/callback lifetimes')
}

fn check_compute_retirement_failure() {
 for mode in 0 .. 3 {
  reset_compute_retirement()
  mut state := fw.G13WorkQueueRingState{cpu_wptr: 7, gpu_doneptr: 7}
  mut queue := G13QueueResources{}
  queue.subqueues[2] = G13Subqueue{state: SharedBuffer{phys: u64(&state)}, command_sequence: 7,
   events: event.credit_queue(112, 0, 126)}
  mut timestamps := fw.G13JobTimestamps{start: 42, end: 84}
  mut job := compute_retirement_job(&queue, 7, 126 * u32(0x100), &timestamps)
  if mode == 0 { state.cpu_wptr = 1280 }
  if mode == 1 { queue.subqueues[2].events = event.credit_queue(113, 0, 126) }
  if mode == 2 { job.stamp_value += u32(0x100) }
  mut manager := GpuManager{g13_compute_jobs: [job]}
  event.set_completed(112, false)
  manager.checked_reap_g13_compute_jobs()
  assert manager.state == .running && compute_retirement_callbacks == 0
  event.set_completed(112, true)
  manager.checked_reap_g13_compute_jobs()
  assert manager.state == .error && job.quarantined && !job.retirement_published
   && compute_retirement_callbacks == 1 && !compute_retirement_success && compute_retirement_frees == 0,
   'invalid compute retirement must retain backing and report one failure'
  state.cpu_wptr = 7; queue.subqueues[2].events = event.credit_queue(112, 0, 126)
  job.stamp_value = 126 * u32(0x100); manager.state = .running
  manager.checked_reap_g13_compute_jobs()
  assert manager.g13_compute_jobs.len == 0 && compute_retirement_callbacks == 1
   && compute_retirement_ends == 1 && compute_retirement_frees == 1
 }
 println('G13 compute retirement: malformed ring, foreign event owner and unknown publication quarantine backing; repaired retries never reuse callback data')
}

fn check_compute_retirement_reverse() {
 reset_compute_retirement()
 mut state := fw.G13WorkQueueRingState{cpu_wptr: 2, gpu_doneptr: 2, cpu_freeptr: 1277}
 mut queue := G13QueueResources{}
 queue.subqueues[2] = G13Subqueue{state: SharedBuffer{phys: u64(&state)}, command_sequence: 1281,
  events: event.credit_queue(112, 0xffffff00, 126)}
 mut timestamps := [3]fw.G13JobTimestamps{}
 mut manager := GpuManager{}
 for index in 0 .. 3 {
  timestamps[index] = fw.G13JobTimestamps{start: u64(index + 1), end: u64(index + 2)}
  manager.g13_compute_jobs << compute_retirement_job(&queue, u64(1279 + index),
   u32(0xffffff00) + u32(124 + index) * u32(0x100), &timestamps[index])
 }
 event.set_completed(112, true)
 before := katomic.barriers()
 manager.checked_reap_g13_compute_jobs()
 assert manager.g13_compute_jobs.len == 0 && compute_retirement_callbacks == 3 && compute_retirement_ends == 3
 assert state.cpu_freeptr == 0 && katomic.barriers() == before + 1
 assert queue.subqueues[2].events.can_submit(126), 'reverse compute retirement cannot roll completion credit backward'
 println('G13 compute retirement: actual reverse reaper preserves monotonic ring and event prefixes through wrap')
}

fn check_compute_retirement() {
 check_compute_retirement_matrix()
 check_compute_retirement_failure()
 check_compute_retirement_reverse()
 check_compute_prepared_retirement()
}

fn check_compute_prepared_retirement() {
 reset_compute_retirement()
 mut state := fw.G13WorkQueueRingState{cpu_wptr: 7, gpu_doneptr: 7, cpu_freeptr: 5}
 original := state
 mut queue := G13QueueResources{}
 queue.subqueues[2] = G13Subqueue{state: SharedBuffer{phys: u64(&state)}, command_sequence: 7,
  events: event.credit_queue(112, 0, 126)}
 mut timestamps := fw.G13JobTimestamps{}
 mut job := compute_retirement_job(&queue, 7, 126 * u32(0x100), &timestamps)
 job.submitted = false; job.pending_counted = false; job.retirement_sequence = 0
 mut manager := GpuManager{g13_compute_jobs: [job]}
 event.set_completed(112, true)
 manager.checked_reap_g13_compute_jobs()
 assert manager.g13_compute_jobs.len == 1 && compute_retirement_frees == 0 && compute_retirement_callbacks == 0
 job.quarantined = true
 manager.checked_reap_g13_compute_jobs()
 assert manager.g13_compute_jobs.len == 0 && compute_retirement_frees == 1 && compute_retirement_callbacks == 1
 assert !compute_retirement_success && compute_retirement_ends == 0
 assert state == original && !queue.subqueues[2].events.can_submit(1), 'unsubmitted compute cleanup cannot invent firmware credit'
 println('G13 compute retirement: prepared caller ownership and abandoned cleanup never invent ring or event retirement')
}
