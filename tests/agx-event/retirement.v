// SPDX-License-Identifier: GPL-2.0-or-later
module main

import gpu.agx.event
import memory

fn check_retained_event_credits() {
 mut completions := 0
 for baseline in [u32(0), 0xffffff00, 0xffff8000, 0x7fffff00, 0x80000000] {
  for reverse in [false, true] {
   mut driver := [128]u32{}
   mut firmware := [128]u32{}
   assert event.configure_event_manager(0x10000, u64(&driver), 0x20000, u64(&firmware))
   driver[0] = baseline
   mut queue := event.WorkQueueEvents{}
   mut tickets := [1024]event.Ticket{}
   for index in 0 .. tickets.len { tickets[index] = queue.retain() or { panic('retained credit backlog') } }
   assert memory.outstanding() == 8 && event.retain_stamp(0)
   for slot := u32(1); slot < 128; slot++ { assert (event.reserve_stamp() or { panic('occupy peer slot') }) == slot }
   assert event.reserve_stamp() == none
   assert !queue.record_completion(1, tickets[0].value), 'foreign slot cannot return credit'
   assert !queue.record_completion(0, tickets[0].value), 'unpublished ticket cannot return credit'
   assert !queue.record_completion(0, tickets[1023].value + u32(0x100)), 'unknown ticket cannot return credit'
   for start := 0; start < tickets.len; start += 64 {
    assert queue.can_submit(64), 'completed publications return credit while their tickets stay retained'
    mut values := [64]u32{}
    for offset in 0 .. 64 {
     ticket := tickets[start + offset]
     values[offset] = ticket.value
     assert queue.admit(ticket.slot, ticket.value)
    }
    assert queue.can_publish_batch(0, values, 64)
    for offset in 0 .. 64 { assert queue.publish(0, values[offset]) }
    assert !queue.record_completion(1, tickets[start].value), 'foreign slot cannot return credit'
    assert !queue.can_submit(64)
    driver[0] = tickets[start + 63].value
    assert !queue.can_submit(64), 'raw GPU progress alone cannot return event credit'
    for step in 0 .. 64 {
     index := start + if reverse { 63 - step } else { step }
     ticket := tickets[index]
     assert queue.record_completion(0, ticket.value), 'every published overflow ticket returns completion credit'
     assert queue.record_completion(0, ticket.value), 'duplicate completion remains idempotent'
     assert (queue.ticket(0, ticket.value) or { panic('early ticket release') }) == ticket
     assert queue.busy() && queue.owns_slot(0) && event.reserve_stamp() == none,
      'recording credit must retain the physical event owner'
     assert memory.outstanding() == 8, 'recording credit cannot free overflow blocks'
     completions++
    }
   }
   assert queue.can_submit(126)
   for index in 0 .. tickets.len {
    assert (queue.ticket(0, tickets[index].value) or { panic('retained identity') }) == tickets[index]
   }
   assert queue.release(0, tickets[1023].value, true)
   assert !queue.record_completion(0, tickets[1023].value), 'inactive retained value cannot return credit'
   for index := tickets.len - 2; index >= 0; index-- {
    assert queue.release(0, tickets[index].value, true)
   }
   assert !queue.busy() && memory.outstanding() == 0
   assert !queue.record_completion(0, tickets[1023].value), 'released ticket cannot return credit'
   assert event.reserve_stamp() == none, 'initial-event pin survives final queue-owner cleanup'
   event.release_stamp(0)
   assert (event.reserve_stamp() or { panic('slot after final pin') }) == 0
   for slot := u32(0); slot < 128; slot++ { event.release_stamp(slot) }
   event.reset_event_manager()
  }
 }
 assert completions == 10240
 println('AGX retained event credits: 10240 completions across full backlogs, forward/reverse and signed/zero wrap; tickets, eight overflow blocks and physical/initial pins remain owned until cleanup')
}
