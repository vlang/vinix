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
	assert os.args.len == 3, 'usage: check PRIOR_QUERY_STATE CURRENT_STATE'
	for arch in ['aarch64', 'x86_64'] {
		old := os.read_file(os.args[1] + '/blob-' + arch + '.c')!
		assert sha256.sum(old.bytes()).hex() == if arch == 'aarch64' {
			'6158b41a11cfc730dae950f0fda2cacc34cd08af6f8b6204a9e4690fbab1e294'
		} else { 'efa6f14a5ad07efc129b8e3c99e781fd697cf65ff5794b25ce371c76bfdec06b' }
		current := os.read_file(os.args[2] + '/blob-' + arch + '.c')!
		no_hidden(current, ['drm__ioctl_syncobj_timeline_signal', 'syncobj__shared_timeline_stub', 'drm__common_ioctl_layout', 'drm__core_ioctl'])
		code := body(current, 'drm__ioctl_syncobj_timeline_signal')
		assert code.count('memory__malloc_packed_fallible(') == 2
		ordered(code, ['syncobj__lookup(', 'memory__malloc_packed_fallible(bytes)',
			'usercopy__copy_from_user(points_storage', 'syncobj__reserve_chain()', 'syncobj__shared_timeline_stub()', 'syncobj__add_chain_point('])
		assert code.contains('syncobj__release_chain_reservation(') && code.contains('memory__free(chains_storage)')
		assert code.contains('memory__free(points_storage)') && code.contains('drm__SyncobjWaitBuffer__free_owned(&buffer)')
		stub := body(current, 'syncobj__shared_timeline_stub')
		assert !stub.contains('memory__') && stub.contains('return &syncobj__timeline_stub_completion;')
		assert normalize(body(old, 'drm__register_driver')) == normalize(body(current, 'drm__register_driver').replace('	syncobj__shared_timeline_stub();
', ''))
		for name in ['syncobj__chain_previous', 'syncobj__chain_contained', 'syncobj__chain_prefix_ready',
			'syncobj__enqueue_chain', 'syncobj__DmaFence__notify_chains_locked', 'syncobj__drain_chain_notifications',
			'syncobj__complete_fence', 'syncobj__is_signaled', 'syncobj__signal', 'syncobj__identity', 'syncobj__snapshot',
			'syncobj__poll_fence', 'syncobj__cancel_fence_event', 'drm__sync_file_info_ioctl',
			'drm__ioctl_syncobj_wait', 'drm__ioctl_syncobj_reset', 'drm__ioctl_syncobj_signal',
			'drm__new_syncobj_handle_buffer', 'drm__SyncobjWaitBuffer__free_owned',
			'drm__ioctl_syncobj_query', 'syncobj__query_timeline_point', 'syncobj__new_private_stub'] {
			assert normalize(body(old, name)) == normalize(body(current, name)), name
		}
		println(arch + ': four timeline SIGNAL/registration bodies reject hidden allocations; two request owners and reservation cleanup explicit; permanent stub allocates nothing; startup adds only getter; twenty-two existing completion/wait/query/private-stub bodies match baseline.')
	}
}
