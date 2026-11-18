// SPDX-License-Identifier: GPL-2.0-or-later
module gpu

import gpu.agx.mmu

fn check_job_mapping_publication() {
	gpu_only := mmu.UatBuffer{va: 0x4000, size: 0x4000}
	private := mmu.UatBuffer{va: 0x8000, size: 0x4000}
	cache := G13TailPointerCache{buffer: unsafe { &private }}
	shared := SharedBuffer{phys: 0x10000, size: 0x4000}
	for failure in 0 .. 10 {
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
		assert mgr.user_flushes == 1 && mgr.user_flush_address == private.va, 'render may only flush the private TPC in its VM'
		assert mgr.flushes == if failure == 0 { 8 } else { failure - 1 }
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
	println('G13 job mappings: GPU-only scratch, private TPC, kernel flushes and all 12 failure boundaries passed')
}
