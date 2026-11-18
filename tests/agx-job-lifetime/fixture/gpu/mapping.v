// SPDX-License-Identifier: GPL-2.0-or-later
module gpu

import gpu.agx.mmu

fn check_job_mapping_publication() {
	gpu_only := mmu.UatBuffer{va: 0x4000, size: 0x4000}
	private := mmu.UatBuffer{va: 0x8000, size: 0x4000}
	cache := G13TailPointerCache{buffer: unsafe { &private }}
	shared := SharedBuffer{phys: 0x10000, size: 0x4000}
	for failure in 0 .. 9 {
		mut mgr := GpuManager{publication_failure: failure}
		mut job := G13RenderJobResources{
			vm_slot: 1
			scene: G13RenderSceneResources{
				scene: shared
				timestamps: shared
				user_buffer: unsafe { &gpu_only }
				heapmeta: unsafe { &gpu_only }
				tilemap: unsafe { &gpu_only }
				tail_pointer_cache: unsafe { &cache }
				preempt: unsafe { &gpu_only }
				aux_framebuffer: unsafe { &gpu_only }
			}
			init_buffer: shared
			barrier: shared
			vertex: shared
			fragment: shared
			vertex_microsequence: shared
			fragment_microsequence: shared
		}
		ok := mgr.publish_render_mappings(mut job) or { false }
		assert mgr.user_flushes == 0, 'render TPC mapping must not request a firmware flush'
		assert mgr.flushes == if failure == 0 { 8 } else { failure }
		assert ok == (failure == 0) && job.mappings_published
	}
	for failure in 0 .. 4 {
		mut mgr := GpuManager{publication_failure: failure}
		mut job := G13ComputeJobResources{
			vm_slot: 1
			preempt: unsafe { &gpu_only }
			command: shared
			microsequence: shared
			timestamps: shared
		}
		ok := mgr.publish_compute_mappings(mut job) or { false }
		assert mgr.user_flushes == 0, 'compute preemption backing must not request a firmware flush'
		assert mgr.flushes == if failure == 0 { 3 } else { failure }
		assert ok == (failure == 0) && job.mappings_published
	}
	println('G13 job mappings: page-table publication and all 11 kernel flush failure boundaries passed')
}

fn check_queue_mapping_publication() {
	private := mmu.UatBuffer{va: 0x8000, size: 0x4000}
	shared := SharedBuffer{phys: 0x10000, size: 0x4000}
	subqueue := G13SubQueueResources{gpu_buffer: shared, state: shared, ring: shared, info: shared}
	// Four queue buffers, four per render subqueue, and five TVB buffers.
	for slot in [u32(1), 0]! {
		context := mmu.UatContext{slot: slot}
		queue := G13QueueResources{
			channel_mask: 3
			vm: unsafe { &context }
			context: shared
			notifier_list: shared
			threshold: shared
			notifier: shared
			subqueues: [subqueue, subqueue, G13SubQueueResources{}]!
			render_buffer: G13RenderBufferResources{
				info: shared
				block_control: shared
				counter: shared
				stats: shared
				kernel_buffer: shared
				page_list: unsafe { &private }
				block_list: unsafe { &private }
			}
		}
		for failure in 0 .. 18 {
			mut mgr := GpuManager{publication_failure: failure}
			ok := mgr.flush_g13_queue_mappings(unsafe { &queue })
			assert mgr.user_flushes == 0, 'TVB list mappings must not request firmware flushes'
			assert mgr.flushes == if failure == 0 { 17 } else { failure }
			assert ok == (failure == 0)
		}
	}
	println('G13 queue mappings: resident and dormant TVB lists and all 17 kernel flush failure boundaries passed')
}
