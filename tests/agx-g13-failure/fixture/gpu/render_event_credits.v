// SPDX-License-Identifier: GPL-2.0-or-later
module gpu

import gpu.agx.event
import gpu.agx.fw

fn check_render_event_credits() {
 mut cases := 0
 for baseline in [u32(0), 0xffffff00, 0xffff8000, 0x7fffff00, 0x80000000] {
  for sequence in [u64(126), 1280, 1281, 0x100000001] {
   for first in 0 .. 2 {
    mut vertex_state := fw.G13WorkQueueRingState{cpu_wptr: 1, gpu_doneptr: 1}
    mut fragment_state := fw.G13WorkQueueRingState{cpu_wptr: 1, gpu_doneptr: 1}
    mut queue := G13QueueResources{}
    queue.subqueues[0] = G13Subqueue{state: SharedBuffer{phys: u64(&vertex_state)}, command_sequence: sequence + 1}
    queue.subqueues[1] = G13Subqueue{state: SharedBuffer{phys: u64(&fragment_state)}, command_sequence: sequence + 1}
    mut job := render_retirement_job(&queue, sequence, sequence)
    queue.subqueues[0].events = event.credit_queue(110, baseline, 126)
    queue.subqueues[1].events = event.credit_queue(111, baseline, 126)
    job.vertex_stamp_value = baseline + 126 * u32(0x100)
    job.fragment_stamp_value = job.vertex_stamp_value
    mut manager := GpuManager{}
    assert !queue.subqueues[0].events.can_submit(1) && !queue.subqueues[1].events.can_submit(1)
    event.set_completed(110, first == 0); event.set_completed(111, first == 1)
    manager.lock.acquire()
    assert manager.retire_g13_render_stages_locked(mut job) == 0
    assert queue.subqueues[first].events.can_submit(1), 'completed render stage returns event admission credit'
    assert !queue.subqueues[1 - first].events.can_submit(1), 'active peer retains its event admission charge'
    assert !job.released && !job.retirement_published
    for pipe in 0 .. 2 {
     slot := u32(110 + pipe)
     assert queue.subqueues[pipe].events.owns_slot(slot), 'credit cannot surrender the event owner'
     for index in 0 .. 126 {
      ticket := queue.subqueues[pipe].events.ticket(slot, baseline + u32(index + 1) * u32(0x100)) or { panic('retained credit ticket') }
      assert ticket.sequence == u64(index) && ticket.serial == u64(index), 'credit preserves every ticket identity'
     }
    }
    assert manager.retire_g13_render_stages_locked(mut job) == 0
    assert queue.subqueues[first].events.can_submit(1) && !queue.subqueues[1 - first].events.can_submit(1)
    event.set_completed(110, true); event.set_completed(111, true)
    assert manager.retire_g13_render_stages_locked(mut job) == 1
    assert queue.subqueues[0].events.can_submit(1) && queue.subqueues[1].events.can_submit(1),
     'completed render stage returns event admission credit'
    assert queue.subqueues[0].events.owns_slot(110) && queue.subqueues[1].events.owns_slot(111)
    manager.lock.release()
    cases++
   }
  }
 }
 assert cases == 40
 println('G13 render event credits: 40 complete stage/ring/stamp-wrap cases return only completed-stage capacity and retain all ticket identities')
}
