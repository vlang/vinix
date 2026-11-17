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
	mut result := []u8{cap: source.len}
	mut index := 0
	for index < source.len {
		mut skip := false
		for prefix in ['__discard_', '__or_opt_', '__or_val_', '_sa', '_t'] {
			if !source[index..].starts_with(prefix) { continue }
			mut end := index + prefix.len
			if end >= source.len || !source[end].is_digit() { continue }
			for end < source.len && source[end].is_digit() { end++ }
			result << (prefix + 'N').bytes(); index = end; skip = true; break
		}
		if !skip { result << source[index]; index++ }
	}
	return result.bytestr()
}

fn ordered(source string, tokens []string) {
	mut offset := 0
	for token in tokens { offset = (source.index_after(token, offset) or { panic(token) }) + token.len }
}

fn check_native(old string, current string, arch string) {
	for name in ['syncobj__new_fence', 'syncobj__new_queue_context', 'syncobj__unwrap_merge', 'syncobj__new_merge_array',
		'syncobj__enable_array', 'syncobj__array_child_complete', 'syncobj__complete_array', 'syncobj__add_chain_point',
		'syncobj__drain_chain_notifications', 'drm__ioctl_syncobj_transfer'] {
		if arch == 'x86_64' && name == 'syncobj__new_fence' {
			assert !old.contains(name + '(') && !current.contains(name + '(')
			continue
		}
		assert normalize(body(old, name)) == normalize(body(current, name)), name
	}
	if arch == 'x86_64' {
		assert !current.contains('fake__new_submission_fence(')
		println(arch + ': fake backend and generic constructor pruned; nine shared DRM context, merge, callback and transfer bodies unchanged.')
		return
	}
	helper := body(current, 'fake__new_submission_fence')
	for token in ['memdup(', 'v_malloc(', 'v_calloc(', '__esc_', '__new_array_', 'array_clone(', 'string__substr(', 'int__str(', 'u64__str('] {
		assert !helper.contains(token), 'hidden allocation in fake helper: ' + token
	}
	ordered(helper, ['syncobj__new_queue_context()', 'if (', 'return', 'syncobj__new_fence(context, 1)'])
	assert helper.count('syncobj__new_fence(') == 1
	submit := body(current, 'fake__FakeG17File__ioctl_submit')
	ordered(submit, ['fake__FakeG17Vm__begin_job(vm)', 'file->inflight_jobs++', 'fake__new_submission_fence()',
		'if (vm_pinned)', 'fake__FakeG17Vm__finish_job(vm)', 'file->inflight_jobs--', 'klock__Lock__release(&file->lock)',
		'-12;', 'array__free(&render_resources)', 'submission__install_output_syncs('])
	assert !submit.contains('syncobj__new_fence(')
	// Added option temporaries shift compiler-generated names; no other names
	// or code are normalized. Validate the original pre-admission and work paths.
	before := body(old, 'fake__FakeG17File__ioctl_submit')
	old_line := '\tsyncobj__DmaFence* fence = syncobj__new_fence(file->owner_key, timer__get_ns());'
	new_line := submit.split_into_lines().filter(it.contains('= fake__new_submission_fence();'))
	assert new_line.len == 1
	assert normalize(before.all_before(old_line)) == normalize(submit.all_before(new_line[0]))
	assert normalize(before.all_after('\tu64 started = timer__get_count();')) == normalize(submit.all_after('\tu64 started = timer__get_count();'))
	for name in ['fake__FakeG17File__finish_close_locked', 'fake__FakeG17File__finish_pending_job', 'fake__fake_completion_worker',
		'workqueue__WorkQueue__complete', 'workqueue__WorkQueue__destroy', 'workqueue__free_workqueue'] {
		assert normalize(body(old, name)) == normalize(body(current, name)), name
	}
	println(arch + ': helper has no hidden allocations before the unchanged fence constructor; exhaustion unwinds VM/file pins, unlocks and frees staged resources before output effects. Admission/work paths and six completion/close/queue bodies unchanged.')
}

fn main() {
	assert os.args.len == 3, 'usage: check PRIOR_BUNDLE CURRENT_STATE'
	for arch in ['aarch64', 'x86_64'] {
		old := os.read_file(os.args[1] + '/blob-' + arch + '.c')!
		assert sha256.sum(old.bytes()).hex() == if arch == 'aarch64' { 'c6ae85258a8c5dc6cad06975530f4a1a305ad06889b2f41d3c70fce0c52bd08b' } else { '241b7204d7cfb971f41c6b6af52d29d33c7c7dedf2ba03ebc9c1ae11bbb40ff2' }
		check_native(old, os.read_file(os.args[2] + '/blob-' + arch + '.c')!, arch)
	}
	host := os.read_file(os.args[2] + '/host-complete/host.c')!
	for name in ['fake__check_order', 'fake__FakeG17File__reserve_output'] {
		code := body(host, name)
		assert !code.contains('memdup(') && !code.contains('__esc_'), name + ': implicit fixture copy'
	}
	println('Host fixture: explicit stack queue block and borrowed output array have no implicit heap copies.')
}
