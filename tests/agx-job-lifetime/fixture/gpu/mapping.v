// SPDX-License-Identifier: GPL-2.0-or-later
module gpu

import gpu.agx.mmu
import gpu.agx.pgtable

fn check_kernel_mapping_flush() {
	mut mgr := GpuManager{flush_fails: true}
	assert !mgr.flush_g13_kernel_buffer(unsafe { nil })
	for protection in [pgtable.gpu_prot_fw_shared_rw, pgtable.gpu_prot_fw_shared_ro,
		pgtable.gpu_prot_fw_private_rw, pgtable.gpu_prot_gpu_ro_fw_private_rw]! {
		mgr.flushes = 0
		no_address := SharedBuffer{size: 0x4000, protection: protection}
		no_size := SharedBuffer{va: 0x10000, protection: protection}
		assert !mgr.flush_g13_kernel_buffer(&no_address)
		assert !mgr.flush_g13_kernel_buffer(&no_size)
		assert mgr.flushes == 0
		buffer := SharedBuffer{phys: 0x4000, va: 0x10000, size: 0x4000, protection: protection}
		cached := protection == pgtable.gpu_prot_fw_private_rw || protection == pgtable.gpu_prot_gpu_ro_fw_private_rw
		assert mgr.flush_g13_kernel_buffer(&buffer) == !cached, 'uncached kernel mappings must skip firmware flushes'
		assert mgr.flushes == if cached { 1 } else { 0 }
	}
}

fn check_job_mapping_publication() {
	gpu_only := mmu.UatBuffer{va: 0x4000, size: 0x4000}
	private := mmu.UatBuffer{va: 0x8000, size: 0x4000}
	cache := G13TailPointerCache{buffer: unsafe { &private }}
	shared := SharedBuffer{phys: 0x10000, va: 0x10000, size: 0x4000, protection: pgtable.gpu_prot_fw_shared_rw}
	private_command := SharedBuffer{phys: 0x14000, va: 0x14000, size: 0x4000}
	readonly_command := SharedBuffer{phys: 0x18000, va: 0x18000, size: 0x4000, protection: pgtable.gpu_prot_gpu_ro_fw_private_rw}
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

fn check_queue_mapping_publication() {
	private := mmu.UatBuffer{va: 0x8000, size: 0x4000}
	shared := SharedBuffer{phys: 0x10000, va: 0x10000, size: 0x4000, protection: pgtable.gpu_prot_fw_shared_rw}
	cached := SharedBuffer{phys: 0x14000, va: 0x14000, size: 0x4000}
	subqueue := G13SubQueueResources{gpu_buffer: cached, state: shared, ring: shared, info: cached}
	// Cached buffer count: one notifier, two per render subqueue and one TVB info.
	for slot in [u32(1), 0]! {
		context := mmu.UatContext{slot: slot}
		queue := G13QueueResources{
			channel_mask: 3
			vm: unsafe { &context }
			context: shared
			notifier_list: shared
			threshold: shared
			notifier: cached
			subqueues: [subqueue, subqueue, G13SubQueueResources{}]!
			render_buffer: G13RenderBufferResources{
				info: cached
				block_control: shared
				counter: shared
				stats: shared
				kernel_buffer: shared
				page_list: unsafe { &private }
				block_list: unsafe { &private }
			}
		}
		for failure in 0 .. 7 {
			mut mgr := GpuManager{publication_failure: failure}
			ok := mgr.flush_g13_queue_mappings(unsafe { &queue })
			assert mgr.user_flushes == 0, 'TVB list mappings must not request firmware flushes'
			assert mgr.flushes == if failure == 0 { 6 } else { failure }
			assert ok == (failure == 0)
		}
	}
	println('G13 queue mappings: resident and dormant VMs and all six cached flush failure positions passed')
}
