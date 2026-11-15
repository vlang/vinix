module gpu

import gpu.agx.alloc
import gpu.agx.channel
import gpu.agx.fw
import gpu.agx.hw
import katomic

fn check_barrier_publishers() {
	for count := u32(1); count <= 2; count++ {
		for failure in -1 .. 5 {
			mut vertex_outer := channel.RingHeader{}
			mut fragment_outer := channel.RingHeader{}
			mut vertex_messages := [4]fw.FwRunWorkQueueMsg{}
			mut fragment_messages := [4]fw.FwRunWorkQueueMsg{}
			mut vertex_state := fw.G13WorkQueueRingState{ cpu_wptr: 1278 }
			mut fragment_state := fw.G13WorkQueueRingState{ cpu_wptr: 1279 }
			mut vertex_ring := [1280]u64{}
			mut fragment_ring := [1280]u64{}
			mut resources := G13QueueResources{}
			resources.subqueues[0] = G13Subqueue{ state: SharedBuffer{ phys: u64(&vertex_state) }, ring: SharedBuffer{ phys: unsafe { u64(&vertex_ring) } }, info: SharedBuffer{ va: 0x1000 } }
			resources.subqueues[1] = G13Subqueue{ state: SharedBuffer{ phys: u64(&fragment_state) }, ring: SharedBuffer{ phys: unsafe { u64(&fragment_ring) } }, info: SharedBuffer{ va: 0x2000 } }
			mut context := Context{}
			mut graph := G13ChannelAllocations{}
			mut mgr := GpuManager{ hw_config: hw.HwConfig{ gpu_gen: .g13 }, g13_channels: &graph }
			mgr.channels.pipes[0] = channel.new_tx_channel('vertex', 1, u64(&vertex_outer), 1, u64(&vertex_messages), 4, 0x30)
			mgr.channels.pipes[1] = channel.new_tx_channel('fragment', 1, u64(&fragment_outer), 1, u64(&fragment_messages), 4, 0x30)
			mut job := G13RenderJobResources{
				queue:             &resources
				context:           &context
				init_buffer:       SharedBuffer{ va: 0x10000, size: 0x180 }
				vertex:            SharedBuffer{ va: 0x20000 }
				barrier:           SharedBuffer{ va: 0x30000 }
				fragment:          SharedBuffer{ va: 0x40000 }
				explicit_barriers: G13CommandBarriers{ offset: 0x80, count: count, configured: true, ready: failure != 4 }
				tvb_size_bytes:    8 * fw.g13_tvb_block_size
			}
			vertex_count := count + 2
			vertex_state.gpu_doneptr = (vertex_state.cpu_wptr + vertex_count + 1) % 1280
			fragment_state.gpu_doneptr = (fragment_state.cpu_wptr + 3) % 1280
			match failure {
				0 { vertex_outer.read_ptr = 1 }
				1 { fragment_outer.read_ptr = 1 }
				2 { vertex_state.gpu_doneptr = (vertex_state.cpu_wptr + vertex_count) % 1280 }
				3 { fragment_state.gpu_doneptr = (fragment_state.cpu_wptr + 2) % 1280 }
				else {}
			}
			before := katomic.barriers()
			published := mgr.publish_g13_render_job_locked(mut job)
			if failure != -1 {
				assert !published && mgr.rings == 0 && katomic.barriers() == before
				assert vertex_state.cpu_wptr == 1278 && fragment_state.cpu_wptr == 1279
				assert vertex_ring == [1280]u64{} && fragment_ring == [1280]u64{}
				assert vertex_outer.write_ptr == 0 && fragment_outer.write_ptr == 0
				assert resources.render_buffer.needs_bind && job.explicit_barriers.count == count
				// Retry after restoring capacity/readiness must use the original prefix.
				vertex_outer.read_ptr = 0
				fragment_outer.read_ptr = 0
				vertex_state.gpu_doneptr = (1278 + vertex_count + 1) % 1280
				fragment_state.gpu_doneptr = 2
				job.explicit_barriers.ready = true
				assert mgr.publish_g13_render_job_locked(mut job)
			} else {
				assert published
			}
			for index := u32(0); index < count; index++ {
				assert vertex_ring[(1278 + index) % 1280] == 0x10080 + u64(index) * 0x80
			}
			assert vertex_ring[(1278 + count) % 1280] == 0x10000
			assert vertex_ring[(1278 + count + 1) % 1280] == 0x20000
			assert fragment_ring[1279] == 0x30000 && fragment_ring[0] == 0x40000
			assert vertex_state.cpu_wptr == (1278 + vertex_count) % 1280 && fragment_state.cpu_wptr == 1
			assert vertex_messages[0].write_ptr == vertex_state.cpu_wptr && fragment_messages[0].write_ptr == 1
			assert job.vertex_retirement_sequence == u64(vertex_count) && job.fragment_retirement_sequence == 2
			assert job.vertex_ring_slot == (1278 + vertex_count - 1) % 1280
			assert !resources.render_buffer.needs_bind
			// An unchanged TVB omits InitBuffer but retains the explicit prefix.
			vertex_state.gpu_doneptr = (vertex_state.cpu_wptr + count + 2) % 1280
			fragment_state.gpu_doneptr = (fragment_state.cpu_wptr + 3) % 1280
			start := vertex_state.cpu_wptr
			assert mgr.publish_g13_render_job_locked(mut job)
			for index := u32(0); index < count; index++ {
				assert vertex_ring[(start + index) % 1280] == 0x10080 + u64(index) * 0x80
			}
			assert vertex_ring[(start + count) % 1280] == 0x20000
			assert job.vertex_retirement_sequence == u64(vertex_count + count + 1)
		}
		for failure in -1 .. 3 {
			mut outer := channel.RingHeader{}
			mut messages := [4]fw.FwRunWorkQueueMsg{}
			mut state := fw.G13WorkQueueRingState{ cpu_wptr: 1279 }
			mut ring := [1280]u64{}
			mut queue := G13QueueResources{}
			queue.subqueues[2] = G13Subqueue{ state: SharedBuffer{ phys: u64(&state) }, ring: SharedBuffer{ phys: unsafe { u64(&ring) } }, info: SharedBuffer{ va: 0x1000 } }
			mut mgr := GpuManager{ hw_config: hw.HwConfig{ gpu_gen: .g13 } }
			mgr.channels.pipes[2] = channel.new_tx_channel('compute', 1, u64(&outer), 1, u64(&messages), 4, 0x30)
			mut job := G13ComputeJobResources{
				queue:             &queue
				microsequence:     SharedBuffer{ va: alloc.g13_private_start + 0x1000, size: 0x400 }
				command:           SharedBuffer{ va: alloc.g13_gpu_readonly_start + 0x1000 }
				explicit_barriers: G13CommandBarriers{ offset: 0x280, count: count, configured: true, ready: failure != 2 }
			}
			state.gpu_doneptr = (1279 + count + 2) % 1280
			if failure == 0 { outer.read_ptr = 1 }
			if failure == 1 { state.gpu_doneptr = (1279 + count + 1) % 1280 }
			for invalid_count in [u32(0), 4]! {
				assert !mgr.submit_g13_queue_commands(&queue, 2, [job.command.va, u64(0), 0]!, invalid_count, 0)
			}
			before := katomic.barriers()
			published := mgr.publish_g13_compute_job_locked(&job)
			if failure != -1 {
				assert !published && mgr.rings == 0 && katomic.barriers() == before
				assert ring == [1280]u64{} && outer.write_ptr == 0 && state.cpu_wptr == 1279
				outer.read_ptr = 0
				state.gpu_doneptr = (1279 + count + 2) % 1280
				job.explicit_barriers.ready = true
				assert mgr.publish_g13_compute_job_locked(&job)
			} else {
				assert published
			}
			for index := u32(0); index < count; index++ {
				assert ring[(1279 + index) % 1280] == job.microsequence.va + 0x280 + u64(index) * 0x80
			}
			assert ring[(1279 + count) % 1280] == job.command.va
			assert state.cpu_wptr == (1279 + count + 1) % 1280 && outer.write_ptr == 1
			assert queue.subqueues[2].command_sequence == u64(count + 1)
			assert queue.subqueues[2].last_command_slot == (1279 + count) % 1280
		}
	}
	println('G13 barrier publishers: one/two prefixes, ring wrap, exact/full capacity, outer-ring refusal, readiness retry, TVB bind omission and retirement sequences passed')
}
