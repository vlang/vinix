module gpu

import gpu.agx.alloc
import gpu.agx.channel
import gpu.agx.fw
import gpu.agx.hw
import katomic

fn check_ring_admission() {
	for pending := u64(0); pending < 1280; pending++ {
		for count := u32(1); count <= 4; count++ {
			mut mgr := GpuManager{}
			published := u64(1) << 40
			assert mgr.g13_ring_has_space_locked(published, published - pending, count) == (1279 - pending > count)
			assert mgr.state == .running
		}
	}
	for which in 0 .. 3 {
		mut mgr := GpuManager{}
		published := if which == 2 { ~u64(0) } else { u64(1280) }
		retired := if which == 0 {
			published + 1
		} else if which == 1 {
			u64(0)
		} else {
			published
		}
		assert !mgr.g13_ring_has_space_locked(published, retired, 1) && mgr.state == .error
	}
	check_compute_host_admission()
	check_render_host_admission()
	println('G13 host admission: 5120 capacity boundaries, invalid/overflow counters, consumed-but-unretired compute/render rings, exact spare-entry refusal, atomic retry and wrapped prefixes passed')
}

fn check_compute_host_admission() {
	for count := u32(1); count <= 3; count++ {
		mut header := channel.RingHeader{}
		mut messages := [4]fw.FwRunWorkQueueMsg{}
		mut state := fw.G13WorkQueueRingState{ cpu_wptr: 1279, gpu_doneptr: 1279 }
		mut ring := [1280]u64{init: 0xdeadbeef}
		published := u64(10 * 1280 + 1279)
		retired := published - (1279 - count)
		mut queue := G13QueueResources{}
		queue.subqueues[2] = G13Subqueue{
			state:            SharedBuffer{ phys: u64(&state) }
			ring:             SharedBuffer{ phys: unsafe { u64(&ring) } }
			info:             SharedBuffer{ va: 0x1000 }
			command_sequence: published
			retired_sequence: retired
		}
		mut mgr := GpuManager{ hw_config: hw.HwConfig{ gpu_gen: .g13 } }
		mgr.channels.pipes[2] = channel.new_tx_channel('compute', 1, u64(&header), 1, unsafe { u64(&messages) }, 4, 0x30)
		values := [alloc.g13_private_start + 0x1000, alloc.g13_private_start + 0x2000,
			alloc.g13_private_start + 0x3000]!
		before := katomic.barriers()
		assert !mgr.submit_g13_queue_commands(&queue, 2, values, count, 0)
		assert mgr.state == .running && mgr.rings == 0 && katomic.barriers() == before
		assert header.write_ptr == 0 && state.cpu_wptr == 1279 && ring == [1280]u64{init: 0xdeadbeef}
		assert queue.subqueues[2].command_sequence == published && queue.subqueues[2].is_new
		assert mgr.retire_g13_subqueue_locked(&queue, 2, retired + 1, u32(retired % 1280))
		assert mgr.submit_g13_queue_commands(&queue, 2, values, count, 0)
		assert queue.subqueues[2].command_sequence == published + count
		assert state.cpu_wptr == (1279 + count) % 1280 && header.write_ptr == 1
		for index := u32(0); index < count; index++ {
			assert ring[(1279 + index) % 1280] == values[index]
		}
		assert ring[count - 1] == 0xdeadbeef
	}
}

fn check_render_host_admission() {
	for blocked in 0 .. 2 {
		for prefixes := u32(0); prefixes <= 2; prefixes++ {
			for initial_bind in [false, true]! {
				mut vertex_header := channel.RingHeader{}
				mut fragment_header := channel.RingHeader{}
				mut vertex_messages := [4]fw.FwRunWorkQueueMsg{}
				mut fragment_messages := [4]fw.FwRunWorkQueueMsg{}
				mut vertex_state := fw.G13WorkQueueRingState{ cpu_wptr: 1278, gpu_doneptr: 1278 }
				mut fragment_state := fw.G13WorkQueueRingState{ cpu_wptr: 1279, gpu_doneptr: 1279 }
				mut vertex_ring := [1280]u64{init: 0xdeadbeef}
				mut fragment_ring := [1280]u64{init: 0xdeadbeef}
				mut queue := G13QueueResources{}
				queue.render_buffer.needs_bind = initial_bind
				queue.render_buffer.bound_blocks = 8
				vertex_count := prefixes + if initial_bind { u32(2) } else { u32(1) }
				for pipe in 0 .. 2 {
					published := u64(10 * 1280 + 1278 + pipe)
					count := if pipe == 0 { vertex_count } else { u32(2) }
					queue.subqueues[pipe] = G13Subqueue{
						state:            SharedBuffer{ phys: if pipe == 0 {
							u64(&vertex_state)
						} else {
							u64(&fragment_state)
						} }
						ring:             SharedBuffer{ phys: if pipe == 0 {
							unsafe { u64(&vertex_ring) }
						} else {
							unsafe { u64(&fragment_ring) }
						} }
						info:             SharedBuffer{ va: u64(pipe + 1) * 0x1000 }
						command_sequence: published
						retired_sequence: if pipe == blocked {
							published - (1279 - count)
						} else {
							published
						}
					}
				}
				mut context := Context{}
				mut graph := G13ChannelAllocations{}
				mut mgr := GpuManager{ hw_config: hw.HwConfig{ gpu_gen: .g13 }, g13_channels: &graph }
				mgr.channels.pipes[0] = channel.new_tx_channel('vertex', 1, u64(&vertex_header), 1, unsafe { u64(&vertex_messages) }, 4, 0x30)
				mgr.channels.pipes[1] = channel.new_tx_channel('fragment', 1, u64(&fragment_header), 1, unsafe { u64(&fragment_messages) }, 4, 0x30)
				mut job := G13RenderJobResources{
					queue:             &queue
					context:           &context
					init_buffer:       SharedBuffer{ va: 0x10000, size: 0x180 }
					vertex:            SharedBuffer{ va: 0x20000 }
					barrier:           SharedBuffer{ va: 0x30000 }
					fragment:          SharedBuffer{ va: 0x40000 }
					explicit_barriers: G13CommandBarriers{ offset: 0x80, count: prefixes, configured: true, ready: true }
					tvb_size_bytes:    8 * fw.g13_tvb_block_size
				}
				before := katomic.barriers()
				assert !mgr.publish_g13_render_job_locked(mut job)
				assert mgr.state == .running && mgr.rings == 0 && katomic.barriers() == before
				assert vertex_header.write_ptr == 0 && fragment_header.write_ptr == 0
				assert vertex_state.cpu_wptr == 1278 && fragment_state.cpu_wptr == 1279
				assert vertex_ring == [1280]u64{init: 0xdeadbeef} && fragment_ring == [1280]u64{init: 0xdeadbeef}
				assert queue.render_buffer.needs_bind == initial_bind && queue.subqueues[0].is_new && queue.subqueues[1].is_new
				assert queue.subqueues[0].command_sequence == 14078 && queue.subqueues[1].command_sequence == 14079
				retired := queue.subqueues[blocked].retired_sequence
				assert mgr.retire_g13_subqueue_locked(&queue, u32(blocked), retired + 1, u32(retired % 1280))
				assert mgr.publish_g13_render_job_locked(mut job)
				assert vertex_state.cpu_wptr == (1278 + vertex_count) % 1280 && fragment_state.cpu_wptr == 1
				assert vertex_header.write_ptr == 1 && fragment_header.write_ptr == 1
				assert queue.subqueues[0].command_sequence == 14078 + vertex_count && queue.subqueues[1].command_sequence == 14081
				for index := u32(0); index < prefixes; index++ {
					assert vertex_ring[(1278 + index) % 1280] == 0x10080 + u64(index) * 0x80
				}
				if initial_bind {
					assert vertex_ring[(1278 + prefixes) % 1280] == 0x10000 && vertex_ring[(1279 + prefixes) % 1280] == 0x20000
				} else {
					assert vertex_ring[(1278 + prefixes) % 1280] == 0x20000
				}
				assert fragment_ring[1279] == 0x30000 && fragment_ring[0] == 0x40000
			}
		}
	}
}
