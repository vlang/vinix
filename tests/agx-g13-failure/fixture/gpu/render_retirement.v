// SPDX-License-Identifier: GPL-2.0-or-later
module gpu

import gpu.agx.event
import gpu.agx.fw
import katomic

fn render_retirement_job(queue &G13QueueResources, vertex u64, fragment u64) G13RenderJobResources {
 unsafe {
  queue.subqueues[0].events = event.published_queue(110, 0x100)
  queue.subqueues[1].events = event.published_queue(111, 0x200)
 }
 return G13RenderJobResources{queue: unsafe { queue }, vertex_event_slot: 110, fragment_event_slot: 111,
  vertex_stamp_value: 0x100, fragment_stamp_value: 0x200,
  vertex_retirement_sequence: vertex, fragment_retirement_sequence: fragment,
  vertex_ring_slot: u32((vertex - 1) % fw.g13_workqueue_entries),
  fragment_ring_slot: u32((fragment - 1) % fw.g13_workqueue_entries)}
}

fn check_render_retirement_matrix() {
 mut cases := 0
 for vertex in [u64(1), 1279, 1280, 1281, 0x100000001] {
  for fragment in [u64(1), 1280, 1281, 0x100000003] {
   for mask in 0 .. 4 {
    mut vertex_state := fw.G13WorkQueueRingState{
     cpu_wptr: u32((vertex + 7) % 1280)
     gpu_doneptr: u32(vertex % 1280)
     cpu_freeptr: if vertex == 1 { u32(0) } else { u32((vertex - 2) % 1280) }
    }
    mut fragment_state := fw.G13WorkQueueRingState{
     cpu_wptr: u32((fragment + 7) % 1280)
     gpu_doneptr: u32(fragment % 1280)
     cpu_freeptr: if fragment == 1 { u32(0) } else { u32((fragment - 2) % 1280) }
    }
    mut queue := G13QueueResources{}
    queue.subqueues[0] = retirement_subqueue(&vertex_state, vertex + 7, vertex - 1)
    queue.subqueues[1] = retirement_subqueue(&fragment_state, fragment + 7, fragment - 1)
    mut job := render_retirement_job(&queue, vertex, fragment)
    mut manager := GpuManager{}
    event.set_completed(110, mask & 1 != 0); event.set_completed(111, mask & 2 != 0)
    mut expected_vertex := vertex_state
    mut expected_fragment := fragment_state
    if mask & 1 != 0 { expected_vertex.cpu_freeptr = job.vertex_ring_slot }
    if mask & 2 != 0 { expected_fragment.cpu_freeptr = job.fragment_ring_slot }
    before := katomic.barriers()
    manager.lock.acquire()
    result := manager.retire_g13_render_stages_locked(mut job)
    assert result == if mask == 3 { 1 } else { 0 }, 'stage completion result'
    assert vertex_state == expected_vertex, 'independent vertex free-pointer image'
    assert fragment_state == expected_fragment, 'independent fragment free-pointer image'
    assert job.vertex_retirement_published == (mask & 1 != 0)
    assert job.fragment_retirement_published == (mask & 2 != 0)
    assert job.retirement_published == (mask == 3) && !job.retirement_failed
    assert !job.released && manager.state == .running
    assert katomic.barriers() == before + (if mask & 1 != 0 { 1 } else { 0 }) + (if mask & 2 != 0 { 1 } else { 0 })
    assert manager.retire_g13_render_stages_locked(mut job) == result
    assert vertex_state == expected_vertex && fragment_state == expected_fragment, 'repeat polls preserve full ring images'
    // A retired stage remains retired even if a later stamp view is stale.
    event.set_completed(110, true); event.set_completed(111, true)
    if mask == 1 { event.set_completed(110, false) }
    if mask == 2 { event.set_completed(111, false) }
    assert manager.retire_g13_render_stages_locked(mut job) == 1
    assert vertex_state.cpu_freeptr == job.vertex_ring_slot && fragment_state.cpu_freeptr == job.fragment_ring_slot,
     'completed stage free pointers'
    assert katomic.barriers() == before + 2, 'one publication per stage'
    manager.lock.release()
    cases++
   }
  }
 }
 assert cases == 80
 println('G13 render retirement: 80 full stage-mask/ring-wrap images, repeat polls and delayed peer completion passed')
}

fn check_render_retirement_failure() {
 for bad_pipe in 0 .. 2 {
  mut vertex_state := fw.G13WorkQueueRingState{cpu_wptr: 5, gpu_doneptr: 5}
  mut fragment_state := fw.G13WorkQueueRingState{cpu_wptr: 9, gpu_doneptr: 9}
  mut queue := G13QueueResources{}
  queue.subqueues[0] = retirement_subqueue(&vertex_state, 5, 0)
  queue.subqueues[1] = retirement_subqueue(&fragment_state, 9, 0)
  mut job := render_retirement_job(&queue, 5, 9)
  mut manager := GpuManager{}
  if bad_pipe == 0 { vertex_state.cpu_wptr = fw.g13_workqueue_entries }
  else { fragment_state.cpu_wptr = fw.g13_workqueue_entries }
  event.set_completed(110, bad_pipe == 0); event.set_completed(111, bad_pipe == 1)
  manager.lock.acquire()
  assert manager.retire_g13_render_stages_locked(mut job) == 0, 'partial failure must wait for active peer'
  assert job.retirement_failed && !job.retirement_published && !job.released
  assert manager.state == .error
  // Pointer repair cannot turn the recorded protocol failure into success.
  vertex_state.cpu_wptr = 5; fragment_state.cpu_wptr = 9
  assert manager.retire_g13_render_stages_locked(mut job) == 0
  event.set_completed(110, true); event.set_completed(111, true)
  assert manager.retire_g13_render_stages_locked(mut job) == -1, 'sticky failure must be reported after peer completion'
  assert !job.retirement_published
  // Existing quarantine recovery retries retirement after reporting failure.
  job.quarantined = true
  assert manager.retire_g13_render_stages_locked(mut job) == 1
  assert job.retirement_published && vertex_state.cpu_freeptr == 4 && fragment_state.cpu_freeptr == 8
  manager.lock.release()
 }
 // An uncompleted stage's invalid ring cannot poison its completed peer.
 mut vertex_state := fw.G13WorkQueueRingState{cpu_wptr: 1280}
 mut fragment_state := fw.G13WorkQueueRingState{cpu_wptr: 9, gpu_doneptr: 9}
 mut queue := G13QueueResources{}
 queue.subqueues[0] = retirement_subqueue(&vertex_state, 5, 0)
 queue.subqueues[1] = retirement_subqueue(&fragment_state, 9, 0)
 mut job := render_retirement_job(&queue, 5, 9)
 mut manager := GpuManager{}
 event.set_completed(110, false); event.set_completed(111, true)
 manager.lock.acquire()
 assert manager.retire_g13_render_stages_locked(mut job) == 0
 assert manager.state == .running && !job.retirement_failed && fragment_state.cpu_freeptr == 8
 manager.lock.release()
 println('G13 render retirement: partial protocol failures wait for peers, remain sticky and support quarantine retry; uncompleted rings remain untouched')
}

fn check_render_retirement_reverse() {
 mut vertex_state := fw.G13WorkQueueRingState{cpu_wptr: 2, gpu_doneptr: 2, cpu_freeptr: 1278}
 mut fragment_state := fw.G13WorkQueueRingState{cpu_wptr: 2, gpu_doneptr: 2, cpu_freeptr: 1278}
 mut queue := G13QueueResources{}
 queue.subqueues[0] = retirement_subqueue(&vertex_state, 1282, 1279)
 queue.subqueues[1] = retirement_subqueue(&fragment_state, 1282, 1279)
 mut old_job := render_retirement_job(&queue, 1280, 1280)
 mut new_job := render_retirement_job(&queue, 1281, 1281)
 mut manager := GpuManager{}
 event.set_completed(110, true); event.set_completed(111, false)
 manager.lock.acquire()
 before := katomic.barriers()
 assert manager.retire_g13_render_stages_locked(mut new_job) == 0
 assert manager.retire_g13_render_stages_locked(mut old_job) == 0
 assert vertex_state.cpu_freeptr == 0 && fragment_state.cpu_freeptr == 1278
 assert katomic.barriers() == before + 1, 'older vertex retirement never rolls the ring backward'
 event.set_completed(111, true)
 assert manager.retire_g13_render_stages_locked(mut new_job) == 1
 assert manager.retire_g13_render_stages_locked(mut old_job) == 1
 assert vertex_state.cpu_freeptr == 0 && fragment_state.cpu_freeptr == 0
 assert katomic.barriers() == before + 2, 'older fragment retirement never rolls the ring backward'
 manager.lock.release()
 println('G13 render retirement: reverse job visits preserve monotonic per-stage free pointers through wrap')
}

fn check_render_retirement() {
 check_render_retirement_matrix()
 check_render_retirement_failure()
 check_render_retirement_reverse()
	check_render_event_credits()
 check_render_reaper_integration()
 check_render_error_completion()
}

struct RetirementTestResult { value u32 }
struct RetirementCompletion { marker u64 = 0xdecaf }
__global retirement_frees = 0
__global retirement_reads = 0
__global retirement_ends = 0
__global retirement_callbacks = 0
__global retirement_success = false
__global retirement_refuse_free = false
__global retirement_stages = [2]int{}

fn retirement_stage_callback(pipe u32, _ voidptr) {
 assert pipe < 2
 retirement_stages[pipe]++
}

fn retirement_test_result(_ &G13RenderJobResources) RetirementTestResult {
 retirement_reads++
 return RetirementTestResult{value: 42}
}
fn (mut manager GpuManager) retirement_test_end() bool { retirement_ends++; return true }
fn (mut manager GpuManager) retirement_test_free(mut job G13RenderJobResources, invalidate bool) bool {
 assert invalidate && job.vertex_retirement_published && job.fragment_retirement_published,
  'shared backing cannot be freed before both stage retirements'
 assert job.completion == unsafe { nil } && job.completion_data == unsafe { nil },
  'completed render callback precedes backing disposal'
 retirement_frees++
 if retirement_refuse_free || manager.state != .running { return false }
 job.released = true
 return true
}
fn retirement_callback(job &G13RenderJobResources, success bool, data voidptr) {
 assert data != unsafe { nil }, 'render callback backing must remain one-shot'
 state := unsafe { &RetirementCompletion(data) }
 assert state.marker == 0xdecaf
 assert job.completion_result_ready || !success
 assert !job.released, 'render callback runs while command backing remains owned'
 retirement_callbacks++; retirement_success = success
 unsafe { free(state) }
}

fn check_render_reaper_integration() {
 for mode in 0 .. 5 {
  retirement_frees = 0; retirement_reads = 0; retirement_ends = 0; retirement_callbacks = 0
  retirement_success = false; retirement_refuse_free = mode == 2
  retirement_stages = [2]int{}
  mut vertex_state := fw.G13WorkQueueRingState{cpu_wptr: 5, gpu_doneptr: 5}
  mut fragment_state := fw.G13WorkQueueRingState{cpu_wptr: 9, gpu_doneptr: 9}
  mut queue := G13QueueResources{}
  queue.subqueues[0] = retirement_subqueue(&vertex_state, 5, 0)
  queue.subqueues[1] = retirement_subqueue(&fragment_state, 9, 0)
  mut job := &G13RenderJobResources{}
  unsafe { *job = render_retirement_job(&queue, 5, 9) }
  job.submitted = true; job.pending_counted = true; job.completion = retirement_callback
  job.completion_data = &RetirementCompletion{}
  job.stage_completion = retirement_stage_callback
  mut manager := GpuManager{g13_render_jobs: [job], g13_queues: [&queue]}
  event.set_completed(110, true); event.set_completed(111, false)
  if mode == 1 { vertex_state.cpu_wptr = 1280 }
  if mode == 3 { queue.subqueues[0].events = event.published_queue(109, 0x100) }
  if mode == 4 { vertex_state.cpu_wptr = 4 }
  manager.checked_reap_g13_render_jobs()
  assert manager.g13_render_jobs.len == 1 && retirement_callbacks == 0 && retirement_frees == 0
   && retirement_reads == 0 && retirement_ends == 0, 'shared backing waits for both stages'
  assert job.pending_counted && !job.released
  protocol_failure := mode in [1, 3, 4]!
  if protocol_failure {
   assert job.retirement_failed && !job.quarantined
   if mode == 4 { assert vertex_state.cpu_freeptr == 0 && queue.subqueues[0].retired_sequence == 0 }
   vertex_state.cpu_wptr = 5
   if mode == 3 { queue.subqueues[0].events = event.published_queue(110, 0x100) }
   manager.checked_reap_g13_render_jobs()
   assert retirement_callbacks == 0 && retirement_frees == 0, 'partial error callback waits for its peer'
  } else {
   assert vertex_state.cpu_freeptr == 4 && fragment_state.cpu_freeptr == 0
   assert retirement_stages == [1, 0]!, 'completed vertex stage publishes its private notification'
  }
  event.set_completed(111, true)
  manager.checked_reap_g13_render_jobs()
  if mode == 0 {
   assert manager.g13_render_jobs.len == 0 && retirement_success && retirement_callbacks == 1
   assert retirement_reads == 1 && retirement_frees == 1 && retirement_ends == 1
  } else {
   assert manager.g13_render_jobs.len == 1 && retirement_callbacks == 1
   assert retirement_success == (mode == 2), 'cleanup refusal preserves successful render completion'
   assert job.quarantined && !job.released
   assert !manager.checked_release_g13_queue_resources(&queue) && !queue.released,
    'completed render backing retains queue ownership after submission pins end'
   assert job.stage_completion == unsafe { nil }, 'aggregate callback clears stage callback backing'
   // Retrying cleanup cannot issue the completion callback a second time.
   manager.state = .running; retirement_refuse_free = false
   manager.checked_reap_g13_render_jobs()
   assert manager.g13_render_jobs.len == 0 && retirement_callbacks == 1
   assert retirement_ends == 1 && retirement_frees >= 1
   assert retirement_reads == 1, 'render cleanup retries retain the first cached result'
  }
  assert vertex_state.cpu_freeptr == 4 && fragment_state.cpu_freeptr == 8
  manager.checked_reap_g13_render_jobs()
  assert retirement_callbacks == 1
  assert manager.checked_release_g13_queue_resources(&queue) && manager.g13_queues.len == 0,
   'render cleanup retry permits final queue destruction'
  assert retirement_stages == if protocol_failure { [0, 0]! } else { [1, 1]! }, 'stage callbacks remain one-shot across quarantine retry'
 }
 retirement_refuse_free = false
 println('G13 render reaper: actual retirement/completion bodies retain shared backing, defer partial-error callbacks and preserve one-shot cleanup retries')
}

fn check_render_error_completion() {
 for status in [u32(1), 3, 6] {
  retirement_callbacks = 0; retirement_reads = 0; retirement_refuse_free = true
  mut vertex_state := fw.G13WorkQueueRingState{cpu_wptr: 5, gpu_doneptr: 5}
  mut fragment_state := fw.G13WorkQueueRingState{cpu_wptr: 9, gpu_doneptr: 9}
  mut queue := G13QueueResources{}
  queue.subqueues[0] = retirement_subqueue(&vertex_state, 5, 0)
  queue.subqueues[1] = retirement_subqueue(&fragment_state, 9, 0)
  mut job := &G13RenderJobResources{}
  unsafe { *job = render_retirement_job(&queue, 5, 9) }
  job.submitted = true; job.error = G13JobError{status: status}
  job.completion = retirement_callback; job.completion_data = &RetirementCompletion{}
  mut manager := GpuManager{g13_render_jobs: [job]}
  event.set_completed(110, true); event.set_completed(111, true)
  manager.checked_reap_g13_render_jobs()
  assert retirement_callbacks == 1 && !retirement_success && job.quarantined,
   'render hardware errors survive deferred cleanup'
  retirement_refuse_free = false
  manager.checked_reap_g13_render_jobs()
  assert manager.g13_render_jobs.len == 0 && retirement_callbacks == 1 && retirement_reads == 1
 }
 println('G13 render completion: three hardware errors remain failures across deferred cleanup')
}
