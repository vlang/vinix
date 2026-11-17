// SPDX-License-Identifier: GPL-2.0-or-later
import crypto.sha256
import os

fn body(source string, name string) string {
	for line in source.split_into_lines() {
		if line == '' || line[0].is_space() || !line.contains(' ' + name + '(') || !line.ends_with(' {') { continue }
		start := source.index(line) or { panic(name) }
		end := source.index_after('\n}\n', start) or { panic(name) }
		return source[start..end + 3]
	}
	panic('missing C function ' + name)
}

fn normalize(source string) string {
	mut out := []u8{cap: source.len}
	mut index := 0
	for index < source.len {
		if source[index..].starts_with('__discard_') && index + 10 < source.len && source[index + 10].is_digit() {
			mut end := index + 10
			for end < source.len && source[end].is_digit() { end++ }
			assert source[end] == `_`
			out << '__discard_PATH'.bytes(); index = end
		} else { out << source[index]; index++ }
	}
	return out.bytestr()
}

fn ordered(source string, tokens []string) {
	mut offset := 0
	for token in tokens { offset = (source.index_after(token, offset) or { panic(token) }) + token.len }
}

fn no_hidden(source string, names []string) {
	for name in names {
		code := body(source, name)
		for token in ['memdup(', 'v_malloc(', 'v_calloc(', '__esc_', '__new_array_', 'array_clone(', 'string__substr(', 'int__str(', 'u64__str('] {
			assert !code.contains(token), name + ': hidden allocation ' + token
		}
	}
}

fn main() {
	assert os.args.len == 3, 'usage: check VERIFIED_PRIOR_STATE CURRENT_STATE'
	prior := os.abs_path(os.args[1]); state := os.abs_path(os.args[2])
	for arch in ['aarch64', 'x86_64'] {
		old := os.read_file(prior + '/blob-' + arch + '.c')!
		assert sha256.sum(old.bytes()).hex() == if arch == 'aarch64' {
			'adfbd071d4d35f3c16d3e0f689cd4b779b883d2c72a8af6254444798f882e775'
		} else { '2a150c955222c385f74dc537f9ccf3967c05257693a7ad5b3113a1aff5cb8ab8' }
		current := os.read_file(state + '/blob-' + arch + '.c')!
		no_hidden(current, ['syncobj__chain_previous', 'syncobj__chain_contained',
			'syncobj__chain_prefix_ready', 'syncobj__enqueue_chain',
			'syncobj__DmaFence__notify_chains_locked', 'syncobj__drain_chain_notifications', 'syncobj__complete_fence',
			'syncobj__signal', 'syncobj__is_signaled', 'syncobj__identity', 'syncobj__snapshot',
			'syncobj__poll_fence', 'syncobj__cancel_fence_event', 'drm__sync_file_info_ioctl'])
		assert current.contains('if (len == 0 && cap == 0) return (array){.element_size = elem_size, .flags = ArrayFlags__managed};')
		ordered(body(current, 'syncobj__complete_fence'), ['klock__Lock__acquire(&f->lock)', 'if (f->signaled)',
			'if (set_error)', 'katomic__store_T_v_bool(', 'notify_events_locked(f)', 'notify_chains_locked(f)', '(*w)->callback(fence)', 'klock__Lock__release(&f->lock)'])
		for name in ['syncobj__lookup', 'syncobj__destroy', 'syncobj__destroy_owner', 'syncobj__insert_handle',
			'syncobj__replace_fence', 'syncobj__get_fence'] {
			assert normalize(body(old, name)) == normalize(body(current, name)), name
		}
		if arch == 'aarch64' {
			no_hidden(current, ['syncobj__reserve_chain', 'syncobj__release_chain_reservation', 'syncobj__initialize_chain',
				'syncobj__register_chain_waiter', 'syncobj__add_chain_point', 'syncobj__get_chain_fence', 'syncobj__signal_error'])
			reserve := body(current, 'syncobj__reserve_chain')
			assert reserve.count('memory__malloc_packed_fallible(') == 1
			assert reserve.contains('array_new(sizeof(syncobj__FenceWaiter*), 0, 0)')
			ordered(body(current, 'syncobj__initialize_chain'), ['f->chain_reserved = false;',
				'register_chain_waiter(previous, &f->chain_previous_waiter, node)', 'register_chain_waiter(payload, &f->chain_payload_waiter, node)'])
			assert normalize(body(old, 'syncobj__get_timeline_fence')) == normalize(body(current, 'syncobj__get_timeline_fence'))
			no_hidden(current, ['submission__stage_packet_syncs', 'submission__packet_sync_snapshot', 'submission__release_sync_array',
				'submission__copy_sync_array', 'submission__SyncArray__item', 'submission__install_output_syncs', 'gpu__agx__file__g13_dependencies_ready'])
			stage := body(current, 'submission__stage_packet_syncs')
			assert stage.count('memory__malloc_packed_fallible(') == 2
			assert stage.contains('syncobj__get_chain_fence(') && stage.contains('syncobj__reserve_chain(')
			assert body(current, 'submission__release_sync_array').contains('syncobj__release_chain_reservation(chain)')
			for name in ['gpu__agx__gpu__GpuManager__prepare_g13_render_job_with_timestamps',
				'gpu__agx__gpu__GpuManager__prepare_g13_compute_job_with_timestamps', 'gpu__agx__gpu__GpuManager__release_g13_queue_resources',
				'gpu__agx__gpu__GpuManager__reap_g13_render_jobs', 'gpu__agx__gpu__GpuManager__reap_g13_compute_jobs',
				'gpu__agx__file__finish_g13_submit', 'gpu__agx__file__g13_compute_completed', 'gpu__agx__file__g13_render_completed',
				'gpu__agx__file__GpuFile__capture_submission_queue', 'gpu__agx__file__release_submission_queue',
				'gpu__agx__file__GpuFile__close', 'gpu__agx__file__GpuFile__capture_g13_timestamps', 'gpu__agx__file__poll_g13_pending'] {
				assert normalize(body(old, name)) == normalize(body(current, name)), name
			}
		}
		println(arch + ': 14 common allocation-sensitive bodies and six unchanged namespace helpers pass; ARM additionally checks seven chain bodies, seven sync-storage bodies, legacy lookup, publication transfer and thirteen unchanged owning paths. Unused ARM-only chain constructors are absent on x86.')
	}
}
