// SPDX-License-Identifier: GPL-2.0-or-later
module gpu

import gpu.agx.mmu

fn check_job_mapping_publication() {
	gpu_only := mmu.UatBuffer{va: 0x4000, size: 0x4000}
	private := mmu.UatBuffer{va: 0x8000, size: 0x4000}
	cache := G13TailPointerCache{buffer: unsafe { &private }}
	shared := SharedBuffer{phys: 0x10000, va: 0x10000, size: 0x4000}
	private_command := SharedBuffer{phys: 0x14000, va: 0x14000, size: 0x4000}
	readonly_command := SharedBuffer{phys: 0x18000, va: 0x18000, size: 0x4000}
	mut mgr := GpuManager{flush_fails: true}
	mut render_job := G13RenderJobResources{
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
		init_buffer: private_command
		barrier: private_command
		vertex: readonly_command
		fragment: readonly_command
		vertex_microsequence: private_command
		fragment_microsequence: private_command
	}
	render_ok := mgr.publish_render_mappings(mut render_job) or { false }
	assert mgr.flushes == 0 && mgr.user_flushes == 0, 'render job preparation must not send a firmware flush'
	assert render_ok && render_job.mappings_published && !render_job.submitted

	mut compute_job := G13ComputeJobResources{
		vm_slot: 1
		preempt: unsafe { &gpu_only }
		command: readonly_command
		microsequence: private_command
		timestamps: shared
	}
	compute_ok := mgr.publish_compute_mappings(mut compute_job) or { false }
	assert mgr.flushes == 0 && mgr.user_flushes == 0, 'compute job preparation must not send a firmware flush'
	assert compute_ok && compute_job.mappings_published && !compute_job.submitted
	println('G13 job mappings: render and compute preparation complete without a firmware flush')
}
