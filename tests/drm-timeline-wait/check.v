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
	assert os.args.len == 3, 'usage: check PRIOR_SIGNAL_BUNDLE CURRENT_STATE'
	for arch in ['aarch64', 'x86_64'] {
		old := os.read_file(os.args[1] + '/blob-' + arch + '.c')!
		assert sha256.sum(old.bytes()).hex() == if arch == 'aarch64' {
			'35c96b7e11668921fbeda504c12d7095eeb927780599f849caab71de86482c6d'
		} else { 'ab309e2e286e3f3962a951e283eb255992bb90550d49d89f9a0dec3763af2caf' }
		current := os.read_file(os.args[2] + '/blob-' + arch + '.c')!
		no_hidden(current, ['drm__ioctl_syncobj_timeline_wait', 'syncobj__prepare_timeline_capture',
			'syncobj__arm_timeline_capture', 'syncobj__captured_timeline_fence', 'syncobj__release_timeline_capture',
			'syncobj__SyncObj__publish_timeline_captures_locked', 'syncobj__TimelineCapture__resolve_locked',
			'syncobj__find_chain_fence', 'drm__common_ioctl_layout', 'drm__core_ioctl'])
		if arch == 'aarch64' { no_hidden(current, ['syncobj__get_chain_fence']) }
		code := body(current, 'drm__ioctl_syncobj_timeline_wait')
		assert code.count('memory__malloc_packed_fallible(') == 2
		ordered(code, ['syncobj__lookup(', 'memory__malloc_packed_fallible((u64)(count) * sizeof(u64))',
			'usercopy__copy_from_user(points_storage', 'memory__malloc_packed_fallible((u64)(count) * sizeof(syncobj__TimelineCapture))',
			'memset(captures_storage, 0,', 'syncobj__prepare_timeline_capture(', 'syncobj__arm_timeline_capture('])
		assert code.contains('u32 handles[64];') && code.contains('void* objects[64] = {0};')
		// Every emitted release path must detach the borrowed nodes before owners.
		for part in code.split('syncobj__release_timeline_capture(')[1..] {
			ordered(part, ['memory__free(captures_storage)', 'memory__free(points_storage)', 'drm__SyncobjWaitBuffer__free_owned(&buffer)'])
		}
		for name in ['syncobj__prepare_timeline_capture', 'syncobj__arm_timeline_capture', 'syncobj__captured_timeline_fence',
			'syncobj__release_timeline_capture', 'syncobj__SyncObj__publish_timeline_captures_locked',
			'syncobj__TimelineCapture__resolve_locked', 'syncobj__find_chain_fence'] {
			assert !body(current, name).contains('memory__'), name
		}
		for name in ['syncobj__replace_fence', 'syncobj__add_chain_point'] {
			expression := if name == 'syncobj__replace_fence' { 'fence' } else { 'reservation' }
			assert normalize(body(old, name)) == normalize(body(current, name).replace('\tsyncobj__SyncObj__publish_timeline_captures_locked(o, ' + expression + ');\n', '')), name
		}
		if arch == 'aarch64' {
			assert body(old, 'syncobj__get_chain_fence').all_after('\tif (point == 0)') == body(current, 'syncobj__find_chain_fence').all_after('\tif (point == 0)')
		}
		for name in ['syncobj__chain_previous', 'syncobj__chain_contained', 'syncobj__chain_prefix_ready',
			'syncobj__enqueue_chain', 'syncobj__DmaFence__notify_chains_locked', 'syncobj__drain_chain_notifications',
			'syncobj__complete_fence', 'syncobj__is_signaled', 'syncobj__signal', 'syncobj__identity', 'syncobj__snapshot',
			'syncobj__poll_fence', 'syncobj__cancel_fence_event', 'drm__sync_file_info_ioctl',
			'drm__ioctl_syncobj_wait', 'drm__ioctl_syncobj_reset', 'drm__ioctl_syncobj_signal',
			'drm__new_syncobj_handle_buffer', 'drm__SyncobjWaitBuffer__free_owned',
			'drm__ioctl_syncobj_query', 'syncobj__query_timeline_point', 'syncobj__new_private_stub',
			'drm__ioctl_syncobj_timeline_signal', 'syncobj__shared_timeline_stub', 'syncobj__prepare_capture',
			'syncobj__captured_fence', 'syncobj__release_capture', 'syncobj__SyncObj__publish_captures_locked'] {
			assert normalize(body(old, name)) == normalize(body(current, name)), name
		}
		println(arch + ': timeline WAIT/registration bodies reject hidden allocations; two table owners and unlink-before-free explicit; capture functions allocate nothing; publication adds only timeline capture notification; twenty-eight existing completion/binary/query/signal bodies match baseline. ARM point lookup inner logic matches; old x86 wrapper was pruned.')
	}
}
