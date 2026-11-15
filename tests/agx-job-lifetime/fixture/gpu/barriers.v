@[has_globals]
module gpu

import gpu.agx.event
import gpu.agx.fw
import gpu.agx.mmu

fn expect_free_events(expected int, pinned int) {
	mut slots := [128]u32{}
	mut count := 0
	for count < 128 {
		slot := event.reserve_stamp() or { break }
		assert int(slot) != pinned, 'a consumer must retain its producer stamp'
		slots[count] = slot
		count++
	}
	assert count == expected
	for index in 0 .. count { event.release_stamp(slots[index]) }
}

fn barrier_put(mut bytes [64]u8, offset int, size int, value u64) {
	for index in 0 .. size { bytes[offset + index] = u8(value >> (index * 8)) }
}

fn expect_barrier(bytes &[4096]u8, offset u64, slot u32, value u32, stamp_self u32) {
	mut expected := [64]u8{}
	barrier_put(mut expected, 0, 4, 4)
	barrier_put(mut expected, 4, 8, 0x20000 + u64(slot) * 4)
	barrier_put(mut expected, 0x0c, 4, value)
	barrier_put(mut expected, 0x10, 4, slot)
	barrier_put(mut expected, 0x14, 4, stamp_self)
	barrier_put(mut expected, 0x18, 4, 0xffffbbbb)
	barrier_put(mut expected, 0x20, 4, 1)
	for index in 0 .. 64 {
		assert bytes[offset + u64(index)] == expected[index], 'barrier byte ${index}'
	}
}

fn check_barrier_lifetimes() {
	assert fw.validate_g13_workqueue_layouts()
	// Every supported microsequence form still needs only its existing 16KiB page.
	for active in [u64(0x1c0), 0x228, 0x1f0, 0x268, sizeof(fw.G13InitBufferCommand)]! {
		assert g13_barrier_tail_offset(active) >= active
		assert g13_barrier_tail_offset(active) % 0x80 == 0
		assert g13_barrier_tail_offset(active) + g13_barrier_tail_size <= 0x4000
	}
	mut driver := [128]u32{}
	mut firmware := [128]u32{}
	assert event.configure_event_manager(0x10000, unsafe { u64(&driver) }, 0x20000, unsafe { u64(&firmware) })
	for render_consumer in [false, true]! {
		for mode in 0 .. 6 {
			for _ in 0 .. 40 {
				mut queue := G13QueueResources{}
				mut context := mmu.UatContext{}
				mut mgr := GpuManager{}
				mut producer_completion := Completion{}
				mut consumer_completion := Completion{}
				mut bytes := [4096]u8{init: 0xa5}
				offset := g13_barrier_tail_offset(if render_consumer {
					u64(sizeof(fw.G13InitBufferCommand))
				} else {
					u64(0x268)
				})
				owner := SharedBuffer{ phys: unsafe { u64(&bytes) }, va: 0x100000, size: sizeof(bytes) }
				mut sources := [2]G13BarrierSource{}
				mut pinned_slot := u32(0)
				mut wait_value := u32(0)
				mut self_value := u32(0)
				mut render := &G13RenderJobResources(unsafe { nil })
				mut compute := &G13ComputeJobResources(unsafe { nil })
				if render_consumer {
					compute = mgr.compute_job(mut queue, &context, &producer_completion)
					render = mgr.render_job(mut queue, &context, &consumer_completion)
					render.init_buffer = owner
					render.explicit_barriers.offset = offset
					sources[0] = G13BarrierSource{ compute: compute }
					pinned_slot, wait_value, self_value = compute.event_slot, compute.stamp_value, render.vertex_stamp_value
				} else {
					render = mgr.render_job(mut queue, &context, &producer_completion)
					compute = mgr.compute_job(mut queue, &context, &consumer_completion)
					compute.microsequence = owner
					compute.explicit_barriers.offset = offset
					sources[0] = G13BarrierSource{ render: render }
					pinned_slot, wait_value, self_value = render.fragment_event_slot, render.fragment_stamp_value, compute.stamp_value
				}
				// Two references to one producer must be released independently.
				sources[1] = sources[0]
				mut invalid := G13ComputeJobResources{}
				if mode == 1 { sources[1] = G13BarrierSource{ compute: &invalid } }
				mgr.flush_fails = mode == 2
				configured := if render_consumer {
					mgr.set_g13_render_barriers(render, sources)
				} else {
					mgr.set_g13_compute_barriers(compute, sources)
				}
				assert configured == (mode != 1 && mode != 2)
				barriers := if render_consumer {
					render.explicit_barriers
				} else {
					compute.explicit_barriers
				}
				assert barriers.count == if mode == 1 { u32(1) } else { u32(2) }
				assert barriers.publishable(&owner) == configured
				expect_barrier(&bytes, offset, pinned_slot, wait_value, self_value)
				if mode != 1 {
					expect_barrier(&bytes, offset + 0x80, pinned_slot, wait_value, self_value)
				}
				for index := u64(0); index < offset; index++ {
					assert bytes[index] == 0xa5
				}
				for index := offset + 0x40; index < offset + 0x80; index++ {
					assert bytes[index] == 0xa5
				}
				// Reconfiguration must not overwrite or add more physical pins.
				assert !(if render_consumer {
					mgr.set_g13_render_barriers(render, sources)
				} else {
					mgr.set_g13_compute_barriers(compute, sources)
				})
				if mode == 5 {
					// Both jobs are in firmware together. Its stamps advance before
					// either CPU reaper; the consumer callback may then arrive first.
					assert queue.subqueues[0].events.publish(render.vertex_event_slot, render.vertex_stamp_value)
					assert queue.subqueues[1].events.publish(render.fragment_event_slot, render.fragment_stamp_value)
					assert queue.subqueues[2].events.publish(compute.event_slot, compute.stamp_value)
					render.submitted = true
					compute.submitted = true
					render.vertex_retirement_sequence = 1
					render.fragment_retirement_sequence = 1
					compute.retirement_sequence = 1
					mgr.reap_g13_compute_jobs()
					mgr.reap_g13_render_jobs()
					assert producer_completion.calls == 0 && consumer_completion.calls == 0
					driver[render.vertex_event_slot] = render.vertex_stamp_value
					driver[render.fragment_event_slot] = render.fragment_stamp_value
					driver[compute.event_slot] = compute.stamp_value
					firmware[pinned_slot] = wait_value
					if render_consumer { mgr.reap_g13_render_jobs() } else { mgr.reap_g13_compute_jobs() }
					assert consumer_completion.calls == 1 && consumer_completion.ok
					assert producer_completion.calls == 0
					expect_free_events(if render_consumer { 127 } else { 126 }, int(pinned_slot))
					if render_consumer { mgr.reap_g13_compute_jobs() } else { mgr.reap_g13_render_jobs() }
					assert producer_completion.calls == 1 && producer_completion.ok
					assert mgr.g13_compute_jobs.len == 0 && mgr.g13_render_jobs.len == 0
					expect_free_events(128, -1)
					continue
				}
				if mode == 0 {
					if render_consumer {
						assert queue.subqueues[2].events.publish(compute.event_slot, compute.stamp_value)
						compute.submitted = true
						compute.retirement_sequence = 1
						driver[compute.event_slot] = compute.stamp_value
						firmware[compute.event_slot] = compute.stamp_value
						mgr.reap_g13_compute_jobs()
					} else {
						assert queue.subqueues[0].events.publish(render.vertex_event_slot, render.vertex_stamp_value)
						assert queue.subqueues[1].events.publish(render.fragment_event_slot, render.fragment_stamp_value)
						render.submitted = true
						render.vertex_retirement_sequence = 1
						render.fragment_retirement_sequence = 1
						driver[render.vertex_event_slot] = render.vertex_stamp_value
						driver[render.fragment_event_slot] = render.fragment_stamp_value
						firmware[render.fragment_event_slot] = render.fragment_stamp_value
						mgr.reap_g13_render_jobs()
					}
					assert producer_completion.ok && event.stamp_value_completed(pinned_slot, wait_value)
				} else if render_consumer {
					mgr.release_g13_compute_job(compute)
				} else {
					mgr.release_g13_render_job(render)
				}
				expect_free_events(if render_consumer { 125 } else { 126 }, int(pinned_slot))
				if mode == 0 {
					if render_consumer {
						assert queue.subqueues[0].events.publish(render.vertex_event_slot, render.vertex_stamp_value)
						assert queue.subqueues[1].events.publish(render.fragment_event_slot, render.fragment_stamp_value)
						render.submitted = true
						render.vertex_retirement_sequence = 1
						render.fragment_retirement_sequence = 1
						driver[render.vertex_event_slot] = render.vertex_stamp_value
						driver[render.fragment_event_slot] = render.fragment_stamp_value
						mgr.reap_g13_render_jobs()
					} else {
						assert queue.subqueues[2].events.publish(compute.event_slot, compute.stamp_value)
						compute.submitted = true
						compute.retirement_sequence = 1
						driver[compute.event_slot] = compute.stamp_value
						mgr.reap_g13_compute_jobs()
					}
					assert consumer_completion.ok
				} else if mode == 4 {
					mgr.state = .stopped
					if render_consumer {
						mgr.release_all_g13_render_jobs()
						mgr.release_g13_render_job(render)
					} else {
						mgr.release_all_g13_compute_jobs()
						mgr.release_g13_compute_job(compute)
					}
				} else {
					mgr.invalidation_fails = mode == 3
					if render_consumer {
						mgr.release_g13_render_job(render)
					} else {
						mgr.release_g13_compute_job(compute)
					}
					if mode == 3 {
						expect_free_events(if render_consumer { 125 } else { 126 }, int(pinned_slot))
						mgr.invalidation_fails = false
						if render_consumer {
							mgr.reap_g13_render_jobs()
						} else {
							mgr.reap_g13_compute_jobs()
						}
					}
				}
				assert producer_completion.calls == 1 && consumer_completion.calls == 1
				assert mgr.g13_compute_jobs.len == 0 && mgr.g13_render_jobs.len == 0
				expect_free_events(128, -1)
			}
		}
	}
	event.reset_event_manager()
	println('AGX firmware barriers: byte oracle, tail canaries, duplicate pins, partial setup/flush failure, producer/consumer callback orders, quarantine retry and stopped cleanup pass 480 cycles with all 128 slots returned')
}
