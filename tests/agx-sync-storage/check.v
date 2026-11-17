// SPDX-License-Identifier: GPL-2.0-or-later
import os

fn body(source string, name string) string {
	for line in source.split_into_lines() {
		if line == '' || line[0].is_space() || !line.contains(' ' + name + '(') || !line.ends_with(' {') {
			continue
		}
		start := source.index(line) or { panic(name) }
		end := source.index_after('\n}\n', start) or { panic(name) }
		return source[start..end + 3]
	}
	panic('missing C body: ' + name)
}

fn ordered(source string, tokens []string) {
	mut position := 0
	for token in tokens {
		position = (source.index_after(token, position) or { panic('missing/out-of-order ' + token) }) + token.len
	}
}

fn matches_at(source string, offset int, prefix string) bool {
	if offset + prefix.len > source.len { return false }
	for index, value in prefix { if source[offset + index] != value { return false } }
	return true
}

fn discard_paths(source string) string {
	mut out := []u8{cap: source.len}
	mut i := 0
	for i < source.len {
		if matches_at(source, i, '__discard_') && i + 10 < source.len && source[i + 10].is_digit() {
			mut end := i + 10
			for end < source.len && source[end].is_digit() { end++ }
			assert source[end] == `_`
			out << '__discard_PATH'.bytes()
			i = end
		} else {
			out << source[i]
			i++
		}
	}
	return out.bytestr()
}

fn main() {
	assert os.args.len == 3, 'usage: check BASELINE_ARM_C CURRENT_ARM_C'
	old := os.read_file(os.args[1])!
	current := os.read_file(os.args[2])!
	for name in ['submission__stage_packet_syncs', 'submission__packet_sync_snapshot',
		'submission__copy_sync_array', 'submission__release_sync_array', 'submission__SyncArray__item',
		'submission__install_output_syncs', 'gpu__agx__file__g13_dependencies_ready'] {
		code := body(current, name)
		for forbidden in ['memdup(', 'v_malloc(', 'v_calloc(', '__esc_', '__new_array_', 'array_clone(',
			'string__substr(', 'int__str(', 'u64__str('] {
			assert !code.contains(forbidden), name + ': hidden allocation ' + forbidden
		}
	}
	stage := body(current, 'submission__stage_packet_syncs')
	assert stage.count('memory__malloc_packed_fallible(') == 2
	assert stage.contains('memory__free((void*)(inputs.items))') && stage.contains('memory__free((void*)(outputs.items))')
	assert stage.contains('~(u32)(0) - out_count')
	copy := body(current, 'submission__copy_sync_array')
	assert copy.count('memory__malloc_packed_fallible(') == 1
	assert copy.contains('memcpy(storage,') && copy.contains('.items = (submission__SyncItem*)(storage)')
	ioctl := body(current, 'gpu__agx__file__GpuFile__ioctl_modern_submit')
	assert ioctl.contains('submission__release_sync_array(inputs)') && ioctl.contains('submission__release_sync_array(outputs)')
	submit := body(current, 'gpu__agx__file__GpuFile__submit_g13_staged')
	ordered(submit, ['submission__copy_sync_array(input_syncs)', 'new_g13_submission_timestamps(',
		'klock__Lock__acquire(&f->lock)', '.dependencies = pending_inputs', 'register_g13_pending(',
		'dependencies_transferred = true;', 'queued = true;'])
	assert submit.contains('if (!dependencies_transferred)') && submit.contains('submission__release_sync_array(pending_inputs)')
	worker := body(current, 'gpu__agx__file__process_pending_submissions')
	ordered(worker, ['poll_g13_pending(', 'release_g13_submission_timestamps(',
		'submission__release_sync_array(item->dependencies)', 'release_file_reference(',
		'katomic__dec_T_u64(', 'memory__free((void*)(item))'])
	for name in ['gpu__agx__gpu__GpuManager__prepare_g13_render_job_with_timestamps',
		'gpu__agx__gpu__GpuManager__prepare_g13_compute_job_with_timestamps',
		'gpu__agx__gpu__GpuManager__release_g13_queue_resources',
		'gpu__agx__gpu__GpuManager__reap_g13_render_jobs',
		'gpu__agx__gpu__GpuManager__reap_g13_compute_jobs', 'gpu__agx__file__finish_g13_submit',
		'gpu__agx__file__g13_compute_completed', 'gpu__agx__file__g13_render_completed',
		'gpu__agx__file__GpuFile__capture_submission_queue', 'gpu__agx__file__release_submission_queue',
		'gpu__agx__file__GpuFile__close', 'gpu__agx__file__GpuFile__capture_g13_timestamps',
		'gpu__agx__file__poll_g13_pending'] {
		assert discard_paths(body(old, name)) == discard_paths(body(current, name)), name + ': unexpected owning-path change'
	}
	println('Native sync storage: seven bodies have no hidden allocation; two staging owners and one independent pending copy have explicit cleanup/transfer; thirteen preparation/completion/queue/close/timestamp/poll bodies match baseline.')
}
