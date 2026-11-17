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
	assert os.args.len == 3, 'usage: check PRIOR_WAIT_BUNDLE CURRENT_STATE'
	for arch in ['aarch64', 'x86_64'] {
		old := os.read_file(os.args[1] + '/blob-' + arch + '.c')!
		assert sha256.sum(old.bytes()).hex() == if arch == 'aarch64' {
			'fc0f46956a2224c7d7d8330d7d71a7a6870e7bcfe4c5ce1150b1583d38bb058b'
		} else { '07b2a98b16a101f618e1906b8bcd7ddff1582cc82abb7b8767ddd958f0366c09' }
		current := os.read_file(os.args[2] + '/blob-' + arch + '.c')!
		no_hidden(current, ['drm__find_syncobj_fence', 'drm__ioctl_syncobj_transfer', 'drm__common_ioctl_layout', 'drm__core_ioctl'])
		lookup := body(current, 'drm__find_syncobj_fence')
		assert lookup.count('__builtin_alloca(sizeof(syncobj__TimelineCapture))') == 1 && !lookup.contains('memory__')
		assert !lookup.contains('syncobj__is_signaled(') && !lookup.contains('syncobj__wait(')
		ordered(lookup, ['syncobj__lookup(', 'flags & ~drm__ioctl__drm_syncobj_wait_for_submit',
			'__builtin_alloca(sizeof(syncobj__TimelineCapture))', '*capture = ', 'syncobj__prepare_timeline_capture(object, capture',
			'syncobj__captured_timeline_fence(capture)', 'syncobj__arm_timeline_capture(capture)',
			'syncobj__now_ns()', '5000000000', 'proc__pending_signals(', 'sched__reschedule()'])
		assert lookup.count('syncobj__release_timeline_capture(capture)') >= 5
		transfer := body(current, 'drm__ioctl_syncobj_transfer')
		assert !transfer.contains('memory__')
		ordered(transfer, ['request->pad != 0', 'request->dst_point != 0', 'syncobj__lookup(',
			'drm__find_syncobj_fence(', 'source.code != 0', 'syncobj__replace_fence(destination, source.fence)'])
		for name in ['syncobj__replace_fence', 'syncobj__add_chain_point', 'syncobj__chain_previous',
			'syncobj__chain_prefix_ready', 'syncobj__drain_chain_notifications', 'syncobj__complete_fence',
			'syncobj__is_signaled', 'syncobj__signal', 'syncobj__identity', 'syncobj__snapshot',
			'syncobj__poll_fence', 'syncobj__cancel_fence_event', 'drm__sync_file_info_ioctl',
			'drm__ioctl_syncobj_wait', 'drm__ioctl_syncobj_reset', 'drm__ioctl_syncobj_signal',
			'drm__ioctl_syncobj_query', 'drm__ioctl_syncobj_timeline_signal', 'drm__ioctl_syncobj_timeline_wait',
			'syncobj__shared_timeline_stub', 'syncobj__prepare_timeline_capture', 'syncobj__arm_timeline_capture',
			'syncobj__captured_timeline_fence', 'syncobj__release_timeline_capture',
			'syncobj__SyncObj__publish_timeline_captures_locked', 'syncobj__TimelineCapture__resolve_locked', 'syncobj__find_chain_fence'] {
			assert normalize(body(old, name)) == normalize(body(current, name)), name
		}
		println(arch + ': four binary TRANSFER/registration bodies reject hidden allocations; lookup capture is stack storage, directly borrowed and detached on all prepared exits; source/destination lookup precedes publication; twenty-seven existing completion/capture/wait/query/signal bodies match baseline.')
	}
}
