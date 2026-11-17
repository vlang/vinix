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
	assert os.args.len == 3, 'usage: check PRIOR_QUERY_CHAIN_STATE CURRENT_STATE'
	for arch in ['aarch64', 'x86_64'] {
		old := os.read_file(os.args[1] + '/blob-' + arch + '.c')!
		assert sha256.sum(old.bytes()).hex() == if arch == 'aarch64' {
			'e71c895fe45787684c3d276bc0d91ae017aec74262360029c704fcefe51deb49'
		} else { '87a3093c21aab9069c19ee5d7f8125cea1efd8dbd7b4f0b0fd05058afdc3c471' }
		current := os.read_file(os.args[2] + '/blob-' + arch + '.c')!
		no_hidden(current, ['drm__ioctl_syncobj_query', 'syncobj__query_timeline_point', 'drm__common_ioctl_layout', 'drm__core_ioctl'])
		code := body(current, 'drm__ioctl_syncobj_query')
		ordered(code, ['if (count > 64)', 'drm__new_syncobj_handle_buffer(count)',
			'usercopy__copy_from_user(', 'syncobj__lookup(', 'syncobj__query_timeline_point(', 'usercopy__copy_to_user('])
		assert code.contains('drm__SyncobjWaitBuffer__free_owned(&buffer)')
		assert !code.contains('memory__malloc_packed_fallible(') && !code.contains('syncobj__new_fence(')
		for name in ['syncobj__chain_previous', 'syncobj__chain_contained', 'syncobj__chain_prefix_ready',
			'syncobj__enqueue_chain', 'syncobj__DmaFence__notify_chains_locked', 'syncobj__drain_chain_notifications',
			'syncobj__complete_fence', 'syncobj__is_signaled', 'syncobj__signal', 'syncobj__identity', 'syncobj__snapshot',
			'syncobj__poll_fence', 'syncobj__cancel_fence_event', 'drm__sync_file_info_ioctl',
			'drm__ioctl_syncobj_wait', 'drm__ioctl_syncobj_reset', 'drm__ioctl_syncobj_signal',
			'drm__new_syncobj_handle_buffer', 'drm__SyncobjWaitBuffer__free_owned'] {
			assert normalize(body(old, name)) == normalize(body(current, name)), name
		}
		println(arch + ': four QUERY/registration/dispatch bodies reject hidden allocation; explicit buffer cleanup and wire-order snapshots pass; nineteen existing chain/completion/binary-wait/storage bodies match baseline.')
	}
}
